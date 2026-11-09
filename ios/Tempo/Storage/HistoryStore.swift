import Foundation
import Observation
import ChessCore

/// A position the user analysed recently.
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var fen: String
    var orientationIsWhite: Bool
    var date: Date
    var source: Source
    /// Last evaluation seen, for display ("+1.20", "M3").
    var evaluation: String?

    enum Source: String, Codable { case scan, setup, board }

    var position: Position { (try? Position(fen: fen)) ?? .start }
    var orientation: PieceColor { orientationIsWhite ? .white : .black }
}

/// Recent positions, stored as a small JSON file in Application Support.
@Observable
final class HistoryStore {
    private(set) var entries: [HistoryEntry] = []
    private let url: URL
    private let limit = 30

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    /// Inserts or refreshes an entry for the same position; returns its id.
    @discardableResult
    func record(position: Position, orientation: PieceColor, source: HistoryEntry.Source) -> UUID {
        let fen = position.fen
        entries.removeAll { $0.fen == fen }
        let entry = HistoryEntry(fen: fen, orientationIsWhite: orientation == .white, date: .now, source: source)
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
        return entry.id
    }

    func updateEvaluation(_ text: String, for id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].evaluation != text else { return }
        entries[i].evaluation = text
        save()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        let snapshot = entries
        let url = url
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }
}
