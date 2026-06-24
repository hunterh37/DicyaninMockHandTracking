import XCTest
import simd
@testable import DicyaninHandRecording
import DicyaninHandTrackingTransport
import DicyaninMockHandTracking

final class HandRecordingTests: XCTestCase {

    // A throwaway store rooted in a unique temp directory, cleaned up per test.
    private func makeTempStore() -> (HandRecordingStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HRTests-\(UUID().uuidString)", isDirectory: true)
        return (HandRecordingStore(directory: dir), dir)
    }

    private func makeSession(name: String = "Wave", frames: Int = 5) -> HandRecordingSession {
        let f = (0..<frames).map { i -> HandRecordingFrame in
            let t = Double(i) * 0.1
            let packet = HandPosePacket(
                leftPosition: SIMD3<Float>(Float(i), -0.2, -0.7),
                rightPosition: SIMD3<Float>(Float(i) + 0.5, -0.2, -0.7),
                leftYaw: Float(i) * 0.01,
                rightYaw: Float(i) * -0.01,
                isPinching: i % 2 == 0,
                leftTracked: true,
                rightTracked: i != 2
            )
            return HandRecordingFrame(time: t, packet: packet)
        }
        return HandRecordingSession(name: name, frames: f)
    }

    // MARK: - Session model

    func testSessionDurationAndCount() {
        let session = makeSession(frames: 5)
        XCTAssertEqual(session.frameCount, 5)
        XCTAssertEqual(session.duration, 0.4, accuracy: 1e-6)
        XCTAssertEqual(HandRecordingSession(name: "empty").duration, 0)
    }

    // MARK: - Store persistence

    func testSaveLoadRoundTrip() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = makeSession()
        try store.save(session)
        let loaded = try store.load(id: session.id)
        XCTAssertEqual(loaded, session)
    }

    func testLoadAllSortedAndDelete() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        var older = makeSession(name: "older")
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        var newer = makeSession(name: "newer")
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        try store.save(older)
        try store.save(newer)

        let all = store.loadAll()
        XCTAssertEqual(all.map(\.name), ["newer", "older"])

        store.delete(id: newer.id)
        XCTAssertEqual(store.loadAll().map(\.name), ["older"])
    }

    func testEncodeDecodeData() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = makeSession()
        let data = try store.encode(session)
        XCTAssertEqual(try store.decode(from: data), session)
    }

    func testExportTemporaryFile() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = makeSession(name: "My Wave!!")
        let url = try store.exportTemporaryFile(for: session)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let decoded = try store.decode(from: Data(contentsOf: url))
        XCTAssertEqual(decoded, session)
    }

    func testFileURLMatchesSavedLocation() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = makeSession()
        try store.save(session)
        let url = store.fileURL(for: session.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "\(session.id.uuidString).json")
    }

    // MARK: - Packet fidelity

    func testPacketValuesSurvivePersistence() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let session = makeSession()
        try store.save(session)
        let loaded = try store.load(id: session.id)
        for (a, b) in zip(session.frames, loaded.frames) {
            XCTAssertEqual(a.time, b.time, accuracy: 1e-6)
            XCTAssertEqual(a.packet.leftPosition, b.packet.leftPosition)
            XCTAssertEqual(a.packet.rightPosition, b.packet.rightPosition)
            XCTAssertEqual(a.packet.leftYaw, b.packet.leftYaw)
            XCTAssertEqual(a.packet.isPinching, b.packet.isPinching)
            XCTAssertEqual(a.packet.rightTracked, b.packet.rightTracked)
        }
    }

    // MARK: - Manager: export helpers

    @MainActor
    func testManagerExportJSONStringIsValid() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)

        let session = makeSession()
        let json = manager.exportJSONString(for: session)
        let data = try XCTUnwrap(json.data(using: .utf8))
        XCTAssertEqual(try store.decode(from: data), session)
    }

    @MainActor
    func testManagerImportSavesAndLists() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)

        let session = makeSession()
        let data = try store.encode(session)
        let imported = try manager.importSession(from: data)
        XCTAssertEqual(imported, session)
        XCTAssertTrue(manager.sessions.contains(session))
    }

    @MainActor
    func testManagerDumpToConsoleDoesNotCrash() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        manager.dumpToConsole(makeSession(frames: 60), batchSize: 25)
    }

    // MARK: - Manager: record + playback against the mock controller

    @MainActor
    func testRecordThenStopSavesSession() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        manager.sampleRate = 120

        XCTAssertEqual(manager.mode, .idle)
        manager.startRecording(named: "Live")
        XCTAssertTrue(manager.isRecording)

        // Move the controller so frames have varying content.
        MockHandTrackingController.shared.leftHandPosition = SIMD3<Float>(0.1, 0.2, -0.7)
        try? await Task.sleep(for: .milliseconds(120))

        let session = manager.stopRecording()
        XCTAssertEqual(manager.mode, .idle)
        let unwrapped = try? XCTUnwrap(session)
        XCTAssertGreaterThan(unwrapped?.frameCount ?? 0, 0)
        XCTAssertEqual(unwrapped?.name, "Live")
        // It was persisted and is now listed.
        XCTAssertTrue(manager.sessions.contains { $0.id == session?.id })
    }

    @MainActor
    func testPlaybackAppliesFinalPoseToController() async {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)

        let target = SIMD3<Float>(0.42, 0.13, -0.66)
        let frames = [
            HandRecordingFrame(time: 0, packet: HandPosePacket(
                leftPosition: .zero, rightPosition: .zero)),
            HandRecordingFrame(time: 0.02, packet: HandPosePacket(
                leftPosition: target, rightPosition: target, leftYaw: 0.5))
        ]
        let session = HandRecordingSession(name: "Replay", frames: frames)

        manager.play(session)
        XCTAssertEqual(manager.mode, .playing)

        // Wait for playback to finish applying all frames.
        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(manager.mode, .idle)
        XCTAssertEqual(MockHandTrackingController.shared.leftHandPosition, target)
        XCTAssertEqual(MockHandTrackingController.shared.leftHandYaw, 0.5, accuracy: 1e-6)
    }

    @MainActor
    func testStartRecordingStopsActivePlayback() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)

        manager.play(makeSession(), loop: true)
        XCTAssertEqual(manager.mode, .playing)
        manager.startRecording(named: "Interrupt")
        XCTAssertEqual(manager.mode, .recording)
        manager.stopRecording()
    }

    @MainActor
    func testUseStoreSwitchesLocation() {
        let manager = HandRecordingManager(store: makeTempStore().0)
        manager.useStore(location: .documents)
        // Should not crash and should produce a valid (possibly empty) list.
        XCTAssertNotNil(manager.sessions)
    }
}
