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
}
