import XCTest
import simd
@testable import DicyaninHandTrackingTransport

final class HandPoseStabilizerTests: XCTestCase {
    private func packet(left: SIMD3<Float> = [-0.2, -0.25, -0.7],
                        right: SIMD3<Float> = [0.2, -0.25, -0.7],
                        leftTracked: Bool = true,
                        rightTracked: Bool = true,
                        pinching: Bool = false,
                        rightJoints: [SIMD3<Float>]? = nil) -> HandPosePacket {
        HandPosePacket(leftPosition: left, rightPosition: right,
                       isPinching: pinching,
                       leftTracked: leftTracked, rightTracked: rightTracked,
                       rightJoints: rightJoints)
    }

    func testFirstPacketPassesThrough() {
        let s = HandPoseStabilizer()
        let out = s.process(packet(), at: 0)
        XCTAssertEqual(out.leftPosition, [-0.2, -0.25, -0.7])
        XCTAssertEqual(out.rightPosition, [0.2, -0.25, -0.7])
    }

    func testSingleFrameTeleportIsIgnored() {
        let s = HandPoseStabilizer()
        _ = s.process(packet(), at: 0)
        // One wild frame (estimator glitch at the frame edge), then back to normal.
        let wild = s.process(packet(right: [3, 2, -4]), at: 1 / 30.0)
        XCTAssertEqual(wild.rightPosition, [0.2, -0.25, -0.7])
        let back = s.process(packet(), at: 2 / 30.0)
        XCTAssertLessThan(simd_distance(back.rightPosition, [0.2, -0.25, -0.7]), 0.01)
    }

    func testSustainedJumpIsAcceptedGradually() {
        let s = HandPoseStabilizer()
        let config = s.configuration
        _ = s.process(packet(), at: 0)
        let target = SIMD3<Float>(0.2, 0.4, -0.7) // 0.65 m up: beyond the gate
        var previous = SIMD3<Float>(0.2, -0.25, -0.7)
        var time = 0.0
        for _ in 0..<60 {
            time += 1 / 30.0
            let out = s.process(packet(right: target), at: time)
            // Never faster than the speed clamp allows.
            let step = simd_distance(out.rightPosition, previous)
            XCTAssertLessThanOrEqual(step, config.maxSpeed * (1 / 30.0) + 1e-4)
            previous = out.rightPosition
        }
        // Eventually converges on the real position.
        XCTAssertLessThan(simd_distance(previous, target), 0.05)
    }

    func testUntrackedHandHoldsLastPose() {
        let s = HandPoseStabilizer()
        _ = s.process(packet(), at: 0)
        // Untracked packets carry the producer's held position; even if that
        // goes bad, output must stay at the last good pose.
        let out = s.process(packet(right: [9, 9, 9], rightTracked: false), at: 1 / 30.0)
        XCTAssertEqual(out.rightPosition, [0.2, -0.25, -0.7])
    }

    func testReacquireBlendsInsteadOfSnapping() {
        let s = HandPoseStabilizer()
        _ = s.process(packet(), at: 0)
        var time = 1 / 30.0
        _ = s.process(packet(rightTracked: false), at: time)
        // Hand comes back 30 cm away (inside the teleport gate).
        let reacquired = SIMD3<Float>(0.2, 0.05, -0.7)
        time += 1 / 30.0
        let out = s.process(packet(right: reacquired), at: time)
        let travelled = simd_distance(out.rightPosition, SIMD3(0.2, -0.25, -0.7))
        // Far less than the full 0.3 m in one frame.
        XCTAssertLessThan(travelled, 0.1)
        XCTAssertGreaterThan(travelled, 0)
    }

    func testPinchFlickerIsDebounced() {
        let s = HandPoseStabilizer()
        _ = s.process(packet(), at: 0)
        // One-frame pinch flicker: suppressed.
        XCTAssertFalse(s.process(packet(pinching: true), at: 1 / 30.0).isPinching)
        XCTAssertFalse(s.process(packet(pinching: false), at: 2 / 30.0).isPinching)
        // Sustained pinch: accepted on the second consecutive frame.
        XCTAssertFalse(s.process(packet(pinching: true), at: 3 / 30.0).isPinching)
        XCTAssertTrue(s.process(packet(pinching: true), at: 4 / 30.0).isPinching)
    }

    func testRunawayJointIsClampedToWrist() {
        let s = HandPoseStabilizer()
        let wrist = SIMD3<Float>(0.2, -0.25, -0.7)
        var joints = [SIMD3<Float>](repeating: wrist, count: HandJointID.count)
        joints[HandJointID.count - 1] = wrist + SIMD3(0, 0, -2) // 2 m long finger
        let out = s.process(packet(right: wrist, rightJoints: joints), at: 0)
        let clamped = out.rightJoints![HandJointID.count - 1]
        XCTAssertLessThanOrEqual(simd_distance(clamped, out.rightPosition),
                                 s.configuration.maxJointOffset + 1e-4)
    }

    func testResetForgetsHistory() {
        let s = HandPoseStabilizer()
        _ = s.process(packet(), at: 0)
        s.reset()
        let far = SIMD3<Float>(2, 2, -2)
        let out = s.process(packet(right: far), at: 1 / 30.0)
        XCTAssertEqual(out.rightPosition, far)
    }
}
