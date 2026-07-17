# Changelog

All notable changes to this project are documented in this file.

## [1.2.2] — Fix cold-launch file-open race (Intel-fork-specific)

### Fixed

- Opening a file from Finder while 7ZIP4MAC wasn't already running could
  silently fail to load it: AppKit's `application(_:open:)` delegate
  callback can fire before SwiftUI's `.onAppear` has wired up the handler,
  a race introduced when the main scene changed from `WindowGroup` to a
  single `Window` (v1.1.0's duplicate-window fix, since `Window` doesn't
  reliably route `.onOpenURL` on macOS 13). `AppDelegate` now buffers
  incoming URLs until a handler is set, then flushes them immediately.
  Verified with 5 consecutive cold launches (previously intermittent).

This fix has no counterpart in the upstream Apple Silicon
[7ZIP4MAC](https://github.com/jensyleo/7ZIP4MAC) — it doesn't use a single
`Window` scene, so this race doesn't exist there.

## [1.2.1] — Extraction completion dialog reports the overwrite policy

### Fixed

- The "Extraction Complete" dialog now always appears (even if the
  completion-dialog setting is off) whenever the overwrite policy isn't
  Overwrite, and its message states exactly what happened: which existing
  files were left untouched (Skip), or that the newly extracted file was
  renamed instead (Rename Extracted File). The underlying extraction was
  already correct; the dialog just never surfaced it.

### Documented

- README: overwrite policy, "Associate Recommended Files…" button,
  multi-file Quick Look, and a known limitation — dragging more than one
  selected entry to Finder only carries a single file (`SwiftUI.Table` has
  no built-in multi-item drag bundling, unlike `List`). Left for a future
  version.

## [1.2.0] — Overwrite policy + multi-file Quick Look

### Added

- Extraction overwrite policy is now configurable (Settings ▸ General):
  Overwrite, Skip, or Rename Extracted File.
- Quick Look (Space) now previews every selected file, not just the first,
  with the standard arrow-through-items navigation.
- README: added a Roadmap section (Sparkle auto-update, Spotlight indexing,
  Finder Sync extension — deferred, not active work).

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
