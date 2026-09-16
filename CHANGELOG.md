# Changelog

All notable changes to this project are documented in this file.

## [1.4.7] — Security fixes, selection navigation, UI polish

### Fixed

- **Security: path-traversal in drag-out and in-archive Copy.** `DragOut.extract`
  (drag an entry out to Finder) and `ArchiveViewModel.copyEntry` (in-archive
  Copy) rebuilt the extracted item's filesystem path from an untrusted entry
  name read out of the opened archive. A crafted entry name like
  `../../../../Users/me/.ssh/id_rsa` made that path resolve outside the
  scratch directory to a real file on disk, which the drag/copy then *moved* —
  silently relocating or exfiltrating an arbitrary file just by dragging an
  entry out or duplicating it within the archive. Both now discover the real
  extracted item via `contentsOfDirectory(at:)`, the same safe pattern
  `ArchiveService`'s tar-unwrap already used, instead of trusting the name.
- **Security: path-traversal in Shortcuts intents.** `CompressFilesIntent`
  and `ExtractArchiveIntent` built file paths directly from
  Shortcuts-supplied `IntentFile.filename`, with the same traversal risk as
  above — a crafted Shortcut could write outside the scratch directory. Now
  sanitized with `lastPathComponent` before use.
- **Arrow-key navigation in the file list:** Up/Down move the selection one
  row at a time (Shift extends a contiguous range), Right enters the
  selected folder, Left goes up a level — matching Finder/Explorer.
  Cmd-Shift-Up/Down extends the selection to the first/last row (Finder's
  own shortcut). Fixed a bug where repeated Shift-arrow presses re-selected
  just the same two rows instead of growing the range, and another where
  Cmd-clicking a row to add it to an existing selection got wiped out by a
  later Shift/Cmd-Shift range extension. The ".." parent-link row is now
  excluded from all keyboard-driven selection.
- **Tiny click area on short row names** (".." to go up in particular): the
  whole row is now clickable, not just the drawn icon+text.
- **".." now acts on a single click** instead of requiring a double-click,
  matching how it reads visually (a lone back-arrow control, not a row you
  select-then-activate).
- **Toolbar icon flicker:** disabled toolbar icons no longer intermittently
  flash full-brightness "enabled" artwork — the dimmed look is now baked
  into a static bitmap instead of relying on `NSToolbarItem`'s own dynamic
  (and unreliable) disabled-state rendering. Toolbar icons enlarged
  (pointSize 19) per feedback. Fixed a smaller race in the toolbar host
  view that could briefly apply a stale action snapshot.

### Not ported

- The base's "icon flicker on hover" fix (pre-resizing `NSWorkspace`
  file-type icons to 16×16 at cache time) reproducibly **crashed the app**
  on this target — confirmed via crash log (`objc_exception_throw` deep
  inside `-[NSImage drawInRect:...]`) with both the legacy
  `lockFocus()`/`unlockFocus()` approach and the modern
  `NSImage(size:flipped:drawingHandler:)` alternative. Reverted to caching
  the unmodified icon (pre-fix behavior) — the hover flicker is cosmetic,
  not worth risking a crash to fix. The dead-code cleanup and file-existence
  dedup refactors from the same base commits were skipped as low-value,
  higher-risk-to-port-faithfully changes with no functional benefit.

Ported from base commits `1fe56fe`, `fb6778a`, `6b2579f`, `8be0427`,
`0cd0f50`, `63a8c54`, `7a4a042`, `716179c`, `efa9b99` (final consolidated
state of each touched file, not each incremental commit). 46/46 SevenZipKit
tests pass. Verified on real hardware: no crashes across repeated opens of
a small `.zip`, a `.zip` with 500 entries, and a 2.7 GB `.iso` with 1,810
entries.

## [1.4.6] — Fix .tar.bz2/.tar.gz/.tar.xz showing empty, argument injection fix

### Fixed

- **`.tar.bz2`/`.tar.gz`/`.tar.xz` no longer show empty on open.** bzip2/gzip/xz
  are single-stream compressors with no entry list of their own — 7-Zip
  reported zero (or, for gzip, exactly one unopenable) entries for the
  compressed stream itself, instead of the real `.tar` contents inside it.
  Opening the archive now transparently extracts that stream to a staging
  directory and lists whatever comes out, recursing if that's itself another
  single-stream layer. `Archive` gains `effectiveURL` (what list/extract/test
  actually read from) and `stagingDirectory` (cleaned up on close/reopen),
  while the file the user opened stays `url` for display. Extract and Test
  now read from `effectiveURL`; Delete/Move are disabled for these archives
  (nothing sensible to write back into). Quick Look and drag-to-Finder are
  adapted for this fork's single-window architecture: `effectiveArchiveURL`
  is read directly from the one `ArchiveViewModel` at the call site, rather
  than through the base's multi-window `OpenArchiveWindowRegistry` (which
  this fork has no use for). Ported from base commits `34472f8` and `36802d8`.
  This is a real cost, not a regression: opening one of these archives now
  needs to decompress the whole stream first (proportional to its size)
  instead of failing instantly with an empty listing — the same trade-off
  the base made.
- **Argument injection via entry names starting with `-`:** an archive entry
  named e.g. `-weird.txt` could be misread by `7zz` as a flag instead of a
  file name. Every command that appends user/archive-controlled paths
  (extract/test/delete/rename/compress) now inserts `--` (end-of-options
  marker) first.
- **`AutomationService.compress`** (Shortcuts/AppleScript) no longer silently
  falls back to `.7z` for an unrecognized destination extension — it now
  throws a clear error, matching the fix already applied to the in-app
  Add/Copy path.

Ported from base commit `f5dd085` (security-relevant parts only — the dead
code cleanup/refactor parts of that commit were skipped as non-functional).
Verified: 46/46 SevenZipKit tests pass; confirmed programmatically that a
real `.tar.gz` and `.tar.bz2` now list their true contents (6 entries)
instead of 1; verified on real hardware that Delete/Move show a clear
message instead of crashing on an unwrapped archive.

## [1.4.5] — Comprehensive Help menu

### Added

- **Help ▸ 7ZIP4MAC Help** now opens a full help window with a searchable
  sidebar of 10 topics (What it does, Keyboard Shortcuts, Opening/Browsing,
  Extracting, Creating, Editing, Passwords, Testing, Toolbar, Settings),
  replacing the old single-alert summary. Search filters topics and their
  content in real time, matching the Finder-style help experience. Ported
  from base commits `874ed9e` and `1675947` (`HelpTopic.swift` for content,
  `HelpView.swift` for the searchable `NavigationSplitView` UI, plus a new
  `Window("7ZIP4MAC Help", id: "help")` scene).
- Adapted `ContentUnavailableView` (macOS 14+) usages to this project's own
  `CompatUnavailableView`, keeping the Help window compatible with macOS 13.

## [1.4.4] — Security and stability fixes

### Fixed

- **Quick Look array bounds checking:** prevent out-of-bounds crash when
  `QLPreviewPanel` calls `previewItemAt(index:)` with a concurrent selection
  change that narrows the item list. Now returns `nil` safely if the index is
  out of bounds.
- **Drag staging sweep race condition:** increase the stale-folder age threshold
  from 1 hour to 24 hours. A short threshold caused drags to be interrupted and
  orphaned folders deleted on app restart if they were still in progress or
  buffering (Finder doesn't signal completion). 24 hours is safe for the
  intended use (cleanup of old staging data).
- **Archive path validation:** reject paths containing null bytes (`\0`). While
  7-Zip output should never produce them, malformed or corrupted archives could,
  and allowing them could cause unexpected behavior downstream.

## [1.4.3] — Toolbar customization, Benchmark Close button

### Added

- **Toolbar customization:** right-click the toolbar to open "Customize Toolbar…" and
  reorder/hide buttons; the layout is persisted per window. Symbol images are cached
  to avoid rebuilding them on every render (selection change, folder nav, extraction
  progress tick). Persisted from `NSToolbarDelegate`'s real add/remove notifications
  only, not on every state change — this prevents one window's stale order from
  stomping another window's fresh reorder when two windows are open simultaneously.
  Implemented via a hand-built `NSToolbar` bridge (in `SevenZip4MACToolbar.swift`)
  instead of SwiftUI's `.toolbar(id:)`, which crashes on macOS 13 when a second
  window opens. Ported from base commits `f237a5b` and `ab94c6e` (toolbar
  customization via AppKit, code-review fixes for multi-window safety + image
  caching).
- **Close button in Benchmark results:** after running a benchmark and seeing the
  results, a "Close" button now appears to the right of "Run Again", allowing you
  to close the Benchmark window without using the window chrome close button.
  Ported from base commit `badd750` (adapted to use `NSApp.keyWindow?.close()`
  instead of `dismissWindow(id:)`, which is macOS 14+ only).

## [1.4.2] — Quick Look toggle/refresh, GNU tar display fix

### Fixed

- **Quick Look now toggles like Finder's:** pressing Space or ⌘Y while the
  panel is already open now closes it, instead of only ever reopening it.
  Clicking a different row while the panel is open refreshes the preview in
  place (previously the preview only updated when explicitly reopened).
  Deselecting everything, or narrowing the selection down to only folders,
  now closes the panel automatically instead of leaving a stale preview on
  screen. Ported from base commit `4a81b2e` (the toggle/refresh logic only —
  see below for what wasn't ported).
- **GNU tar archives no longer hide their top-level contents.** GNU tar
  prefixes every path with `./` and lists the archive root as a bare `.`;
  left as-is, that `.` became the first path component everywhere, which the
  hidden-file filter (anything starting with `.`) then hid — wiping out the
  entire top level of the file list for any `.tar` made with GNU tar. Fixed
  in `SevenZipKit`'s listing parser, which is shared, dependency-free code —
  ported directly from base commit `b4d4835` with no adaptation needed.
  Covered by a new unit test.

### Not ported: toolbar customization (would have introduced a crash)

Base commit `4a81b2e` also added `.toolbar(id:)` / `CustomizableToolbarContent`
support (right-click the toolbar → "Customize Toolbar…", with the layout
remembered). This fork initially ported it too, but the base's very next
commit (`af58846`) reverted it after finding a reproducible AppKit crash
(`EXC_BREAKPOINT` inside `NSToolbar`'s `_insertNewItemWithItemIdentifier:`)
that fires whenever a **second window** is created while a customizable
toolbar identifier is in use — exactly the situation this fork already has
with its separate Benchmark window (Tools ▸ Benchmark). The port was pulled
before publishing, matching the base's own revert. Verified on real Intel
hardware: opening the Benchmark window while an archive is open no longer
carries this risk, since the toolbar was never made customizable here.

## [1.4.1] — Fix silent name-collision bug in in-archive Rename/Move/Copy

### Fixed

- Renaming, moving, or copying an entry within an archive to a path that
  already existed there was accepted silently: the 7-Zip CLI's `rn` doesn't
  check for this itself, so it created a second entry under the same
  name instead of erroring — data still on disk, but orphaned under a name
  nothing lists as available (whichever entry 7-Zip happens to read first
  "wins"). `copyEntry` had the same gap in the other direction: it silently
  overwrote the existing entry rather than confirming first. Both now check
  for the collision up front and show "An item named "…" already exists
  here." instead of touching anything. Verified on real Intel hardware.
- Ported from base commit `08a4bbd` (the duplicate-name-collision part only —
  that commit's cross-archive drag and Rename-on-conflict UI depend on
  multi-window support, which this fork doesn't have; see below).

### Architectural note: Why this fork doesn't have multi-window

Multi-window support, cross-archive drag-and-drop, and the Rename-on-conflict dialog (base commits `7c72505` and `08a4bbd`) are **intentionally not ported**. This fork deliberately uses a single `Window` (not `WindowGroup`) with one shared `ArchiveViewModel`.

**Reason:** macOS 13 (Ventura) has a well-documented bug where `WindowGroup(for: URL?.self)` silently breaks `.onOpenURL` routing when the app is already running and the user double-clicks a file in Finder to open a second archive. The URL event is dropped (the window doesn't open) or a duplicate scaffold window briefly appears and is torn down.

**Evidence:** Confirmed via Apple Developer Forums (threads 727369, 750916, 730232) — this is not hypothetical or a single reporter's issue, but a macOS 13-specific SwiftUI routing bug with no Apple-published fix. Every developer who hit this on Ventura was forced to abandon `.onOpenURL` and implement `NSApplicationDelegate.application(_:open:)` manually (which is what this fork does via `AppDelegate.onOpenFiles`).

**Why porting multi-window would be risky here:** Adopting `WindowGroup(for: URL?.self)` on macOS 13 would rebuild the architecture on top of known-broken machinery, with zero documented evidence that anyone has successfully used that exact pattern on Ventura while avoiding the bug. The benefit of multi-window is nullified if the bug manifests during Finder file-open.

**For users on macOS 14+:** The upstream [7ZIP4MAC](https://github.com/jensyleo/7ZIP4MAC) has multi-window and targets later macOS where this bug is absent or fixed. This fork (7ZIP4MAC-INTEL) is purpose-built for Intel Macs + older macOS — single-window, proven-stable architecture, documented workaround for a real Ventura bug.

See the project memory file `windowgroup_macos13_decision.md` for full research details.

## [1.4.0] — Sync with base version: add Quick Look documentation

### Added

- Documented Quick Look preview for local builds. The feature was already
  present in the code but undocumented: developers can now compile
  7ZIP4MAC-INTEL locally with Quick Look support by adding their Apple ID to
  Xcode and updating the build script. Public releases remain main-app-only
  (no Quick Look bundled).

### Updated

- README: clarified that multi-item drag-out works (both `v1.3.3` and the base
  v1.4.0 support this — v1.3.3 fixed it via the AppKit `EntryDragTrigger`
  overlay; the base already had it). Noted that double-clicking an entry
  that's already part of a selection must be done on a solo entry first.
- Synced documentation with upstream [7ZIP4MAC](https://github.com/jensyleo/7ZIP4MAC)
  base version; macOS 13-specific notes and Intel-specific differences
  preserved.

## [1.3.3] — Fix Finder drag-out on macOS 13 (single and multi-item)

### Fixed

- Drag-out to Finder was fundamentally broken on this fork's macOS 13 target
  even before the v1.3.0 multi-item feature — SwiftUI's `Button` + `.onDrag`
  gesture recognizers conflict on this OS version, with `Button`'s press
  gesture almost always winning, so the drag gesture never started (reported:
  "no me permite arrastrar al Finder como la versión para procesadores M").
  Replaced `Button`/`.onDrag` as the interaction surface for every row with a
  custom AppKit-level trigger (`EntryDragTrigger`): an `NSViewRepresentable`
  overlay that disambiguates click vs. drag in `mouseDown` by tracking pointer
  movement against a threshold, then either runs the existing single-click /
  double-click handling or starts a real `NSDraggingSession` backed by
  `NSFilePromiseProvider` (the same mechanism used for multi-item drag
  upstream on Apple Silicon). Verified on real Intel hardware: click,
  ⌘-click, ⇧-click, and double-click selection/activation all still work, and
  both single- and multi-item drag-out to Finder now work.

## [1.3.2] — Revert multi-item drag-out (broke all drag-out on macOS 13)

### Fixed

- The v1.3.0 multi-item drag-out feature (`MultiItemDragTrigger`, a custom
  AppKit `NSFilePromiseProvider` + manual mouse-tracking overlay) broke
  drag-out to Finder entirely on macOS 13 — not just multi-selection, a
  single-item drag no longer started at all. Reported directly: "no me
  permite arrastrar al Finder como la versión para procesadores M."
  Reverted `FileListView.swift`/`DragOut.swift` to the pre-1.3.0 single-item
  `.onDrag` implementation (byte-identical, diffed against the last known-good
  commit) and deleted `MultiItemDragTrigger.swift`. Multi-item drag-out is a
  known limitation again (documented in the README) rather than a broken
  feature — revisiting it needs a macOS-13-specific approach, verified live
  on real hardware rather than guessed at from a sandbox that can't reliably
  simulate AppKit drag gestures.

## [1.3.1] — Fix file associations not taking effect on real Finder double-click

### Fixed

- Associating a format in Settings ▸ File Types looked successful (no
  error), but double-clicking a file of that type in Finder kept opening
  the previous default app (e.g. Archive Utility silently decompressing a
  `.zip` in place, with no visible window). `NSWorkspace.setDefaultApplication`
  only updates LaunchServices' Editor/Shell role bindings, never the "All"
  role a real Finder double-click consults. Now also calls
  `LSSetDefaultRoleHandlerForContentType(_:.all:_:)`. Verified end-to-end
  with a real double-click in Finder, before and after. Applied to
  `restoreOriginals()` too, so uninstalling correctly hands back the "All"
  role.
- **Confirmed this is a macOS-version behavior gap, not a code difference
  between forks**: diffed `FileAssociationService.swift` directly against
  the upstream Apple Silicon
  [7ZIP4MAC](https://github.com/jensyleo/7ZIP4MAC) — byte-identical, only
  calls `NSWorkspace`, no `LSSetDefaultRoleHandlerForContentType` — and
  that fork does not exhibit this bug on its newer macOS deployment
  target. `NSWorkspace.setDefaultApplication` apparently propagates to
  LaunchServices' "All" role on newer macOS but not on macOS 13, this
  fork's target. The extra call is specific to this fork and should stay
  even if a future upstream diff doesn't have it.

## [1.3.0] — Real multi-item drag-out + ⌘A (Select All)

### Added

- `⌘A` now selects every entry in the current folder (wired via the same
  `NSEvent` local monitor pattern already used for Space/Return/Delete,
  since `Table` swallows key events before SwiftUI's `.onKeyPress` sees them).
- Dragging out several selected entries to Finder now delivers every one as
  a loose file, matching a single-entry drag — no wrapper folder. `Table`
  has no built-in way to bundle a multi-selection into one drag session
  (unlike `List`), so this is handled by a small AppKit layer
  (`MultiItemDragTrigger`, `NSFilePromiseProvider`) that only engages for
  rows already part of a multi-selection; single-entry drag is untouched.

### Known limitation

- Double-clicking an entry that's already part of a larger selection isn't
  a supported gesture — click it alone first, then double-click normally.

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
