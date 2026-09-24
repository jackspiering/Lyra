import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum FileSystemVault {
    /// Directories nested deeper than this are listed empty and not walked.
    static let maxDirectoryDepth = 64
    /// Notes larger than this are still openable, but are left out of search,
    /// aliases, and the backlink index.
    static let maxIndexedBodyBytes = 2 * 1024 * 1024

    struct ScanResult: Equatable {
        var node: VaultNode
        var didTruncate: Bool
    }

    static func shouldInclude(name: String) -> Bool {
        !name.hasPrefix(".")
    }

    static func scan(
        root: URL,
        shouldCancel: () -> Bool = { false },
        maxDepth: Int = maxDirectoryDepth
    ) throws -> VaultNode {
        try scanResult(root: root, shouldCancel: shouldCancel, maxDepth: maxDepth).node
    }

    static func scanResult(
        root: URL,
        shouldCancel: () -> Bool = { false },
        maxDepth: Int = maxDirectoryDepth
    ) throws -> ScanResult {
        try scanNode(root: root, shouldCancel: shouldCancel, depth: 0, maxDepth: maxDepth)
    }

    enum IndexedBody: Equatable {
        case body(String)
        case oversized
        case unreadable
    }

    /// Reads at most `maxBytes` of UTF-8 without following a final-path symlink.
    /// Returns `.oversized` for large files and `.unreadable` for missing,
    /// unreadable, non-regular, or invalid UTF-8 files.
    static func indexedUTF8Body(
        at url: URL,
        maxBytes: Int = maxIndexedBodyBytes
    ) -> IndexedBody {
        guard let data = safeBoundedData(at: url, maxBytes: maxBytes) else {
            return .unreadable
        }
        if data.count > maxBytes { return .oversized }
        guard let text = String(data: data, encoding: .utf8) else {
            return .unreadable
        }
        return .body(text)
    }

    /// Bounded read that refuses symlinks and non-regular files. Uses a file
    /// descriptor so validation and reading cannot be separated by a path swap.
    static func safeBoundedData(at url: URL, maxBytes: Int) -> Data? {
        let fd = url.path.withCString { path in
            open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        }
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            var status = stat()
            guard fstat(fd, &status) == 0,
                  (Int(status.st_mode) & Int(S_IFMT)) == Int(S_IFREG) else {
                try? handle.close()
                return nil
            }
            return try handle.read(upToCount: maxBytes + 1)
        } catch {
            try? handle.close()
            return nil
        }
    }

    /// Creates an empty file only when no object already exists at `url`.
    /// Returns false for collisions and I/O errors.
    static func exclusivelyCreateEmptyFile(at url: URL) -> Bool {
        let fd = url.path.withCString { path in
            open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o666))
        }
        guard fd >= 0 else { return false }
        return close(fd) == 0
    }

    static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func scanNode(
        root: URL,
        shouldCancel: () -> Bool,
        depth: Int,
        maxDepth: Int
    ) throws -> ScanResult {
        if shouldCancel() { throw CancellationError() }
        guard !isSymbolicLink(root) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let name = root.lastPathComponent
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else {
            throw CocoaError(.fileNoSuchFile)
        }

        if !isDir.boolValue {
            return ScanResult(
                node: VaultNode(name: name, url: root, isDirectory: false, children: nil),
                didTruncate: false
            )
        }

        // Note: `.skipsPackageDescendants` only applies to directory enumerators, not
        // contentsOfDirectory — packages are skipped via `.isPackageKey` below.
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isRegularFileKey],
            options: []
        )

        var children: [VaultNode] = []
        var didTruncate = false
        for childURL in contents {
            if shouldCancel() { throw CancellationError() }
            do {
                let childName = childURL.lastPathComponent
                guard shouldInclude(name: childName) else { continue }

                let values = try childURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isRegularFileKey]
                )
                // Skip bundles / packages so a stray .app or .rtfd is not expanded.
                if values.isPackage == true { continue }
                // Do not let a vault tree cross its filesystem boundary. This
                // also avoids reading a file symlink that points at another
                // vault or a private file.
                if values.isSymbolicLink == true {
                    continue
                }

                let childIsDir = values.isDirectory ?? false
                if childIsDir {
                    if childName.caseInsensitiveCompare(AttachmentStore.folderName) == .orderedSame {
                        continue
                    }
                    if depth >= maxDepth {
                        didTruncate = true
                        children.append(
                            VaultNode(name: childName, url: childURL, isDirectory: true, children: [])
                        )
                        continue
                    }
                    let nested = try scanNode(
                        root: childURL,
                        shouldCancel: shouldCancel,
                        depth: depth + 1,
                        maxDepth: maxDepth
                    )
                    didTruncate = didTruncate || nested.didTruncate
                    children.append(nested.node)
                } else if childURL.pathExtension.lowercased() == "md", values.isRegularFile == true {
                    children.append(VaultNode(name: childName, url: childURL, isDirectory: false, children: nil))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // One unreadable child must not blank the whole vault.
                continue
            }
        }

        children.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return ScanResult(
            node: VaultNode(name: name, url: root, isDirectory: true, children: children),
            didTruncate: didTruncate
        )
    }

    /// Returns whether `candidate` resolves below `root`, including the root
    /// itself. This is used before mutations because a stale tree can outlive
    /// a directory that was replaced on disk.
    static func isWithin(_ candidate: URL, root: URL) -> Bool {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let candidateComponents = candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy { $0 == $1 }
    }

    /// True only for an object strictly below `root`. The vault root itself is
    /// within the vault but must never be renamed or deleted as a note.
    static func isStrictDescendant(_ candidate: URL, root: URL) -> Bool {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let candidateComponents = candidate.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard candidateComponents.count > rootComponents.count else { return false }
        return zip(rootComponents, candidateComponents).allSatisfy { $0 == $1 }
    }

    /// Vault-relative path using path components, so `/vault/Notes2/x.md` is
    /// never shortened relative to `/vault/Notes`. Falls back to the filename
    /// for the root itself and for paths outside the vault.
    static func relativePath(for url: URL, under root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return Array(fileComponents.dropFirst(rootComponents.count)).joined(separator: "/")
    }

    /// Returns whether the URL itself is a symlink. This deliberately does not
    /// compare the full path with its resolved form because macOS commonly
    /// aliases `/var` and `/tmp` to `/private/...`.
    static func hasSymlink(_ url: URL) -> Bool {
        isSymbolicLink(url)
    }

    /// Checks the path components from a selected vault root to a candidate,
    /// excluding unrelated system aliases in the root's ancestors.
    static func hasSymlink(_ url: URL, relativeTo root: URL) -> Bool {
        let base = root.standardizedFileURL
        let candidate = url.standardizedFileURL
        let baseComponents = base.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count >= baseComponents.count,
              zip(baseComponents, candidateComponents).allSatisfy({ $0 == $1 }) else {
            return true
        }
        if isSymbolicLink(base) { return true }

        var current = base
        for component in candidateComponents.dropFirst(baseComponents.count) {
            current.appendPathComponent(component)
            if isSymbolicLink(current) { return true }
        }
        return false
    }

    static func isSafePath(_ candidate: URL, within root: URL) -> Bool {
        isWithin(candidate, root: root) && !hasSymlink(candidate, relativeTo: root)
    }

    static func isSafeDirectory(_ url: URL, within root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && isSafePath(url, within: root)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func collectNoteURLs(from node: VaultNode) -> [URL] {
        if !node.isDirectory {
            return node.url.pathExtension.lowercased() == "md" ? [node.url] : []
        }
        return (node.children ?? []).flatMap(collectNoteURLs(from:))
    }

    static func parentDirectory(for selection: VaultNode?, vaultRoot: URL) -> URL {
        guard let selection else { return vaultRoot }
        return selection.isDirectory ? selection.url : selection.url.deletingLastPathComponent()
    }

    static func findNode(id: String, in node: VaultNode) -> VaultNode? {
        if node.id == id { return node }
        for child in node.children ?? [] {
            if let found = findNode(id: id, in: child) { return found }
        }
        return nil
    }
}
