import SwiftUI

/// visionOS demo that receives live hand poses from the macOS WebcamHandRunner.
///
/// Run WebcamHandRunner on your Mac, hold your hands up to the webcam, then run
/// this app in the visionOS simulator: the gloves in the immersive scene follow
/// your real hands. Poses arrive via DicyaninHandTrackingTransport and are
/// applied to MockHandTrackingController.shared, the same state the on-screen
/// joysticks drive, so no consumer code changes are needed.
@main
struct WebcamHandtrackingApp: App {
    var body: some Scene {
        WindowGroup(id: "control") {
            ContentView()
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: "webcam") {
            ImmersiveView()
        }
    }
}
