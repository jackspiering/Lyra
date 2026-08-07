import Foundation

enum FileSystemVault {
    static func shouldInclude(name: String) -> Bool {
        !name.hasPrefix(".")
    }

    static func scan(root: URL, shouldCancel: () -> Bool = { false }) throws -> VaultNode {
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
            return VaultNode(name: name, url: root, isDirectory: false, children: nil)
        }

        // Note: `.skipsPackageDescendants` only applies to directory enumerators, not
        // contentsOfDirectory — packages are skipped via `.isPackageKey` below.
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
            options: []
        )

        var children: [VaultNode] = []
        for childURL in contents {
            if shouldCancel() { throw CancellationError() }
            do {
                let childName = childURL.lastPathComponent
                guard shouldInclude(name: childName) else { continue }

                let values = try childURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
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
                    children.append(try scan(root: childURL, shouldCancel: shouldCancel))
                } else if childURL.pathExtension.lowercased() == "md" {
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
        return VaultNode(name: name, url: root, isDirectory: true, children: children)
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
