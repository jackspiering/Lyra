import Foundation

struct VaultNode: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [VaultNode]?
}

extension VaultNode {
    /// Markdown notes at or below this node (a note counts itself).
    var noteCount: Int {
        guard isDirectory else { return 1 }
        return (children ?? []).reduce(0) { $0 + $1.noteCount }
    }
}
