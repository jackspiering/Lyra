import Foundation

enum NoteViewMode: String, CaseIterable, Identifiable {
    case source
    case livePreview
    case reading

    var id: String { rawValue }

    var label: String {
        switch self {
        case .source: return "Source"
        case .livePreview: return "Live"
        case .reading: return "Reading"
        }
    }

    func next() -> NoteViewMode {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}
