import Foundation

/// One page of the Help window — a sidebar of topics rather than one long
/// scrolling page, so a question has a place to be looked up rather than
/// scrolled to.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let sections: [HelpSection]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct HelpSection: Identifiable, Hashable {
    let id = UUID()
    var heading: String?
    var paragraphs: [String] = []
    /// Term-and-explanation rows, for actions and settings enumerated one
    /// after another.
    var rows: [Row] = []

    struct Row: Identifiable, Hashable {
        let id = UUID()
        let term: String
        let detail: String
        /// A quiet tag beside the term — a default value, "Off by default".
        var note: String?
    }
}

enum HelpLibrary {
    static let topics: [HelpTopic] = [
        HelpTopic(id: "what-it-does", title: "What 7ZIP4MAC does", symbol: "sparkles", sections: [
            HelpSection(paragraphs: [
                "7ZIP4MAC is a native interface for the official 7-Zip engine, bundled unmodified inside the app. It lets you browse, extract, create, and edit archives in most formats — 7z, ZIP, TAR, GZ, BZ2, XZ, RAR, ISO, CAB, CPIO, ARJ, LZH, WIM, RPM, DEB, CHM, and more.",
                "This app performs no compression itself — all archive operations run through the official 7-Zip engine.",
            ]),
        ]),
        HelpTopic(id: "keyboard-shortcuts", title: "Keyboard Shortcuts", symbol: "keyboard", sections: [
            HelpSection(paragraphs: [
                "Only shortcuts 7ZIP4MAC itself actually implements — not every inherited standard macOS one (⌘W, ⌘Q, ⌘M), which every app already has and doesn't need repeating here.",
            ]),
            HelpSection(heading: "Archive window", rows: [
                .init(term: "⌘O", detail: "Open an archive."),
                .init(term: "⌘N", detail: "Create a new archive."),
                .init(term: "⌘E", detail: "Extract all items."),
                .init(term: "⌘⇧B", detail: "Open the Benchmark window."),
                .init(term: "Space / ⌘Y", detail: "Toggle Quick Look preview of selected items."),
                .init(term: "Return", detail: "Enter the selected folder."),
                .init(term: "Escape", detail: "Exit to parent folder (or close archive if at root)."),
            ]),
        ]),
        HelpTopic(id: "browsing", title: "Opening and browsing archives", symbol: "folder.badge.questionmark", sections: [
            HelpSection(heading: "Opening", paragraphs: [
                "Open an archive with File ▸ Open (⌘O) or by dragging a file onto the 7ZIP4MAC window. The archive's contents appear in a file list with icons, sizes, dates, and compression details.",
            ]),
            HelpSection(heading: "Navigation", paragraphs: [
                "Double-click a folder to enter it. Click the back/forward navigation arrows at the top to move between folders you've already opened. Press Return to enter a folder, or Escape to go back to its parent.",
                "The breadcrumb at the top shows your current location — click any part of it to jump directly to that level.",
            ]),
            HelpSection(heading: "Selection and preview", rows: [
                .init(term: "Select items", detail: "Click to select one, ⌘-click to toggle others, Shift-click to select a range."),
                .init(term: "Quick Look", detail: "Press Space or ⌘Y to preview one or more selected items; press again to close."),
                .init(term: "Drag to extract", detail: "Drag any selected item to Finder to extract just that item there (folders are extracted with their full contents)."),
            ]),
            HelpSection(heading: "Right-click menu", rows: [
                .init(term: "Extract", detail: "Extract the selected item to a destination you choose."),
                .init(term: "Reveal in Finder", detail: "Jump to the actual extracted file on disk (if it's already been extracted)."),
            ]),
        ]),
        HelpTopic(id: "extraction", title: "Extracting archives", symbol: "arrow.down.doc", sections: [
            HelpSection(heading: "Extract All", paragraphs: [
                "Click Extract All (⌘E) to extract the entire archive. You'll be asked to choose a destination folder. 7ZIP4MAC uses your Settings ▸ General overwrite policy (Overwrite / Skip / Rename Extracted File) if any files already exist at the destination.",
            ]),
            HelpSection(heading: "Extract selection", paragraphs: [
                "Select one or more items first, then Extract All extracts only those items instead, preserving their folder structure inside your chosen destination.",
            ]),
            HelpSection(heading: "Drag to extract", paragraphs: [
                "Drag any selected item straight to Finder to extract just that item there. If you drag a folder, it's extracted with its entire contents inside.",
            ]),
            HelpSection(heading: "Overwrite policy", rows: [
                .init(term: "Overwrite", detail: "Replace any existing file."),
                .init(term: "Skip", detail: "Leave existing files alone."),
                .init(term: "Rename", detail: "Rename the extracted file if a conflict occurs."),
            ]),
        ]),
        HelpTopic(id: "creation", title: "Creating archives", symbol: "doc.badge.plus", sections: [
            HelpSection(heading: "New Archive", paragraphs: [
                "Click New Archive (⌘N) or File ▸ New Archive. Choose files and folders, select an archive format and compression level, set a password (optional), then click Create to choose where to save it.",
            ]),
            HelpSection(heading: "Profiles", paragraphs: [
                "Profiles are saved format/compression/password combinations you can reuse. After your first archive, Settings ▸ Profiles lets you create, rename, and delete them. Each new archive defaults to your last-used profile.",
            ]),
            HelpSection(heading: "Formats", rows: [
                .init(term: "7z", detail: "7ZIP4MAC's native format — best compression, supports passwords and huge files.", note: "Default"),
                .init(term: "ZIP", detail: "Maximum compatibility with older systems; slightly larger files."),
                .init(term: "TAR", detail: "Unix/Linux standard — no compression by itself; usually combined with GZ or BZ2."),
            ]),
        ]),
        HelpTopic(id: "editing", title: "Editing archives", symbol: "pencil.circle", sections: [
            HelpSection(heading: "Add files", paragraphs: [
                "Right-click inside an archive and select Add, or click the toolbar Add button. Choose files or folders to add; they're inserted at the archive's current level.",
            ]),
            HelpSection(heading: "Rename", paragraphs: [
                "Right-click an entry and select Rename, or select it and click the toolbar Rename button. Enter a new name; the change is applied immediately.",
            ]),
            HelpSection(heading: "Move and Copy", paragraphs: [
                "Move lets you reorganize entries within the archive (changing their folder location). Copy duplicates an entry under a new name. Both require single-item selection.",
            ]),
            HelpSection(heading: "Delete", paragraphs: [
                "Select one or more items and click Delete (or press Delete key). Confirm the removal — it's permanent.",
            ]),
        ]),
        HelpTopic(id: "passwords", title: "Encrypted archives", symbol: "lock.circle", sections: [
            HelpSection(heading: "Opening encrypted archives", paragraphs: [
                "When you open a password-protected archive, 7ZIP4MAC prompts for the password. Enter it and click OK; the password is kept in memory for that session only and never written to disk.",
            ]),
            HelpSection(heading: "Creating encrypted archives", paragraphs: [
                "When creating a new archive, check 'Encrypt file names' (optional — protects filenames too) and enter a password. Leaving the password blank creates an unencrypted archive.",
            ]),
            HelpSection(heading: "Password notes", rows: [
                .init(term: "Passwords are case-sensitive", detail: "ABC ≠ abc"),
                .init(term: "Forgotten passwords cannot be recovered", detail: "7-Zip encryption is strong; there is no backdoor."),
                .init(term: "ZIP password support is limited", detail: "Some very old software may not recognize modern ZIP encryption."),
            ]),
        ]),
        HelpTopic(id: "testing", title: "Testing archive integrity", symbol: "checkmark.seal", sections: [
            HelpSection(heading: "Test", paragraphs: [
                "Click the toolbar Test button (or ⌘⇧T if you've set that shortcut) to verify that an archive can be read and decompressed without errors. Testing extracts everything to a temporary folder, checks every byte, then deletes the temp folder.",
            ]),
            HelpSection(heading: "Before relying on an archive", paragraphs: [
                "If you're about to delete the original files or move an archive to long-term storage, run Test first. Corruption from disk errors, incomplete transfers, or malware is rare but possible; testing gives you confidence.",
            ]),
        ]),
        HelpTopic(id: "toolbar", title: "Toolbar and customization", symbol: "square.and.pencil", sections: [
            HelpSection(heading: "Customizing the toolbar", paragraphs: [
                "Right-click the toolbar at the top of the window and select 'Customize Toolbar…'. Drag buttons to reorder them, drag them away to remove them, or click 'Restore Defaults' to reset. Your custom layout is remembered.",
            ]),
            HelpSection(heading: "Toolbar buttons", rows: [
                .init(term: "Open", detail: "Open an archive."),
                .init(term: "New Archive", detail: "Create a new archive."),
                .init(term: "Extract All", detail: "Extract everything or selected items."),
                .init(term: "Test", detail: "Verify archive integrity."),
                .init(term: "Add", detail: "Add files to the archive."),
                .init(term: "Rename", detail: "Rename the selected item."),
                .init(term: "Move", detail: "Move the selected item to a different folder inside the archive."),
                .init(term: "Copy", detail: "Copy the selected item under a new name."),
                .init(term: "Delete", detail: "Delete the selected item(s)."),
                .init(term: "Up", detail: "Go to the parent folder."),
                .init(term: "Quick Look", detail: "Preview selected items (Space)."),
                .init(term: "Inspector", detail: "Show file details and statistics."),
                .init(term: "Close", detail: "Close the current archive."),
                .init(term: "More", detail: "Additional actions (Uninstall)."),
            ]),
        ]),
        HelpTopic(id: "settings", title: "Settings and preferences", symbol: "gearshape", sections: [
            HelpSection(heading: "General", rows: [
                .init(term: "Default format", detail: "Format used when creating a new archive (7z, ZIP, TAR, etc.)."),
                .init(term: "Compression level", detail: "Balance between size and speed."),
                .init(term: "Default password", detail: "Pre-fill the password field when creating encrypted archives."),
                .init(term: "Overwrite policy", detail: "What to do when an extracted file already exists (Overwrite, Skip, or Rename)."),
                .init(term: "Show hidden files", detail: "If on, archive listings include files starting with a dot (.gitignore, etc.)."),
            ]),
            HelpSection(heading: "Profiles", paragraphs: [
                "Manage saved format/compression/password combinations. Create new profiles to quickly switch between favorite archive settings.",
            ]),
        ]),
    ]
}
