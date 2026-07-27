import XCTest
@testable import Lyra

final class UntitledNameTests: XCTestCase {
    func testEmptyDirectoryReturnsUntitled() throws {
        let dir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(UntitledName.next(in: dir), "Untitled.md")
    }

    func testExistingUntitledIncrements() throws {
        let dir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("Untitled.md").path,
            contents: Data(),
            attributes: nil
        )
        XCTAssertEqual(UntitledName.next(in: dir), "Untitled 2.md")

        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("Untitled 2.md").path,
            contents: Data(),
            attributes: nil
        )
        XCTAssertEqual(UntitledName.next(in: dir), "Untitled 3.md")
    }

    func testFolderNameWithoutExtension() throws {
        let dir = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertEqual(UntitledName.next(base: "New Folder", ext: nil, in: dir), "New Folder")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("New Folder"),
            withIntermediateDirectories: false
        )
        XCTAssertEqual(UntitledName.next(base: "New Folder", ext: nil, in: dir), "New Folder 2")
    }
}
