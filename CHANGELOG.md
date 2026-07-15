# Changelog

All notable changes to this project are documented in this file.

## [1.1.0] — Initial Intel port

### Added

- Intel (x86_64) build of 7ZIP4MAC, forked from the Apple Silicon
  [7ZIP4MAC](https://github.com/jensyleo/7ZIP4MAC) project. `ARCHS`/`VALID_ARCHS`
  pinned to `x86_64` — this is not a universal binary.
- `CompatUnavailableView`, a macOS 13-compatible stand-in for SwiftUI's
  `ContentUnavailableView` (macOS 14+ only).
- Hand-rolled trailing inspector panel (`HStack` + `Divider`) replacing the
  macOS 14+ `.inspector(isPresented:content:)` modifier, including explicit
  window-resize logic so the panel actually gets room to render.
- Single-window app scene (`Window`, not `WindowGroup`): opening a file from
  Finder while the app is already running routes to the existing window
  instead of spawning a duplicate.
- `NSApplicationDelegate`-based file-open bridge (`application(_:open:)`),
  needed because a single `Window` scene doesn't reliably deliver
  `.onOpenURL` document-open events on macOS 13's SwiftUI runtime.
- Uninstaller now restores each associated file format to its original
  default handler (`AppSettings.originalHandlerPaths`,
  `FileAssociationService.restoreOriginals`) instead of leaving the
  assignment dangling on a deleted app.
- "Associate Recommended Files…" button and a one-time first-launch nudge to
  Settings ▸ File Types.

### Changed

- Deployment target: macOS 13.0 (down from the Apple Silicon fork's macOS 26).
- Swift language mode: 5.0 (down from Swift 6.0 / strict concurrency).
- `@Observable`-macro view models (`ArchiveViewModel`, `CompressionViewModel`,
  `BenchmarkViewModel`, `AppSettings`, `ProfileStore`, `RecentsStore`) ported
  to `ObservableObject` + `@Published`, matching macOS 13's SwiftUI runtime.
- App entry point's top-level state containers switched to `@StateObject`
  (were incorrectly `@State`, which doesn't subscribe to `objectWillChange`).
- Test suite ported from Swift Testing to XCTest for broader toolchain
  compatibility.

### Fixed

- Inspector panel not rendering: the window never grew to accommodate it,
  so it was silently clipped instead of appearing.
- File-type associations not actually registering with LaunchServices:
  toggles in Settings ▸ File Types showed "on" by default, which was
  mistaken for "already associated," even though nothing had been submitted
  to `NSWorkspace.setDefaultApplication` yet.
