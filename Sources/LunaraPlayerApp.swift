import SwiftUI

@main
struct LunaraPlayerApp: App {
    init() {
        ImageCache.configureDiskCache()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
