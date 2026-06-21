import SwiftUI
import DicyaninMockHandTracking

/// Control window: opens the immersive scene and hosts the mock hand controls.
struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var immersiveOpen = false

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Mock Hand Tracking Demo")
                    .font(.largeTitle.bold())
                Text("Open the immersive scene, then drag the RIGHT HAND joystick. The green sphere follows the mock hand position.")
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
                    } else {
                        if case .opened = await openImmersiveSpace(id: "demo") {
                            immersiveOpen = true
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            // The control overlay shipped by the package.
            MockHandControlView()
        }
        .padding(40)
    }
}
