import GuitarTunerKit
import GuitarTunerUI
import SwiftUI

/// iOS entry point. The audio session is configured inside `TunerController`, so the
/// app itself only has to own the controller and hand it to the shared UI.
@main
struct GuitarTuneriOSApp: App {
    @State private var controller = TunerController()

    var body: some Scene {
        WindowGroup {
            TunerView(controller: controller)
                .preferredColorScheme(.dark)
        }
    }
}
