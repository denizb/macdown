import Foundation

/// A small, dependency-free Markdown → HTML renderer covering CommonMark
/// essentials plus the common GitHub extensions (tables, task lists,
/// strikethrough, autolinks). Raw HTML in the source is escaped, never passed through.
struct MarkdownRenderer {
    private struct LinkReference {
        let url: String
        let title: String?
    }

    private var references: [String: LinkReference] = [:]

    static func html(from markdown: String) -> String {
        var renderer = MarkdownRenderer()
        let lines = renderer.extractReferences(from: normalize(markdown))
        return renderer.renderBlocks(lines)
    }

    private static func normalize(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "    ")
            .components(separatedBy: "\n")
    }

    // MARK: - Reference definitions

    private static let referencePattern = try! NSRegularExpression(
        pattern: #"^ {0,3}\[([^\]]+)\]:\s*<?([^\s>]+)>?(?:\s+["'(](.*)["')])?\s*$"#
    )

    private mutating func extractReferences(from lines: [String]) -> [String] {
        var kept: [String] = []
        var fence: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                kept.append(line)
                continue
            }
            if let marker = Self.fenceMarker(trimmed) {
                fence = marker
                kept.append(line)
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            if let match = Self.referencePattern.firstMatch(in: line, range: range),
               let label = Range(match.range(at: 1), in: line),
               let url = Range(match.range(at: 2), in: line) {
                let title = Range(match.range(at: 3), in: line).map { String(line[$0]) }
                references[Self.referenceKey(String(line[label]))] = LinkReference(url: String(line[url]), title: title)
            } else {
                kept.append(line)
            }
        }
        return kept
    }

    private static func referenceKey(_ label: String) -> String {
        label.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Blocks

    private func renderBlocks(_ lines: [String], tight: Bool = false) -> String {
        var out = ""
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let content = renderInline(paragraph.joined(separator: "\n"))
            out += tight ? content + "\n" : "<p>\(content)</p>\n"
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = Self.indentation(of: line)

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Indented code block (only when not continuing a paragraph).
            if indent >= 4 && paragraph.isEmpty {
                var code: [String] = []
                while i < lines.count {
                    let l = lines[i]
                    if Self.indentation(of: l) >= 4 {
                        code.append(String(l.dropFirst(4)))
                    } else if l.trimmingCharacters(in: .whitespaces).isEmpty {
                        code.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                while code.last?.isEmpty == true { code.removeLast() }
                out += "<pre><code>\(Self.escape(code.joined(separator: "\n")))\n</code></pre>\n"
                continue
            }

            if let fence = Self.fenceMarker(trimmed) {
                flushParagraph()
                let language = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").first.map(String.init) ?? ""
                var code: [String] = []
                i += 1
                while i < lines.count {
                    let l = lines[i]
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix(fence) { i += 1; break }
                    code.append(String(l.dropFirst(min(indent, Self.indentation(of: l)))))
                    i += 1
                }
                let cls = language.isEmpty ? "" : " class=\"language-\(Self.escapeAttribute(language))\""
                let body = code.isEmpty ? "" : Self.escape(code.joined(separator: "\n")) + "\n"
                out += "<pre><code\(cls)>\(body)</code></pre>\n"
                continue
            }

            // Setext headings underline a paragraph.
            if !paragraph.isEmpty, let level = Self.setextLevel(trimmed) {
                let text = paragraph.joined(separator: "\n")
                paragraph = []
                out += heading(level: level, text: text)
                i += 1
                continue
            }

            if let (level, text) = Self.atxHeading(trimmed) {
                flushParagraph()
                out += heading(level: level, text: text)
                i += 1
                continue
            }

            if Self.isThematicBreak(trimmed) {
                flushParagraph()
                out += "<hr>\n"
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix(">") {
                        var rest = l.dropFirst()
                        if rest.first == " " { rest = rest.dropFirst() }
                        quoted.append(String(rest))
                    } else if !l.isEmpty, !(quoted.last ?? "").isEmpty, Self.isLazyContinuation(l) {
                        quoted.append(l)
                    } else {
                        break
                    }
                    i += 1
                }
                out += "<blockquote>\n\(renderBlocks(quoted))</blockquote>\n"
                continue
            }

            if line.contains("|"), i + 1 < lines.count, let alignments = Self.tableAlignments(lines[i + 1]) {
                let header = Self.tableCells(line)
                if header.count == alignments.count {
                    flushParagraph()
                    i = renderTable(lines, from: i, header: header, alignments: alignments, into: &out)
                    continue
                }
            }

            if let marker = Self.listMarker(line), paragraph.isEmpty || marker.canInterruptParagraph {
                flushParagraph()
                i = renderList(lines, from: i, into: &out)
                continue
            }

            paragraph.append(trimmed + (line.hasSuffix("  ") ? "  " : ""))
            i += 1
        }
        flushParagraph()
        return out
    }

    private func heading(level: Int, text: String) -> String {
        let slug = Self.slug(text)
        return "<h\(level) id=\"\(slug)\">\(renderInline(text))</h\(level)>\n"
    }

    private static func fenceMarker(_ trimmed: String) -> String? {
        for char in ["`", "~"] {
            let run = trimmed.prefix(while: { String($0) == char })
            if run.count >= 3 {
                // Backtick fences may not contain backticks in the info string.
                if char == "`" && trimmed.dropFirst(run.count).contains("`") { return nil }
                return String(run)
            }
        }
        return nil
    }

    private static func atxHeading(_ trimmed: String) -> (Int, String)? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing sequence: "## Title ##"
        let closing = text.reversed().prefix(while: { $0 == "#" }).count
        if closing > 0 {
            let withoutClosing = text.dropLast(closing)
            if withoutClosing.isEmpty || withoutClosing.last == " " {
                text = withoutClosing.trimmingCharacters(in: .whitespaces)
            }
        }
        return (hashes, text)
    }

    private static func setextLevel(_ trimmed: String) -> Int? {
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        let chars = trimmed.filter { $0 != " " }
        guard chars.count >= 3, let first = chars.first, "-*_".contains(first) else { return false }
        return chars.allSatisfy { $0 == first }
    }

    private static func isLazyContinuation(_ trimmed: String) -> Bool {
        !(trimmed.hasPrefix("#") || isThematicBreak(trimmed) || fenceMarker(trimmed) != nil || listMarker(trimmed) != nil)
    }

    private static func indentation(of line: String) -> Int {
        line.prefix(while: { $0 == " " }).count
    }

    // MARK: Lists

    private struct ListMarker {
        let indent: Int
        let ordered: Bool
        let start: Int
        let delimiter: Character
        /// Column at which the item's content begins.
        let contentOffset: Int
        let isEmpty: Bool

        var canInterruptParagraph: Bool { !isEmpty && (!ordered || start == 1) }
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let indent = indentation(of: line)
        let rest = line.dropFirst(indent)
        guard let first = rest.first else { return nil }

        var markerLength: Int
        var ordered = false
        var start = 1
        var delimiter = first
        if "-*+".contains(first) {
            markerLength = 1
        } else {
            let digits = rest.prefix(while: \.isASCII).prefix(while: \.isNumber)
            guard (1...9).contains(digits.count) else { return nil }
            let after = rest.dropFirst(digits.count)
            guard let d = after.first, d == "." || d == ")" else { return nil }
            ordered = true
            start = Int(digits) ?? 1
            delimiter = d
            markerLength = digits.count + 1
        }

        let afterMarker = rest.dropFirst(markerLength)
        if afterMarker.isEmpty {
            return ListMarker(indent: indent, ordered: ordered, start: start, delimiter: delimiter,
                              contentOffset: indent + markerLength + 1, isEmpty: true)
        }
        guard afterMarker.first == " " else { return nil }
        var spaces = afterMarker.prefix(while: { $0 == " " }).count
        if spaces > 4 { spaces = 1 } // Treat as indented code inside the item.
        return ListMarker(indent: indent, ordered: ordered, start: start, delimiter: delimiter,
                          contentOffset: indent + markerLength + spaces, isEmpty: false)
    }

    private func renderList(_ lines: [String], from startIndex: Int, into out: inout String) -> Int {
        guard let first = Self.listMarker(lines[startIndex]) else { return startIndex + 1 }
        var items: [[String]] = []
        var current: [String] = []
        var contentOffset = first.contentOffset
        var loose = false
        var pendingBlank = false
        var i = startIndex

        func isSibling(_ marker: ListMarker) -> Bool {
            marker.ordered == first.ordered && marker.delimiter == first.delimiter
                && marker.indent < contentOffset && marker.indent <= first.indent + 3
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                pendingBlank = true
                current.append("")
                i += 1
                continue
            }

            let indent = Self.indentation(of: line)
            if let marker = Self.listMarker(line), isSibling(marker) {
                if i != startIndex {
                    if pendingBlank { loose = true }
                    items.append(current)
                }
                current = [String(line.dropFirst(min(marker.contentOffset, line.count)))]
                contentOffset = marker.contentOffset
                pendingBlank = false
            } else if indent >= contentOffset {
                if pendingBlank && current.contains(where: { !$0.isEmpty }) { loose = true }
                current.append(String(line.dropFirst(contentOffset)))
                pendingBlank = false
            } else if !pendingBlank && Self.isLazyContinuation(trimmed) && !(current.last ?? "").isEmpty {
                current.append(trimmed)
            } else {
                break
            }
            i += 1
        }
        items.append(current)

        // A trailing blank line belongs to whatever follows the list, not the list.
        while var last = items.last, last.last?.isEmpty == true {
            last.removeLast()
            items[items.count - 1] = last
        }
        // Blank lines only at the end of an item's content don't make the list loose,
        // but blank lines between blocks within an item do (handled above).

        let tag = first.ordered ? "ol" : "ul"
        let startAttr = first.ordered && first.start != 1 ? " start=\"\(first.start)\"" : ""
        out += "<\(tag)\(startAttr)>\n"
        for var item in items {
            while item.last?.isEmpty == true { item.removeLast() }
            var checkbox = ""
            if let firstLine = item.first {
                for (prefix, checked) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] where firstLine.hasPrefix(prefix) {
                    checkbox = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                    item[0] = String(firstLine.dropFirst(prefix.count))
                }
            }
            let cls = checkbox.isEmpty ? "" : " class=\"task\""
            let body = renderBlocks(item, tight: !loose)
            let trimmedBody = body.hasSuffix("\n") && !body.hasSuffix(">\n") ? String(body.dropLast()) : body
            out += "<li\(cls)>\(checkbox)\(trimmedBody)</li>\n"
        }
        out += "</\(tag)>\n"
        return i
    }

    // MARK: Tables

    private enum Alignment { case none, left, center, right }

    private static func tableCells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") && !row.hasSuffix("\\|") { row.removeLast() }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        var inCode = false
        for char in row {
            if escaped {
                if char != "|" { cell.append("\\") }
                cell.append(char)
                escaped = false
            } else if char == "\\" {
                escaped = true
            } else if char == "`" {
                inCode.toggle()
                cell.append(char)
            } else if char == "|" && !inCode {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(char)
            }
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func tableAlignments(_ line: String) -> [Alignment]? {
        guard line.contains("-") else { return nil }
        let cells = tableCells(line)
        var result: [Alignment] = []
        for cell in cells {
            let left = cell.hasPrefix(":"), right = cell.hasSuffix(":")
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            switch (left, right) {
            case (true, true): result.append(.center)
            case (true, false): result.append(.left)
            case (false, true): result.append(.right)
            case (false, false): result.append(.none)
            }
        }
        return result
    }

    private func renderTable(_ lines: [String], from start: Int, header: [String],
                             alignments: [Alignment], into out: inout String) -> Int {
        func attr(_ index: Int) -> String {
            switch alignments[index] {
            case .none: return ""
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }

        out += "<table>\n<thead>\n<tr>"
        for (index, cell) in header.enumerated() {
            out += "<th\(attr(index))>\(renderInline(cell))</th>"
        }
        out += "</tr>\n</thead>\n"

        var i = start + 2
        var bodyRows = ""
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || !line.contains("|") { break }
            let cells = Self.tableCells(line)
            bodyRows += "<tr>"
            for index in alignments.indices {
                let cell = index < cells.count ? cells[index] : ""
                bodyRows += "<td\(attr(index))>\(renderInline(cell))</td>"
            }
            bodyRows += "</tr>\n"
            i += 1
        }
        if !bodyRows.isEmpty { out += "<tbody>\n\(bodyRows)</tbody>\n" }
        out += "</table>\n"
        return i
    }

    // MARK: - Inline

    private func renderInline(_ text: String) -> String {
        renderInline(Array(text))
    }

    private func renderInline(_ s: [Character]) -> String {
        var out = ""
        var i = 0
        let n = s.count

        while i < n {
            let c = s[i]
            switch c {
            case "\\":
                if i + 1 < n, s[i + 1] == "\n" {
                    out += "<br>\n"
                    i += 2
                } else if i + 1 < n, s[i + 1].isASCII, s[i + 1].isPunctuation || s[i + 1].isSymbol {
                    out += Self.escape(String(s[i + 1]))
                    i += 2
                } else {
                    out += "\\"
                    i += 1
                }

            case "`":
                let run = Self.runLength(s, at: i, of: "`")
                if let close = Self.findBacktickRun(s, from: i + run, length: run) {
                    var code = String(s[(i + run)..<close]).replacingOccurrences(of: "\n", with: " ")
                    if code.count >= 2, code.hasPrefix(" "), code.hasSuffix(" "), code.contains(where: { $0 != " " }) {
                        code = String(code.dropFirst().dropLast())
                    }
                    out += "<code>\(Self.escape(code))</code>"
                    i = close + run
                } else {
                    out += String(repeating: "`", count: run)
                    i += run
                }

            case "!" where i + 1 < n && s[i + 1] == "[":
                if let (html, next) = parseLink(s, at: i + 1, image: true) {
                    out += html
                    i = next
                } else {
                    out += "!"
                    i += 1
                }

            case "[":
                if let (html, next) = parseLink(s, at: i, image: false) {
                    out += html
                    i = next
                } else {
                    out += "["
                    i += 1
                }

            case "<":
                if let close = s[i...].firstIndex(of: ">") {
                    let inner = String(s[(i + 1)..<close])
                    if !inner.contains(" "), inner.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^<>]*$"#, options: .regularExpression) != nil {
                        out += "<a href=\"\(Self.escapeAttribute(inner))\">\(Self.escape(inner))</a>"
                        i = close + 1
                        continue
                    }
                    if inner.range(of: #"^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$"#, options: .regularExpression) != nil {
                        out += "<a href=\"mailto:\(Self.escapeAttribute(inner))\">\(Self.escape(inner))</a>"
                        i = close + 1
                        continue
                    }
                }
                out += "&lt;"
                i += 1

            case "*", "_", "~":
                if let (html, next) = parseEmphasis(s, at: i) {
                    out += html
                    i = next
                } else {
                    let run = Self.runLength(s, at: i, of: c)
                    out += String(repeating: c, count: run)
                    i += run
                }

            case "\n":
                // Two trailing spaces force a hard line break.
                if out.hasSuffix("  ") {
                    while out.hasSuffix(" ") { out.removeLast() }
                    out += "<br>\n"
                } else {
                    while out.hasSuffix(" ") { out.removeLast() }
                    out += "\n"
                }
                i += 1

            case "h" where i == 0 || s[i - 1].isWhitespace || s[i - 1] == "(":
                if let (html, next) = Self.parseBareURL(s, at: i) {
                    out += html
                    i = next
                } else {
                    out += "h"
                    i += 1
                }

            default:
                out += Self.escape(String(c))
                i += 1
            }
        }
        while out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    private static func runLength(_ s: [Character], at i: Int, of c: Character) -> Int {
        var j = i
        while j < s.count && s[j] == c { j += 1 }
        return j - i
    }

    private static func findBacktickRun(_ s: [Character], from start: Int, length: Int) -> Int? {
        var j = start
        while j < s.count {
            if s[j] == "`" {
                let run = runLength(s, at: j, of: "`")
                if run == length { return j }
                j += run
            } else {
                j += 1
            }
        }
        return nil
    }

    private func parseEmphasis(_ s: [Character], at i: Int) -> (String, Int)? {
        let c = s[i]
        let n = s.count
        let run = Self.runLength(s, at: i, of: c)

        let candidates: [(Int, String, String)]
        switch c {
        case "~":
            guard run == 2 || run == 1 else { return nil }
            candidates = [(run, "<del>", "</del>")]
        default:
            switch run {
            case 1: candidates = [(1, "<em>", "</em>")]
            case 2: candidates = [(2, "<strong>", "</strong>")]
            default: candidates = [(3, "<em><strong>", "</strong></em>"), (2, "<strong>", "</strong>"), (1, "<em>", "</em>")]
            }
        }

        for (length, open, close) in candidates {
            let contentStart = i + length
            guard contentStart < n, !s[contentStart].isWhitespace else { continue }
            // "_" must not open inside a word.
            if c == "_", i > 0, s[i - 1].isLetter || s[i - 1].isNumber { return nil }

            var j = contentStart
            while j < n {
                if s[j] == "`" {
                    // Skip over code spans so their contents can't close emphasis.
                    let r = Self.runLength(s, at: j, of: "`")
                    if let end = Self.findBacktickRun(s, from: j + r, length: r) { j = end + r; continue }
                    j += r
                    continue
                }
                if s[j] == "\\" { j += 2; continue }
                if s[j] == c {
                    let closeRun = Self.runLength(s, at: j, of: c)
                    let precededBySpace = s[j - 1].isWhitespace
                    // A run after whitespace opens nested emphasis; skip past it as a unit.
                    if precededBySpace, j + closeRun < n, !s[j + closeRun].isWhitespace,
                       let (_, end) = parseEmphasis(s, at: j) {
                        j = end
                        continue
                    }
                    let followedByWord = c == "_" && j + closeRun < n && (s[j + closeRun].isLetter || s[j + closeRun].isNumber)
                    if closeRun >= length, !precededBySpace, !followedByWord {
                        let inner = Array(s[contentStart..<j])
                        return (open + renderInline(inner) + close, j + length)
                    }
                    j += closeRun
                    continue
                }
                j += 1
            }
        }
        return nil
    }

    private func parseLink(_ s: [Character], at i: Int, image: Bool) -> (String, Int)? {
        let n = s.count
        // Find the matching close bracket.
        var depth = 0
        var j = i
        var closeBracket: Int?
        while j < n {
            switch s[j] {
            case "\\": j += 1
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth == 0 { closeBracket = j }
            case "`":
                let r = Self.runLength(s, at: j, of: "`")
                if let end = Self.findBacktickRun(s, from: j + r, length: r) { j = end + r - 1 } else { j += r - 1 }
            default: break
            }
            if closeBracket != nil { break }
            j += 1
        }
        guard let close = closeBracket else { return nil }
        let label = Array(s[(i + 1)..<close])

        var url: String
        var title: String?
        var next: Int

        if close + 1 < n, s[close + 1] == "(" {
            // Inline link: [text](url "title")
            var parens = 0
            var k = close + 1
            var end: Int?
            while k < n {
                if s[k] == "\\" { k += 2; continue }
                if s[k] == "(" { parens += 1 }
                if s[k] == ")" {
                    parens -= 1
                    if parens == 0 { end = k; break }
                }
                k += 1
            }
            guard let endParen = end else { return nil }
            let inside = String(s[(close + 2)..<endParen]).trimmingCharacters(in: .whitespacesAndNewlines)
            (url, title) = Self.splitDestination(inside)
            next = endParen + 1
        } else {
            // Reference link: [text][ref], [text][], or [text]
            var refLabel = String(label)
            next = close + 1
            if close + 1 < n, s[close + 1] == "[", let refClose = s[(close + 2)...].firstIndex(of: "]") {
                let explicit = String(s[(close + 2)..<refClose])
                if !explicit.isEmpty { refLabel = explicit }
                next = refClose + 1
            }
            guard let ref = references[Self.referenceKey(refLabel)] else { return nil }
            url = ref.url
            title = ref.title
        }

        let titleAttr = title.map { " title=\"\(Self.escapeAttribute($0))\"" } ?? ""
        if image {
            return ("<img src=\"\(Self.escapeAttribute(url))\" alt=\"\(Self.escapeAttribute(Self.plainText(label)))\"\(titleAttr)>", next)
        }
        return ("<a href=\"\(Self.escapeAttribute(url))\"\(titleAttr)>\(renderInline(label))</a>", next)
    }

    private static func splitDestination(_ inside: String) -> (String, String?) {
        var url = inside
        var title: String?
        if inside.hasPrefix("<"), let end = inside.firstIndex(of: ">") {
            url = String(inside[inside.index(after: inside.startIndex)..<end])
            let rest = inside[inside.index(after: end)...].trimmingCharacters(in: .whitespaces)
            title = unquote(rest)
        } else if let space = inside.firstIndex(where: \.isWhitespace) {
            url = String(inside[..<space])
            title = unquote(inside[space...].trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return (url, title)
    }

    private static func unquote(_ text: String) -> String? {
        guard text.count >= 2, let first = text.first, let last = text.last else { return nil }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") || (first == "(" && last == ")") {
            return String(text.dropFirst().dropLast())
        }
        return nil
    }

    private static func parseBareURL(_ s: [Character], at i: Int) -> (String, Int)? {
        let prefix = String(s[i..<min(i + 8, s.count)])
        guard prefix.hasPrefix("http://") || prefix.hasPrefix("https://") else { return nil }
        var j = i
        while j < s.count, !s[j].isWhitespace, s[j] != "<" { j += 1 }
        var url = String(s[i..<j])
        while let last = url.last, ".,;:!?*_~'\"".contains(last) || (last == ")" && url.filter({ $0 == "(" }).count < url.filter({ $0 == ")" }).count) {
            url.removeLast()
            j -= 1
        }
        guard url.count > (url.hasPrefix("https") ? 8 : 7) else { return nil }
        return ("<a href=\"\(escapeAttribute(url))\">\(escape(url))</a>", j)
    }

    // MARK: - Helpers

    private static func plainText(_ chars: [Character]) -> String {
        String(chars).replacingOccurrences(of: #"[*_`~\[\]]|\]\([^)]*\)"#, with: "", options: .regularExpression)
    }

    static func slug(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: #"\]\([^)]*\)"#, with: "", options: .regularExpression)
        var slug = ""
        for char in plain.lowercased() {
            if char.isLetter || char.isNumber || char == "-" || char == "_" {
                slug.append(char)
            } else if char == " " {
                slug.append("-")
            }
        }
        return escapeAttribute(slug)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for char in text {
            switch char {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(char)
            }
        }
        return out
    }

    static func escapeAttribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
