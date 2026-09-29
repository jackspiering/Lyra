import XCTest
@testable import Lyra

final class NoteTitleTests: XCTestCase {
    func testDisplayTitleUsesFilenameStem() {
        let url = URL(fileURLWithPath: "/vault/Welcome.md")
        XCTAssertEqual(NoteTitle.displayTitle(fileURL: url), "Welcome")
    }

    @MainActor
    func testSidebarShowsNoteStemAndFullFolderName() {
        let note = VaultNode(name: "Node.js.md", url: URL(fileURLWithPath: "/v/Node.js.md"), isDirectory: false, children: nil)
        let folder = VaultNode(name: "Archive.md", url: URL(fileURLWithPath: "/v/Archive.md"), isDirectory: true, children: [])
        XCTAssertEqual(note.displayName, "Node.js")
        XCTAssertEqual(folder.displayName, "Archive.md")
    }

    func testDisplayTitleKeepsInnerDots() {
        let url = URL(fileURLWithPath: "/vault/Node.js.md")
        XCTAssertEqual(NoteTitle.displayTitle(fileURL: url), "Node.js")
    }

    func testDisplayTitleNilURLIsEmpty() {
        XCTAssertEqual(NoteTitle.displayTitle(fileURL: nil), "")
    }

    func testTitleBecomesStem() {
        XCTAssertEqual(NoteTitle.stem(forTitle: "New Title"), .ok("New Title"))
    }

    func testTitleRejectsInvalidStem() {
        guard case .invalid = NoteTitle.stem(forTitle: "  Bad/Name  ") else {
            return XCTFail("expected an invalid title")
        }
    }

    func testTitleStripsMdSuffix() {
        XCTAssertEqual(NoteTitle.stem(forTitle: "Note.md"), .ok("Note"))
    }

    func testBreadcrumbListsVaultThenFolders() {
        let root = URL(fileURLWithPath: "/Users/me/Field Notes")
        let note = URL(fileURLWithPath: "/Users/me/Field Notes/Essays/Drafts/On Slow Writing.md")
        XCTAssertEqual(
            NoteTitle.breadcrumb(fileURL: note, vaultRoot: root),
            ["Field Notes", "Essays", "Drafts"]
        )
    }

    func testBreadcrumbAtVaultRootIsVaultName() {
        let root = URL(fileURLWithPath: "/vault")
        let note = URL(fileURLWithPath: "/vault/Inbox.md")
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: note, vaultRoot: root), ["vault"])
    }

    func testBreadcrumbOutsideVaultOrMissingIsEmpty() {
        let root = URL(fileURLWithPath: "/vault")
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: URL(fileURLWithPath: "/elsewhere/A.md"), vaultRoot: root), [])
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: URL(fileURLWithPath: "/vault-2/A.md"), vaultRoot: root), [])
        XCTAssertEqual(NoteTitle.breadcrumb(fileURL: nil, vaultRoot: root), [])
    }
}
