import Foundation

/// Persists rejected photo IDs and cached Vision results as JSON in Application Support.
@MainActor
final class DecisionStore {
    private struct Snapshot: Codable {
        var version: Int
        var rejected: [String]
        var analyses: [String: AnalysisResult]
    }

    /// Bump when AnalysisResult or VisionFilter changes meaningfully; old analyses are then discarded.
    private static let analysisVersion = 1

    nonisolated static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("decisions.json")
    }

    private var rejected = Set<String>()
    private var analyses: [String: AnalysisResult] = [:]
    private let fileURL: URL
    private let writer = SnapshotWriter()
    private var saveTask: Task<Void, Never>?
    private var saveSequence = 0

    init(fileURL: URL = DecisionStore.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    // MARK: Rejections

    var rejectedCount: Int { rejected.count }

    func isRejected(_ id: String) -> Bool { rejected.contains(id) }

    func reject(_ id: String) {
        rejected.insert(id)
        scheduleSave()
    }

    func unreject(_ id: String) {
        rejected.remove(id)
        scheduleSave()
    }

    func resetRejections() {
        rejected.removeAll()
        saveNow()
    }

    // MARK: Analysis cache

    func analysis(for id: String) -> AnalysisResult? { analyses[id] }

    func setAnalysis(_ result: AnalysisResult, for id: String) {
        analyses[id] = result
        scheduleSave()
    }

    func clearAnalysisCache() {
        analyses.removeAll()
        saveNow()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        rejected = Set(snapshot.rejected)
        if snapshot.version == Self.analysisVersion {
            analyses = snapshot.analyses
        }
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Encodes on a background thread. Pass `synchronously` when the app is about to be suspended.
    func saveNow(synchronously: Bool = false) {
        saveTask?.cancel()
        saveTask = nil
        saveSequence += 1
        let sequence = saveSequence
        let snapshot = Snapshot(version: Self.analysisVersion, rejected: Array(rejected), analyses: analyses)
        let url = fileURL
        let writer = writer
        let work: @Sendable () -> Void = {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            writer.write(data, sequence: sequence, to: url)
        }
        if synchronously {
            work()
        } else {
            Task.detached(priority: .utility) { work() }
        }
    }
}

/// Serializes file writes and drops snapshots older than the last one written.
private final class SnapshotWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastWritten = 0

    func write(_ data: Data, sequence: Int, to url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard sequence > lastWritten else { return }
        lastWritten = sequence
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
