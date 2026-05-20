import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("NSWindow") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let window = NSApplication.shared.windows.first else { return }
        window.isRestorable = false
        window.setFrame(NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: 680, height: 360), display: true, animate: false)
        window.center()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct hm_app_check_toolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 680, height: 360)
        .windowResizability(.contentMinSize)
    }
}