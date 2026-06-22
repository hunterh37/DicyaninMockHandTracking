import SwiftUI
import RealityKit

/// Immersive scene with a single green sphere that tracks the right hand.
///
/// We keep a reference to the sphere entity and mutate its `position` directly
/// from `HandSource`'s pose stream — no scene rebuilds. In the simulator it
/// moves with the `MockHandControlView` joystick; on device the same code path
/// follows the real hand, with no change to this view.
struct ImmersiveView: View {
    private let handSource = HandSource()
    @State private var sphere = ModelEntity(
        mesh: .generateSphere(radius: 0.05),
        materials: [SimpleMaterial(color: .green, isMetallic: false)]
    )

    var body: some View {
        RealityView { content in
            content.add(sphere)
        }
        .task {
            do {
                try await handSource.start()
            } catch {
                print("HandSource failed to start: \(error)")
                return
            }
            for await pose in handSource.poses() {
                sphere.position = pose.position
            }
        }
    }
}
