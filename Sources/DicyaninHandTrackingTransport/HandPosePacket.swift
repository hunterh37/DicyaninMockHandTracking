import Foundation
import simd

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

    public init(leftPosition: SIMD3<Float>,
                rightPosition: SIMD3<Float>,
                leftYaw: Float = 0,
                rightYaw: Float = 0,
                isPinching: Bool = false,
                leftTracked: Bool = true,
                rightTracked: Bool = true) {
        self.leftPosition = leftPosition
        self.rightPosition = rightPosition
        self.leftYaw = leftYaw
        self.rightYaw = rightYaw
        self.isPinching = isPinching
        self.leftTracked = leftTracked
        self.rightTracked = rightTracked
    }

    // SIMD3<Float> isn't Codable by default; encode each as a 3-element array.
    private enum CodingKeys: String, CodingKey {
        case l, r, ly, ry, p, lt, rt
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
