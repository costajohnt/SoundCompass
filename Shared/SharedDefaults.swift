import Foundation

/// The `UserDefaults` suite shared between the watch app and its
/// complication extension.
///
/// An app extension runs in its own sandbox: `UserDefaults.standard`
/// inside the widget is a *different file* from the watch app's. The two
/// can only meet in an App Group container, declared in both targets'
/// entitlements. If the group is unavailable (e.g. a build signed without
/// the capability) this falls back to `.standard`, which keeps the app
/// working and leaves the complication showing its placeholder.
enum SharedDefaults {
    static let appGroup = "group.com.costajohnt.soundcompass"

    static let lastDirectionKey = "soundcompass.watch.lastDirection"
    static let lastUpdateKey = "soundcompass.watch.lastUpdate"

    static var store: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }
}
