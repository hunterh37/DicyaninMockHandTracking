import SwiftUI
import DicyaninHandGlove

struct ImmersiveView: View {
    var body: some View {
        HandGloveView(configuration: .init(
            style: .model(left: "LeftGlove", right: "RightGlove")
        ))
    }
}
