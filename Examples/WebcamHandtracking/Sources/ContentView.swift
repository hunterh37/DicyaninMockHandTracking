import SwiftUI
import DicyaninMockHandTracking

/// Control window: opens the immersive scene and connects the webcam bridge.
struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var immersiveOpen = false
    @ObservedObject private var hands = MockHandTrackingController.shared

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Webcam Hand Tracking")
                    .font(.largeTitle.bold())
                Text("1. Run WebcamHandRunner on your Mac and grant camera access.\n2. Open the immersive scene.\n3. Toggle the webcam bridge and hold your hands up to the Mac's camera.\nThe gloves follow your real hands. Pinch thumb-to-index to fire a pinch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            Button(immersiveOpen ? "Close Immersive Scene" : "Open Immersive Scene") {
                Task {
                    if immersiveOpen {
                        await dismissImmersiveSpace()
                        immersiveOpen = false
                    } else if case .opened = await openImmersiveSpace(id: "webcam") {
                        immersiveOpen = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            Toggle(isOn: Binding(
                get: { hands.isWebcamConnected },
                set: { on in
                    if on { hands.connectToWebcamRunner() }
                    else { hands.disconnectWebcamRunner() }
                }
            )) {
                Label(hands.isWebcamConnected ? "Webcam connected — hold your hands up"
                                              : "Connect to WebcamHandRunner",
                      systemImage: hands.isWebcamConnected ? "video.fill" : "video")
            }
            .toggleStyle(.button)
            .tint(hands.isWebcamConnected ? .green : .accentColor)

            // Fallback: on-screen joysticks drive the same state.
            MockHandControlView()
        }
        .padding(40)
    }
}
