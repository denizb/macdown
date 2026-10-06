# MacDown

A native macOS Markdown editor: SwiftUI `DocumentGroup` app with a highlighted editor and a live HTML preview. Swift Package, no Xcode project, no third-party dependencies.

## Build, test, run

- `swift build` / `swift test` — tests are Swift Testing (`@Test`), in `Tests/MacDownTests`.
- `scripts/build-app.sh [debug|release]` — builds `build/MacDown.app` (copies `Resources/Info.plist` + icon, ad-hoc signs).
- Launch: `open -a "$PWD/build/MacDown.app" some.md` (`open -a` needs an absolute path to the bundle).
- Quit: `osascript -e 'quit app "MacDown"'`.

## Layout (`Sources/MacDown`)

- `MacDownApp.swift` — app entry, `DocumentGroup`, `AppDelegate` (appearance, window tabbing, launch document).
- `MarkdownDocument.swift` — `ReferenceFileDocument` for `.md`.
- `ContentView.swift` — toolbar, view modes (editor / split / preview), word count.
- `EditorView.swift`, `MarkdownTextView.swift` — `NSTextView`-based editor; `MarkdownHighlighter.swift` styles it.
- `MarkdownRenderer.swift` — hand-written Markdown → HTML renderer (covered by tests).
- `PreviewView.swift` — `WKWebView` preview, `LocalFileSchemeHandler` serves images relative to the doc.
- `Commands.swift` — Format and View menu commands. `Settings.swift` — appearance/fonts, `SettingsKey`.

## Decisions

- **Minimum macOS is 15** (`Package.swift` and `LSMinimumSystemVersion` in `Info.plist` — keep them in sync). Agreed with the user, needed for `defaultLaunchBehavior`.
- **Liquid Glass needs the SDK stamp:** SwiftPM writes the deployment target (15.0) as the binary's SDK version, so macOS shows the pre-Tahoe look. `build-app.sh` re-stamps it with `vtool` to the real SDK before signing; check with `vtool -show-build`. Glass-only APIs (`ToolbarSpacer`, extending content under the toolbar) are gated with `#available(macOS 26, *)`.
- **Launch document:** `DocumentGroup` used to add a blank Untitled window on every launch, even on top of restored windows, so they piled up. Fixed with `.defaultLaunchBehavior(.suppressed)` plus `AppDelegate.applicationDidFinishLaunching`, which opens a new doc only on a default launch (`launchIsDefaultUserInfoKey`) when no documents were restored. `applicationShouldOpenUntitledFile` is never called by SwiftUI here — don't use it. Verified: fresh launch → 1 Untitled; relaunch with restored windows → count unchanged; fresh launch with a file → only that file.

## Testing the running app (GUI)

- `swift scripts/list-windows.swift` lists MacDown window IDs/titles; `screencapture -x -o -l <id> out.png` screenshots one. Needs Screen Recording permission for the host app (VS Code) — the user has granted it.
- `osascript` System Events / UI scripting does **not** work (no Accessibility permission), so you can't click or close windows programmatically.
- `--args -ApplePersistenceIgnoreState YES` simulates a fresh launch with no window restoration.
- In zsh, `log` is a builtin — use `/usr/bin/log show ...` for unified logs.
- Unsaved Untitled docs are autosaved and restored by macOS on every launch; that's normal, not a bug.
