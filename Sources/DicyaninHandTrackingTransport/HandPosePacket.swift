import Foundation
import simd

/// Canonical joint list shared by the webcam runner (Vision's 21 hand joints)
/// and the visionOS consumer (which maps them onto `HandSkeleton.JointName`).
/// Wire order is `allCases` order: joint arrays are encoded as 21 positions.
public enum HandJointID: String, Codable, CaseIterable, Sendable {
    case wrist
    case thumbKnuckle, thumbIntermediateBase, thumbIntermediateTip, thumbTip
    case indexKnuckle, indexIntermediateBase, indexIntermediateTip, indexTip
    case middleKnuckle, middleIntermediateBase, middleIntermediateTip, middleTip
    case ringKnuckle, ringIntermediateBase, ringIntermediateTip, ringTip
    case littleKnuckle, littleIntermediateBase, littleIntermediateTip, littleTip

    public static let count = HandJointID.allCases.count
}

/// The on-the-wire representation of both hands at one instant.
///
/// This is the single shared contract between the **webcam runner** (which
/// produces packets from Vision hand-pose estimation on a Mac) and the **live
/// visionOS app** (which applies them to `MockHandTrackingController.shared`).
/// Positions are head-relative, matching the mock controller's coordinate
/// convention: `x` is right, `y` is up, `z` is forward (negative is in front
/// of the viewer). Yaw is in radians about the head-up axis.
///
/// Encoded as compact JSON and framed with a trailing newline on the wire, so a
/// reader can split a TCP byte stream into packets on `\n` boundaries.
public struct HandPosePacket: Codable, Sendable, Equatable {
    public var leftPosition: SIMD3<Float>
    public var rightPosition: SIMD3<Float>
    public var leftYaw: Float
    public var rightYaw: Float
    public var isPinching: Bool

    /// Whether each hand was actually seen by the estimator this frame. A hand
    /// that drops out keeps its last position but reports `false` here so the
    /// consumer can decide whether to hold or reset it.
    public var leftTracked: Bool
    public var rightTracked: Bool

    /// Optional full skeleton: 21 head-relative joint positions in
    /// `HandJointID.allCases` order. `nil` when the producer only has a palm
    /// position (older runners), so old and new peers stay wire-compatible.
    public var leftJoints: [SIMD3<Float>]?
    public var rightJoints: [SIMD3<Float>]?

    public init(leftPosition: SIMD3<Float>,
                rightPosition: SIMD3<Float>,
                leftYaw: Float = 0,
                rightYaw: Float = 0,
                isPinching: Bool = false,
                leftTracked: Bool = true,
                rightTracked: Bool = true,
                leftJoints: [SIMD3<Float>]? = nil,
                rightJoints: [SIMD3<Float>]? = nil) {
        self.leftPosition = leftPosition
        self.rightPosition = rightPosition
        self.leftYaw = leftYaw
        self.rightYaw = rightYaw
        self.isPinching = isPinching
        self.leftTracked = leftTracked
        self.rightTracked = rightTracked
        self.leftJoints = leftJoints
        self.rightJoints = rightJoints
    }

    // SIMD3<Float> isn't Codable by default; encode each as a 3-element array.
    private enum CodingKeys: String, CodingKey {
        case l, r, ly, ry, p, lt, rt, lj, rj
    }

    private static func packJoints(_ joints: [SIMD3<Float>]?) -> [Float]? {
        guard let joints else { return nil }
        var flat: [Float] = []
        flat.reserveCapacity(joints.count * 3)
        for j in joints { flat.append(contentsOf: [j.x, j.y, j.z]) }
        return flat
    }

    private static func unpackJoints(_ flat: [Float]?) -> [SIMD3<Float>]? {
        guard let flat, flat.count % 3 == 0, !flat.isEmpty else { return nil }
        return stride(from: 0, to: flat.count, by: 3).map {
            SIMD3(flat[$0], flat[$0 + 1], flat[$0 + 2])
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let l = try c.decode([Float].self, forKey: .l)
        let r = try c.decode([Float].self, forKey: .r)
        guard l.count == 3, r.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: .l, in: c,
                debugDescription: "position arrays must have 3 elements")
        }
        leftPosition = SIMD3(l[0], l[1], l[2])
        rightPosition = SIMD3(r[0], r[1], r[2])
        leftYaw = try c.decode(Float.self, forKey: .ly)
        rightYaw = try c.decode(Float.self, forKey: .ry)
        isPinching = try c.decode(Bool.self, forKey: .p)
        leftTracked = try c.decodeIfPresent(Bool.self, forKey: .lt) ?? true
        rightTracked = try c.decodeIfPresent(Bool.self, forKey: .rt) ?? true
        leftJoints = Self.unpackJoints(try c.decodeIfPresent([Float].self, forKey: .lj))
        rightJoints = Self.unpackJoints(try c.decodeIfPresent([Float].self, forKey: .rj))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode([leftPosition.x, leftPosition.y, leftPosition.z], forKey: .l)
        try c.encode([rightPosition.x, rightPosition.y, rightPosition.z], forKey: .r)
        try c.encode(leftYaw, forKey: .ly)
        try c.encode(rightYaw, forKey: .ry)
        try c.encode(isPinching, forKey: .p)
        try c.encode(leftTracked, forKey: .lt)
        try c.encode(rightTracked, forKey: .rt)
        try c.encodeIfPresent(Self.packJoints(leftJoints), forKey: .lj)
        try c.encodeIfPresent(Self.packJoints(rightJoints), forKey: .rj)
    }
}

public enum HandPoseWire {
    /// Default TCP port the runner serves on and the visionOS app dials.
    /// Chosen in the dynamic/private range to avoid clashes.
    public static let defaultPort: UInt16 = 50673

    /// Bonjour service type used for zero-config discovery on a LAN (e.g. a
    /// real Vision Pro finding the Mac runner over Wi-Fi).
    public static let bonjourServiceType = "_dicyaninhands._tcp"

    private static let encoder = JSONEncoder()

    /// Encode a packet as a single newline-terminated frame.
    public static func frame(_ packet: HandPosePacket) throws -> Data {
        var data = try encoder.encode(packet)
        data.append(0x0A) // '\n'
        return data
    }

    /// Decode one frame (without the trailing newline).
    public static func decode(_ data: Data) throws -> HandPosePacket {
        try JSONDecoder().decode(HandPosePacket.self, from: data)
    }
}
