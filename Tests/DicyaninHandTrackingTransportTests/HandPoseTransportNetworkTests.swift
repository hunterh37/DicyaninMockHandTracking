import XCTest
import simd
import Foundation
@testable import DicyaninHandTrackingTransport

final class HandPoseTransportNetworkTests: XCTestCase {

    // MARK: - Packet defaults

    func testInitDefaults() {
        let p = HandPosePacket(leftPosition: SIMD3(1, 2, 3), rightPosition: SIMD3(4, 5, 6))
        XCTAssertEqual(p.leftYaw, 0)
        XCTAssertEqual(p.rightYaw, 0)
        XCTAssertFalse(p.isPinching)
        XCTAssertTrue(p.leftTracked)
        XCTAssertTrue(p.rightTracked)
        XCTAssertNil(p.leftJoints)
        XCTAssertNil(p.rightJoints)
    }

    // MARK: - Joint packing edge cases

    func testEmptyJointArrayDecodesToNil() throws {
        let s = #"{"l":[0,0,0],"r":[0,0,0],"ly":0,"ry":0,"p":false,"lj":[],"rj":[]}"#
        let decoded = try JSONDecoder().decode(HandPosePacket.self, from: Data(s.utf8))
        XCTAssertNil(decoded.leftJoints)
        XCTAssertNil(decoded.rightJoints)
    }

    func testEncodingEmptyJointsProducesNilOnDecode() throws {
        let p = HandPosePacket(leftPosition: .zero, rightPosition: .zero,
                               leftJoints: [], rightJoints: [])
        let decoded = try JSONDecoder().decode(
            HandPosePacket.self, from: try JSONEncoder().encode(p))
        XCTAssertNil(decoded.leftJoints)
        XCTAssertNil(decoded.rightJoints)
    }

    func testMalformedRightPositionThrows() {
        let bad = #"{"l":[1,2,3],"r":[4,5],"ly":0,"ry":0,"p":false}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(HandPosePacket.self, from: Data(bad.utf8)))
    }

    func testDecodeRejectsGarbageFrame() {
        XCTAssertThrowsError(try HandPoseWire.decode(Data("not json".utf8)))
    }

    // MARK: - Sender init

    func testSenderStartReachesReadyAndReportsPort() {
        let port: UInt16 = 50691
        let sender = try! HandPoseSender(port: port, advertiseBonjour: false)
        let ready = expectation(description: "ready")
        sender.onStateChange = { state in
            if case let .ready(p) = state { XCTAssertEqual(p, port); ready.fulfill() }
        }
        sender.start()
        wait(for: [ready], timeout: 5)
        sender.stop()
    }

    // MARK: - End to end loopback

    func testSenderToReceiverDeliversPacket() {
        let port: UInt16 = 50692
        let sender = try! HandPoseSender(port: port, advertiseBonjour: false)

        let clientConnected = expectation(description: "client connected")
        sender.onClientCountChange = { count in
            if count > 0 { clientConnected.fulfill() }
        }
        let ready = expectation(description: "ready")
        sender.onStateChange = { if case .ready = $0 { ready.fulfill() } }
        sender.start()
        wait(for: [ready], timeout: 5)

        let receiver = HandPoseReceiver(.host("localhost", port: port))
        let sent = HandPosePacket(
            leftPosition: SIMD3(0.3, 0.1, -0.7),
            rightPosition: SIMD3(-0.3, 0.1, -0.7),
            leftYaw: 0.2, rightYaw: -0.2,
            isPinching: true, leftTracked: true, rightTracked: false)

        let received = expectation(description: "received")
        let task = Task {
            for await packet in receiver.packets() {
                XCTAssertEqual(packet, sent)
                received.fulfill()
                break
            }
        }

        wait(for: [clientConnected], timeout: 5)
        let pump = DispatchQueue(label: "pump")
        let stopFlag = NSLock()
        var stop = false
        pump.async {
            while true {
                stopFlag.lock(); let s = stop; stopFlag.unlock()
                if s { break }
                sender.broadcast(sent); usleep(20_000)
            }
        }

        wait(for: [received], timeout: 5)
        stopFlag.lock(); stop = true; stopFlag.unlock()
        task.cancel()
        receiver.cancel()
        sender.stop()
    }
}
