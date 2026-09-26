import Photos
import SwiftUI

@main
struct WallpaperSelectionApp: App {
    @StateObject private var deck = DeckModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(deck)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                deck.store.saveNow(synchronously: true)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var deck: DeckModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = PhotoLibraryService.shared.authorizationStatus

    var body: some View {
        Group {
            switch status {
            case .authorized:
                SwipeDeckView()
            case .notDetermined:
                Color.black
                    .ignoresSafeArea()
                    .task { status = await PhotoLibraryService.shared.requestAuthorization() }
            default:
                PermissionView(status: status)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may have changed access in Settings while the app was in the background.
            if phase == .active {
                status = PhotoLibraryService.shared.authorizationStatus
            }
        }
    }
}
