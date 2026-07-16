import XCTest
import simd
@testable import DicyaninHandRecording
import DicyaninHandTrackingTransport
import DicyaninMockHandTracking

final class HandRecordingEdgeTests: XCTestCase {

    private func makeTempStore() -> (HandRecordingStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HREdge-\(UUID().uuidString)", isDirectory: true)
        return (HandRecordingStore(directory: dir), dir)
    }

    private func makeSession(name: String = "Wave", frames: Int = 4) -> HandRecordingSession {
        let f = (0..<frames).map { i -> HandRecordingFrame in
            HandRecordingFrame(time: Double(i) * 0.1, packet: HandPosePacket(
                leftPosition: SIMD3<Float>(Float(i), 0, -0.7),
                rightPosition: SIMD3<Float>(Float(i), 0, -0.7)))
        }
        return HandRecordingSession(name: name, frames: f)
    }

    // MARK: - Frame model

    func testFrameHasJoints() {
        let bare = HandRecordingFrame(time: 0, packet: HandPosePacket(
            leftPosition: .zero, rightPosition: .zero))
        XCTAssertFalse(bare.hasJoints)

        let withLeft = HandRecordingFrame(time: 0, packet: HandPosePacket(
            leftPosition: .zero, rightPosition: .zero),
            leftJoints: ["wrist": Array(repeating: 0, count: 16)])
        XCTAssertTrue(withLeft.hasJoints)

        let withRight = HandRecordingFrame(time: 0, packet: HandPosePacket(
            leftPosition: .zero, rightPosition: .zero),
            rightJoints: ["wrist": Array(repeating: 0, count: 16)])
        XCTAssertTrue(withRight.hasJoints)
    }

    func testFrameWithJointsCodableRoundTrip() throws {
        let frame = HandRecordingFrame(
            time: 1.5,
            packet: HandPosePacket(leftPosition: SIMD3(1, 2, 3), rightPosition: .zero),
            leftJoints: ["wrist": (0..<16).map(Float.init)],
            rightJoints: ["thumbTip": (16..<32).map(Float.init)])
        let decoded = try JSONDecoder().decode(
            HandRecordingFrame.self, from: try JSONEncoder().encode(frame))
        XCTAssertEqual(decoded, frame)
        XCTAssertTrue(decoded.hasJoints)
    }

    // MARK: - Store edge cases

    func testLoadAllOnMissingDirectoryIsEmpty() {
        let (store, _) = makeTempStore()   // never created on disk
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testLoadMissingThrows() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try store.load(id: UUID()))
    }

    func testDeleteMissingIsIgnored() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.delete(id: UUID())   // must not throw
    }

    func testLoadAllSkipsCorruptFiles() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        try store.save(makeSession(name: "good"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("\(UUID().uuidString).json"))
        // Non-json files are ignored entirely.
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let all = store.loadAll()
        XCTAssertEqual(all.map(\.name), ["good"])
    }

    func testEncodePrettyIsHumanReadableAndDecodes() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = makeSession()
        let data = try store.encodePretty(session)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("\n"))
        XCTAssertEqual(try store.decode(from: data), session)
    }

    func testExportTemporaryFileEmbedsSafeNameAndIDPrefix() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = makeSession(name: "My Wave 2")
        let url = try store.exportTemporaryFile(for: session)
        defer { try? FileManager.default.removeItem(at: url) }
        let base = url.deletingPathExtension().lastPathComponent
        XCTAssertTrue(base.hasPrefix("My-Wave-2-"))
        XCTAssertTrue(base.hasSuffix(String(session.id.uuidString.prefix(8))))
    }

    func testLocationInitProducesDistinctDirectories() {
        let appSupport = HandRecordingStore(location: .applicationSupport)
        let documents = HandRecordingStore(location: .documents)
        XCTAssertNotEqual(appSupport.directory, documents.directory)
        XCTAssertEqual(appSupport.directory.lastPathComponent, "DicyaninHandRecording")
    }

    // MARK: - Manager

    @MainActor
    func testExportDataMatchesStoreEncode() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        let session = makeSession()
        XCTAssertEqual(try manager.exportData(for: session), try store.encode(session))
    }

    @MainActor
    func testPlayByMissingIdReturnsFalse() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        XCTAssertFalse(manager.play(id: UUID()))
    }

    @MainActor
    func testPlayBySavedIdReturnsTrue() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        let session = makeSession()
        try store.save(session)
        XCTAssertTrue(manager.play(id: session.id))
        manager.stopPlayback()
    }

    @MainActor
    func testPlayEmptySessionIsNoop() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        manager.play(HandRecordingSession(name: "empty"))
        XCTAssertEqual(manager.mode, .idle)
    }

    @MainActor
    func testStopRecordingWhenIdleReturnsNil() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        XCTAssertNil(manager.stopRecording())
    }

    @MainActor
    func testDeleteRemovesFromSessions() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        let session = makeSession()
        try store.save(session)
        manager.refresh()
        XCTAssertTrue(manager.sessions.contains { $0.id == session.id })
        manager.delete(session)
        XCTAssertFalse(manager.sessions.contains { $0.id == session.id })
    }

    @MainActor
    func testFileURLAndExportTemporaryFileGoThroughStore() throws {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        let session = makeSession()
        XCTAssertEqual(manager.fileURL(for: session), store.fileURL(for: session.id))
        let url = try manager.exportTemporaryFile(for: session)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "json")
    }

    @MainActor
    func testStopPlaybackClearsPlayingBackFlag() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        manager.play(makeSession(), loop: true)
        XCTAssertTrue(MockHandTrackingController.shared.isPlayingBack)
        manager.stopPlayback()
        XCTAssertFalse(MockHandTrackingController.shared.isPlayingBack)
        XCTAssertEqual(manager.mode, .idle)
    }

    @MainActor
    func testIsRecordingIsPlayingReflectMode() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isPlaying)
        manager.startRecording(named: "R")
        XCTAssertTrue(manager.isRecording)
        manager.stopRecording()
        manager.play(makeSession(), loop: true)
        XCTAssertTrue(manager.isPlaying)
        manager.stopPlayback()
    }

    @MainActor
    func testExportJSONStringFallsBackToEmptyObjectNever() {
        let (store, dir) = makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = HandRecordingManager(store: store)
        let json = manager.exportJSONString(for: makeSession())
        XCTAssertTrue(json.contains("frames"))
    }
}
