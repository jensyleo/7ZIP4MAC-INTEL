import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SevenZipKit

/// Writes one archive entry to disk on demand, as an `NSFilePromiseProvider`
/// — the AppKit type Finder itself uses for drag-and-drop. Used for every
/// drag now (not just multi-selection): SwiftUI's `Button` + `.onDrag`
/// combination — reliable on the upstream Apple Silicon build's newer
/// macOS — doesn't reliably start a drag at all on macOS 13. `Button`'s own
/// press gesture wins the conflict with `.onDrag`'s drag-gesture recognizer
/// almost every time on this OS, so drag-out silently never began (reported
/// directly: "no me permite arrastrar al Finder", true even for a single,
/// unselected entry). Bypassing SwiftUI's gesture system entirely — the same
/// fix that took several iterations to land upstream for multi-item drag —
/// is the fix for single-item drag here too.
private final class ArchiveEntryFilePromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    private let archiveURL: URL
    private let entryPath: String
    private let entryName: String
    private let password: String?

    init(archiveURL: URL, entryPath: String, entryName: String, password: String?, typeIdentifier: String) {
        self.archiveURL = archiveURL
        self.entryPath = entryPath
        self.entryName = entryName
        self.password = password
        super.init()
        fileType = typeIdentifier
        delegate = self
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        entryName
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let entryPath = entryPath
        let archiveURL = archiveURL
        let password = password
        Task {
            do {
                let extractedURL = try await DragOut.extract(
                    entryPath: entryPath, archiveURL: archiveURL, password: password
                )
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: extractedURL, to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}

/// A transparent AppKit view overlaid on every draggable `Table` row's Name
/// cell. It disambiguates the mouse-down between a real drag (begins a
/// genuine `NSDraggingSession`, one loose file per dragged entry) and a
/// plain click/double-click (forwarded to the same selection logic the
/// `Table` row's `Button` used to own) — the classic AppKit "wait past the
/// drag threshold, then decide" pattern, since this view sits on top of
/// everything else and sees the mouse-down first.
final class EntryDragTriggerView: NSView, NSDraggingSource {
    var entries: [ArchiveEntry] = []
    var archiveURL: URL?
    var password: String?
    var onPlainClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only this view itself is ever hit — there's nothing beneath it to
        // delegate to (it exists purely to intercept the gesture).
        bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        guard let window, let archiveURL, !entries.isEmpty else {
            onPlainClick?()
            return
        }

        // Classic click-vs-drag disambiguation: keep pulling events until
        // either the pointer moves past the drag threshold (→ real drag) or
        // the button comes up first (→ plain click, no drag happened).
        // Deliberately the simplest possible form of this loop (no explicit
        // `until`/`inMode`/`dequeue`) — verified upstream on Apple Silicon;
        // needs live verification here on macOS 13, where AppKit event
        // delivery has already shown version-specific quirks elsewhere in
        // this fork (LaunchServices roles, window document-open events).
        let startLocation = event.locationInWindow
        let dragThreshold: CGFloat = 4
        var didDrag = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let dx = next.locationInWindow.x - startLocation.x
            let dy = next.locationInWindow.y - startLocation.y
            if hypot(dx, dy) > dragThreshold {
                didDrag = true
                break
            }
        }

        if didDrag {
            beginDrag(with: event, archiveURL: archiveURL)
        } else {
            onPlainClick?()
        }
    }

    private func beginDrag(with event: NSEvent, archiveURL: URL) {
        let icon = NSWorkspace.shared.icon(for: .data)
        let items: [NSDraggingItem] = entries.map { entry in
            let provider = ArchiveEntryFilePromiseProvider(
                archiveURL: archiveURL,
                entryPath: entry.path,
                entryName: entry.name,
                password: password,
                typeIdentifier: DragOut.typeIdentifier(for: entry)
            )
            let draggingItem = NSDraggingItem(pasteboardWriter: provider)
            draggingItem.setDraggingFrame(bounds, contents: icon)
            return draggingItem
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// SwiftUI wrapper for `EntryDragTriggerView`. Overlaid on every draggable
/// row — see `EntryDragModifier`.
struct EntryDragTrigger: NSViewRepresentable {
    let entries: [ArchiveEntry]
    let archiveURL: URL
    let password: String?
    let onPlainClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> EntryDragTriggerView {
        let view = EntryDragTriggerView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: EntryDragTriggerView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: EntryDragTriggerView) {
        view.entries = entries
        view.archiveURL = archiveURL
        view.password = password
        view.onPlainClick = onPlainClick
        view.onDoubleClick = onDoubleClick
    }
}
