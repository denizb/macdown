import AppKit
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case editor, split, preview

    var id: Self { self }

    var title: String {
        switch self {
        case .editor: "Editor Only"
        case .split: "Editor and Preview"
        case .preview: "Preview Only"
        }
    }

    var symbol: String {
        switch self {
        case .editor: "doc.plaintext"
        case .split: "rectangle.split.2x1"
        case .preview: "eye"
        }
    }

    /// The mode a newly opened window starts in, from Settings.
    static func initial(for fileURL: URL?) -> ViewMode {
        let preferred = UserDefaults.standard.string(forKey: SettingsKey.defaultViewMode)
            .flatMap(ViewMode.init(rawValue:)) ?? .preview
        // A blank new document has nothing to preview yet.
        return fileURL == nil && preferred == .preview ? .editor : preferred
    }
}

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    var fileURL: URL?

    // Empty until the window first appears, then pinned so a restored window keeps its
    // mode and saving a new document (which sets fileURL) doesn't change it.
    @SceneStorage("viewMode") private var storedMode = ""
    @SceneStorage("splitFraction") private var splitFraction = 0.5
    @State private var editorScroll = 0.0

    @AppStorage(SettingsKey.editorFont) private var editorFont: EditorFont = .monospaced
    @AppStorage(SettingsKey.editorFontSize) private var editorFontSize = 14.0
    @AppStorage(SettingsKey.previewFont) private var previewFont: PreviewFont = .system
    @AppStorage(SettingsKey.previewFontSize) private var previewFontSize = 15.0

    private var mode: ViewMode {
        ViewMode(rawValue: storedMode) ?? .initial(for: fileURL)
    }

    private var modeBinding: Binding<ViewMode> {
        Binding(get: { mode }, set: { storedMode = $0.rawValue })
    }

    var body: some View {
        GeometryReader { proxy in
            let editorWidth = width(of: proxy.size.width)
            // The editor stays in the hierarchy in every mode so its text view (and
            // undo history) survives layout switches; it just collapses to zero width.
            HStack(spacing: 0) {
                EditorView(document: document, font: font, onScroll: { editorScroll = $0 })
                    .frame(width: editorWidth)
                    .opacity(mode == .preview ? 0 : 1)
                    .allowsHitTesting(mode != .preview)
                    .accessibilityHidden(mode == .preview)

                if mode != .editor {
                    if mode == .split {
                        SplitDivider(fraction: $splitFraction, totalWidth: proxy.size.width)
                    }
                    PreviewView(
                        markdown: document.text,
                        baseDirectory: fileURL?.deletingLastPathComponent(),
                        fontFamily: previewFont,
                        fontSize: previewFontSize,
                        scrollFraction: mode == .split ? editorScroll : nil
                    )
                }
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .navigationSubtitle(stats)
        .focusedSceneValue(\.viewMode, modeBinding)
        .toolbar { toolbar }
        .onAppear {
            if storedMode.isEmpty { storedMode = mode.rawValue }
        }
        .onChange(of: mode) { _, newMode in
            if newMode == .preview {
                // Don't leave keyboard focus in the hidden editor.
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private func width(of total: CGFloat) -> CGFloat {
        switch mode {
        case .editor: total
        case .preview: 0
        case .split: max(200, min(total - 200, (total * splitFraction).rounded()))
        }
    }

    private var font: NSFont {
        switch editorFont {
        case .monospaced: .monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
        case .system: .systemFont(ofSize: editorFontSize)
        }
    }

    private var stats: String {
        let text = document.text
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let minutes = max(1, Int((Double(words) / 230).rounded()))
        return words == 0 ? "Empty" : "\(words.formatted()) words · \(minutes) min read"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            ControlGroup {
                FormatButton("Bold", symbol: "bold", action: #selector(MarkdownTextView.toggleBold(_:)))
                FormatButton("Italic", symbol: "italic", action: #selector(MarkdownTextView.toggleItalic(_:)))
                FormatButton("Strikethrough", symbol: "strikethrough", action: #selector(MarkdownTextView.toggleStrikethrough(_:)))
            } label: {
                Label("Text Style", systemImage: "textformat")
            }
            .disabled(mode == .preview)

            Menu {
                FormatButton("Heading 1", symbol: "1.square", action: #selector(MarkdownTextView.makeHeading1(_:)))
                FormatButton("Heading 2", symbol: "2.square", action: #selector(MarkdownTextView.makeHeading2(_:)))
                FormatButton("Heading 3", symbol: "3.square", action: #selector(MarkdownTextView.makeHeading3(_:)))
                Divider()
                FormatButton("Bulleted List", symbol: "list.bullet", action: #selector(MarkdownTextView.toggleBulletList(_:)))
                FormatButton("Numbered List", symbol: "list.number", action: #selector(MarkdownTextView.toggleNumberedList(_:)))
                FormatButton("Checklist", symbol: "checklist", action: #selector(MarkdownTextView.toggleTaskList(_:)))
                Divider()
                FormatButton("Quote", symbol: "text.quote", action: #selector(MarkdownTextView.toggleBlockquote(_:)))
                FormatButton("Code Block", symbol: "curlybraces", action: #selector(MarkdownTextView.insertCodeBlock(_:)))
                FormatButton("Link", symbol: "link", action: #selector(MarkdownTextView.insertLink(_:)))
            } label: {
                Label("Insert", systemImage: "list.bullet.indent")
            }
            .disabled(mode == .preview)
        }

        ToolbarItem {
            Picker("Layout", selection: modeBinding) {
                ForEach(ViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Choose what the window shows")
        }

        if let fileURL {
            ToolbarItem {
                ShareLink(item: fileURL)
            }
        }
    }
}

/// A toolbar/menu button that sends a formatting action to the focused editor.
struct FormatButton: View {
    let title: String
    let symbol: String
    let action: Selector

    init(_ title: String, symbol: String, action: Selector) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button {
            NSApp.sendAction(action, to: nil, from: nil)
        } label: {
            Label(title, systemImage: symbol)
        }
        .help(title)
    }
}

/// A thin, native-looking divider that can be dragged to resize the panes.
struct SplitDivider: View {
    @Binding var fraction: Double
    let totalWidth: CGFloat
    @State private var startFraction: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startFraction ?? fraction
                                startFraction = start
                                fraction = min(0.85, max(0.15, start + value.translation.width / max(totalWidth, 1)))
                            }
                            .onEnded { _ in startFraction = nil }
                    )
                    .onTapGesture(count: 2) { fraction = 0.5 }
            }
            .accessibilityHidden(true)
    }
}
