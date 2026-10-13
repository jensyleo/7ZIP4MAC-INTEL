import SwiftUI
import AppKit
import Combine

/// Lets several archives be open at once, one per window, without
/// `WindowGroup`.
///
/// `WindowGroup`'s open-a-file routing is unreliable on macOS 13 (Finder
/// open events are dropped or spawn blank scaffold windows), which is why the
/// main scene is a single `Window`. That window keeps showing the first
/// archive; every further archive opened while it is busy gets an extra
/// AppKit-owned window hosting its own ``ContentView`` and its own
/// ``ArchiveViewModel``, so nothing is shared between windows and opening a
/// second archive never replaces the first.
@MainActor
final class ArchiveWindowManager: ObservableObject {
    /// The main window's view model.
    let main = ArchiveViewModel()
    /// Each window has its own "create archive" flow so its sheets show only
    /// in the window that started it.
    let mainCompression = CompressionViewModel()

    /// The view model of the window the user is working in — what menu
    /// commands (Close Archive, Extract All…) act on.
    @Published private(set) var active: ArchiveViewModel
    @Published private(set) var activeCompression: CompressionViewModel

    /// Builds a window's content for a view model; set once by the app, which
    /// owns the settings/profile/recents objects every window shares.
    var makeContent: ((ArchiveViewModel, CompressionViewModel) -> AnyView)?
    /// Called for each new view model (e.g. to record recents).
    var configure: ((ArchiveViewModel) -> Void)?
    /// Brings the main window back if the user closed it.
    var showMainWindow: (() -> Void)?

    private struct Extra {
        let window: NSWindow
        let viewModel: ArchiveViewModel
        let compression: CompressionViewModel
    }
    private var extras: [ObjectIdentifier: Extra] = [:]
    private var titleObservers: [ObjectIdentifier: AnyCancellable] = [:]
    /// True once the user closed the main window and it hasn't come back. At a
    /// cold launch the window simply isn't on screen *yet*, which must not be
    /// mistaken for this — reopening it then would create a second main window.
    private var mainWindowClosed = false
    private var observers: [NSObjectProtocol] = []

    init() {
        active = main
        activeCompression = mainCompression
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor [weak self] in self?.windowBecameKey(window) }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor [weak self] in self?.windowWillClose(window) }
        })
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("main") == true
    }

    private func windowBecameKey(_ window: NSWindow) {
        if let extra = extras[ObjectIdentifier(window)] {
            active = extra.viewModel
            activeCompression = extra.compression
        } else if isMainWindow(window) {
            mainWindowClosed = false
            active = main
            activeCompression = mainCompression
        }
    }

    private func windowWillClose(_ window: NSWindow) {
        if isMainWindow(window) {
            mainWindowClosed = true
            main.close()
            if active === main { activeCompression = mainCompression }
            return
        }
        titleObservers.removeValue(forKey: ObjectIdentifier(window))
        guard let extra = extras.removeValue(forKey: ObjectIdentifier(window)) else { return }
        extra.viewModel.close()
        if active === extra.viewModel {
            active = main
            activeCompression = mainCompression
        }
    }

    private func isIdle(_ viewModel: ArchiveViewModel) -> Bool {
        switch viewModel.state {
        case .empty, .failed: return true
        case .loading, .loaded: return false
        }
    }

    /// Opens `url` in the window the user is in if that window is empty,
    /// otherwise in a new window — never over an archive already showing.
    func open(_ url: URL) {
        let mainUsable = isIdle(main)
        if isIdle(active), !(active === main && mainWindowClosed) {
            active.open(url: url)
        } else if mainUsable, !mainWindowClosed {
            main.open(url: url)
        } else if mainUsable {
            showMainWindow?()
            main.open(url: url)
        } else {
            openInNewWindow(url)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openInNewWindow(_ url: URL) {
        guard let makeContent else { main.open(url: url); return }
        let viewModel = ArchiveViewModel()
        let compression = CompressionViewModel()
        configure?(viewModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: makeContent(viewModel, compression))
        window.title = "7ZIP4MAC"
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        // Stagger from the window the user is looking at so it isn't hidden
        // exactly behind it.
        if let anchor = NSApp.keyWindow ?? NSApp.mainWindow {
            window.setFrame(anchor.frame, display: false)
            window.setFrameTopLeftPoint(NSPoint(x: anchor.frame.minX + 28, y: anchor.frame.maxY - 28))
        } else {
            window.center()
        }
        // `navigationTitle` doesn't reach a window hosted outside a SwiftUI
        // scene, so the title follows the archive here.
        titleObservers[ObjectIdentifier(window)] = viewModel.objectWillChange.sink { [weak window, weak viewModel] in
            DispatchQueue.main.async {
                window?.title = viewModel?.archiveURL?.lastPathComponent ?? "7ZIP4MAC"
            }
        }
        extras[ObjectIdentifier(window)] = Extra(window: window, viewModel: viewModel, compression: compression)
        active = viewModel
        activeCompression = compression
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.open(url: url)
    }
}
