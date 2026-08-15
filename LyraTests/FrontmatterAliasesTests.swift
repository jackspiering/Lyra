import XCTest
@testable import Lyra

final class FrontmatterAliasesTests: XCTestCase {
    func testInlineList() {
        let md = """
        ---
        aliases: [Plan, Map]
        ---
        Body
        """
        XCTAssertEqual(FrontmatterAliases.parse(from: md), ["Plan", "Map"])
    }

    func testSingleValue() {
        let md = """
        ---
        aliases: Plan
        ---
        """
        XCTAssertEqual(FrontmatterAliases.parse(from: md), ["Plan"])
    }

    func testYamlList() {
        let md = """
        ---
        aliases:
          - One
          - "Two"
        ---
        """
        XCTAssertEqual(FrontmatterAliases.parse(from: md), ["One", "Two"])
    }

    func testIgnoresOtherKeysAndBody() {
        let md = """
        ---
        title: Not An Alias
        aliases: Real
        tags: [nope]
        ---
        aliases: Fake
        """
        XCTAssertEqual(FrontmatterAliases.parse(from: md), ["Real"])
    }

    func testRequiresLeadingFence() {
        XCTAssertEqual(FrontmatterAliases.parse(from: "aliases: Plan\n"), [])
        XCTAssertEqual(FrontmatterAliases.parse(from: "# Title\n---\naliases: X\n---\n"), [])
    }

    func testUnclosedFenceIsIgnored() {
        XCTAssertEqual(FrontmatterAliases.parse(from: "---\naliases: X\n"), [])
    }
}
