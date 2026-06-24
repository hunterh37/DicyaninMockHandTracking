import SwiftUI
import DicyaninMockHandTracking
import DicyaninHandRecording

struct ContentView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var immersiveOpen = false

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Glove Demo")
                    .font(.largeTitle.bold())
                Text("Open the immersive scene, then drag the hand joysticks. A glove follows each mock hand. On device the same view follows your real hands joint for joint.")
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
                    } else if case .opened = await openImmersiveSpace(id: "gloves") {
                        immersiveOpen = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            MockHandControlView()

            HandRecordingControlView()
        }
        .padding(40)
    }
}
