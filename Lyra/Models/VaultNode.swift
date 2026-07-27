import Foundation

struct VaultNode: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [VaultNode]?
}
