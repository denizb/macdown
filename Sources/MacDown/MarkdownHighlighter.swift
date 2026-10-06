import AppKit

/// Lightweight regex-based syntax highlighting for the editor.
///
/// Every color is a dynamic system color, so highlighting adapts to light/dark
/// mode, Increase Contrast and the user's accent color without re-highlighting.
@MainActor
struct MarkdownHighlighter {
    var baseFont: NSFont

    private struct Rule {
        let regex: NSRegularExpression
        let apply: (NSTextStorage, NSTextCheckingResult, NSFont) -> Void
    }

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = [.anchorsMatchLines]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let syntaxColor = NSColor.tertiaryLabelColor
    private static let accent = NSColor.controlAccentColor

    private static let rules: [Rule] = [
        // Headings: bold text, faded hashes.
        Rule(regex: regex(#"^(#{1,6})[ \t]+.*$"#)) { storage, match, font in
            storage.addAttribute(.font, value: font.withWeight(.bold), range: match.range)
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: 1))
        },
        // Setext heading underlines.
        Rule(regex: regex(#"^(?:=+|-+)[ \t]*$"#)) { storage, match, _ in
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)
        },
        // Bold.
        Rule(regex: regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)) { storage, match, font in
            storage.addAttribute(.font, value: font.withWeight(.bold), range: match.range)
            fadeDelimiters(storage, match, length: 2)
        },
        // Italic.
        Rule(regex: regex(#"(?<![\*\w])(\*|_)(?=[^\s\*_])(.+?)(?<=[^\s\*_])\1(?![\*\w])"#)) { storage, match, font in
            storage.addAttribute(.font, value: font.withTraits(.italicFontMask), range: match.range)
            fadeDelimiters(storage, match, length: 1)
        },
        // Strikethrough.
        Rule(regex: regex(#"~~(?=\S)(.+?)(?<=\S)~~"#)) { storage, match, _ in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        },
        // Links and images: [text](url)
        Rule(regex: regex(#"(!?\[)([^\]\n]*)(\]\()([^)\n]*)(\))"#)) { storage, match, _ in
            storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 2))
            for group in [1, 3, 5] { storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range(at: group)) }
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 4))
        },
        // Bare URLs and autolinks.
        Rule(regex: regex(#"<?https?://[^\s>)]+>?"#)) { storage, match, _ in
            storage.addAttribute(.foregroundColor, value: accent, range: match.range)
        },
        // List markers and task boxes.
        Rule(regex: regex(#"^[ \t]*(?:[-*+]|\d+[.)])(?=[ \t])(?:[ \t]+\[[ xX]\])?"#)) { storage, match, font in
            storage.addAttribute(.foregroundColor, value: accent, range: match.range)
            storage.addAttribute(.font, value: font.withWeight(.semibold), range: match.range)
        },
        // Blockquotes.
        Rule(regex: regex(#"^[ \t]*>.*$"#)) { storage, match, _ in
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
        },
        // Horizontal rules.
        Rule(regex: regex(#"^[ \t]*(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$"#)) { storage, match, _ in
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: match.range)
        },
        // Inline code (applied late so it overrides emphasis inside code).
        Rule(regex: regex(#"(`+)(?!`)(.+?)(?<!`)\1(?!`)"#)) { storage, match, font in
            storage.addAttributes(codeAttributes(font), range: match.range)
        },
        // Fenced code blocks (last, so nothing inside them is styled).
        Rule(regex: regex(#"^[ \t]*(```|~~~)[^\n]*\n[\s\S]*?(?:^[ \t]*\1[ \t]*$|\z)"#)) { storage, match, font in
            storage.removeAttribute(.strikethroughStyle, range: match.range)
            storage.addAttributes(codeAttributes(font), range: match.range)
        },
    ]

    private static func fadeDelimiters(_ storage: NSTextStorage, _ match: NSTextCheckingResult, length: Int) {
        let r = match.range
        storage.addAttribute(.foregroundColor, value: syntaxColor, range: NSRange(location: r.location, length: length))
        storage.addAttribute(.foregroundColor, value: syntaxColor, range: NSRange(location: NSMaxRange(r) - length, length: length))
    }

    private static func codeAttributes(_ font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular),
            .foregroundColor: NSColor.systemPink,
            .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.08),
        ]
    }

    func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: Self.paragraphStyle,
        ], range: full)
        for rule in Self.rules {
            rule.regex.enumerateMatches(in: storage.string, range: full) { match, _, _ in
                if let match { rule.apply(storage, match, baseFont) }
            }
        }
        storage.endEditing()
    }

    private static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        return style
    }()
}

extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        if isFixedPitch {
            return .monospacedSystemFont(ofSize: pointSize, weight: weight)
        }
        return .systemFont(ofSize: pointSize, weight: weight)
    }

    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: traits)
    }
}
