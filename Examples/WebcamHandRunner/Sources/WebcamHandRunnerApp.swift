import SwiftUI

/// A tiny macOS app that watches your webcam, estimates your hand poses with
/// Vision, and broadcasts them to a running visionOS app via
/// `DicyaninHandTrackingTransport`. Hold your hands up to the camera and the
/// same pose data the on-screen mock joysticks would produce is piped, live,
/// into your visionOS app.
@main
struct WebcamHandRunnerApp: App {
    @StateObject private var model = HandRunnerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 560)
                .task { await model.start() }
        }
        .windowResizability(.contentMinSize)
    }
}
