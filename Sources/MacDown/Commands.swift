import AppKit
import SwiftUI

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
}

/// Menu bar ▸ Format. Items reach the focused editor through the responder chain.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            item("Bold", #selector(MarkdownTextView.toggleBold(_:)), "b")
            item("Italic", #selector(MarkdownTextView.toggleItalic(_:)), "i")
            item("Strikethrough", #selector(MarkdownTextView.toggleStrikethrough(_:)), "x", [.command, .shift])
            item("Inline Code", #selector(MarkdownTextView.toggleInlineCode(_:)), "c", [.command, .option])
            item("Link", #selector(MarkdownTextView.insertLink(_:)), "k")

            Divider()

            item("Heading 1", #selector(MarkdownTextView.makeHeading1(_:)), "1", [.command, .option])
            item("Heading 2", #selector(MarkdownTextView.makeHeading2(_:)), "2", [.command, .option])
            item("Heading 3", #selector(MarkdownTextView.makeHeading3(_:)), "3", [.command, .option])
            item("Body Text", #selector(MarkdownTextView.makeBody(_:)), "0", [.command, .option])

            Divider()

            // Same shortcuts as Notes.
            item("Bulleted List", #selector(MarkdownTextView.toggleBulletList(_:)), "7", [.command, .shift])
            item("Numbered List", #selector(MarkdownTextView.toggleNumberedList(_:)), "9", [.command, .shift])
            item("Checklist", #selector(MarkdownTextView.toggleTaskList(_:)), "l", [.command, .shift])
            item("Quote", #selector(MarkdownTextView.toggleBlockquote(_:)), "'")
            item("Code Block", #selector(MarkdownTextView.insertCodeBlock(_:)), "c", [.command, .option, .shift])
        }
    }

    private func item(_ title: String, _ action: Selector, _ key: KeyEquivalent,
                      _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { NSApp.sendAction(action, to: nil, from: nil) }
            .keyboardShortcut(key, modifiers: modifiers)
    }
}

/// Menu bar ▸ View ▸ layout choices for the focused document window.
struct ViewModeCommands: Commands {
    @FocusedBinding(\.viewMode) private var mode

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, viewMode in
                Toggle(viewMode.title, isOn: Binding(
                    get: { mode == viewMode },
                    set: { if $0 { mode = viewMode } }
                ))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            .disabled(mode == nil)

            Divider()
        }
    }
}
