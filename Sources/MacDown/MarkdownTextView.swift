import AppKit

/// The editor's text view. Formatting commands are plain Objective-C actions so
/// menu items and toolbar buttons can reach whichever editor is first responder
/// through the responder chain, exactly like built-in AppKit commands.
final class MarkdownTextView: NSTextView {

    // MARK: Inline formatting

    @objc func toggleBold(_ sender: Any?) { toggleWrap("**") }
    @objc func toggleItalic(_ sender: Any?) { toggleWrap("*") }
    @objc func toggleStrikethrough(_ sender: Any?) { toggleWrap("~~") }
    @objc func toggleInlineCode(_ sender: Any?) { toggleWrap("`") }

    @objc func insertLink(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        let pasteboardURL = NSPasteboard.general.string(forType: .string)
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { $0.scheme == nil ? nil : $0 }

        if let url = pasteboardURL {
            // Link text from the selection, destination from the clipboard.
            let title = selected.isEmpty ? "link" : selected
            let replacement = "[\(title)](\(url.absoluteString))"
            replace(range, with: replacement, select: NSRange(location: range.location + 1, length: (title as NSString).length))
        } else {
            let title = selected.isEmpty ? "link" : selected
            let replacement = "[\(title)](url)"
            let urlLocation = range.location + (title as NSString).length + 3
            replace(range, with: replacement, select: NSRange(location: urlLocation, length: 3))
        }
    }

    // MARK: Block formatting

    @objc func makeHeading1(_ sender: Any?) { setLinePrefix("# ") }
    @objc func makeHeading2(_ sender: Any?) { setLinePrefix("## ") }
    @objc func makeHeading3(_ sender: Any?) { setLinePrefix("### ") }
    @objc func makeBody(_ sender: Any?) { setLinePrefix("") }
    @objc func toggleBulletList(_ sender: Any?) { toggleLinePrefix("- ") }
    @objc func toggleTaskList(_ sender: Any?) { toggleLinePrefix("- [ ] ") }
    @objc func toggleNumberedList(_ sender: Any?) { toggleLinePrefix("1. ") }
    @objc func toggleBlockquote(_ sender: Any?) { toggleLinePrefix("> ") }

    @objc func insertCodeBlock(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        let replacement = "```\n\(selected)\n```"
        replace(range, with: replacement, select: NSRange(location: range.location + 4, length: (selected as NSString).length))
    }

    // MARK: Smarter editing

    /// Pressing Return inside a list continues it; pressing it on an empty item ends the list.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let caret = selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        let line = ns.substring(with: NSRange(location: lineRange.location, length: caret.location - lineRange.location))

        guard caret.length == 0, let match = Self.listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            super.insertNewline(sender)
            return
        }

        let prefix = (line as NSString).substring(with: match.range)
        if match.range.length == (line as NSString).length {
            // Empty item: remove the marker instead of continuing the list.
            replace(NSRange(location: lineRange.location, length: match.range.length), with: "",
                    select: NSRange(location: lineRange.location, length: 0))
            return
        }

        var next = prefix
        if let number = Int(prefix.trimmingCharacters(in: .whitespaces).prefix(while: \.isNumber)) {
            next = prefix.replacingOccurrences(of: "\(number)", with: "\(number + 1)")
        }
        next = next.replacingOccurrences(of: "[x] ", with: "[ ] ").replacingOccurrences(of: "[X] ", with: "[ ] ")
        insertText("\n" + next, replacementRange: caret)
    }

    private static let listPrefix = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?|^\s*>\s?"#)

    // MARK: Helpers

    private func toggleWrap(_ marker: String) {
        let ns = string as NSString
        let range = selectedRange()
        let m = (marker as NSString).length

        // Markers just outside the selection: unwrap.
        if range.location >= m, NSMaxRange(range) + m <= ns.length,
           ns.substring(with: NSRange(location: range.location - m, length: m)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(range), length: m)) == marker {
            let outer = NSRange(location: range.location - m, length: range.length + 2 * m)
            replace(outer, with: ns.substring(with: range), select: NSRange(location: outer.location, length: range.length))
            return
        }

        // Markers inside the selection: unwrap.
        let selected = ns.substring(with: range)
        if range.length >= 2 * m, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(with: NSRange(location: m, length: range.length - 2 * m))
            replace(range, with: inner, select: NSRange(location: range.location, length: (inner as NSString).length))
            return
        }

        replace(range, with: marker + selected + marker, select: NSRange(location: range.location + m, length: range.length))
    }

    private func selectedLinesRange() -> NSRange {
        let ns = string as NSString
        var range = ns.lineRange(for: selectedRange())
        // Don't include the trailing newline in the edit.
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 0x0A {
            range.length -= 1
        }
        return range
    }

    private func toggleLinePrefix(_ prefix: String) {
        let range = selectedLinesRange()
        let lines = (string as NSString).substring(with: range).components(separatedBy: "\n")
        let allPrefixed = lines.allSatisfy { $0.hasPrefix(prefix) || $0.isEmpty }
        let updated = lines.enumerated().map { index, line -> String in
            if allPrefixed { return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line }
            if line.isEmpty && lines.count > 1 { return line }
            let numbered = prefix == "1. " ? "\(index + 1). " : prefix
            return numbered + Self.strippingBlockPrefix(line)
        }.joined(separator: "\n")
        replace(range, with: updated, select: NSRange(location: range.location, length: (updated as NSString).length))
    }

    private func setLinePrefix(_ prefix: String) {
        let range = selectedLinesRange()
        let lines = (string as NSString).substring(with: range).components(separatedBy: "\n")
        let updated = lines.map { line in
            line.isEmpty && lines.count > 1 ? line : prefix + Self.strippingHeading(line)
        }.joined(separator: "\n")
        replace(range, with: updated, select: NSRange(location: range.location + (updated as NSString).length, length: 0))
    }

    private static func strippingHeading(_ line: String) -> String {
        line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
    }

    private static func strippingBlockPrefix(_ line: String) -> String {
        line.replacingOccurrences(of: #"^(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s?)"#, with: "", options: .regularExpression)
    }

    /// Replaces text as a single undoable user edit.
    private func replace(_ range: NSRange, with replacement: String, select selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }
}
