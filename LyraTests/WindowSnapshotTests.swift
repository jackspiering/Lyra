import AppKit
import SwiftUI
import XCTest
@testable import Lyra

/// Renders the vault window over a sample vault to PNG files so a pull
/// request shows what the UI looks like; CI uploads them as an artifact.
/// Runs only when `LYRA_SNAPSHOTS=1` (xcodebuild forwards
/// `TEST_RUNNER_LYRA_SNAPSHOTS`). There are no pixel assertions.
///
/// Rendering is offscreen, so system materials (the titlebar, sidebar glass,
/// the status pill blur) can look flatter than in the running app.
@MainActor
final class WindowSnapshotTests: XCTestCase {
    private static let windowSize = NSSize(width: 1280, height: 800)
    private static let restoredDefaults = ["lyra.noteViewMode", "lyra.lastVaultBookmark"]

    private var root: URL!
    private var outputDirectory: URL!
    private var windows: [NSWindow] = []
    private var savedDefaults: [String: Any] = [:]

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["LYRA_SNAPSHOTS"] == "1" else {
            throw XCTSkip("Set LYRA_SNAPSHOTS=1 (TEST_RUNNER_LYRA_SNAPSHOTS=1 for xcodebuild) to render snapshots.")
        }
        root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        // Sandboxed test host: write inside the app container's tmp.
        outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyraSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for key in Self.restoredDefaults {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    override func tearDownWithError() throws {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows = []
        for key in Self.restoredDefaults {
            UserDefaults.standard.set(savedDefaults[key], forKey: key)
        }
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
    }

    func testRenderWelcome() throws {
        for dark in [true, false] {
            let view = ContentView(store: VaultStore(), tabs: NoteTabController(), openNewVaultWindow: nil)
            try render(view, name: "welcome", dark: dark)
        }
    }

    func testRenderVaultWindow() throws {
        let vault = try SampleVault.write(under: root)
        for mode in NoteViewMode.allCases {
            UserDefaults.standard.set(mode.rawValue, forKey: "lyra.noteViewMode")
            for dark in [true, false] {
                let (store, tabs) = try openSampleVault(vault)
                let view = ContentView(store: store, tabs: tabs, openNewVaultWindow: nil)
                try render(view, name: "window-\(mode.rawValue)", dark: dark)
            }
        }
        for dark in [true, false] {
            let (store, _) = try openSampleVault(vault, openNotes: false)
            let view = ContentView(store: store, tabs: NoteTabController(), openNewVaultWindow: nil)
            try render(view, name: "window-empty-tab", dark: dark)
        }
    }

    func testRenderPanels() throws {
        let vault = try SampleVault.write(under: root)
        let (store, _) = try openSampleVault(vault)
        let target = vault.appendingPathComponent(SampleVault.mainNote)
        let backlinks = store.backlinks(to: target, liveBodies: [:])
        XCTAssertFalse(backlinks.isEmpty, "sample vault should link to the main note")
        for dark in [true, false] {
            try render(
                BacklinksInspector(items: backlinks, onOpen: { _ in }, onHide: {})
                    .frame(width: 280, height: 560),
                name: "backlinks",
                dark: dark,
                size: NSSize(width: 280, height: 560)
            )
            try render(
                SidebarView(store: store).frame(width: 260, height: 560),
                name: "sidebar",
                dark: dark,
                size: NSSize(width: 260, height: 560)
            )
            try render(
                SnapshotPalette(store: store, mode: .searchVault, query: "writing"),
                name: "palette-search",
                dark: dark,
                size: NSSize(width: 760, height: 560)
            )
            try render(
                SnapshotPalette(store: store, mode: .goToFile, query: "wr"),
                name: "palette-go-to-file",
                dark: dark,
                size: NSSize(width: 760, height: 460)
            )
        }
    }

    // MARK: - Helpers

    private func openSampleVault(
        _ vault: URL,
        openNotes: Bool = true
    ) throws -> (VaultStore, NoteTabController) {
        let store = VaultStore()
        let tabs = NoteTabController()
        store.openVault(at: vault)
        spin(until: { store.rootNode != nil }, timeout: 10)
        XCTAssertNotNil(store.rootNode, "sample vault did not scan")
        guard openNotes else { return (store, tabs) }
        let main = vault.appendingPathComponent(SampleVault.mainNote)
        XCTAssertTrue(tabs.openInActiveTab(url: main))
        for extra in SampleVault.extraTabs {
            XCTAssertTrue(tabs.openInNewTab(url: vault.appendingPathComponent(extra)))
        }
        tabs.select(tabs.tabs[0].id)
        store.selection = main.path
        return (store, tabs)
    }

    private func render<V: View>(
        _ view: V,
        name: String,
        dark: Bool,
        size: NSSize? = nil
    ) throws {
        let size = size ?? Self.windowSize
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = SnapshotWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.toolbarStyle = .unified
        window.backgroundColor = LyraTheme.chrome
        window.contentViewController = controller
        window.setContentSize(size)
        window.setFrameOrigin(.zero)
        window.orderFrontRegardless()
        windows.append(window)

        // Let SwiftUI lay out, run `.task`s (word counts, backlinks), and draw.
        spin(for: 1.2)
        // Nothing focused: a field editor would draw its selection.
        window.makeFirstResponder(nil)
        spin(for: 0.1)

        let target: NSView = window.contentView?.superview ?? controller.view
        target.layoutSubtreeIfNeeded()
        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
            return XCTFail("no bitmap for \(name)")
        }
        target.cacheDisplay(in: target.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no PNG for \(name)")
        }
        let file = outputDirectory.appendingPathComponent("\(name)-\(dark ? "night" : "parchment").png")
        try png.write(to: file)
        print("snapshot: \(file.path)")

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = file.lastPathComponent
        attachment.lifetime = .keepAlways
        add(attachment)

        window.orderOut(nil)
    }

    private func spin(for seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func spin(until condition: () -> Bool, timeout: TimeInterval) {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

/// A window the test can size beyond the CI display (1024×768), which would
/// otherwise clamp every frame.
private final class SnapshotWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// A palette over a paper backdrop, with a query typed.
private struct SnapshotPalette: View {
    let store: VaultStore
    let mode: VaultPalette.Mode
    @State var query: String

    var body: some View {
        ZStack {
            LyraTheme.paperColor
            VaultPalette(
                mode: mode,
                query: $query,
                results: { query in
                    await ContentView.paletteResults(mode: mode, query: query, store: store, liveBodies: [:])
                },
                onOpen: { _ in },
                onClose: {}
            )
        }
    }
}

/// A small vault that exercises the sidebar, tabs, Source styling, Reading
/// blocks, and backlinks.
private enum SampleVault {
    static let mainNote = "Essays/On Slow Writing.md"
    static let extraTabs = ["Reading/Deep Work.md", "Essays/Tools That Disappear.md"]

    static func write(under parent: URL) throws -> URL {
        let vault = parent.appendingPathComponent("Field Notes", isDirectory: true)
        if FileManager.default.fileExists(atPath: vault.path) { return vault }
        let notes: [String: String] = [
            mainNote: """
            Most tools for thinking are built for speed. They promise capture in a keystroke and \
            retrieval in a blink. But the notes I return to were rarely written quickly — they were \
            **rewritten**, slowly, until the idea held its own weight.

            ## A folder, not a platform

            The whole vault is plain Markdown on disk. When I link to [[The Commonplace Book]] or \
            [[Tools That Disappear]], that link is just text — `grep` can find it, git can diff it, \
            and it will outlive this app.

            > "Writing is nature's way of letting you know how sloppy your thinking is."

            - Write first, organise later.
            - Let links emerge instead of designing a taxonomy.
            - [x] Re-read the backlinks before starting a new note
            - [ ] Publish the *slow writing* essay

            ```swift
            let note = try String(contentsOf: url, encoding: .utf8)
            ```
            """,
            "Essays/Tools That Disappear.md": """
            # Tools That Disappear

            The best editor is the one you forget about, which is the argument of [[On Slow Writing]].
            """,
            "Essays/The Commonplace Book.md": "A commonplace book collects passages worth keeping.\n",
            "Reading/Deep Work.md": "Notes on focus. See [[On Slow Writing]] for the writing side.\n",
            "Reading/How to Take Smart Notes.md": """
            Ahrens' slip-box pairs well with [[On Slow Writing]]: fewer notes, better ones.
            """,
            "Projects/Planning/2026 Writing Goals.md": "- Publish [[On Slow Writing]] before autumn.\n",
            "Archive/Old Draft.md": "An early draft.\n",
            "Inbox.md": "- Call the printer\n- Outline the next essay\n",
            "Zettelkasten.md": "Index of permanent notes.\n",
        ]
        for (path, body) in notes {
            let url = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        return vault
    }
}
