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

    func register(name: String) -> UUID {
        let id = UUID()
        names[id] = name
        aggregator.register(id)
        refresh()
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
        refresh()
    }

    /// The panel's single Cancel button stops every item of the drag.
    func cancelAll() {
        for handler in cancelHandlers.values { handler() }
    }

    private func refresh() {
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

    private let limiter = SlotLimiter(limit: 2)

    /// Call once per item about to be extracted. Creates and activates the
    /// panel for the first item of this drag; later items reuse it.
    func beginItem(itemName: String) -> DragTransferItem {
        activeCount += 1
        return DragTransferItem(name: itemName, state: state ?? makePanel())
    }

    /// Call once per item when its transfer ends (success or failure). Only
    /// closes the panel once every item this controller tracks has finished.
    func finishItem(_ item: DragTransferItem) {
        item.finish()
        activeCount -= 1
        guard activeCount <= 0 else { return }
        panel?.close()
        panel = nil
        state = nil
        activeCount = 0
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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DragTransferView(state: state))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        return state
    }
}
