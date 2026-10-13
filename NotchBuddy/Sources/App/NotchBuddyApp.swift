import SwiftUI
import AppKit

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() { MyCloudMigration.run() }

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
