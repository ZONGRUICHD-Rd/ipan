import SwiftUI

@main
struct iPANApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            CameraScreen(settings: settings)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
