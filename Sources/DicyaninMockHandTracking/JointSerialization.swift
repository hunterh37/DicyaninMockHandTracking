//
//  JointSerialization.swift
//  DicyaninMockHandTracking
//
//  Converts a hand's per-joint world transforms between the live ARKit/mock
//  representation (`[HandSkeleton.JointName: simd_float4x4]`) and a plain,
//  cross-platform, Codable representation (`[String: [Float]]`) used for
//  recording on disk. Keeping the on-disk form platform-neutral lets the
//  recording module build for macOS while the visionOS app captures and
//  replays full articulated joints.
//

#if os(visionOS)
import ARKit.hand_skeleton
import simd

/// Plain, Codable per-joint payload: joint stable-name → 16 column-major floats.
public typealias SerializedJoints = [String: [Float]]

public enum JointSerialization {

    /// Stable string name for every joint the glove tracks. These strings are
    /// the on-disk contract for recordings, so they must never change.
    static let stableNames: [HandSkeleton.JointName: String] = {
        var map: [HandSkeleton.JointName: String] = [
            .thumbKnuckle: "thumbKnuckle",
            .thumbIntermediateBase: "thumbIntermediateBase",
            .thumbIntermediateTip: "thumbIntermediateTip",
            .thumbTip: "thumbTip",
            .indexFingerMetacarpal: "indexFingerMetacarpal",
            .indexFingerKnuckle: "indexFingerKnuckle",
            .indexFingerIntermediateBase: "indexFingerIntermediateBase",
            .indexFingerIntermediateTip: "indexFingerIntermediateTip",
            .indexFingerTip: "indexFingerTip",
            .middleFingerMetacarpal: "middleFingerMetacarpal",
            .middleFingerKnuckle: "middleFingerKnuckle",
            .middleFingerIntermediateBase: "middleFingerIntermediateBase",
            .middleFingerIntermediateTip: "middleFingerIntermediateTip",
            .middleFingerTip: "middleFingerTip",
            .ringFingerMetacarpal: "ringFingerMetacarpal",
            .ringFingerKnuckle: "ringFingerKnuckle",
            .ringFingerIntermediateBase: "ringFingerIntermediateBase",
            .ringFingerIntermediateTip: "ringFingerIntermediateTip",
            .ringFingerTip: "ringFingerTip",
            .littleFingerMetacarpal: "littleFingerMetacarpal",
            .littleFingerKnuckle: "littleFingerKnuckle",
            .littleFingerIntermediateBase: "littleFingerIntermediateBase",
            .littleFingerIntermediateTip: "littleFingerIntermediateTip",
            .littleFingerTip: "littleFingerTip",
            .forearmWrist: "forearmWrist",
            .forearmArm: "forearmArm"
        ]
        // Include the bare wrist if the runtime exposes it, so nothing is lost.
        map[.wrist] = "wrist"
        return map
    }()

    static let byStableName: [String: HandSkeleton.JointName] =
        Dictionary(uniqueKeysWithValues: stableNames.map { ($0.value, $0.key) })

    /// Flatten joint transforms to the on-disk Codable form.
    public static func serialize(_ joints: [HandSkeleton.JointName: simd_float4x4]) -> SerializedJoints {
        var out: SerializedJoints = [:]
        out.reserveCapacity(joints.count)
        for (name, m) in joints {
            guard let key = stableNames[name] else { continue }
            out[key] = m.flattenedColumnMajor
        }
        return out
    }

    /// Rebuild joint transforms from the on-disk Codable form.
    public static func deserialize(_ dict: SerializedJoints) -> [HandSkeleton.JointName: simd_float4x4] {
        var out: [HandSkeleton.JointName: simd_float4x4] = [:]
        out.reserveCapacity(dict.count)
        for (key, floats) in dict {
            guard let name = byStableName[key], floats.count == 16 else { continue }
            out[name] = simd_float4x4(flattenedColumnMajor: floats)
        }
        return out
    }
}

extension simd_float4x4 {
    /// 16 floats, column-major (col0 xyzw, col1 xyzw, …).
    var flattenedColumnMajor: [Float] {
        [columns.0.x, columns.0.y, columns.0.z, columns.0.w,
         columns.1.x, columns.1.y, columns.1.z, columns.1.w,
         columns.2.x, columns.2.y, columns.2.z, columns.2.w,
         columns.3.x, columns.3.y, columns.3.z, columns.3.w]
    }

    init(flattenedColumnMajor f: [Float]) {
        self.init(columns: (
            SIMD4<Float>(f[0], f[1], f[2], f[3]),
            SIMD4<Float>(f[4], f[5], f[6], f[7]),
            SIMD4<Float>(f[8], f[9], f[10], f[11]),
            SIMD4<Float>(f[12], f[13], f[14], f[15])
        ))
    }
}
#endif
