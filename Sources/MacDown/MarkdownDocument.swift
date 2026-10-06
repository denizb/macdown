import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A reference-type document so the text view owns undo: NSTextView registers
/// its edits with the document's undo manager, which is also what marks the
/// document as edited (and drives autosave and Versions).
final class MarkdownDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    @Published var text: String

    init(text: String = "") {
        self.text = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let fallback = String(data: data, encoding: .macOSRoman) {
            text = fallback
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
