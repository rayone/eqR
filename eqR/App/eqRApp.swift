import SwiftUI

@main
struct EqRApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // eqR is a menu bar app (LSUIElement); the main window is managed
        // by AppDelegate so it can be opened from the status item menu.
        //
        // This scene is the standard Settings window. Being an accessory
        // application, eqR has no App menu to open it from, so the status
        // menu does — see `MenuBarController`.
        Settings {
            SettingsView()
        }
    }
}
