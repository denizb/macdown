import AppKit
import SwiftUI

struct EditorView: NSViewRepresentable {
    @ObservedObject var document: MarkdownDocument
    var font: NSFont
    var onScroll: (Double) -> Void = { _ in }

    @Environment(\.undoManager) private var undoManager

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Markdown editor")

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        context.coordinator.textView = textView
        context.coordinator.highlighter = MarkdownHighlighter(baseFont: font)
        context.coordinator.undoManager = undoManager
        context.coordinator.onScroll = onScroll
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        textView.string = document.text
        context.coordinator.rehighlight()

        // Focus the editor when a new window opens.
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.undoManager = undoManager
        coordinator.onScroll = onScroll
        guard let textView = coordinator.textView else { return }

        var needsHighlight = false
        if coordinator.highlighter?.baseFont != font {
            coordinator.highlighter = MarkdownHighlighter(baseFont: font)
            needsHighlight = true
        }
        // Only push text in when it changed outside the editor (e.g. Revert To ▸).
        if textView.string != document.text {
            let selection = textView.selectedRanges
            textView.string = document.text
            textView.selectedRanges = selection.filter { NSMaxRange($0.rangeValue) <= (document.text as NSString).length }
            needsHighlight = true
        }
        if needsHighlight { coordinator.rehighlight() }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let document: MarkdownDocument
        weak var textView: MarkdownTextView?
        var highlighter: MarkdownHighlighter?
        var undoManager: UndoManager?
        var onScroll: (Double) -> Void = { _ in }

        init(document: MarkdownDocument) {
            self.document = document
        }

        func rehighlight() {
            guard let textView, let storage = textView.textStorage, let highlighter else { return }
            highlighter.highlight(storage)
            textView.typingAttributes = [
                .font: highlighter.baseFont,
                .foregroundColor: NSColor.textColor,
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            rehighlight()
            document.text = textView.string
        }

        /// Route the text view's undo through the document so edits mark it dirty.
        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        @objc func boundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let documentHeight = clipView.documentView?.frame.height else { return }
            let scrollable = documentHeight - clipView.bounds.height
            onScroll(scrollable > 0 ? min(max(clipView.bounds.minY / scrollable, 0), 1) : 0)
        }
    }
}
