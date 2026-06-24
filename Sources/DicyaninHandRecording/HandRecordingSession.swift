import Foundation
import DicyaninHandTrackingTransport

/// One captured hand pose plus the time, in seconds from the start of the
/// recording, at which it occurred.
public struct HandRecordingFrame: Codable, Sendable, Equatable {
    /// Seconds since the recording began.
    public var time: TimeInterval
    /// The hand pose captured at ``time``.
    public var packet: HandPosePacket

    public init(time: TimeInterval, packet: HandPosePacket) {
        self.time = time
        self.packet = packet
    }
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
}
