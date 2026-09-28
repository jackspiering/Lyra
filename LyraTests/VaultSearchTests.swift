import XCTest
@testable import Lyra

final class VaultSearchTests: XCTestCase {
    func testEmptyQueryMatchesAll() {
        XCTAssertTrue(VaultSearch.matches(nodeName: "A.md", path: "/v/A.md", query: ""))
        XCTAssertTrue(VaultSearch.matches(nodeName: "A.md", path: "/v/A.md", query: "   "))
    }

    func testSubstringCaseInsensitive() {
        XCTAssertTrue(VaultSearch.matches(nodeName: "Welcome.md", path: "notes/Welcome.md", query: "come"))
        XCTAssertTrue(VaultSearch.matches(nodeName: "Welcome.md", path: "notes/Welcome.md", query: "WELCOME"))
        XCTAssertFalse(VaultSearch.matches(nodeName: "Welcome.md", path: "notes/Welcome.md", query: "zzz"))
    }

    func testPathSubstringMatches() {
        XCTAssertTrue(VaultSearch.matches(nodeName: "Note.md", path: "projects/alpha/Note.md", query: "alpha"))
        XCTAssertFalse(VaultSearch.matches(nodeName: "Note.md", path: "projects/alpha/Note.md", query: "beta"))
    }

    func testFilteredTreeEmptyQueryReturnsRoot() {
        let root = sampleTree()
        let filtered = VaultSearch.filteredTree(root: root, query: "")
        XCTAssertEqual(filtered, root)
    }

    func testFilteredTreeKeepsAncestorsOfMatches() {
        let root = sampleTree()
        let filtered = VaultSearch.filteredTree(root: root, query: "deep")

        // vault → folder → Deep.md
        XCTAssertEqual(filtered.name, "vault")
        let children = filtered.children ?? []
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].name, "folder")
        let nested = children[0].children ?? []
        XCTAssertEqual(nested.map(\.name), ["Deep.md"])
    }

    func testFilteredTreeIncludesMatchingFolderAndPathDescendants() {
        let root = sampleTree()
        let filtered = VaultSearch.filteredTree(root: root, query: "folder")

        // Folder matches by name; Deep.md matches because relative path contains "folder".
        let children = filtered.children ?? []
        XCTAssertEqual(children.map(\.name), ["folder"])
        XCTAssertEqual((children[0].children ?? []).map(\.name), ["Deep.md"])
        // Top.md is not under folder and does not match.
        XCTAssertFalse((filtered.children ?? []).contains { $0.name == "Top.md" })
    }

    func testFilteredTreeMatchingFolderKeepsOnlyMatchingLeaves() {
        let vault = URL(fileURLWithPath: "/tmp/vault")
        let projects = vault.appendingPathComponent("projects")
        let root = VaultNode(
            name: "vault",
            url: vault,
            isDirectory: true,
            children: [
                VaultNode(
                    name: "projects",
                    url: projects,
                    isDirectory: true,
                    children: [
                        VaultNode(
                            name: "Alpha.md",
                            url: projects.appendingPathComponent("Alpha.md"),
                            isDirectory: false,
                            children: nil
                        ),
                        VaultNode(
                            name: "Beta.md",
                            url: projects.appendingPathComponent("Beta.md"),
                            isDirectory: false,
                            children: nil
                        ),
                    ]
                ),
            ]
        )
        let filtered = VaultSearch.filteredTree(root: root, query: "alpha")
        let children = filtered.children ?? []
        XCTAssertEqual(children.map(\.name), ["projects"])
        XCTAssertEqual((children[0].children ?? []).map(\.name), ["Alpha.md"])
    }

    func testFilteredTreeNoMatchYieldsEmptyChildren() {
        let root = sampleTree()
        let filtered = VaultSearch.filteredTree(root: root, query: "zzz-nope")
        XCTAssertEqual(filtered.name, "vault")
        XCTAssertEqual(filtered.children ?? [], [])
    }

    func testFilteredTreeMatchesByPathSegment() {
        let root = sampleTree()
        // "folder" is in the relative path of Deep.md → keep the note under ancestors
        let filtered = VaultSearch.filteredTree(root: root, query: "folder/Deep")
        let children = filtered.children ?? []
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].name, "folder")
        XCTAssertEqual((children[0].children ?? []).map(\.name), ["Deep.md"])
    }

    // MARK: - Fixtures

    private func sampleTree() -> VaultNode {
        let vault = URL(fileURLWithPath: "/tmp/vault")
        let folder = vault.appendingPathComponent("folder")
        let deep = folder.appendingPathComponent("Deep.md")
        let top = vault.appendingPathComponent("Top.md")
        return VaultNode(
            name: "vault",
            url: vault,
            isDirectory: true,
            children: [
                VaultNode(
                    name: "folder",
                    url: folder,
                    isDirectory: true,
                    children: [
                        VaultNode(name: "Deep.md", url: deep, isDirectory: false, children: nil),
                    ]
                ),
                VaultNode(name: "Top.md", url: top, isDirectory: false, children: nil),
            ]
        )
    }

    // MARK: - Go to File ranking

    private func entries(_ paths: [String]) -> [VaultSearch.NoteEntry] {
        paths.map { VaultSearch.NoteEntry(url: URL(fileURLWithPath: "/v/" + $0), relativePath: $0) }
    }

    private func ranked(_ paths: [String], _ query: String) -> [String] {
        VaultSearch.rankNotes(entries(paths), query: query).map(\.relativePath)
    }

    func testRankEmptyQueryListsNotesByPath() {
        XCTAssertEqual(
            ranked(["b/Note 10.md", "a.md", "b/Note 2.md"], "  "),
            ["a.md", "b/Note 2.md", "b/Note 10.md"]
        )
    }

    func testRankPrefersExactThenPrefixThenWordThenSubstring() {
        let paths = ["Rewriting.md", "Writing Goals.md", "On Slow Writing.md", "Writing.md", "x/Notes.md"]
        XCTAssertEqual(
            ranked(paths, "writing"),
            ["Writing.md", "Writing Goals.md", "On Slow Writing.md", "Rewriting.md"]
        )
    }

    func testRankMatchesFolderPathAndLettersInOrder() {
        XCTAssertEqual(ranked(["Essays/Draft.md", "Other.md"], "essays"), ["Essays/Draft.md"])
        XCTAssertEqual(ranked(["On Slow Writing.md", "Other.md"], "osw"), ["On Slow Writing.md"])
        XCTAssertEqual(ranked(["On Slow Writing.md"], "writing slow"), ["On Slow Writing.md"])
        XCTAssertTrue(ranked(["On Slow Writing.md"], "zzz").isEmpty)
    }

    func testRankIsCaseInsensitiveAndBreaksTiesByShorterName() {
        XCTAssertEqual(ranked(["b/Deep Work Notes.md", "a/DEEP WORK.md"], "deep work"), ["a/DEEP WORK.md", "b/Deep Work Notes.md"])
    }

    func testRankHonoursLimit() {
        XCTAssertEqual(VaultSearch.rankNotes(entries(["a.md", "b.md", "c.md"]), query: "", limit: 2).count, 2)
    }

    func testNoteEntryNameAndFolder() {
        let entry = VaultSearch.NoteEntry(url: URL(fileURLWithPath: "/v/Essays/On Slow Writing.md"), relativePath: "Essays/On Slow Writing.md")
        XCTAssertEqual(entry.name, "On Slow Writing")
        XCTAssertEqual(entry.folder, "Essays")
    }
}
