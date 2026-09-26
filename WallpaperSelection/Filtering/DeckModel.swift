import Photos
import SwiftUI

struct Candidate: Identifiable, Equatable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }

    static func == (lhs: Candidate, rhs: Candidate) -> Bool { lhs.id == rhs.id }
}

/// Walks the library newest-first, filters photos, and keeps a small buffer of wallpaper
/// candidates ready ahead of the card on screen. Also owns swipe decisions and undo.
@MainActor
final class DeckModel: ObservableObject {
    enum Decision {
        case accepted(Candidate)
        case rejected(Candidate)

        var isAccept: Bool {
            if case .accepted = self { return true }
            return false
        }
    }

    @Published private(set) var cards: [Candidate] = []
    @Published private(set) var acceptedCount = 0
    @Published private(set) var rejectedCount = 0
    @Published private(set) var scannedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var isScanning = false
    @Published private(set) var hasStarted = false
    @Published private(set) var canUndo = false
    @Published var errorMessage: String?

    let store = DecisionStore()
    private let library = PhotoLibraryService.shared

    private var fetchResult: PHFetchResult<PHAsset>?
    /// Fetch-result indexes in the order they'll be shown (shuffled for random order).
    private var scanOrder: [Int] = []
    private var nextIndex = 0
    private var acceptedIDs = Set<String>()
    private var queuedIDs = Set<String>()
    private var history: [Decision] = [] {
        didSet { canUndo = !history.isEmpty }
    }
    private var scanTask: Task<Void, Never>?
    private var generation = 0
    private var activeSettings = FilterSettings.current
    private var albumOperation: Task<Void, Never>?
    private var cachedAssets: [PHAsset] = []
    private var cardPixelSize = CGSize(width: 1179, height: 2556)

    private let bufferTarget = 6
    private let parallelism = 3
    private let prefetchCount = 3
    private let historyLimit = 50
    private let yieldEvery = 300

    init() {
        #if DEBUG
        // UI tests pass -uiTestResetStore YES to start from a clean slate.
        if UserDefaults.standard.bool(forKey: "uiTestResetStore") {
            store.resetRejections()
            store.clearAnalysisCache()
        }
        #endif
    }

    var isExhausted: Bool { hasStarted && !isScanning && nextIndex >= totalCount }
    var isLimitedToDates: Bool { activeSettings.limitDates }

    // MARK: Lifecycle

    /// (Re)starts scanning from the newest photo. Cached analyses make repeat scans fast.
    func start() {
        scanTask?.cancel()
        scanTask = nil
        generation += 1
        activeSettings = FilterSettings.current

        let fetch = library.fetchImages(settings: activeSettings)
        fetchResult = fetch
        totalCount = fetch.count
        scanOrder = Array(0..<fetch.count)
        if activeSettings.order == .random { scanOrder.shuffle() }
        acceptedIDs = Set(library.albumAssets().map(\.localIdentifier))
        acceptedCount = acceptedIDs.count
        rejectedCount = store.rejectedCount

        cards = []
        queuedIDs = []
        history = []
        nextIndex = 0
        scannedCount = 0
        isScanning = false
        hasStarted = true

        updatePrefetch()
        fillIfNeeded()
    }

    func restartIfSettingsChanged() {
        if FilterSettings.current != activeSettings { start() }
    }

    func resetRejections() {
        store.resetRejections()
        start()
    }

    func clearAnalysisCache() {
        store.clearAnalysisCache()
        start()
    }

    func setCardPixelSize(_ size: CGSize) {
        guard size.width > 0, size != cardPixelSize else { return }
        library.stopCachingAll()
        cachedAssets = []
        cardPixelSize = size
        updatePrefetch()
    }

    // MARK: Decisions

    func accept(_ card: Candidate) {
        guard removeCard(card) else { return }
        acceptedIDs.insert(card.id)
        acceptedCount = acceptedIDs.count
        pushHistory(.accepted(card))
        performAlbumOperation("Couldn't add the photo to \(PhotoLibraryService.albumTitle)") { [library] in
            try await library.add(card.asset)
        }
        afterDecision()
    }

    func reject(_ card: Candidate) {
        guard removeCard(card) else { return }
        store.reject(card.id)
        rejectedCount = store.rejectedCount
        pushHistory(.rejected(card))
        afterDecision()
    }

    /// Reverts the last decision and puts that card back on top. Returns what was undone.
    @discardableResult
    func undo() -> Decision? {
        guard let last = history.popLast() else { return nil }
        switch last {
        case .accepted(let card):
            acceptedIDs.remove(card.id)
            acceptedCount = acceptedIDs.count
            performAlbumOperation("Couldn't remove the photo from \(PhotoLibraryService.albumTitle)") { [library] in
                try await library.remove(card.asset)
            }
            cards.insert(card, at: 0)
        case .rejected(let card):
            store.unreject(card.id)
            rejectedCount = store.rejectedCount
            cards.insert(card, at: 0)
        }
        updatePrefetch()
        return last
    }

    /// Used from the accepted grid: takes the photo out of the album and stops suggesting it.
    func removeFromAlbum(_ asset: PHAsset) async {
        let id = asset.localIdentifier
        acceptedIDs.remove(id)
        acceptedCount = acceptedIDs.count
        store.reject(id)
        rejectedCount = store.rejectedCount
        history.removeAll { decision in
            if case .accepted(let card) = decision { return card.id == id }
            return false
        }
        await performAlbumOperation("Couldn't remove the photo from \(PhotoLibraryService.albumTitle)") { [library] in
            try await library.remove(asset)
        }.value
    }

    private func removeCard(_ card: Candidate) -> Bool {
        guard let index = cards.firstIndex(of: card) else { return false }
        cards.remove(at: index)
        return true
    }

    private func pushHistory(_ decision: Decision) {
        history.append(decision)
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }

    private func afterDecision() {
        updatePrefetch()
        fillIfNeeded()
    }

    /// Album changes run one after another so an accept followed by a quick undo can't be reordered.
    @discardableResult
    private func performAlbumOperation(_ failureMessage: String,
                                       _ operation: @escaping () async throws -> Void) -> Task<Void, Never> {
        let previous = albumOperation
        let task = Task { [weak self] in
            await previous?.value
            do {
                try await operation()
            } catch {
                self?.errorMessage = "\(failureMessage): \(error.localizedDescription)"
            }
        }
        albumOperation = task
        return task
    }

    // MARK: Scanning

    private func fillIfNeeded() {
        guard scanTask == nil, cards.count < bufferTarget, nextIndex < totalCount else { return }
        let gen = generation
        isScanning = true
        scanTask = Task { [weak self] in
            await self?.scan(generation: gen)
        }
    }

    private func scan(generation gen: Int) async {
        let settings = activeSettings
        var sinceYield = 0

        while gen == generation, !Task.isCancelled, cards.count < bufferTarget,
              let fetch = fetchResult, nextIndex < fetch.count {
            // Cheap pass: skip known/ineligible photos and use cached results; collect a batch for Vision.
            var batch: [PHAsset] = []
            while batch.count < parallelism, cards.count < bufferTarget,
                  nextIndex < fetch.count, sinceYield < yieldEvery {
                let asset = fetch.object(at: scanOrder[nextIndex])
                nextIndex += 1
                sinceYield += 1
                let id = asset.localIdentifier
                if acceptedIDs.contains(id) || queuedIDs.contains(id) || store.isRejected(id) { continue }
                if !MetadataFilter.passes(asset, settings: settings) { continue }
                if let cached = store.analysis(for: id) {
                    if cached.passes(settings) { enqueue(asset) }
                    continue
                }
                batch.append(asset)
            }
            scannedCount = nextIndex

            if sinceYield >= yieldEvery {
                sinceYield = 0
                await Task.yield()
                guard gen == generation else { return }
            }
            guard !batch.isEmpty else { continue }

            let results = await analyze(batch)
            guard gen == generation, !Task.isCancelled else { return }
            for (asset, result) in results {
                guard let result else { continue } // image unavailable; try again next scan
                let id = asset.localIdentifier
                store.setAnalysis(result, for: id)
                if result.passes(settings), !store.isRejected(id), !acceptedIDs.contains(id) {
                    enqueue(asset)
                }
            }
        }

        guard gen == generation else { return }
        scanTask = nil
        isScanning = false
    }

    /// Runs Vision on several photos in parallel off the main actor, preserving order.
    private func analyze(_ assets: [PHAsset]) async -> [(PHAsset, AnalysisResult?)] {
        await withTaskGroup(of: (Int, AnalysisResult?).self) { group in
            for (index, asset) in assets.enumerated() {
                group.addTask {
                    guard let image = await PhotoLibraryService.shared.analysisImage(for: asset) else {
                        return (index, nil)
                    }
                    return (index, VisionFilter.analyze(image))
                }
            }
            var results = [AnalysisResult?](repeating: nil, count: assets.count)
            for await (index, result) in group {
                results[index] = result
            }
            return Array(zip(assets, results))
        }
    }

    private func enqueue(_ asset: PHAsset) {
        cards.append(Candidate(asset: asset))
        queuedIDs.insert(asset.localIdentifier)
        updatePrefetch()
    }

    /// Keeps full-screen images for the next few cards warm in PhotoKit's cache.
    private func updatePrefetch() {
        let wanted = cards.prefix(prefetchCount).map(\.asset)
        let wantedIDs = Set(wanted.map(\.localIdentifier))
        let cachedIDs = Set(cachedAssets.map(\.localIdentifier))
        let toStop = cachedAssets.filter { !wantedIDs.contains($0.localIdentifier) }
        let toStart = wanted.filter { !cachedIDs.contains($0.localIdentifier) }
        if !toStop.isEmpty { library.stopCaching(toStop, targetSize: cardPixelSize) }
        if !toStart.isEmpty { library.startCaching(toStart, targetSize: cardPixelSize) }
        cachedAssets = wanted
    }
}
