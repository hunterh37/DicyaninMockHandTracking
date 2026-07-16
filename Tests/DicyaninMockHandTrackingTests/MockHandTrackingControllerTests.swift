import XCTest
import simd
import Combine
@testable import DicyaninMockHandTracking
import DicyaninHandTrackingTransport

@MainActor
final class MockHandTrackingControllerTests: XCTestCase {

    private var controller: MockHandTrackingController { .shared }

    override func setUp() async throws {
        // Reset the shared singleton to a known baseline before each test.
        controller.disconnectWebcamRunner()
        controller.setPlayingBack(false)
        controller.leftHandPosition = [-0.22, -0.26, -0.72]
        controller.rightHandPosition = [0.22, -0.26, -0.72]
        controller.leftHandYaw = 0
        controller.rightHandYaw = 0
        controller.isPinching = false
    }

    // MARK: - apply(packet:)

    func testApplyUpdatesTrackedHandsAndYawAndPinch() {
        let packet = HandPosePacket(
            leftPosition: SIMD3(0.5, 0.1, -0.6),
            rightPosition: SIMD3(-0.5, 0.1, -0.6),
            leftYaw: 0.3, rightYaw: -0.4,
            isPinching: true,
            leftTracked: true, rightTracked: true)
        controller.apply(packet)

        XCTAssertEqual(controller.leftHandPosition, SIMD3(0.5, 0.1, -0.6))
        XCTAssertEqual(controller.rightHandPosition, SIMD3(-0.5, 0.1, -0.6))
        XCTAssertEqual(controller.leftHandYaw, 0.3, accuracy: 1e-6)
        XCTAssertEqual(controller.rightHandYaw, -0.4, accuracy: 1e-6)
        XCTAssertTrue(controller.isPinching)
    }

    func testApplyKeepsPositionOfUntrackedHand() {
        let before = controller.leftHandPosition
        let packet = HandPosePacket(
            leftPosition: SIMD3(9, 9, 9),   // should be ignored: leftTracked == false
            rightPosition: SIMD3(-0.5, 0.1, -0.6),
            leftTracked: false, rightTracked: true)
        controller.apply(packet)

        XCTAssertEqual(controller.leftHandPosition, before)
        XCTAssertEqual(controller.rightHandPosition, SIMD3(-0.5, 0.1, -0.6))
    }

    // MARK: - simulatePinch

    func testSimulatePinchPulsesThenReleases() async {
        XCTAssertFalse(controller.isPinching)
        controller.simulatePinch()
        XCTAssertTrue(controller.isPinching)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(controller.isPinching)
    }

    // MARK: - Playback flag

    func testSetPlayingBackTogglesFlag() {
        XCTAssertFalse(controller.isPlayingBack)
        controller.setPlayingBack(true)
        XCTAssertTrue(controller.isPlayingBack)
        controller.setPlayingBack(false)
        XCTAssertFalse(controller.isPlayingBack)
    }

    // MARK: - Snapshot stream

    func testUpdatesDeliversInitialSnapshot() async {
        controller.leftHandPosition = SIMD3(0.11, 0.22, -0.7)
        var iterator = controller.updates().makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.leftHandPosition, SIMD3(0.11, 0.22, -0.7))
    }

    func testSnapshotEquatable() {
        let a = MockHandSnapshot(leftHandPosition: .zero, rightHandPosition: .zero, isPinching: false)
        let b = MockHandSnapshot(leftHandPosition: .zero, rightHandPosition: .zero, isPinching: false)
        XCTAssertEqual(a, b)
    }

    // MARK: - visionOS-only joint plumbing

    #if os(visionOS)
    func testPositionChangeRecomputesRestPoseJoints() {
        controller.leftHandPosition = SIMD3(0.3, 0, -0.7)
        // Rest pose publishes all 27 skeleton joints.
        XCTAssertEqual(controller.leftHandJoints.count, HandJoints.all.count)
        // Wrist world translation tracks the hand position (plus the wrist bone offset).
        let wrist = controller.leftHandJoints[.forearmWrist]
        XCTAssertNotNil(wrist)
    }

    func testApplyWithWireJointsBuildsSkeleton() {
        let positions = (0..<HandJointID.count).map { i -> SIMD3<Float> in
            SIMD3(Float(i) * 0.01, 0, -0.7)
        }
        let packet = HandPosePacket(
            leftPosition: .zero, rightPosition: .zero,
            leftJoints: positions, rightJoints: positions)
        controller.apply(packet)
        // Full skeleton including derived metacarpals + forearm is published.
        XCTAssertFalse(controller.leftHandJoints.isEmpty)
        XCTAssertNotNil(controller.leftHandJoints[.indexFingerMetacarpal])
        XCTAssertNotNil(controller.leftHandJoints[.forearmArm])
    }
    #endif
}
