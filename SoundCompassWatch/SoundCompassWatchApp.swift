import SwiftUI

@main
struct SoundCompassWatchApp: App {
    @StateObject private var bridge = WatchConnectivityBridge()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(bridge)
                .onAppear { bridge.activate() }
        }
    }
}
