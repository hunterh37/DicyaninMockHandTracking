//
//  HandGloveView.swift
//  DicyaninHandGlove
//
//  Adapted from Apple's "Tracking and visualizing hand movement" sample
//  (HandTrackingView.swift): adds one empty entity per hand with a
//  hand-tracking component and lets the system do the rest.
//

#if os(visionOS)
import SwiftUI
import RealityKit

/// Drop-in immersive content that renders a glove on each tracked hand.
///
/// On device the gloves follow real ARKit hand tracking. In the visionOS
/// simulator they follow `MockHandTrackingController` (the same joysticks /
/// webcam bridge the rest of this package uses), so you can develop the glove
/// without a headset.
///
/// Re-implementing the Apple glove sample is now a single view:
/// ```swift
/// ImmersiveSpace(id: "Gloves") {
///     HandGloveView()
/// }
/// ```
/// Drop in your own rigged glove model:
/// ```swift
/// HandGloveView(configuration: .init(
///     style: .model(left: "LeftGlove_v001", right: "RightGlove_v001")
/// ))
/// ```
public struct HandGloveView: View {
    private let configuration: HandGloveConfiguration

    public init(configuration: HandGloveConfiguration = .default) {
        self.configuration = configuration
    }

    public var body: some View {
        RealityView { content in
            HandGloveView.addHands(to: content, configuration: configuration)
        }
    }

    /// Adds the glove hands into any RealityView content. Use this when you want
    /// the gloves inside a scene you're already building, instead of the
    /// standalone ``HandGloveView``.
    @MainActor
    public static func addHands(
        to content: any RealityViewContentProtocol,
        configuration: HandGloveConfiguration = .default
    ) {
        if configuration.tracksLeftHand {
            let left = Entity()
            left.components.set(HandTrackingComponent(chirality: .left, configuration: configuration))
            content.add(left)
        }
        if configuration.tracksRightHand {
            let right = Entity()
            right.components.set(HandTrackingComponent(chirality: .right, configuration: configuration))
            content.add(right)
        }
    }
}
#endif
