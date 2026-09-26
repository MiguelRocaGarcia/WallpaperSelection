import Photos
import UIKit

enum PhotoLibraryError: LocalizedError {
    case albumCreationFailed

    var errorDescription: String? {
        switch self {
        case .albumCreationFailed: return "Couldn't create the \(PhotoLibraryService.albumTitle) album."
        }
    }
}

/// Wraps PhotoKit: authorization, fetching, image loading and the Wallpapers album.
final class PhotoLibraryService: @unchecked Sendable {
    static let shared = PhotoLibraryService()
    static let albumTitle = "Wallpapers"

    let imageManager = PHCachingImageManager()
    private let albumIDKey = "wallpaperAlbumID"

    // MARK: Authorization

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: Fetching

    /// Still images, newest first, limited to the settings' date range when that's turned on.
    func fetchImages(settings: FilterSettings) -> PHFetchResult<PHAsset> {
        var predicates = [NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)]
        if settings.limitDates {
            predicates.append(Self.datePredicate(start: settings.startDate, end: settings.endDate))
        }
        let options = PHFetchOptions()
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: options)
    }

    /// Photos taken from the start of `start`'s day through the end of `end`'s day.
    static func datePredicate(start: Date, end: Date, calendar: Calendar = .current) -> NSPredicate {
        let from = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let until = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return NSPredicate(format: "creationDate >= %@ AND creationDate < %@", from as NSDate, until as NSDate)
    }

    // MARK: Album

    func existingAlbum() -> PHAssetCollection? {
        if let id = UserDefaults.standard.string(forKey: albumIDKey),
           let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject {
            return album
        }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", Self.albumTitle)
        let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
        if let album {
            UserDefaults.standard.set(album.localIdentifier, forKey: albumIDKey)
        }
        return album
    }

    func albumAssets() -> [PHAsset] {
        guard let album = existingAlbum() else { return [] }
        let result = PHAsset.fetchAssets(in: album, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func ensureAlbum() async throws -> PHAssetCollection {
        if let album = existingAlbum() { return album }
        let placeholder = PlaceholderBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Self.albumTitle)
            placeholder.id = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let id = placeholder.id,
              let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
        else { throw PhotoLibraryError.albumCreationFailed }
        UserDefaults.standard.set(album.localIdentifier, forKey: albumIDKey)
        return album
    }

    /// Adds a reference to the album; the photo itself is never duplicated.
    func add(_ asset: PHAsset) async throws {
        let album = try await ensureAlbum()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets([asset] as NSArray)
        }
    }

    /// Removes from the album only; the photo stays in the library.
    func remove(_ asset: PHAsset) async throws {
        guard let album = existingAlbum() else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.removeAssets([asset] as NSArray)
        }
    }

    // MARK: Images

    /// Small image for Vision analysis. Downloads from iCloud if needed.
    func analysisImage(for asset: PHAsset) async -> UIImage? {
        await image(for: asset, targetSize: CGSize(width: 512, height: 512), contentMode: .aspectFit, options: Self.analysisOptions)
    }

    /// Low-quality local image shown instantly while the full-quality one loads.
    func quickImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await image(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: Self.quickOptions)
    }

    /// Grid thumbnail. Tries the instant local preview first; if iOS hasn't generated one yet,
    /// asks for a properly rendered (and if needed, downloaded) image instead.
    func thumbnailImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        if let quick = await quickImage(for: asset, targetSize: targetSize) { return quick }
        return await image(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: Self.analysisOptions)
    }

    /// Screen-sized image for the full-screen card. Same options as prefetching so the cache is hit.
    func cardImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await image(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: Self.cardOptions)
    }

    func startCaching(_ assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: Self.cardOptions)
    }

    func stopCaching(_ assets: [PHAsset], targetSize: CGSize) {
        imageManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: Self.cardOptions)
    }

    func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
    }

    private func image(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode,
                       options: PHImageRequestOptions) async -> UIImage? {
        let box = ImageRequestBox()
        let manager = imageManager
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                guard box.setContinuation(continuation) else { return }
                let id = manager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode,
                                                   options: options) { image, _ in
                    box.finish(image)
                }
                box.setRequestID(id)
            }
        } onCancel: {
            if let id = box.cancel() {
                manager.cancelImageRequest(id)
            }
        }
    }

    private static let analysisOptions: PHImageRequestOptions = {
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true
        return o
    }()

    private static let quickOptions: PHImageRequestOptions = {
        let o = PHImageRequestOptions()
        o.deliveryMode = .fastFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = false
        return o
    }()

    private static let cardOptions: PHImageRequestOptions = {
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = true
        return o
    }()
}

private final class PlaceholderBox: @unchecked Sendable {
    var id: String?
}

/// Bridges a PHImageManager request (single callback in the delivery modes used here) to async/await,
/// making sure the continuation resumes exactly once, including on cancellation.
private final class ImageRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var requestID: PHImageRequestID?
    private var isCancelled = false

    /// Returns false (and resumes immediately) if the task was already cancelled.
    func setContinuation(_ c: CheckedContinuation<UIImage?, Never>) -> Bool {
        lock.lock()
        if isCancelled {
            lock.unlock()
            c.resume(returning: nil)
            return false
        }
        continuation = c
        lock.unlock()
        return true
    }

    func setRequestID(_ id: PHImageRequestID) {
        lock.lock()
        requestID = id
        lock.unlock()
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: image)
    }

    func cancel() -> PHImageRequestID? {
        lock.lock()
        isCancelled = true
        let id = requestID
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: nil)
        return id
    }
}
