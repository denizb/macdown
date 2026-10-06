import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum EditorFont: String, CaseIterable, Identifiable {
    case monospaced, system

    var id: Self { self }

    var title: String {
        switch self {
        case .monospaced: "SF Mono"
        case .system: "SF Pro"
        }
    }
}

enum PreviewFont: String, CaseIterable, Identifiable {
    case system, serif

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "SF Pro"
        case .serif: "New York"
        }
    }
}

/// Keys shared by `@AppStorage` across the app.
enum SettingsKey {
    static let appearance = "appearance"
    static let editorFont = "editorFont"
    static let editorFontSize = "editorFontSize"
    static let previewFont = "previewFont"
    static let previewFontSize = "previewFontSize"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.appearance) private var appearance: Appearance = .system
    @AppStorage(SettingsKey.editorFont) private var editorFont: EditorFont = .monospaced
    @AppStorage(SettingsKey.editorFontSize) private var editorFontSize = 14.0
    @AppStorage(SettingsKey.previewFont) private var previewFont: PreviewFont = .system
    @AppStorage(SettingsKey.previewFontSize) private var previewFontSize = 15.0

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Editor") {
                Picker("Font", selection: $editorFont) {
                    ForEach(EditorFont.allCases) { Text($0.title).tag($0) }
                }
                fontSizeRow(value: $editorFontSize)
            }

            Section("Preview") {
                Picker("Font", selection: $previewFont) {
                    ForEach(PreviewFont.allCases) { Text($0.title).tag($0) }
                }
                fontSizeRow(value: $previewFontSize)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
        .onChange(of: appearance) { _, newValue in newValue.apply() }
    }

    private func fontSizeRow(value: Binding<Double>) -> some View {
        LabeledContent("Size") {
            HStack {
                Text("\(Int(value.wrappedValue)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper("Size", value: value, in: 9...32, step: 1)
                    .labelsHidden()
            }
        }
    }
}
