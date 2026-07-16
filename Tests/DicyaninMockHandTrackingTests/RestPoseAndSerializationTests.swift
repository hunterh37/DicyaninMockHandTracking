#if os(visionOS)
import XCTest
import simd
import ARKit.hand_skeleton
@testable import DicyaninMockHandTracking

final class RestPoseAndSerializationTests: XCTestCase {

    // MARK: - HandJoints topology

    func testJointTopologyIsComplete() {
        XCTAssertEqual(HandJoints.all.count, 26)
        // Every finger chain links each joint to its predecessor; the forearm pair
        // is intentionally excluded.
        XCTAssertNil(HandJoints.parents[.thumbKnuckle])          // first of its chain
        XCTAssertEqual(HandJoints.parents[.thumbIntermediateBase], .thumbKnuckle)
        XCTAssertEqual(HandJoints.parents[.indexFingerTip], .indexFingerIntermediateTip)
        XCTAssertNil(HandJoints.parents[.forearmWrist])
        XCTAssertNil(HandJoints.parents[.forearmArm])
    }

    // MARK: - HandRestPose

    func testWorldTransformsCoverEveryJoint() {
        let t = HandRestPose.worldTransforms(
            position: SIMD3(0.2, -0.1, -0.7), yaw: 0, chirality: .right)
        XCTAssertEqual(t.count, HandJoints.all.count)
    }

    func testRootTranslationTracksHandPosition() {
        // With zero yaw, a joint at local origin lands at the hand position.
        // The forearm arm bone is offset, so check a joint whose local Z we know:
        // metacarpal bone has Z 0, X 0 for the middle finger.
        let pos = SIMD3<Float>(0.5, 0.25, -0.65)
        let t = HandRestPose.worldTransforms(position: pos, yaw: 0, chirality: .right)
        let mid = try! XCTUnwrap(t[.middleFingerMetacarpal])
        let translation = SIMD3(mid.columns.3.x, mid.columns.3.y, mid.columns.3.z)
        XCTAssertEqual(translation.x, pos.x, accuracy: 1e-5)
        XCTAssertEqual(translation.y, pos.y, accuracy: 1e-5)
        XCTAssertEqual(translation.z, pos.z, accuracy: 1e-5)
    }

    func testChiralityMirrorsLateralOffset() {
        let joint = HandJoints.all.first { $0.name == .littleFingerKnuckle }!
        let left = HandRestPose.localPosition(for: joint, chirality: .left)
        let right = HandRestPose.localPosition(for: joint, chirality: .right)
        XCTAssertEqual(left.x, -right.x, accuracy: 1e-6)
        XCTAssertEqual(left.z, right.z, accuracy: 1e-6)
    }

    func testYawRotatesJointsAboutUpAxis() {
        // A 90 degree yaw maps +Z local offset onto the X axis.
        let pos = SIMD3<Float>.zero
        let t = HandRestPose.worldTransforms(position: pos, yaw: .pi / 2, chirality: .right)
        let arm = try! XCTUnwrap(t[.forearmArm])   // local Z = +0.18
        let x = arm.columns.3.x
        XCTAssertEqual(abs(x), 0.18, accuracy: 1e-4)
    }

    // MARK: - JointSerialization

    func testSerializeDeserializeRoundTrip() {
        let joints = HandRestPose.worldTransforms(
            position: SIMD3(0.1, 0.2, -0.6), yaw: 0.3, chirality: .left)
        let serialized = JointSerialization.serialize(joints)
        XCTAssertEqual(serialized.count, joints.count)
        // Each entry is 16 column-major floats.
        for (_, floats) in serialized { XCTAssertEqual(floats.count, 16) }

        let restored = JointSerialization.deserialize(serialized)
        XCTAssertEqual(restored.count, joints.count)
        for (name, m) in joints {
            let r = try! XCTUnwrap(restored[name])
            for col in 0..<4 {
                XCTAssertEqual(r[col], m[col])
            }
        }
    }

    func testDeserializeSkipsWrongLengthEntries() {
        let bad: SerializedJoints = ["thumbTip": [1, 2, 3]]   // not 16 floats
        XCTAssertTrue(JointSerialization.deserialize(bad).isEmpty)
    }

    func testDeserializeSkipsUnknownJointNames() {
        let unknown: SerializedJoints = ["notARealJoint": Array(repeating: 0, count: 16)]
        XCTAssertTrue(JointSerialization.deserialize(unknown).isEmpty)
    }
}
#endif
