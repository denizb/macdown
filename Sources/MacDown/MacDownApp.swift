import AppKit
import SwiftUI

@main
struct MacDownApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            FormatCommands()
            ViewModeCommands()
        }
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        let stored = UserDefaults.standard.string(forKey: SettingsKey.appearance)
        (stored.flatMap(Appearance.init(rawValue:)) ?? .system).apply()
        // Use native window tabs for documents (Window ▸ Merge All Windows, etc.).
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    // The scene's own launch document is suppressed (it was added even on top of restored
    // windows), so open one here only when nothing was restored or opened.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // False when launched to open files; those documents arrive after this call.
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        guard isDefaultLaunch else { return }
        DispatchQueue.main.async {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.newDocument(nil)
            }
        }
    }
}

