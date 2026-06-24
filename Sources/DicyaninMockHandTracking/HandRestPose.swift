//
//  HandRestPose.swift
//  DicyaninMockHandTracking
//
//  The simulator has no live ARKit hand skeleton, so the mock publishes a fixed
//  open-hand layout. This type is the single source of truth for that layout:
//  the glove renderer places joint entities with `localPosition(for:)`, and
//  `MockHandTrackingController` publishes the same joints as world transforms
//  (rest pose composed with the hand's position and yaw) so joint-based
//  consumers (palm contact, pointing rays) have a source in the simulator.
//

#if os(visionOS)
import ARKit.hand_skeleton
import simd

public enum HandRestPose {
    public enum Chirality: Sendable {
        case left
        case right

        var mirror: Float { self == .left ? -1 : 1 }
    }

    // Lateral offset per finger (meters), thumb splayed out to the side.
    private static let fingerX: [Finger: Float] = [
        .forearm: 0, .thumb: -0.040, .index: -0.020, .middle: 0, .ring: 0.020, .little: 0.038
    ]

    // Forward distance from the wrist per bone (negative Z points away from the body).
    private static let boneZ: [Bone: Float] = [
        .arm: 0.18, .wrist: 0.06, .metacarpal: 0.0,
        .knuckle: -0.03, .intermediateBase: -0.06, .intermediateTip: -0.085, .tip: -0.105
    ]

    /// Position of a joint in the hand's local space, relative to the hand root.
    public static func localPosition(
        for joint: (name: HandSkeleton.JointName, finger: Finger, bone: Bone),
        chirality: Chirality
    ) -> SIMD3<Float> {
        let mirror = chirality.mirror
        var x = (fingerX[joint.finger] ?? 0) * mirror
        // Splay the thumb further out as it extends.
        if joint.finger == .thumb { x += (boneZ[joint.bone] ?? 0) * 0.4 * mirror }
        return [x, 0, boneZ[joint.bone] ?? 0]
    }

    /// Every joint as a world transform, given the hand root's world position and
    /// yaw. Matches what the glove renderer produces: `T(position) * R(yaw) * T(local)`.
    public static func worldTransforms(
        position: SIMD3<Float>,
        yaw: Float,
        chirality: Chirality
    ) -> [HandSkeleton.JointName: simd_float4x4] {
        let rootTranslation = simd_float4x4(translation: position)
        let rootRotation = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        let root = rootTranslation * rootRotation

        var transforms: [HandSkeleton.JointName: simd_float4x4] = [:]
        transforms.reserveCapacity(HandJoints.all.count)
        for joint in HandJoints.all {
            let local = simd_float4x4(translation: localPosition(for: joint, chirality: chirality))
            transforms[joint.name] = root * local
        }
        return transforms
    }
}

private extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }
}
#endif
