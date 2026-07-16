import XCTest
import simd
@testable import DicyaninMockHandTracking
import DicyaninHandTrackingTransport

@MainActor
final class WebcamBridgeTests: XCTestCase {

    private var controller: MockHandTrackingController { .shared }

    override func setUp() async throws {
        controller.disconnectWebcamRunner()
        controller.setPlayingBack(false)
        controller.leftHandPosition = [-0.22, -0.26, -0.72]
        controller.rightHandPosition = [0.22, -0.26, -0.72]
        controller.leftHandYaw = 0
        controller.rightHandYaw = 0
        controller.isPinching = false
    }

    func testDisconnectResetsConnectedFlag() {
        controller.connectToWebcamRunner(host: "localhost", port: 50699)
        controller.disconnectWebcamRunner()
        XCTAssertFalse(controller.isWebcamConnected)
    }

    func testConnectHostSetsConnectedFlag() async {
        controller.connectToWebcamRunner(host: "localhost", port: 50698)
        // The connect Task flips the flag on the main actor; yield to let it run.
        for _ in 0..<10 where !controller.isWebcamConnected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.isWebcamConnected)
        controller.disconnectWebcamRunner()
    }

    func testConnectBonjourSetsConnectedFlag() async {
        controller.connectToWebcamRunner(bonjourName: "does-not-exist")
        for _ in 0..<10 where !controller.isWebcamConnected {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.isWebcamConnected)
        controller.disconnectWebcamRunner()
        XCTAssertFalse(controller.isWebcamConnected)
    }

    func testReconnectTearsDownPrevious() {
        controller.connectToWebcamRunner(host: "localhost", port: 50697)
        controller.connectToWebcamRunner(host: "localhost", port: 50696)
        controller.disconnectWebcamRunner()
        XCTAssertFalse(controller.isWebcamConnected)
    }

    func testApplyReleasesHeldPinchWhenPacketClearsIt() {
        controller.simulatePinch()
        XCTAssertTrue(controller.isPinching)
        controller.apply(HandPosePacket(leftPosition: .zero, rightPosition: .zero,
                                        isPinching: false))
        XCTAssertFalse(controller.isPinching)
    }

    func testApplyHoldsPinchAcrossFrames() {
        controller.apply(HandPosePacket(leftPosition: .zero, rightPosition: .zero,
                                        isPinching: true))
        XCTAssertTrue(controller.isPinching)
        controller.apply(HandPosePacket(leftPosition: .zero, rightPosition: .zero,
                                        isPinching: true))
        XCTAssertTrue(controller.isPinching)
    }

    func testApplyAlwaysUpdatesYawEvenWhenUntracked() {
        controller.apply(HandPosePacket(
            leftPosition: SIMD3(9, 9, 9), rightPosition: SIMD3(9, 9, 9),
            leftYaw: 1.1, rightYaw: -1.1,
            leftTracked: false, rightTracked: false))
        XCTAssertEqual(controller.leftHandYaw, 1.1, accuracy: 1e-6)
        XCTAssertEqual(controller.rightHandYaw, -1.1, accuracy: 1e-6)
    }
}
