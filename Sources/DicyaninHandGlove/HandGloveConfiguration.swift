//
//  HandGloveConfiguration.swift
//  DicyaninHandGlove
//

#if os(visionOS)
import RealityKit
import SwiftUI

/// How a hand glove should be rendered on top of the tracked skeleton.
public enum HandGloveStyle: Sendable {
    /// Apple's original sample look: one sphere per joint, nothing connecting
    /// them. The most faithful reproduction of the downloaded sample.
    case joints

    /// A filled-in glove: a sphere at every joint plus a bone segment spanning
    /// each consecutive pair of joints, so the hand reads as a solid glove.
    /// This is the default.
    case glove

    /// Load a rigged glove model by name from the app's main bundle (for
    /// example `"RightGlove_v001"` / `"LeftGlove_v001"`, or your own export).
    ///
    /// The model is attached to the wrist joint and follows the hand. Supply the
    /// resource name *without* the `.usdz` extension. Provide a name per
    /// chirality so left/right can use mirrored assets; pass the same name twice
    /// to reuse one model. If the resource can't be loaded the glove falls back
    /// to ``glove``.
    case model(left: String, right: String)
}

/// Visual + behavioral configuration for a tracked glove.
public struct HandGloveConfiguration: Sendable {
    /// Which hands to render.
    public var tracksLeftHand: Bool
    public var tracksRightHand: Bool

    /// How the glove is drawn.
    public var style: HandGloveStyle

    /// Radius of the joint spheres, in meters. Knuckles render slightly larger.
    public var jointRadius: Float

    /// Radius of the connecting bone segments, in meters (used by ``HandGloveStyle/glove``).
    public var boneRadius: Float

    /// The glove surface color (used by the procedural styles).
    public var color: Color

    /// Whether the glove material is metallic.
    public var isMetallic: Bool

    /// Local transform applied to a ``HandGloveStyle/model`` glove relative to the
    /// wrist joint, to align the USDZ's authored orientation/scale with ARKit's
    /// wrist frame. Defaults to identity; override if your model needs a rotation
    /// or offset to sit correctly on the hand.
    public var modelWristOffset: simd_float4x4

    public init(
        tracksLeftHand: Bool = true,
        tracksRightHand: Bool = true,
        style: HandGloveStyle = .glove,
        jointRadius: Float = 0.01,
        boneRadius: Float = 0.008,
        color: Color = Color(red: 0.10, green: 0.12, blue: 0.16),
        isMetallic: Bool = false,
        modelWristOffset: simd_float4x4 = matrix_identity_float4x4
    ) {
        self.tracksLeftHand = tracksLeftHand
        self.tracksRightHand = tracksRightHand
        self.style = style
        self.jointRadius = jointRadius
        self.boneRadius = boneRadius
        self.color = color
        self.isMetallic = isMetallic
        self.modelWristOffset = modelWristOffset
    }

    /// A sensible default: a dark glove on both hands.
    public static let `default` = HandGloveConfiguration()

    var material: SimpleMaterial {
        SimpleMaterial(color: UIColor(color), isMetallic: isMetallic)
    }
}
#endif
