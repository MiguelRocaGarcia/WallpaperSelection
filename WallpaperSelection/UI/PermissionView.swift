import Photos
import SwiftUI

struct PermissionView: View {
    let status: PHAuthorizationStatus

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
            Text("Full photo access needed")
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var message: String {
        if status == .limited {
            return "You've only allowed access to some photos. To find wallpapers across your whole library, choose Full Access in Settings ▸ Privacy & Security ▸ Photos ▸ Wallpapers."
        }
        return "Wallpapers needs access to your photos to find ones without people and add your picks to a Wallpapers album. Everything is analyzed on your iPhone."
    }
}
