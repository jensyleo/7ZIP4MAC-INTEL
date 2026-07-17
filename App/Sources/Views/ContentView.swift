import SwiftUI
import AppKit
import UniformTypeIdentifiers
import SevenZipKit

/// The archive window's root view. Composes the toolbar, the file list and the
/// status bar, and switches between empty / loading / loaded / failed states.
struct ContentView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @ObservedObject var compression: CompressionViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var profileStore: ProfileStore
    @ObservedObject var recents: RecentsStore
    @State private var selection: Set<ArchiveEntry.ID> = []
    @State private var isDropTargeted = false
    @State private var pendingDeletePaths: [String]?
    @State private var pendingDroppedURLs: [URL]?
    @AppStorage("showInspector") private var showInspector = false

    var body: some View {
        primaryContent
            .modifier(secondaryAlerts)
    }

    /// The archive-state switch plus window chrome (frame, drop target,
    /// title, toolbar, inspector). Split out from `body` because the full
    /// modifier chain in one expression pushed the type-checker over its
    /// complexity budget ("unable to type-check this expression in
    /// reasonable time").
    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.state {
        case .empty:
            EmptyStateView(
                onOpen: presentOpenPanel,
                recents: recents.existing,
                onOpenRecent: { url in selection = []; viewModel.open(url: url) }
            )
        case .loading(let url):
            LoadingStateView(url: url)
        case .failed(let message):
            FailureStateView(message: message, onRetry: presentOpenPanel)
        case .loaded(let archive):
            VStack(spacing: 0) {
                FileListView(viewModel: viewModel, selection: $selection,
                             onQuickLook: performQuickLook, onExtractSelection: extract,
                             onTestSelection: testArchiveOrSelection,
                             onAdd: addFiles,
                             onRenameSelection: renameSelected,
                             onMoveSelection: moveSelected, onCopySelection: copySelected,
                             onDeleteSelection: confirmDeleteSelected)
                StatusBarView(archive: archive)
            }
        }
    }

    /// Width of the hand-rolled inspector panel itself (excluding the divider).
    private let inspectorPanelWidth: CGFloat = 280
    /// Width of the `Divider` between the content and the inspector panel.
    private let inspectorDividerWidth: CGFloat = 1
    /// Total width the inspector occupies, including its divider — used to
    /// grow/shrink the window itself when toggling it (see
    /// ``toggleInspector()``). Derived from the two constants above so the
    /// panel's own `.frame(width:)` and the window-resize delta can never
    /// drift out of sync.
    private var inspectorWidth: CGFloat { inspectorPanelWidth + inspectorDividerWidth }

    /// `.inspector(isPresented:content:)` is macOS 14+ only; this hand-rolled
    /// trailing panel (a plain `HStack` + `Divider`) reproduces the same
    /// "toggleable trailing sidebar" look on macOS 13.
    private var primaryContent: some View {
        HStack(spacing: 0) {
            Group {
                stateContent
            }
            .frame(minWidth: 640, minHeight: 400)
            .overlay { dropOverlay }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
            .navigationTitle(viewModel.archiveURL?.lastPathComponent ?? "7ZIP4MAC")
            .toolbar { toolbarContent }

            if showInspector {
                Divider()
                InspectorView(entry: singleSelectedEntry)
                    .frame(width: inspectorPanelWidth)
            }
        }
    }

    /// The extraction/compression/test/password sheets and alerts, factored
    /// out of `body` so the full modifier chain doesn't overwhelm the type
    /// checker in one expression (see ``primaryContent``).
    private var secondaryAlerts: some ViewModifier {
        SecondaryAlerts(
            viewModel: viewModel,
            compression: compression,
            settings: settings,
            profileStore: profileStore,
            pendingDeletePaths: $pendingDeletePaths,
            pendingDroppedURLs: $pendingDroppedURLs,
            selection: $selection,
            onOpenCreated: { url in
                selection = []
                viewModel.open(url: url)
            },
            onHandleIncoming: handleIncoming
        )
    }

    /// Routes an incoming file-open (double-click / "Open With") to opening
    /// the archive.
    private func handleIncoming(_ url: URL) {
        switch AppURLRouter.command(for: url) {
        case .openArchive(let archiveURL):
            selection = []
            viewModel.open(url: archiveURL)
        case .none:
            break
        }
    }

    func startNewArchive() {
        let sources = SourceSelectionPanel.present()
        guard !sources.isEmpty else { return }
        compression.begin(
            sources: sources,
            format: settings.defaultFormat,
            level: settings.defaultLevel,
            encryptFileNames: settings.defaultEncryptFileNames
        )
    }

    /// Extracts every selected file to a temporary file and shows them all in
    /// Quick Look (with the standard arrow-through-items navigation). Folders
    /// are skipped — Quick Look has nothing useful to show.
    func performQuickLook() {
        guard let archiveURL = viewModel.archiveURL else { return }
        let entries = viewModel.visibleEntries.filter { selection.contains($0.id) && !$0.isDirectory }
        guard !entries.isEmpty else { return }
        let password = viewModel.sessionPassword
        Task {
            var urls: [URL] = []
            for entry in entries {
                do {
                    let url = try await DragOut.extract(
                        entryPath: entry.path, archiveURL: archiveURL, password: password
                    )
                    urls.append(url)
                } catch {
                    ArchiveLog.ui.error("Quick Look failed for \(entry.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            guard !urls.isEmpty else { return }
            QuickLookPreviewer.shared.preview(urls: urls)
        }
    }

    private var canQuickLook: Bool {
        viewModel.visibleEntries.contains { selection.contains($0.id) && !$0.isDirectory }
    }

    private var singleSelectedEntry: ArchiveEntry? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return viewModel.visibleEntries.first { $0.id == id && !$0.isParentLink }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        archiveToolbarItems
        editToolbarItems
        windowToolbarItems
    }

    /// Open/create/extract/test — the core archive-level actions.
    @ToolbarContentBuilder
    private var archiveToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: presentOpenPanel) {
                Label("Open", systemImage: "folder")
            }
            .help("Open an archive")
        }
        ToolbarItem(placement: .navigation) {
            Button(action: startNewArchive) {
                Label("New Archive", systemImage: "doc.zipper")
            }
            .help("Create a new archive")
            .disabled(compression.isRunning)
        }
        ToolbarItem {
            Button(action: extract) {
                Label(selection.isEmpty ? "Extract All" : "Extract Selected",
                      systemImage: "arrow.up.bin")
            }
            .help(selection.isEmpty ? "Extract the whole archive" : "Extract the selected items")
            .disabled(viewModel.archive == nil || viewModel.isExtracting)
        }
        ToolbarItem {
            Button(action: testArchiveOrSelection) {
                Label(selection.isEmpty ? "Test" : "Test Selected", systemImage: "checkmark.seal")
            }
            .help(selection.isEmpty ? "Test the whole archive's integrity" : "Test the selected items' integrity")
            .disabled(viewModel.archive == nil)
        }
    }

    /// Add/Rename/Move/Copy/Delete — in-place edits on entries, each its own
    /// direct toolbar button (no longer tucked into an "Edit" dropdown) so
    /// they're one click away; the toolbar's own overflow chevron handles it
    /// if the window gets too narrow to show them all.
    @ToolbarContentBuilder
    private var editToolbarItems: some ToolbarContent {
        ToolbarItem {
            Button { addFiles() } label: {
                Label("Add…", systemImage: "tray.and.arrow.down")
            }
            .help("Add files or folders into the archive")
            .disabled(viewModel.archive == nil)
        }
        ToolbarItem {
            Button { renameSelected() } label: {
                Label("Rename…", systemImage: "pencil")
            }
            .help("Rename the selected item")
            .disabled(selection.count != 1)
        }
        ToolbarItem {
            Button { moveSelected() } label: {
                Label("Move…", systemImage: "arrow.turn.up.right")
            }
            .help("Move the selected item within the archive")
            .disabled(selection.count != 1)
        }
        ToolbarItem {
            Button { copySelected() } label: {
                Label("Copy…", systemImage: "doc.on.doc")
            }
            .help("Copy the selected item within the archive")
            .disabled(selection.count != 1)
        }
        ToolbarItem {
            Button(role: .destructive) { confirmDeleteSelected() } label: {
                Label(selection.count > 1 ? "Delete Selected" : "Delete", systemImage: "trash")
            }
            .help("Delete the selected item(s) from the archive")
            .disabled(selection.isEmpty)
        }
    }

    /// Up/Quick Look/Inspector/Close/More — window and navigation controls.
    @ToolbarContentBuilder
    private var windowToolbarItems: some ToolbarContent {
        ToolbarItem {
            Button(action: viewModel.goUp) {
                Label("Up", systemImage: "chevron.up")
            }
            .help("Go up one folder")
            .disabled(viewModel.currentFolder.isEmpty)
        }
        ToolbarItem {
            Button(action: performQuickLook) {
                Label("Quick Look", systemImage: "eye")
            }
            .help("Preview the selected item (Space)")
            .disabled(!canQuickLook)
        }
        ToolbarItem {
            Button { toggleInspector() } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle inspector")
        }
        ToolbarItem {
            Button(action: viewModel.close) {
                Label("Close", systemImage: "xmark.circle")
            }
            .help("Close the current archive")
            .disabled(viewModel.archive == nil)
        }
        ToolbarItem {
            Menu {
                Button("Uninstall 7ZIP4MAC…", role: .destructive) {
                    Uninstaller.confirmAndUninstall(settings: settings)
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More actions")
        }
    }

    // MARK: - Drag & drop feedback

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Intents

    /// Toggles the inspector and grows/shrinks the window by its width.
    ///
    /// Unlike the real `.inspector()` modifier (macOS 14+), a plain `HStack`
    /// doesn't get automatic window-resize-on-reveal: `stateContent` fills
    /// available space (`maxWidth: .infinity` inside `FileListView`'s table),
    /// so its reported ideal size never changes and the window never grows to
    /// make room — the inspector was silently clipped instead of appearing.
    /// Resizing the window explicitly reproduces the expected behavior.
    private func toggleInspector() {
        let opening = !showInspector
        showInspector.toggle()
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        var frame = window.frame
        frame.size.width = opening
            ? frame.size.width + inspectorWidth
            : max(frame.size.width - inspectorWidth, window.minSize.width)
        window.setFrame(frame, display: true, animate: true)
    }

    private func presentOpenPanel() {
        guard let url = ArchiveOpenPanel.present() else { return }
        selection = []
        viewModel.open(url: url)
    }

    private func extract() {
        guard let archive = viewModel.archive else { return }
        guard let folder = DestinationPanel.present(
            suggestedName: archive.url.lastPathComponent
        ) else { return }
        // Selected file paths (folders are implied by their contents' paths).
        // ".." (the up-a-folder row) isn't a real archive entry, so it's
        // filtered out here the same way test/delete already do — otherwise
        // selecting it and hitting Extract would ask the engine to extract a
        // nonexistent ".." path.
        let paths = Array(selection).filter { $0 != ".." }
        let selectedEntries = archive.entries.filter { paths.contains($0.id) }
        let selectionHasFolder = selectedEntries.contains { $0.isDirectory }

        // The archive-name wrapper subfolder is only for whole-archive
        // extraction — there it keeps the archive's loose top-level files
        // from scattering into the destination. A selected folder is already
        // its own container, so wrapping it again just nests it needlessly;
        // and a pure file selection should land flat where the user pointed.
        let wholeArchive = paths.isEmpty
        viewModel.extract(into: folder, selectedPaths: paths,
                          intoSubfolder: wholeArchive && settings.extractIntoSubfolder,
                          flattenPaths: !wholeArchive && !selectionHasFolder,
                          overwritePolicy: settings.defaultOverwritePolicy)
    }

    private func testArchiveOrSelection() {
        let paths = selection.isEmpty ? [] : Array(selection).filter { $0 != ".." }
        // Test always confirms — it's the only action whose result isn't
        // otherwise visible anywhere (unlike Add/Delete/Move/Copy, which show
        // up in the file list), so it isn't user-configurable.
        viewModel.test(selectedPaths: paths, notifySuccess: true)
    }

    /// Lets the user pick files/folders to add into the already-open archive.
    private func addFiles() {
        let sources = SourceSelectionPanel.present()
        guard !sources.isEmpty else { return }
        viewModel.addFiles(sources, notifySuccess: settings.notifyOnAdd)
    }

    /// The single selected entry's archive path, for Move/Copy (both need
    /// exactly one source — there's no meaningful "move 3 items to the same
    /// single destination path" within an archive).
    private var singleSelectedPath: String? {
        guard selection.count == 1, let id = selection.first, id != ".." else { return nil }
        return id
    }

    /// Renames an entry in place — unlike Move, this only offers the last
    /// path component (the name), keeping it in the same folder, matching
    /// what "Rename" means in Finder.
    private func renameSelected() {
        guard let path = singleSelectedPath else { return }
        let currentName = (path as NSString).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent
        guard let newName = PathPromptPanel.present(
            title: "Rename Item",
            message: "Enter a new name for “\(currentName)”.",
            currentValue: currentName
        ) else { return }
        let newPath = parent.isEmpty ? newName : "\(parent)/\(newName)"
        viewModel.moveEntry(path: path, toPath: newPath, notifySuccess: settings.notifyOnMove)
    }

    private func moveSelected() {
        guard let path = singleSelectedPath else { return }
        guard let newPath = PathPromptPanel.present(
            title: "Move Item",
            message: "Enter the new path within the archive for “\((path as NSString).lastPathComponent)”.",
            currentValue: path
        ) else { return }
        viewModel.moveEntry(path: path, toPath: newPath, notifySuccess: settings.notifyOnMove)
    }

    private func copySelected() {
        guard let path = singleSelectedPath else { return }
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        let suggestedName = ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)"
        let parent = (path as NSString).deletingLastPathComponent
        let suggestedPath = parent.isEmpty ? suggestedName : "\(parent)/\(suggestedName)"
        guard let newPath = PathPromptPanel.present(
            title: "Copy Item",
            message: "Enter the path within the archive for the copy of “\(name)”.",
            currentValue: suggestedPath
        ) else { return }
        viewModel.copyEntry(path: path, toPath: newPath, notifySuccess: settings.notifyOnCopy)
    }

    private func confirmDeleteSelected() {
        let paths = Array(selection).filter { $0 != ".." }
        guard !paths.isEmpty else { return }
        pendingDeletePaths = paths
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.loadURL(from: provider) { urls.append(url) }
            }
            guard !urls.isEmpty else { return }

            if viewModel.archive != nil {
                // An archive is already open — ask whether the drop should be
                // added into it, rather than assuming (dropping a file onto an
                // open archive is ambiguous: "add this" vs "open this instead").
                pendingDroppedURLs = urls
            } else {
                selection = []
                viewModel.open(url: urls[0])
            }
        }
        return true
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}

/// The extraction/compression/test/password sheets and alerts, factored out
/// of `ContentView.body` for the same type-checker-complexity reason as
/// ``EditAlerts`` and ``DropAlerts``.
private struct SecondaryAlerts: ViewModifier {
    @ObservedObject var viewModel: ArchiveViewModel
    @ObservedObject var compression: CompressionViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var profileStore: ProfileStore
    @Binding var pendingDeletePaths: [String]?
    @Binding var pendingDroppedURLs: [URL]?
    @Binding var selection: Set<ArchiveEntry.ID>
    let onOpenCreated: (URL) -> Void
    let onHandleIncoming: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: extractionSheetPresented) {
                if case .running(let progress) = viewModel.extractionState {
                    ProgressPanelView(
                        title: "Extracting \(viewModel.archiveURL?.lastPathComponent ?? "archive")",
                        progress: progress,
                        onCancel: viewModel.cancelExtraction
                    )
                }
            }
            .alert("Extraction Complete", isPresented: extractionFinishedPresented, presenting: finishedDestination) { destination in
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(finishedRevealTargets)
                    viewModel.dismissExtractionResult()
                }
                Button("Done", role: .cancel) { viewModel.dismissExtractionResult() }
            } message: { destination in
                switch finishedOverwritePolicy {
                case .overwrite:
                    Text("Files were extracted to “\(destination.lastPathComponent)”.")
                case .skip:
                    Text("Files were extracted to “\(destination.lastPathComponent)”. Any file that already existed there was left untouched (Skip).")
                case .rename:
                    Text("Files were extracted to “\(destination.lastPathComponent)”. Any file that already existed there was kept, and the newly extracted one was given a different name (Rename Extracted File).")
                }
            }
            .alert("Couldn’t Extract", isPresented: extractionFailedPresented, presenting: failureMessage) { _ in
                Button("OK", role: .cancel) { viewModel.dismissExtractionResult() }
            } message: { message in
                Text(message)
            }
            .modifier(CompressionFlow(
                compression: compression,
                profileStore: profileStore,
                revealWhenDone: settings.revealInFinderWhenDone,
                onOpenCreated: onOpenCreated
            ))
            .onAppear { viewModel.showHiddenEntries = settings.showHiddenEntries }
            .onChange(of: settings.showHiddenEntries) { newValue in
                viewModel.showHiddenEntries = newValue
            }
            .onChange(of: finishedDestination) { destination in
                dismissExtractionResultIfQuiet(destination)
            }
            .onOpenURL { url in onHandleIncoming(url) }
            .alert("Archive Test", isPresented: testPresented, presenting: viewModel.testMessage) { _ in
                Button("OK", role: .cancel) { viewModel.dismissTest() }
            } message: { message in
                Text(message)
            }
            .modifier(EditAlerts(
                viewModel: viewModel,
                pendingDeletePaths: $pendingDeletePaths,
                selection: $selection,
                notifySuccess: settings.notifyOnDelete
            ))
            .modifier(DropAlerts(
                viewModel: viewModel,
                pendingDroppedURLs: $pendingDroppedURLs,
                selection: $selection,
                notifyOnAdd: settings.notifyOnAdd
            ))
            .sheet(isPresented: passwordPromptPresented) {
                PasswordPromptView(
                    archiveName: viewModel.pendingPasswordURL?.lastPathComponent ?? "archive",
                    showError: viewModel.passwordAttemptFailed,
                    attemptCount: viewModel.passwordAttemptCount,
                    maxAttempts: viewModel.maxPasswordAttempts,
                    onUnlock: { password in
                        viewModel.submitPassword(password)
                    },
                    onCancel: viewModel.cancelPasswordEntry
                )
            }
    }

    private var extractionSheetPresented: Binding<Bool> {
        Binding(get: { viewModel.isExtracting }, set: { if !$0 { viewModel.cancelExtraction() } })
    }

    // Always shown when files were skipped or renamed instead of overwritten
    // — that's not cosmetic "it's done" noise, it's information the user
    // needs to know their files (or the newly extracted ones) ended up
    // somewhere other than expected.
    private var shouldShowExtractionFinished: Bool {
        guard finishedDestination != nil else { return false }
        if settings.confirmAfterExtraction { return true }
        return finishedOverwritePolicy != .overwrite
    }

    private var extractionFinishedPresented: Binding<Bool> {
        Binding(
            get: { shouldShowExtractionFinished },
            set: { if !$0 { viewModel.dismissExtractionResult() } }
        )
    }

    private var extractionFailedPresented: Binding<Bool> {
        Binding(get: { failureMessage != nil }, set: { if !$0 { viewModel.dismissExtractionResult() } })
    }

    private var finishedDestination: URL? {
        if case .finished(let destination, _, _) = viewModel.extractionState { return destination }
        return nil
    }

    private var finishedRevealTargets: [URL] {
        if case .finished(_, let revealTargets, _) = viewModel.extractionState { return revealTargets }
        return []
    }

    private var finishedOverwritePolicy: ExtractionRequest.OverwritePolicy {
        if case .finished(_, _, let overwritePolicy) = viewModel.extractionState { return overwritePolicy }
        return .overwrite
    }

    /// When the completion dialog is disabled, extraction just finishes
    /// quietly — clear the finished state so it doesn't linger. Files that
    /// were skipped/renamed instead of overwritten always show the dialog
    /// regardless (see `extractionFinishedPresented`), so don't dismiss those
    /// out from under the user.
    private func dismissExtractionResultIfQuiet(_ destination: URL?) {
        guard destination != nil else { return }
        let dialogIsOff: Bool = !settings.confirmAfterExtraction
        let policyWasDefault: Bool = finishedOverwritePolicy == .overwrite
        if dialogIsOff, policyWasDefault {
            viewModel.dismissExtractionResult()
        }
    }

    private var failureMessage: String? {
        if case .failed(let message) = viewModel.extractionState { return message }
        return nil
    }

    private var testPresented: Binding<Bool> {
        Binding(get: { viewModel.testMessage != nil }, set: { if !$0 { viewModel.dismissTest() } })
    }

    private var passwordPromptPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingPasswordURL != nil },
            set: { if !$0 { viewModel.cancelPasswordEntry() } }
        )
    }
}

/// The "edit archive" result alert plus the delete-confirmation alert,
/// factored out of `ContentView.body` — with everything else already in
/// that modifier chain, adding these two inline pushed the type-checker over
/// its complexity budget ("unable to type-check this expression").
private struct EditAlerts: ViewModifier {
    @ObservedObject var viewModel: ArchiveViewModel
    @Binding var pendingDeletePaths: [String]?
    @Binding var selection: Set<ArchiveEntry.ID>
    var notifySuccess: Bool

    func body(content: Content) -> some View {
        content
            .alert("Edit Archive", isPresented: editPresented, presenting: viewModel.editMessage) { _ in
                Button("OK", role: .cancel) { viewModel.dismissEdit() }
            } message: { message in
                Text(message)
            }
            .alert("Delete Item?", isPresented: deleteConfirmPresented, presenting: pendingDeletePaths) { paths in
                Button("Delete", role: .destructive) {
                    viewModel.deleteEntries(paths: paths, notifySuccess: notifySuccess)
                    selection = []
                    pendingDeletePaths = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletePaths = nil }
            } message: { paths in
                Text(deleteConfirmMessage(for: paths))
            }
    }

    private var editPresented: Binding<Bool> {
        Binding(get: { viewModel.editMessage != nil }, set: { if !$0 { viewModel.dismissEdit() } })
    }

    private var deleteConfirmPresented: Binding<Bool> {
        Binding(get: { pendingDeletePaths != nil }, set: { if !$0 { pendingDeletePaths = nil } })
    }

    private func deleteConfirmMessage(for paths: [String]) -> String {
        guard paths.count == 1 else { return "\(paths.count) items will be permanently removed from the archive." }
        let name = (paths[0] as NSString).lastPathComponent
        return "“\(name)” will be permanently removed from the archive."
    }
}

/// Asks what to do with file(s) dropped onto the window while an archive is
/// already open — "add to the open archive" vs "open this instead" — factored
/// out for the same type-checker-complexity reason as ``EditAlerts``.
private struct DropAlerts: ViewModifier {
    @ObservedObject var viewModel: ArchiveViewModel
    @Binding var pendingDroppedURLs: [URL]?
    @Binding var selection: Set<ArchiveEntry.ID>
    var notifyOnAdd: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Add to the open archive?",
            isPresented: presented,
            presenting: pendingDroppedURLs
        ) { urls in
            Button("Add to “\(viewModel.archiveURL?.lastPathComponent ?? "Archive")”") {
                viewModel.addFiles(urls, notifySuccess: notifyOnAdd)
                pendingDroppedURLs = nil
            }
            if urls.count == 1 {
                Button("Open “\(urls[0].lastPathComponent)” Instead") {
                    selection = []
                    viewModel.open(url: urls[0])
                    pendingDroppedURLs = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDroppedURLs = nil }
        } message: { urls in
            Text(dropMessage(for: urls))
        }
    }

    private var presented: Binding<Bool> {
        Binding(get: { pendingDroppedURLs != nil }, set: { if !$0 { pendingDroppedURLs = nil } })
    }

    private func dropMessage(for urls: [URL]) -> String {
        guard urls.count == 1 else { return "You dropped \(urls.count) items." }
        return "You dropped “\(urls[0].lastPathComponent)”."
    }
}
