import SwiftUI
import AppKit
import SevenZipKit

/// Live state for one drag-out session: every item being extracted, combined
/// into a single steady progress figure. Each item keeps its *own* byte
/// counters (see ``ProgressAggregator``) — an earlier version let all items
/// write one shared figure, so the bar jumped between whichever item
/// reported last on a multi-item drag.
@MainActor
final class DragTransferState: ObservableObject {
    @Published private(set) var progress: ProgressInfo = .zero
    @Published private(set) var title = ""

    private var cancelHandlers: [UUID: () -> Void] = [:]
    private var names: [UUID: String] = [:]
    private var aggregator = ProgressAggregator()
    private var finishedCount = 0
    private var latestFile: String?
    private var estimator = RateEstimator()

    func register(name: String, expectedBytes: UInt64 = 0) -> UUID {
        let id = UUID()
        names[id] = name
        aggregator.register(id, expectedTotal: expectedBytes)
        refresh(force: true)
        return id
    }

    func report(_ id: UUID, _ info: ProgressInfo) {
        aggregator.update(id, processed: info.processedBytes, total: info.totalBytes)
        if let file = info.currentFile { latestFile = file }
        refresh()
    }

    func setCancel(_ id: UUID, _ handler: (() -> Void)?) {
        cancelHandlers[id] = handler
    }

    func finish(_ id: UUID) {
        aggregator.finish(id)
        finishedCount += 1
        refresh(force: true)
    }

    /// The panel's single Cancel button stops every item of the drag.
    func cancelAll() {
        for handler in cancelHandlers.values { handler() }
    }

    /// How often the panel redraws while bytes are flowing. Dozens of items
    /// each report many times a second; publishing every one kept the main
    /// thread so busy that the bar painted late.
    private static let publishInterval: TimeInterval = 0.1
    private var lastPublish = Date.distantPast
    private var pendingPublish: Task<Void, Never>?

    /// Publishes now when `force` (a structural change) or when enough time
    /// has passed; otherwise schedules one trailing publish so the last
    /// figure is never lost.
    private func refresh(force: Bool = false) {
        let elapsed = Date.now.timeIntervalSince(lastPublish)
        if force || elapsed >= Self.publishInterval {
            pendingPublish?.cancel()
            pendingPublish = nil
            publish()
            return
        }
        guard pendingPublish == nil else { return }
        pendingPublish = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.publishInterval - elapsed) * 1_000_000_000) + 1_000_000)
            guard !Task.isCancelled, let self else { return }
            self.pendingPublish = nil
            self.publish()
        }
    }

    private func publish() {
        lastPublish = .now
        let snapshot = aggregator.snapshot()
        let rate = estimator.rate(processed: snapshot.processed)
        let remaining = RateEstimator.remaining(total: snapshot.total, processed: snapshot.processed, rate: rate)
        progress = ProgressInfo(
            fractionCompleted: snapshot.fraction,
            processedBytes: snapshot.processed,
            totalBytes: snapshot.total,
            bytesPerSecond: rate,
            estimatedTimeRemaining: remaining,
            currentFile: latestFile
        )
        if names.count == 1, let only = names.values.first {
            title = "Extracting \(only)"
        } else {
            let done = finishedCount > 0 ? " — \(finishedCount) done" : ""
            title = "Extracting \(names.count) items\(done)"
        }
    }
}

/// One item's handle on the shared ``DragTransferState``.
@MainActor
final class DragTransferItem {
    private let id: UUID
    private let state: DragTransferState

    fileprivate init(name: String, state: DragTransferState) {
        self.state = state
        self.id = state.register(name: name)
    }

    /// An item that was registered up front.
    fileprivate init(id: UUID, state: DragTransferState) {
        self.state = state
        self.id = id
    }

    /// Set once the underlying `Task` exists, so the panel's Cancel button
    /// can actually stop it instead of just sitting there unwired.
    var onCancel: (() -> Void)? {
        didSet { state.setCancel(id, onCancel) }
    }

    func report(_ info: ProgressInfo) {
        state.report(id, info)
    }

    fileprivate func finish() {
        state.finish(id)
    }
}

private struct DragTransferView: View {
    @ObservedObject var state: DragTransferState

    var body: some View {
        ProgressPanelView(
            title: state.title,
            progress: state.progress,
            onCancel: { state.cancelAll() }
        )
    }
}

/// Owns the floating progress panel shown while dragged-out entries extract
/// to Finder. A floating panel (not a sheet) because the drag has already
/// left this app's window by the time `writePromiseTo` fires.
///
/// One instance is shared across every item of the *same* drag gesture
/// (see `EntryDragTriggerView.beginDrag`): Finder calls `writePromiseTo`
/// once per entry, and each used to make its own panel independently, so a
/// multi-item drag flashed a new activating window per item.
///
/// At most two items extract at once; the rest wait in ``acquireSlot()``.
/// Finder starts every promise simultaneously, and running dozens of
/// extractions against a network volume in parallel only slows each one.
///
/// Made key/active, not a non-activating panel: AppKit renders the bar in a
/// dimmed gray in a non-key window; by the time the panel appears the drag
/// gesture is over, so activating is safe.
@MainActor
final class DragProgressPanelController {
    private var panel: NSPanel?
    private var state: DragTransferState?
    private var activeCount = 0
    private var finishedCount = 0

    /// Every item of this drag — path, name and size — known when the drag
    /// starts. Finder asks for the files one after another, so without this a
    /// quick item could finish before the next had begun, the panel would
    /// close with it, and the next item would open a new panel with the bar
    /// back at zero.
    private let expected: [(path: String, name: String, bytes: UInt64)]
    private var preregistered: [String: UUID] = [:]

    private let limiter = SlotLimiter(limit: 2)

    init(expected: [(path: String, name: String, bytes: UInt64)] = []) {
        self.expected = expected
    }

    /// Call once per item about to be extracted. Creates and activates the
    /// panel for the first item of this drag; later items reuse it.
    func beginItem(path: String, itemName: String) -> DragTransferItem {
        activeCount += 1
        let state = state ?? makePanel()
        if let id = preregistered[path] {
            return DragTransferItem(id: id, state: state)
        }
        return DragTransferItem(name: itemName, state: state)
    }

    /// Call once per item when its transfer ends (success or failure). Only
    /// closes the panel once every item this controller tracks has finished.
    func finishItem(_ item: DragTransferItem) {
        item.finish()
        activeCount -= 1
        finishedCount += 1
        let allDone = expected.isEmpty ? activeCount <= 0 : finishedCount >= expected.count
        guard allDone else { return }
        // Leave the finished panel — at 100% — up for a moment before it goes,
        // so the end of the transfer is seen to reach the end.
        let closing = panel
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            closing?.parent?.removeChildWindow(closing!)
            closing?.close()
        }
        panel = nil
        state = nil
        activeCount = 0
        finishedCount = 0
    }

    /// Waits for one of the extraction slots. Throws `CancellationError` —
    /// without holding a slot — if cancelled while waiting. Pair every
    /// successful call with ``releaseSlot()``.
    func acquireSlot() async throws {
        try await limiter.acquire()
    }

    func releaseSlot() {
        let limiter = limiter
        Task { await limiter.release() }
    }

    private func makePanel() -> DragTransferState {
        let state = DragTransferState()
        self.state = state
        preregistered = [:]
        for item in expected {
            preregistered[item.path] = state.register(name: item.name, expectedBytes: item.bytes)
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // Above this app's own windows, but not above other apps': a normal
        // window level (not `.floating`, which sits over every app and stayed
        // there when the user put another app on top — reported as "the progress
        // window stays above everything", 2026-11-05) plus being a child
        // of an archive window, which keeps it just above its parent.
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DragTransferView(state: state))
        let parent = NSApp.keyWindow ?? NSApp.mainWindow
            ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
        if let parent {
            // Centre over the window it belongs to, then follow it.
            panel.setFrameOrigin(NSPoint(
                x: parent.frame.midX - panel.frame.width / 2,
                y: parent.frame.midY - panel.frame.height / 2
            ))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        parent?.addChildWindow(panel, ordered: .above)
        self.panel = panel
        return state
    }
}
