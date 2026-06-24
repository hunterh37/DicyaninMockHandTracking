//
//  HandTrackingComponent.swift
//  DicyaninHandGlove
//
//  Adapted from Apple's "Tracking and visualizing hand movement" sample
//  (HandTrackingComponent.swift). Extended to carry a glove configuration and
//  the bone segments used by the filled-glove style.
//

#if os(visionOS)
import RealityKit
import ARKit.hand_skeleton

/// A component that tracks an entity's children to the joints of one hand.
///
/// Attach this to an empty `Entity` and add it to a `RealityView`; the
/// ``HandTrackingSystem`` populates and drives the joints.
public struct HandTrackingComponent: Component {
    /// The chirality for the hand this component tracks.
    public let chirality: AnchoringComponent.Target.Chirality

    /// How this hand's glove is rendered.
    public let configuration: HandGloveConfiguration

    /// Maps each joint name to the entity that represents it.
    var joints: [HandSkeleton.JointName: Entity] = [:]

    /// Maps a child joint name to the bone-segment entity that connects it to
    /// its parent joint (used by the filled-glove style).
    var bones: [HandSkeleton.JointName: ModelEntity] = [:]

    /// Whether the per-joint entities have been created yet.
    var isBuilt = false

    /// Creates a new hand-tracking component.
    /// - Parameters:
    ///   - chirality: Which hand to track.
    ///   - configuration: How to render the glove.
    public init(
        chirality: AnchoringComponent.Target.Chirality,
        configuration: HandGloveConfiguration = .default
    ) {
        self.chirality = chirality
        self.configuration = configuration
        HandTrackingSystem.registerSystem()
    }
}
#endif
