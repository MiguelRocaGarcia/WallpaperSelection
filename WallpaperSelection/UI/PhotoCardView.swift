import Photos
import SwiftUI

/// A photo filling the whole screen with aspect-fill, the same way iOS crops a wallpaper.
struct PhotoCardView: View {
    let asset: PHAsset
    let size: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isFullQuality = false
    @State private var filename = ""

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            }
            if !isFullQuality {
                // Shown while the full-quality original loads (e.g. downloading from iCloud).
                ProgressView()
                    .tint(.white)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo")
        .accessibilityValue(filename)
        .task(id: asset.localIdentifier) {
            filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
            let pixelSize = CGSize(width: size.width * displayScale, height: size.height * displayScale)
            let library = PhotoLibraryService.shared
            if image == nil, let quick = await library.quickImage(for: asset, targetSize: pixelSize) {
                image = quick
            }
            if let full = await library.cardImage(for: asset, targetSize: pixelSize) {
                image = full
            }
            isFullQuality = true
        }
    }
}
