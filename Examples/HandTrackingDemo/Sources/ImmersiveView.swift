import SwiftUI
import RealityKit
import DicyaninHandGlove

/// Immersive scene that renders a glove on each hand, built on Apple's
/// "Tracking and visualizing hand movement" sample.
///
/// This is the whole integration: one view. In the simulator the gloves follow
/// the `MockHandControlView` joysticks (or the webcam bridge); on device the
/// same code path follows the real ARKit hand skeleton, joint for joint.
///
/// To use a rigged glove USDZ instead of the procedural glove, add the model to
/// the app bundle and pass `.model(left:right:)`:
/// ```swift
/// HandGloveView(configuration: .init(
///     style: .model(left: "LeftGlove_v001", right: "RightGlove_v001")
/// ))
/// ```
struct ImmersiveView: View {
    var body: some View {
        HandGloveView()
    }
}
