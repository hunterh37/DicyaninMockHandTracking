import Foundation
import DicyaninHandTrackingTransport

/// One captured hand pose plus the time, in seconds from the start of the
/// recording, at which it occurred.
public struct HandRecordingFrame: Codable, Sendable, Equatable {
    /// Seconds since the recording began.
    public var time: TimeInterval
    /// The coarse hand pose (position + yaw + pinch) captured at ``time``. Always
    /// present, so old consumers and the webcam wire format keep working.
    public var packet: HandPosePacket

    /// Optional full per-joint world transforms, keyed by stable joint name with
    /// 16 column-major floats each. Present when captured from live ARKit (device)
    /// or the simulator's articulated rest pose. When present, playback uses these
    /// for full finger articulation; when absent it falls back to ``packet``.
    public var leftJoints: [String: [Float]]?
    public var rightJoints: [String: [Float]]?

    public init(
        time: TimeInterval,
        packet: HandPosePacket,
        leftJoints: [String: [Float]]? = nil,
        rightJoints: [String: [Float]]? = nil
    ) {
        self.time = time
        self.packet = packet
        self.leftJoints = leftJoints
        self.rightJoints = rightJoints
    }

    /// True when this frame carries full articulated joints.
    public var hasJoints: Bool { leftJoints != nil || rightJoints != nil }
}

/// A complete, replayable capture of both hands over time.
///
/// A session is the unit the recording manager produces, the store persists,
/// and the replay driver plays back. It is plain `Codable`, so an app can save
/// it, ship it inside an app bundle, sync it, or hand it to another device, and
/// replay the exact glove animation anywhere this package runs.
public struct HandRecordingSession: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity used for storage filenames and list selection.
    public var id: UUID
    /// Human-facing name shown in pickers.
    public var name: String
    /// When the capture was made.
    public var createdAt: Date
    /// Ordered captured frames, ascending by ``HandRecordingFrame/time``.
    public var frames: [HandRecordingFrame]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        frames: [HandRecordingFrame] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.frames = frames
    }

    /// Length of the recording in seconds (time of the last frame).
    public var duration: TimeInterval { frames.last?.time ?? 0 }

    /// Number of captured frames.
    public var frameCount: Int { frames.count }

    /// Returns a new session containing only the frames between `startTime` and
    /// `endTime` (inclusive), with frame times rebased so the first kept frame
    /// starts at zero.
    public func trimmed(from startTime: TimeInterval, to endTime: TimeInterval) -> HandRecordingSession {
        let kept = frames.filter { $0.time >= startTime && $0.time <= endTime }
        let baseTime = kept.first?.time ?? 0
        let rebased = kept.map { frame in
            var f = frame
            f.time = frame.time - baseTime
            return f
        }
        return HandRecordingSession(
            id: UUID(),
            name: "\(name) (trimmed)",
            createdAt: Date(),
            frames: rebased
        )
    }

    /// Which hands to keep when filtering a recording.
    public enum HandFilter: String, CaseIterable, Sendable {
        case both = "Both Hands"
        case leftOnly = "Left Only"
        case rightOnly = "Right Only"
    }

    /// Returns a new session with only the specified hand(s) retained.
    /// The other hand's joints are removed and its tracking flag is set to false.
    public func filtered(hand: HandFilter) -> HandRecordingSession {
        guard hand != .both else { return self }
        let filtered = frames.map { frame -> HandRecordingFrame in
            var f = frame
            switch hand {
            case .leftOnly:
                f.rightJoints = nil
                f.packet.rightTracked = false
                f.packet.rightPosition = .zero
                f.packet.rightYaw = 0
            case .rightOnly:
                f.leftJoints = nil
                f.packet.leftTracked = false
                f.packet.leftPosition = .zero
                f.packet.leftYaw = 0
            case .both:
                break
            }
            return f
        }
        return HandRecordingSession(
            id: id,
            name: name,
            createdAt: createdAt,
            frames: filtered
        )
    }

    /// Combined trim + hand filter in one step.
    public func trimmed(from startTime: TimeInterval,
                        to endTime: TimeInterval,
                        hand: HandFilter = .both) -> HandRecordingSession {
        let kept = frames.filter { $0.time >= startTime && $0.time <= endTime }
        let baseTime = kept.first?.time ?? 0
        let rebased = kept.map { frame in
            var f = frame
            f.time = frame.time - baseTime
            return f
        }
        var result = HandRecordingSession(
            id: UUID(),
            name: "\(name) (trimmed)",
            createdAt: Date(),
            frames: rebased
        )
        if hand != .both {
            result = result.filtered(hand: hand)
        }
        return result
    }

    /// The frame closest to the given time, or `nil` when the session is empty.
    public func frame(nearestTo time: TimeInterval) -> HandRecordingFrame? {
        guard !frames.isEmpty else { return nil }
        return frames.min(by: { abs($0.time - time) < abs($1.time - time) })
    }
}
