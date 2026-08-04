import Foundation

enum NoteViewMode: String, CaseIterable, Identifiable {
    case source
    case reading

    var id: String { rawValue }

    var label: String {
        switch self {
        case .source: return "Source"
        case .reading: return "Reading"
        }
    }

    func next() -> NoteViewMode {
        self == .source ? .reading : .source
    }
}
