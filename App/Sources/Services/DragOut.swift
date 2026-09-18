import Foundation
import UniformTypeIdentifiers
import SevenZipKit

/// Builds drag item providers that extract an archive entry lazily — only when
/// the user actually drops it onto Finder (a file promise). Nothing is written
/// to disk if the drag is cancelled.
enum DragOut {

    /// Parent dir for all drag staging folders. Finder copies the promised
    /// file itself and never tells us when it's done, so we can't delete right
    /// after a drag — leftovers are reclaimed on launch via `sweepStaleStaging`.
    private static var stagingRoot: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "7ZIP4MAC-Drag", directoryHint: .isDirectory)
    }

    /// An item provider for dragging a single entry out of the archive.
    ///
    /// - Parameters:
    ///   - entry: The file or folder to drag out.
    ///   - archiveURL: The archive the entry lives in.
    ///   - password: Password for encrypted archives, if any (read live at
    ///     drag-start by the caller). Empty is treated as "no password".
    static func itemProvider(
        for entry: ArchiveEntry,
        archiveURL: URL,
        password rawPassword: String?
    ) -> NSItemProvider {
        // Treat "" as nil so the engine never gets a bare `-p` (which can make
        // it block on an interactive password prompt).
        let password = (rawPassword?.isEmpty == false) ? rawPassword : nil
        let provider = NSItemProvider()
        provider.suggestedName = entry.name

        let typeIdentifier = Self.typeIdentifier(for: entry)
        let entryPath = entry.path

        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            Task.detached {
                do {
                    let url = try await Self.extract(
                        entryPath: entryPath,
                        archiveURL: archiveURL,
                        password: password
                    )
                    progress.completedUnitCount = 1
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }
        return provider
    }

    /// Extracts a single entry (a folder is extracted with its whole subtree)
    /// into a unique staging directory and returns the extracted item's URL.
    static func extract(
        entryPath: String,
        archiveURL: URL,
        password: String?
    ) async throws -> URL {
        let executable = try BundledEngine.resolve()
        let service = ArchiveService(executable: executable)

        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let temp = stagingRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let request = ExtractionRequest(
            archiveURL: archiveURL,
            destinationURL: temp,
            password: password,
            selectedPaths: [entryPath],
            overwritePolicy: .overwrite
        )
        try await service.extract(request) { _ in }
        let extracted = try locateExtractedItem(forEntryPath: entryPath, in: temp)
        try Self.rejectSymlinkEscapingScratch(extracted, scratch: temp)
        return extracted
    }

    /// Refuses an extracted item that's a symlink pointing outside `scratch`
    /// — 7-Zip recreates a symlink entry's target verbatim, and that target
    /// is just as untrusted as the entry's own name. Unlike a crafted
    /// *name* (already handled by never building paths from `entryPath`),
    /// a crafted *target* like "/Users/me/.ssh/id_rsa" is the resolved
    /// result the OS itself will follow the moment anything reads through
    /// this link — most immediately Quick Look, which `DragOut.extract`
    /// also feeds: pressing Space on an entry that looks like an innocuous
    /// file would silently render the real target file's content instead.
    /// A symlink whose target resolves *inside* `scratch` (pointing at
    /// another file 7-Zip also just extracted) is harmless and left alone.
    private static func rejectSymlinkEscapingScratch(_ url: URL, scratch: URL) throws {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return
        }
        let resolvedTarget = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent())
            .standardizedFileURL
        let scratchPath = scratch.standardizedFileURL.path
        guard resolvedTarget.path == scratchPath || resolvedTarget.path.hasPrefix(scratchPath + "/") else {
            throw ArchiveError.operationFailed(
                code: -1,
                message: "This entry is a symbolic link pointing outside the archive's extracted contents and can't be opened this way."
            )
        }
    }

    /// Finds the item 7-Zip actually extracted for `entryPath` inside `root`,
    /// without ever building a filesystem path by concatenating `entryPath`
    /// itself: that's an untrusted string from inside a possibly-malicious
    /// archive, and a name like "../../../../Users/me/.ssh/id_rsa" would
    /// resolve outside `root` to a real file on disk — which callers then
    /// *move*, silently relocating or exfiltrating whatever that traversal
    /// landed on.
    ///
    /// Instead this walks the real directories 7-Zip wrote under `root`, one
    /// level per path component of `entryPath`, requiring each ancestor to
    /// have exactly one child before descending into it. A malicious
    /// `entryPath` can't steer this anywhere unsafe: 7-Zip sanitizes `../`
    /// itself, so everything under `root` is already confined there, and
    /// this only ever *counts* `entryPath`'s components (to know how many
    /// levels an entry like "docs/reports/file.pdf" should nest) — never
    /// their content. Not comparing each level's name against the expected
    /// component too: entry names round-tripped through the archive can
    /// differ in Unicode normalization from what 7-Zip writes to an APFS
    /// volume, which would otherwise fail a perfectly legitimate extraction.
    ///
    /// A naive first attempt at this fix returned `root`'s *only top-level*
    /// item — the first path component's directory — for any nested entry,
    /// dragging out the whole ancestor folder chain instead of the file
    /// itself. Shared with `ArchiveViewModel.copyEntry`, which extracts a
    /// single entry into a scratch folder the same way and has the same
    /// nesting problem.
    static func locateExtractedItem(forEntryPath entryPath: String, in root: URL) throws -> URL {
        let trimmed = entryPath.hasSuffix("/") ? String(entryPath.dropLast()) : entryPath
        let depth = trimmed.split(separator: "/").count
        var current = root
        for _ in 0..<max(depth, 1) {
            let children = try FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: nil)
            guard let onlyChild = children.first, children.count == 1 else {
                throw ArchiveError.operationFailed(code: -1, message: "Extraction did not produce the expected single item.")
            }
            current = onlyChild
        }
        return current
    }

    /// Deletes staging folders left over from previous drags. Call once at app
    /// startup — Finder never signals completion, so we sweep anything older
    /// than `age` instead. Use 24 hours (not 1 hour) to avoid race conditions
    /// where a drag is still in progress when the app restarts.
    static func sweepStaleStaging(olderThan age: TimeInterval = 86400) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in items {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    static func typeIdentifier(for entry: ArchiveEntry) -> String {
        let ext = (entry.name as NSString).pathExtension
        if entry.isDirectory {
            // A directory whose name is a known package extension (.app,
            // .bundle, .framework, …) needs that real UTI declared, not a
            // generic "public.folder": Finder silently refuses the drop
            // entirely for one of these when it's promised as a plain
            // folder while ending in ".app" — no error, the drag just does
            // nothing. `conformingTo: .package` synthesizes a placeholder
            // "dyn.*" identifier for any extension it doesn't actually
            // recognize as a package type — never nil — so that has to be
            // filtered back out, or *every* folder with a dot in its name
            // (a plain folder named "notes.2024", say) would wrongly take
            // this branch too.
            if !ext.isEmpty, let type = UTType(filenameExtension: ext, conformingTo: .package),
               !type.identifier.hasPrefix("dyn.") {
                return type.identifier
            }
            return UTType.folder.identifier
        }
        if !ext.isEmpty, let type = UTType(filenameExtension: ext), !type.conforms(to: .text) {
            return type.identifier
        }
        // Text-conforming UTIs (plain text, source code, etc.) make Finder
        // treat the drop as a text clipping instead of accepting our file
        // promise, so the drop silently does nothing. A generic data type
        // still lets Finder land the file with its real name/extension.
        return UTType.data.identifier
    }
}
