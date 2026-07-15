import SwiftUI
import DicyaninHandGlove

/// A glove on each hand. In the simulator the gloves follow the webcam bridge
/// (or the joysticks); on device they follow the real ARKit hand skeleton.
struct ImmersiveView: View {
    var body: some View {
        ZStack {
            HandGloveView()
            PinchSphereView()
        }
    }
}
