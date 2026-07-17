import SwiftUI
import AppKit

/// Bridges AppKit's "open these documents" delegate callback — fired when
/// Finder delivers a double-click/"Open With" event to an already-running
/// instance — into the app.
///
/// Needed because `Window` (unlike `WindowGroup`) doesn't reliably route
/// `.onOpenURL` document-open events on macOS 13's SwiftUI runtime: switching
/// the main scene from `WindowGroup` to a single `Window` (to fix duplicate
/// windows, see `SevenZip4MacApp.body`) silently broke opening a second
/// archive from Finder while already running — the event just never reached
/// `ContentView`'s `.onOpenURL`. This delegate method is the same AppKit-level
/// callback SwiftUI's `.onOpenURL` is built on, called directly instead of
/// relying on SwiftUI to forward it to the right scene.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// On a cold launch (app not already running), AppKit can call
    /// `application(_:open:)` before SwiftUI has finished building the
    /// scene and its `.onAppear` has had a chance to set this — a race that
    /// silently dropped the very first file to open, since nothing was
    /// listening yet. Buffering into `pendingURLs` until a handler exists,
    /// then flushing immediately once it's set, closes that window.
    var onOpenFiles: (([URL]) -> Void)? {
        didSet { flushPendingURLsIfPossible() }
    }

    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        flushPendingURLsIfPossible()
    }

    private func flushPendingURLsIfPossible() {
        guard let onOpenFiles, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs = []
        onOpenFiles(urls)
    }
}

/// Application entry point.
///
/// Owns the single ``ArchiveViewModel`` for the window and wires the File menu.
/// Finder double-click integration is a later phase (see ROADMAP); for now an
/// archive is opened via ⌘O or by dropping it onto the window.
@main
@MainActor
struct SevenZip4MacApp: App {
    @StateObject private var viewModel = ArchiveViewModel()
    @StateObject private var compression = CompressionViewModel()
    @StateObject private var benchmark = BenchmarkViewModel()
    @StateObject private var settings = AppSettings()
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var recents = RecentsStore()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        SingleInstance.enforceOrExit()
        // Reclaim any drag-out staging folders left behind by previous runs
        // (Finder copies the promised file itself and never signals us when
        // it's done, so leftovers are swept on launch instead).
        DragOut.sweepStaleStaging()
    }

    var body: some Scene {
        // A single `Window`, not `WindowGroup`: every window would share the
        // exact same `ArchiveViewModel` anyway (there's no per-window state),
        // so a second window can never show anything different — it can only
        // ever mirror the first. `WindowGroup` doesn't know that and opens a
        // brand new window whenever Finder delivers an "open this file" event
        // while the app is already running, producing two windows that both
        // render the same (shared) freshly opened archive. `Window` guarantees
        // there is only ever one, so opening a file while running just routes
        // straight to the existing window instead.
        Window("7ZIP4MAC", id: "main") {
            ContentView(viewModel: viewModel, compression: compression,
                        settings: settings, profileStore: profileStore, recents: recents)
                .onAppear {
                    viewModel.onArchiveOpened = { recents.record($0) }
                    appDelegate.onOpenFiles = { urls in
                        for url in urls where url.isFileURL {
                            viewModel.open(url: url)
                        }
                    }
                    // Point the user at Settings ▸ File Types once, on first
                    // launch — but never associate anything automatically:
                    // macOS shows a real confirmation dialog per format ("Do
                    // you want .zip files to open with 7ZIP4MAC or keep using
                    // Archive Utility?"), and firing all of them at once would
                    // ambush the user with a stack of system dialogs they
                    // didn't ask for. The "Associate Recommended Files…"
                    // button there warns about that before doing anything.
                    if !settings.hasShownFileTypesOnboarding {
                        // `openSettings` (the `EnvironmentValues` action) is
                        // macOS 14+ only; this selector is the pre-Sonoma way
                        // to open a SwiftUI app's `Settings` scene and still
                        // works on macOS 13.
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About 7ZIP4MAC") { showAboutPanel() }
            }
            CommandGroup(replacing: .help) {
                Button("7ZIP4MAC Help") { showHelp() }
            }
            CommandMenu("Tools") {
                Button("Benchmark…") { openWindow(id: "benchmark") }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .newItem) {
                Button("New Archive…") {
                    let sources = SourceSelectionPanel.present()
                    if !sources.isEmpty {
                        compression.begin(
                            sources: sources,
                            format: settings.defaultFormat,
                            level: settings.defaultLevel,
                            encryptFileNames: settings.defaultEncryptFileNames
                        )
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(compression.isRunning)

                Button("Open Archive…") {
                    if let url = ArchiveOpenPanel.present() {
                        viewModel.open(url: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    ForEach(recents.existing, id: \.self) { url in
                        Button(url.lastPathComponent) { viewModel.open(url: url) }
                    }
                    if !recents.existing.isEmpty {
                        Divider()
                        Button("Clear Menu") { recents.clear() }
                    }
                }
                .disabled(recents.existing.isEmpty)

                Button("Close Archive") {
                    viewModel.close()
                }
                .disabled(viewModel.archive == nil)

                Divider()

                Button("Extract All…") {
                    guard let archive = viewModel.archive,
                          let folder = DestinationPanel.present(suggestedName: archive.url.lastPathComponent)
                    else { return }
                    viewModel.extract(into: folder, intoSubfolder: settings.extractIntoSubfolder)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(viewModel.archive == nil || viewModel.isExtracting)
            }
        }

        Settings {
            SettingsView(settings: settings, profileStore: profileStore)
        }

        Window("Benchmark", id: "benchmark") {
            BenchmarkView(viewModel: benchmark)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Concise help shown from the Help menu.
@MainActor
func showHelp() {
    let alert = NSAlert()
    alert.messageText = "How 7ZIP4MAC works"
    alert.informativeText = """
    7ZIP4MAC is a native interface for the official 7-Zip engine, bundled unmodified inside the app.

    • Open (⌘O) or drop an archive to browse its contents; double-click a folder to enter it.
    • New Archive (⌘N) creates a 7z / ZIP / TAR archive — pick a profile or your own \
    format, compression level and password.
    • Extract All (⌘E) extracts everything; select items first to extract only those.
    • Drag any entry straight to Finder to extract just that item there.
    • Select an item and press Space for a Quick Look preview.
    • Test verifies an archive's integrity without extracting it.
    • Encrypted archives prompt for a password when opened.
    • Tools ▸ Benchmark measures this Mac's compression speed.

    This app performs no compression itself — all archive operations run through the \
    official 7-Zip engine (see About for its license).
    """
    alert.runModal()
}

/// Standard About panel with 7-Zip engine credits.
/// (Name, version and copyright come from the Info.plist automatically.)
@MainActor
func showAboutPanel() {
    let credits = NSMutableAttributedString(
        string: "A native macOS interface for 7-Zip.\n\nThis app is a frontend only — all compression, extraction and encryption is performed by the official, unmodified 7-Zip engine, bundled with this app.\n\nBundles 7-Zip, Copyright © 1999–2026 Igor Pavlov, under the GNU LGPL (with unRAR restrictions and BSD-licensed components for some code).\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    )
    credits.append(NSAttributedString(
        string: "gnu.org/licenses/lgpl-3.0",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://www.gnu.org/licenses/lgpl-3.0.html")!,
        ]
    ))
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApp.activate(ignoringOtherApps: true)
}
