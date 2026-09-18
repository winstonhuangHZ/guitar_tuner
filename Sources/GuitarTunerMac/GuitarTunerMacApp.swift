import GuitarTunerKit
import GuitarTunerUI
import SwiftUI

#if os(macOS)
import AppKit

/// `swift run` launches a bare executable rather than a bundled app, so the process has
/// to promote itself to a regular app for the window, menu bar and microphone prompt to
/// behave normally.
final class GuitarTunerAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

@main
struct GuitarTunerMacApp: App {
    @State private var controller = TunerController()

    #if os(macOS)
    @NSApplicationDelegateAdaptor(GuitarTunerAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup("Guitar Tuner") {
            AppView(controller: controller)
                .preferredColorScheme(.light)
        }
        #if os(macOS)
        .defaultSize(width: 520, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }
}
