import Foundation

/// Decision for restoring the last vault from a security-scoped bookmark.
enum VaultBookmarkRestore {
    enum Decision: Equatable {
        /// Bookmark resolved and is fresh — open and re-persist.
        case autoOpen
        /// Bookmark resolved but macOS marked it stale — ask the user first.
        case promptUser
        /// Nothing usable was resolved.
        case skip
    }

    static func decision(didResolve: Bool, isStale: Bool) -> Decision {
        guard didResolve else { return .skip }
        return isStale ? .promptUser : .autoOpen
    }

    /// Stale bookmarks must not be rewritten until the user confirms the folder.
    static func shouldPersistOnRestore(_ decision: Decision) -> Bool {
        decision == .autoOpen
    }
}
