import XCTest
import simd
import Foundation
@testable import DicyaninHandTrackingTransport

final class HandPosePacketTests: XCTestCase {

    private func joints(_ base: Float) -> [SIMD3<Float>] {
        (0..<HandJointID.count).map { i in
            let f = base + Float(i)
            return SIMD3(f, f + 0.1, f + 0.2)
        }
    }

    // MARK: - Joint ID contract

    func testJointIDCountAndOrderAreStable() {
        XCTAssertEqual(HandJointID.count, 21)
        XCTAssertEqual(HandJointID.allCases.count, 21)
        // Wire order is depended on by producers/consumers: wrist first, tips last.
        XCTAssertEqual(HandJointID.allCases.first, .wrist)
        XCTAssertEqual(HandJointID.allCases.last, .littleTip)
        // No duplicate raw values.
        let raws = HandJointID.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count)
    }

    // MARK: - Codable round trips

    func testCodableRoundTripCoarsePacket() throws {
        let packet = HandPosePacket(
            leftPosition: SIMD3(1, 2, 3),
            rightPosition: SIMD3(-1, -2, -3),
            leftYaw: 0.5, rightYaw: -0.25,
            isPinching: true,
            leftTracked: true, rightTracked: false
        )
        let data = try JSONEncoder().encode(packet)
        XCTAssertEqual(try JSONDecoder().decode(HandPosePacket.self, from: data), packet)
    }

    func testCodableRoundTripWithFullJoints() throws {
        let packet = HandPosePacket(
            leftPosition: SIMD3(0, 0, -0.7),
            rightPosition: SIMD3(0, 0, -0.7),
            leftJoints: joints(0), rightJoints: joints(100)
        )
        let decoded = try JSONDecoder().decode(
            HandPosePacket.self, from: try JSONEncoder().encode(packet))
        XCTAssertEqual(decoded, packet)
        XCTAssertEqual(decoded.leftJoints?.count, HandJointID.count)
        XCTAssertEqual(decoded.rightJoints?.count, HandJointID.count)
    }

    func testJointsStayNilWhenAbsent() throws {
        let packet = HandPosePacket(leftPosition: .zero, rightPosition: .zero)
        let decoded = try JSONDecoder().decode(
            HandPosePacket.self, from: try JSONEncoder().encode(packet))
        XCTAssertNil(decoded.leftJoints)
        XCTAssertNil(decoded.rightJoints)
    }

    // MARK: - Backward compatibility

    func testLegacyPacketWithoutTrackedOrJointsDecodes() throws {
        // An older peer only wrote l, r, ly, ry, p.
        let legacy = #"{"l":[1,2,3],"r":[4,5,6],"ly":0.1,"ry":0.2,"p":true}"#
        let decoded = try JSONDecoder().decode(
            HandPosePacket.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.leftPosition, SIMD3(1, 2, 3))
        XCTAssertTrue(decoded.leftTracked)   // defaults to true
        XCTAssertTrue(decoded.rightTracked)
        XCTAssertNil(decoded.leftJoints)
    }

    func testMalformedPositionArrayThrows() {
        let bad = #"{"l":[1,2],"r":[4,5,6],"ly":0,"ry":0,"p":false}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(HandPosePacket.self, from: Data(bad.utf8)))
    }

    func testJointArrayNotMultipleOfThreeDropsToNil() throws {
        // lj has 4 floats (not divisible by 3): unpack must reject it as nil.
        let s = #"{"l":[0,0,0],"r":[0,0,0],"ly":0,"ry":0,"p":false,"lj":[1,2,3,4]}"#
        let decoded = try JSONDecoder().decode(HandPosePacket.self, from: Data(s.utf8))
        XCTAssertNil(decoded.leftJoints)
    }

    // MARK: - Wire framing

    func testFrameIsNewlineTerminatedAndDecodes() throws {
        let packet = HandPosePacket(
            leftPosition: SIMD3(0.1, 0.2, -0.7), rightPosition: SIMD3(-0.1, 0.2, -0.7),
            isPinching: true)
        let frame = try HandPoseWire.frame(packet)
        XCTAssertEqual(frame.last, 0x0A)
        let body = frame.dropLast()
        XCTAssertEqual(try HandPoseWire.decode(Data(body)), packet)
    }

    func testDrainMultipleFramesFromStream() throws {
        // Simulate a TCP byte stream: two frames concatenated, split on '\n'.
        let a = HandPosePacket(leftPosition: SIMD3(1, 0, 0), rightPosition: .zero)
        let b = HandPosePacket(leftPosition: SIMD3(2, 0, 0), rightPosition: .zero)
        var stream = Data()
        stream.append(try HandPoseWire.frame(a))
        stream.append(try HandPoseWire.frame(b))

        var packets: [HandPosePacket] = []
        while let nl = stream.firstIndex(of: 0x0A) {
            let frame = stream[stream.startIndex..<nl]
            stream.removeSubrange(stream.startIndex...nl)
            packets.append(try HandPoseWire.decode(Data(frame)))
        }
        XCTAssertEqual(packets, [a, b])
    }

    // MARK: - Wire constants

    func testWireConstants() {
        XCTAssertEqual(HandPoseWire.defaultPort, 50673)
        XCTAssertEqual(HandPoseWire.bonjourServiceType, "_dicyaninhands._tcp")
    }
}
