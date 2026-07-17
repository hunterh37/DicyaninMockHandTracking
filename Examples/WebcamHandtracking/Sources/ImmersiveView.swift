import SwiftUI
import simd
import DicyaninHandGlove

/// World-space lift applied to everything in the immersive scene. The mock and
/// webcam hand sources are head-relative (y = 0 is eye level) while the
/// ImmersiveSpace origin sits on the floor at the user's feet, so unlifted
/// content renders below the room floor. Raising it by roughly eye height puts
/// the floor plate, fruit, and gloves in front of the viewer, above the floor.
enum SceneSpace {
    static let lift = SIMD3<Float>(0, 1.4, 0)
}

/// A glove on each hand. In the simulator the gloves follow the webcam bridge
/// (or the joysticks); on device they follow the real ARKit hand skeleton.
struct ImmersiveView: View {
    var body: some View {
        ZStack {
            HandGloveView(configuration: {
                var config = HandGloveConfiguration.default
                config.rootOffset = SceneSpace.lift
                return config
            }())
            FruitSceneView()
        }
    }
}
