import Photos

/// Cheap checks that only use PHAsset metadata, so most of the library is skipped without loading pixels.
enum MetadataFilter {
    static func passes(width: Int, height: Int, isScreenshot: Bool, minShortSide: Int) -> Bool {
        guard !isScreenshot else { return false }
        guard height > width else { return false }
        return min(width, height) >= minShortSide
    }

    static func passes(_ asset: PHAsset, settings: FilterSettings) -> Bool {
        passes(
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
            minShortSide: settings.minShortSide
        )
    }
}
