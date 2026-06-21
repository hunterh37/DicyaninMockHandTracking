import SwiftUI

/// Minimal visionOS app demonstrating `DicyaninMockHandTracking`.
///
/// A 2D control window drives a mock right hand; an immersive space shows a
/// green sphere that follows that hand in real time. In the simulator the
/// sphere is steered by the on-screen joystick (`MockHandControlView`); on a
/// real device the same code path reads ARKit hand anchors instead — see
/// `HandSource`.
@main
struct HandTrackingDemoApp: App {
    var body: some Scene {
        WindowGroup(id: "control") {
            ContentView()
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: "demo") {
            ImmersiveView()
        }
    }
}
