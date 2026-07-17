import Foundation
import simd

/// Safety filter between a raw hand-pose stream and its consumer. Webcam hand
/// estimation degrades sharply when a hand nears the frame edge: joints jump
/// meters in one frame, depth collapses, and tracking flickers. Applied to
/// each incoming packet, this stabilizer keeps the published hands sane:
///
/// - Teleport gate: a single-frame jump past `teleportDistance` is ignored;
///   the jump is only accepted after `teleportConfirmFrames` consecutive
///   far samples (a real fast move keeps reporting the new region).
/// - Speed clamp: palm travel is limited to `maxSpeed`, so even an accepted
///   jump glides instead of snapping.
/// - Exponential smoothing on position and yaw removes per-frame jitter. For
///   `reacquireBlendDuration` after tracking returns, a lower rate eases the
///   hand from its held pose to the live pose.
/// - Joint sanity: joints are re-anchored to the smoothed wrist, clamped to
///   `maxJointOffset` from it (rejecting meter-long fingers from bad
///   detections), then smoothed.
/// - Pinch debounce: the pinch flag only flips after `pinchDebounceFrames`
///   consecutive frames agree, suppressing single-frame flickers that cause
///   spurious grabs and drops.
///
/// Not thread-safe: feed it from a single actor or queue.
public final class HandPoseStabilizer {
    public struct Configuration: Sendable {
        /// Max palm travel speed in m/s; faster motion is clamped to a glide.
        public var maxSpeed: Float = 3.0
        /// Single-frame jump beyond this (meters) is treated as a glitch.
        public var teleportDistance: Float = 0.35
        /// Consecutive far samples required to accept a teleport as real.
        public var teleportConfirmFrames: Int = 3
        /// Position/yaw smoothing rate (1/s). Higher tracks tighter.
        public var smoothingRate: Float = 25
        /// Smoothing rate during the reacquire blend after tracking loss.
        public var reacquireSmoothingRate: Float = 8
        /// How long the gentler reacquire rate applies, in seconds.
        public var reacquireBlendDuration: Float = 0.3
        /// Max joint distance from the wrist; farther joints are pulled in.
        public var maxJointOffset: Float = 0.30
        /// Consecutive frames a new pinch state must persist before publishing.
        public var pinchDebounceFrames: Int = 2

        public init() {}
    }

    public let configuration: Configuration

    private struct HandState {
        var position: SIMD3<Float>
        var yaw: Float
        var joints: [SIMD3<Float>]?
        var wasTracked: Bool
        /// Consecutive samples beyond the teleport gate.
        var farFrames = 0
        /// True while catching up to an accepted teleport (gate suspended).
        var chasing = false
        /// Seconds of gentle blending left after a reacquire.
        var reacquireRemaining: Float = 0
    }

    private var left: HandState?
    private var right: HandState?
    private var lastTime: TimeInterval?

    private var pinchOutput = false
    private var pinchCandidate = false
    private var pinchCandidateFrames = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Drop all history; the next packet passes through as-is.
    public func reset() {
        left = nil
        right = nil
        lastTime = nil
        pinchOutput = false
        pinchCandidate = false
        pinchCandidateFrames = 0
    }

    /// Stabilize one packet. `time` must be monotonically non-decreasing.
    public func process(_ packet: HandPosePacket, at time: TimeInterval) -> HandPosePacket {
        let dt = Float(min(max(time - (lastTime ?? time), 0), 0.1))
        lastTime = time

        var out = packet
        (out.leftPosition, out.leftYaw, out.leftJoints) = step(
            state: &left, tracked: packet.leftTracked,
            position: packet.leftPosition, yaw: packet.leftYaw,
            joints: packet.leftJoints, dt: dt)
        (out.rightPosition, out.rightYaw, out.rightJoints) = step(
            state: &right, tracked: packet.rightTracked,
            position: packet.rightPosition, yaw: packet.rightYaw,
            joints: packet.rightJoints, dt: dt)
        out.isPinching = debouncePinch(packet.isPinching)
        return out
    }

    // MARK: - Per-hand pipeline

    private func step(
        state: inout HandState?,
        tracked: Bool,
        position: SIMD3<Float>,
        yaw: Float,
        joints: [SIMD3<Float>]?,
        dt: Float
    ) -> (SIMD3<Float>, Float, [SIMD3<Float>]?) {
        guard var s = state else {
            // First sample: accept as-is so startup doesn't glide in from zero.
            let sane = saneJoints(joints, wrist: position, previous: nil, alpha: 1)
            state = HandState(position: position, yaw: yaw, joints: sane, wasTracked: tracked)
            return (position, yaw, sane)
        }
        defer { state = s }

        guard tracked else {
            // Hold the last good pose; remember the loss so reacquire blends.
            s.wasTracked = false
            s.farFrames = 0
            s.chasing = false
            return (s.position, s.yaw, s.joints)
        }

        if !s.wasTracked {
            s.wasTracked = true
            s.reacquireRemaining = configuration.reacquireBlendDuration
        }

        // Teleport gate: ignore isolated huge jumps.
        let distance = simd_distance(position, s.position)
        if s.chasing {
            if distance < configuration.teleportDistance { s.chasing = false }
        } else if distance > configuration.teleportDistance {
            s.farFrames += 1
            if s.farFrames < configuration.teleportConfirmFrames {
                return (s.position, s.yaw, s.joints)
            }
            s.farFrames = 0
            s.chasing = true
        } else {
            s.farFrames = 0
        }

        // Speed clamp, then exponential smoothing (gentler while reacquiring).
        let rate: Float
        if s.reacquireRemaining > 0 {
            s.reacquireRemaining -= dt
            rate = configuration.reacquireSmoothingRate
        } else {
            rate = configuration.smoothingRate
        }
        let alpha = dt > 0 ? 1 - exp(-rate * dt) : 1
        let target = clampTravel(from: s.position, to: position, dt: dt)
        s.position += (target - s.position) * alpha
        s.yaw += shortestAngle(from: s.yaw, to: yaw) * alpha
        s.joints = saneJoints(joints, wrist: s.position, previous: s.joints, alpha: alpha)
        return (s.position, s.yaw, s.joints)
    }

    private func clampTravel(
        from current: SIMD3<Float>, to target: SIMD3<Float>, dt: Float
    ) -> SIMD3<Float> {
        let delta = target - current
        let distance = simd_length(delta)
        let maxStep = configuration.maxSpeed * max(dt, 0.001)
        guard distance > maxStep, distance > 0 else { return target }
        return current + delta * (maxStep / distance)
    }

    /// Re-anchor raw joints to the smoothed wrist, clamp their reach, and
    /// smooth them against the previous frame. The wrist is index 0 in
    /// `HandJointID.allCases` wire order.
    private func saneJoints(
        _ raw: [SIMD3<Float>]?,
        wrist: SIMD3<Float>,
        previous: [SIMD3<Float>]?,
        alpha: Float
    ) -> [SIMD3<Float>]? {
        guard let raw, let rawWrist = raw.first else { return previous }
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(raw.count)
        for (index, joint) in raw.enumerated() {
            var offset = joint - rawWrist
            let reach = simd_length(offset)
            if reach > configuration.maxJointOffset {
                offset *= configuration.maxJointOffset / reach
            }
            var p = wrist + offset
            if let previous, previous.count == raw.count {
                p = previous[index] + (p - previous[index]) * alpha
            }
            out.append(p)
        }
        return out
    }

    private func shortestAngle(from: Float, to: Float) -> Float {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d < -.pi { d += 2 * .pi }
        return d
    }

    private func debouncePinch(_ raw: Bool) -> Bool {
        if raw == pinchOutput {
            pinchCandidateFrames = 0
            return pinchOutput
        }
        if raw == pinchCandidate {
            pinchCandidateFrames += 1
        } else {
            pinchCandidate = raw
            pinchCandidateFrames = 1
        }
        if pinchCandidateFrames >= configuration.pinchDebounceFrames {
            pinchOutput = raw
            pinchCandidateFrames = 0
        }
        return pinchOutput
    }
}
