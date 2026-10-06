// Lists MacDown's on-screen windows as "<windowID> <title>". Usage: swift scripts/list-windows.swift
// Screenshot one with: screencapture -x -o -l <windowID> out.png  (needs Screen Recording permission)
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where w[kCGWindowOwnerName as String] as? String == "MacDown" && w[kCGWindowLayer as String] as? Int == 0 {
    print(w[kCGWindowNumber as String] ?? "?", w[kCGWindowName as String] as? String ?? "-")
}
