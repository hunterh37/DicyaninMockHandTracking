import Foundation
import Combine
import os
import DicyaninMockHandTracking
import DicyaninHandTrackingTransport

/// Singleton an app enables to record, persist, and replay glove hand-tracking
/// sessions.
///
/// Recording samples ``MockHandTrackingController/shared`` at a fixed rate and
/// stores each pose as a ``HandPosePacket``. Replay feeds those packets back
/// into the same controller via `apply(_:)`, so the glove (and every other
/// consumer of the mock controller) animates exactly as it did when captured,
/// on device or in the simulator.
///
/// ```swift
/// // Enable once (e.g. from your root view's task).
/// let recorder = HandRecordingManager.shared
///
/// recorder.startRecording(named: "Wave")
/// // ... user moves their hands ...
/// let session = recorder.stopRecording()   // saved to disk
///
/// recorder.play(session)                    // re-animates the gloves
/// ```
@MainActor
public final class HandRecordingManager: ObservableObject {
    public static let shared = HandRecordingManager()

    /// What the manager is currently doing.
    public enum Mode: Equatable, Sendable {
        case idle
        case recording
        case playing
    }

    /// Current activity.
    @Published public private(set) var mode: Mode = .idle

    /// Sessions on disk, most recent first. Refreshed on save/delete.
    @Published public private(set) var sessions: [HandRecordingSession] = []

    /// Seconds elapsed in the active recording or playback (for UI progress).
    @Published public private(set) var elapsed: TimeInterval = 0

    /// How many times per second poses are captured while recording.
    public var sampleRate: Double = 60

    private var store: HandRecordingStore
    private let controller = MockHandTrackingController.shared

    private var recordStart: Date?
    private var recordingName: String = ""
    private var recordingID: UUID = UUID()
    private var capturedFrames: [HandRecordingFrame] = []
    private var captureTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?

    public init(store: HandRecordingStore = HandRecordingStore()) {
        self.store = store
        self.sessions = store.loadAll()
    }

    public var isRecording: Bool { mode == .recording }
    public var isPlaying: Bool { mode == .playing }

    // MARK: - Recording

    /// Begins capturing hand poses into a new session. Stops playback first if
    /// running. Call ``stopRecording()`` to finish and persist.
    public func startRecording(named name: String = "Recording") {
        guard mode != .recording else { return }
        stopPlayback()

        recordingID = UUID()
        recordingName = name
        capturedFrames = []
        recordStart = Date()
        elapsed = 0
        mode = .recording

        let interval = 1.0 / max(1, sampleRate)
        captureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let start = self.recordStart else { break }
                let t = Date().timeIntervalSince(start)
                self.capturedFrames.append(self.snapshotFrame(at: t))
                self.elapsed = t
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Stops recording, saves the session to disk, and returns it. Returns `nil`
    /// if no recording was active.
    @discardableResult
    public func stopRecording() -> HandRecordingSession? {
        guard mode == .recording else { return nil }
        captureTask?.cancel()
        captureTask = nil
        mode = .idle

        let session = HandRecordingSession(
            id: recordingID,
            name: recordingName,
            createdAt: recordStart ?? Date(),
            frames: capturedFrames
        )
        recordStart = nil
        capturedFrames = []

        try? store.save(session)
        sessions = store.loadAll()
        return session
    }

    /// Reads the controller's current published state into a wire packet.
    private func snapshotPacket() -> HandPosePacket {
        HandPosePacket(
            leftPosition: controller.leftHandPosition,
            rightPosition: controller.rightHandPosition,
            leftYaw: controller.leftHandYaw,
            rightYaw: controller.rightHandYaw,
            isPinching: controller.isPinching,
            leftTracked: true,
            rightTracked: true
        )
    }

    /// Captures one frame: the coarse packet always, plus full articulated joint
    /// transforms on visionOS (live ARKit on device, rest pose in the simulator).
    private func snapshotFrame(at t: TimeInterval) -> HandRecordingFrame {
        #if os(visionOS)
        let left = controller.leftHandJoints
        let right = controller.rightHandJoints
        return HandRecordingFrame(
            time: t,
            packet: snapshotPacket(),
            leftJoints: left.isEmpty ? nil : JointSerialization.serialize(left),
            rightJoints: right.isEmpty ? nil : JointSerialization.serialize(right)
        )
        #else
        return HandRecordingFrame(time: t, packet: snapshotPacket())
        #endif
    }

    // MARK: - Playback

    /// Replays a session by feeding its frames back into the mock controller at
    /// their captured times. Stops recording first if running.
    /// - Parameters:
    ///   - session: The session to play.
    ///   - loop: Replay continuously until ``stopPlayback()`` is called.
    public func play(_ session: HandRecordingSession, loop: Bool = false) {
        guard !session.frames.isEmpty else { return }
        if mode == .recording { _ = stopRecording() }
        stopPlayback()
        mode = .playing
        elapsed = 0

        // Take ownership of the controller's joints so the device ARKit feed
        // stops overwriting them while we replay.
        controller.setPlayingBack(true)

        playbackTask = Task { @MainActor [weak self] in
            repeat {
                let start = Date()
                for frame in session.frames {
                    if Task.isCancelled { break }
                    let wait = frame.time - Date().timeIntervalSince(start)
                    if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                    if Task.isCancelled { break }
                    self?.applyFrame(frame)
                    self?.elapsed = frame.time
                }
            } while loop && !Task.isCancelled
            self?.controller.setPlayingBack(false)
            self?.mode = .idle
        }
    }

    /// Drives one frame into the controller: full articulated joints when the
    /// frame carries them, otherwise the coarse packet.
    private func applyFrame(_ frame: HandRecordingFrame) {
        #if os(visionOS)
        if frame.hasJoints {
            controller.applyJoints(
                left: frame.leftJoints.map(JointSerialization.deserialize),
                right: frame.rightJoints.map(JointSerialization.deserialize),
                isPinching: frame.packet.isPinching
            )
            return
        }
        #endif
        controller.apply(frame.packet)
    }

    /// Replays a saved session by id. Returns `false` if no such session exists.
    @discardableResult
    public func play(id: UUID, loop: Bool = false) -> Bool {
        guard let session = try? store.load(id: id) else { return false }
        play(session, loop: loop)
        return true
    }

    /// Stops any in-progress playback and returns the manager to idle.
    public func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        controller.setPlayingBack(false)
        if mode == .playing { mode = .idle }
    }

    // MARK: - Library management

    /// Reloads the on-disk session list.
    public func refresh() {
        sessions = store.loadAll()
    }

    /// Deletes a saved session and refreshes the list.
    public func delete(_ session: HandRecordingSession) {
        store.delete(id: session.id)
        sessions = store.loadAll()
    }

    /// Switches where recordings are stored and reloads the list. Pass
    /// `.documents` so recordings show up in the Files app for off-device
    /// export (the host app must enable file sharing in its Info.plist).
    public func useStore(location: HandRecordingStore.Location) {
        store = HandRecordingStore(location: location)
        sessions = store.loadAll()
    }

    // MARK: - Export

    /// Encodes a session to JSON for export or bundling with an app.
    public func exportData(for session: HandRecordingSession) throws -> Data {
        try store.encode(session)
    }

    /// The session encoded as a pretty-printed JSON string, suitable for
    /// copying, sharing, or logging.
    public func exportJSONString(for session: HandRecordingSession) -> String {
        guard let data = try? store.encodePretty(session),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    /// Writes the session to a temporary `.json` file and returns its URL for a
    /// `ShareLink` or document exporter.
    public func exportTemporaryFile(for session: HandRecordingSession) throws -> URL {
        try store.exportTemporaryFile(for: session)
    }

    /// On-disk URL of a saved session (in the active store).
    public func fileURL(for session: HandRecordingSession) -> URL {
        store.fileURL(for: session.id)
    }

    /// Prints every captured value for a session to the unified log (and Xcode
    /// console). Frames are emitted in batches so no single log line is
    /// truncated by the logging system, making it safe for long recordings.
    /// Grab the output from the Xcode console or Console.app to pull a recording
    /// off a device without any file plumbing.
    public func dumpToConsole(_ session: HandRecordingSession, batchSize: Int = 25) {
        let log = Logger(subsystem: "com.dicyanin.handrecording", category: "dump")
        log.log("BEGIN \(session.name, privacy: .public) id=\(session.id.uuidString, privacy: .public) frames=\(session.frameCount) duration=\(session.duration, format: .fixed(precision: 3))s")

        var line = ""
        var count = 0
        for frame in session.frames {
            let p = frame.packet
            line += String(
                format: "[%.3f] L(%.4f,%.4f,%.4f) yaw=%.3f | R(%.4f,%.4f,%.4f) yaw=%.3f pinch=%@ lt=%@ rt=%@\n",
                frame.time,
                p.leftPosition.x, p.leftPosition.y, p.leftPosition.z, p.leftYaw,
                p.rightPosition.x, p.rightPosition.y, p.rightPosition.z, p.rightYaw,
                p.isPinching ? "1" : "0", p.leftTracked ? "1" : "0", p.rightTracked ? "1" : "0"
            )
            count += 1
            if count % batchSize == 0 {
                log.log("\(line, privacy: .public)")
                line = ""
            }
        }
        if !line.isEmpty { log.log("\(line, privacy: .public)") }
        log.log("END \(session.id.uuidString, privacy: .public)")
    }

    /// Imports a session from JSON data (for example a recording shipped in an
    /// app bundle), saves it, and returns it.
    @discardableResult
    public func importSession(from data: Data) throws -> HandRecordingSession {
        let session = try store.decode(from: data)
        try store.save(session)
        sessions = store.loadAll()
        return session
    }
}
