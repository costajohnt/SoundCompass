import SwiftUI

@main
struct SoundCompassApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var detector: AudioDirectionDetector
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = SettingsStore()
        let detector = AudioDirectionDetector(settings: store)
        _settings = StateObject(wrappedValue: store)
        _detector = StateObject(wrappedValue: detector)
        // Register the detector with the intent broker so Siri/Shortcuts
        // entry points (`StartListeningIntent`, etc.) can drive it without
        // re-creating a second detector.
        IntentBroker.register(detector)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(detector)
                .environmentObject(settings)
                .preferredColorScheme(resolvedColorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // UIBackgroundModes: audio keeps the tap alive in background,
            // but we still want the detector to know we've been backgrounded
            // so it can freeze the front/back resolver (which burns motion
            // updates) and re-prime the classifier when we come back.
            switch newPhase {
            case .background:
                detector.handleBackgroundTransition()
            case .active:
                detector.handleForegroundTransition()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// Turns the stored `SettingsStore.Theme` into the `ColorScheme?`
    /// that `preferredColorScheme(_:)` expects. `.system` returns `nil`
    /// so SwiftUI falls back to the OS setting.
    private var resolvedColorScheme: ColorScheme? {
        switch settings.theme {
        case .system: return nil
        case .dark:   return .dark
        case .light:  return .light
        }
    }
}
