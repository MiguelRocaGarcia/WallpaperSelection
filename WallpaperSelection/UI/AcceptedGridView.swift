import Photos
import SwiftUI

/// Shows what's in the Wallpapers album, with the option to take photos back out.
struct AcceptedGridView: View {
    @EnvironmentObject private var deck: DeckModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [Candidate] = []
    @State private var preview: Candidate?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 3)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(items) { item in
                        Button { preview = item } label: {
                            ThumbnailView(asset: item.asset)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Wallpaper photo")
                        .accessibilityIdentifier("thumbnail-\(item.id)")
                    }
                }
                .padding(3)
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No wallpapers yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Swipe right on a photo to add it to your \(PhotoLibraryService.albumTitle) album.")
                    )
                }
            }
            .navigationTitle("\(PhotoLibraryService.albumTitle) (\(items.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: reload)
        .fullScreenCover(item: $preview) { item in
            AcceptedPreviewView(candidate: item) {
                Task {
                    await deck.removeFromAlbum(item.asset)
                    reload()
                }
            }
        }
    }

    private func reload() {
        // Album order is insertion order; show the most recently added first.
        items = PhotoLibraryService.shared.albumAssets().reversed().map { Candidate(asset: $0) }
    }
}

struct ThumbnailView: View {
    let asset: PHAsset
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color(white: 0.15)
            .aspectRatio(9.0 / 19.5, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: asset.localIdentifier) {
                let size = CGSize(width: 130 * displayScale, height: 280 * displayScale)
                image = await PhotoLibraryService.shared.thumbnailImage(for: asset, targetSize: size)
            }
    }
}

struct AcceptedPreviewView: View {
    let candidate: Candidate
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    var body: some View {
        ZStack {
            GeometryReader { geo in
                PhotoCardView(asset: candidate.asset, size: geo.size)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close")
                }
                Spacer()
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Remove from \(PhotoLibraryService.albumTitle)", systemImage: "minus.circle")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("removeFromAlbumButton")
            }
            .foregroundStyle(.white)
            .padding()
        }
        .background(Color.black)
        .confirmationDialog("Remove this photo from the \(PhotoLibraryService.albumTitle) album?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                onRemove()
                dismiss()
            }
        } message: {
            Text("The photo stays in your library and won't be suggested again.")
        }
    }
}
