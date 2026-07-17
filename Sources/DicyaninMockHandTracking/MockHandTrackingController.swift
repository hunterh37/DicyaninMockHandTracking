import Foundation
import simd
import Combine
import DicyaninHandTrackingTransport
#if os(visionOS)
import ARKit.hand_skeleton
#endif

/// A snapshot of both simulated hands at one instant.
public struct MockHandSnapshot: Sendable, Equatable {
    public var leftHandPosition: SIMD3<Float>
    public var rightHandPosition: SIMD3<Float>
    public var isPinching: Bool
}

/// Singleton that drives simulated hand positions for the visionOS simulator.
/// The HandGestureModel / HandTracker read from this in simulator builds instead of ARKit.
@MainActor
public final class MockHandTrackingController: ObservableObject {
    public static let shared = MockHandTrackingController()

    // World-space hand positions (head-relative; Y=0 is eye level, negative Z is in front).
    // Pushed forward (Z = -0.72) and pulled in/up slightly so the hand model + gun sit out
    // ahead of the camera where they're actually visible in the simulator.
    @Published public var leftHandPosition: SIMD3<Float> = [-0.22, -0.26, -0.72] {
        didSet { recomputeJoints(.left) }
    }
    @Published public var rightHandPosition: SIMD3<Float> = [0.22, -0.26, -0.72] {
        didSet { recomputeJoints(.right) }
    }

    // Per-hand yaw offset (radians, about the head-up axis). Lets the simulator operator
    // aim the gun left/right independently of where the head is looking. Driven by the
    // rotation sliders under each joystick (MockHandStickView).
    @Published public var leftHandYaw: Float = 0 {
        didSet { recomputeJoints(.left) }
    }
    @Published public var rightHandYaw: Float = 0 {
        didSet { recomputeJoints(.right) }
    }

    @Published public var isPinching: Bool = false

    #if os(visionOS)
    /// World-space transform of every hand-skeleton joint for the left hand,
    /// derived from the simulator rest pose composed with `leftHandPosition` and
    /// `leftHandYaw`. This is the simulator's stand-in for an ARKit `HandSkeleton`,
    /// so joint-based logic (palm contact, pointing rays) has a source in the sim.
    @Published public private(set) var leftHandJoints: [HandSkeleton.JointName: simd_float4x4] = [:]

    /// World-space joint transforms for the right hand. See ``leftHandJoints``.
    @Published public private(set) var rightHandJoints: [HandSkeleton.JointName: simd_float4x4] = [:]
    #endif

    private var pinchTask: Task<Void, Never>?

    /// True while a recording is being replayed into this controller. While set,
    /// the device ARKit feed stops overwriting the joints so playback owns them.
    /// Read by `HandTrackingSystem` to decide whether to render from live ARKit
    /// or from the joints being applied by the recording manager.
    @Published public private(set) var isPlayingBack: Bool = false

    /// True while a live webcam runner is feeding this controller. When set,
    /// on-screen `MockHandControlView` joysticks should be treated as read-only
    /// (the network is the source of truth).
    @Published public private(set) var isWebcamConnected: Bool = false

    private var webcamReceiver: HandPoseReceiver?
    private var webcamTask: Task<Void, Never>?

    /// Safety filter applied to every incoming webcam packet before it reaches
    /// the published state. Guards against estimator glitches near the frame
    /// edge (teleporting palms, meter-long fingers, pinch flicker) and blends
    /// smoothly when a lost hand is reacquired. Adjust before connecting.
    public var webcamStabilization = HandPoseStabilizer.Configuration()

    private init() {
        #if os(visionOS)
        recomputeJoints(.left)
        recomputeJoints(.right)
        #endif
    }

    private enum Hand { case left, right }

    /// Recompute and publish the joint world transforms for one hand from its
    /// current position and yaw. Cheap (27 joints) and only fires when the hand
    /// actually moves.
    private func recomputeJoints(_ hand: Hand) {
        #if os(visionOS)
        switch hand {
        case .left:
            leftHandJoints = HandRestPose.worldTransforms(
                position: leftHandPosition, yaw: leftHandYaw, chirality: .left
            )
        case .right:
            rightHandJoints = HandRestPose.worldTransforms(
                position: rightHandPosition, yaw: rightHandYaw, chirality: .right
            )
        }
        #endif
    }

    /// Fires a momentary pinch (60 ms), matching a real thumb-index gesture.
    public func simulatePinch() {
        isPinching = true
        pinchTask?.cancel()
        pinchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            self.isPinching = false
        }
    }

    /// Stream of hand snapshots, emitted whenever the operator moves a joystick,
    /// adjusts a slider, or fires a pinch — driven by the controller's
    /// `@Published` state, not a timer. The current snapshot is delivered on
    /// subscribe, so consumers always start with a valid value.
    public func updates() -> AsyncStream<MockHandSnapshot> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let stream = $leftHandPosition
                    .combineLatest($rightHandPosition, $isPinching)
                    .map { MockHandSnapshot(leftHandPosition: $0, rightHandPosition: $1, isPinching: $2) }
                    .values
                for await snapshot in stream {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Full-joint feed (device ARKit / recording playback)

    #if os(visionOS)
    /// Publish externally-sourced world-space joint transforms for one or both
    /// hands. This is the single seam the device ARKit feed and the recording
    /// player both write through, so the glove (which reads `leftHandJoints` /
    /// `rightHandJoints`) and the recorder (which samples them) stay in sync on
    /// device exactly the way they already do in the simulator.
    ///
    /// Unlike `apply(_:)`, this does not touch `leftHandPosition` / `…Yaw`, so it
    /// won't trigger the rest-pose recompute — the supplied joints are authored
    /// directly, preserving full finger articulation.
    public func applyJoints(
        left: [HandSkeleton.JointName: simd_float4x4]? = nil,
        right: [HandSkeleton.JointName: simd_float4x4]? = nil,
        isPinching: Bool? = nil
    ) {
        if let left { leftHandJoints = left }
        if let right { rightHandJoints = right }
        if let isPinching { self.isPinching = isPinching }
    }
    #endif

    /// Toggle the playback flag. Called by the recording manager around replay so
    /// the device ARKit feed yields ownership of the joints to the recording.
    public func setPlayingBack(_ active: Bool) {
        isPlayingBack = active
    }

    // MARK: - Live webcam bridge

    /// Apply a packet received from the webcam runner to the published hand
    /// state. Because every consumer (`updates()`, `HandSource`,
    /// `MockHandControlView`) already reacts to these `@Published` properties,
    /// the webcam poses flow into the live app through the exact same path the
    /// on-screen joysticks use — no consumer needs to change.
    public func apply(_ packet: HandPosePacket) {
        if packet.leftTracked { leftHandPosition = packet.leftPosition }
        if packet.rightTracked { rightHandPosition = packet.rightPosition }
        leftHandYaw = packet.leftYaw
        rightHandYaw = packet.rightYaw
        #if os(visionOS)
        // Full skeleton, when the runner sends one. Overwrites the rest-pose
        // joints the position setters just recomputed, so per-finger motion
        // from the webcam wins over the canned pose.
        if packet.leftTracked, let joints = packet.leftJoints {
            leftHandJoints = Self.skeletonTransforms(joints, yaw: packet.leftYaw)
        }
        if packet.rightTracked, let joints = packet.rightJoints {
            rightHandJoints = Self.skeletonTransforms(joints, yaw: packet.rightYaw)
        }
        #endif
        // Mirror the pinch state directly: a held pinch stays true for the whole
        // hold (grab interactions need this), instead of the momentary
        // simulatePinch() pulse which would oscillate while the fingers stay closed.
        if isPinching != packet.isPinching {
            pinchTask?.cancel()
            isPinching = packet.isPinching
        }
    }

    #if os(visionOS)
    /// ARKit skeleton joint for each wire joint.
    private static let skeletonName: [HandJointID: HandSkeleton.JointName] = [
        .wrist: .wrist,
        .thumbKnuckle: .thumbKnuckle, .thumbIntermediateBase: .thumbIntermediateBase,
        .thumbIntermediateTip: .thumbIntermediateTip, .thumbTip: .thumbTip,
        .indexKnuckle: .indexFingerKnuckle, .indexIntermediateBase: .indexFingerIntermediateBase,
        .indexIntermediateTip: .indexFingerIntermediateTip, .indexTip: .indexFingerTip,
        .middleKnuckle: .middleFingerKnuckle, .middleIntermediateBase: .middleFingerIntermediateBase,
        .middleIntermediateTip: .middleFingerIntermediateTip, .middleTip: .middleFingerTip,
        .ringKnuckle: .ringFingerKnuckle, .ringIntermediateBase: .ringFingerIntermediateBase,
        .ringIntermediateTip: .ringFingerIntermediateTip, .ringTip: .ringFingerTip,
        .littleKnuckle: .littleFingerKnuckle, .littleIntermediateBase: .littleFingerIntermediateBase,
        .littleIntermediateTip: .littleFingerIntermediateTip, .littleTip: .littleFingerTip,
    ]

    /// Joints ARKit has but Vision does not: metacarpals sit halfway between the
    /// wrist and the matching knuckle, and the forearm extends away from the palm.
    private static let metacarpalFor: [(HandSkeleton.JointName, HandJointID)] = [
        (.indexFingerMetacarpal, .indexKnuckle),
        (.middleFingerMetacarpal, .middleKnuckle),
        (.ringFingerMetacarpal, .ringKnuckle),
        (.littleFingerMetacarpal, .littleKnuckle),
    ]

    /// Build world-space joint transforms from 21 wire positions
    /// (`HandJointID.allCases` order). Orientation is the hand yaw for every
    /// joint: positions carry the articulation, which is what the glove and
    /// joint-based logic (tips, palm) consume.
    private static func skeletonTransforms(
        _ positions: [SIMD3<Float>], yaw: Float
    ) -> [HandSkeleton.JointName: simd_float4x4] {
        let ids = HandJointID.allCases
        guard positions.count >= ids.count else { return [:] }
        let rot = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        var byID: [HandJointID: SIMD3<Float>] = [:]
        for (i, id) in ids.enumerated() { byID[id] = positions[i] }

        func transform(_ p: SIMD3<Float>) -> simd_float4x4 {
            var m = rot
            m.columns.3 = SIMD4(p, 1)
            return m
        }

        var out: [HandSkeleton.JointName: simd_float4x4] = [:]
        for (id, name) in skeletonName {
            if let p = byID[id] { out[name] = transform(p) }
        }
        if let wrist = byID[.wrist] {
            for (name, knuckleID) in metacarpalFor {
                if let k = byID[knuckleID] { out[name] = transform((wrist + k) * 0.5) }
            }
            out[.forearmWrist] = transform(wrist)
            if let middle = byID[.middleKnuckle] {
                out[.forearmArm] = transform(wrist + (wrist - middle) * 2)
            }
        }
        return out
    }
    #endif

    /// Connect to a running webcam runner and stream its hand poses into this
    /// controller live. Call once (e.g. from `task {}` on your root view) in
    /// simulator builds. Use `"localhost"` when the app runs in the visionOS
    /// simulator on the same Mac as the runner.
    ///
    /// Safe to call repeatedly; an existing connection is torn down first.
    public func connectToWebcamRunner(
        host: String = "localhost",
        port: UInt16 = HandPoseWire.defaultPort
    ) {
        connect(to: .host(host, port: port))
    }

    /// Discover and connect to a webcam runner over Bonjour (for a real Vision
    /// Pro on the same Wi-Fi as the Mac).
    public func connectToWebcamRunner(bonjourName: String? = nil) {
        connect(to: .bonjour(name: bonjourName))
    }

    private func connect(to endpoint: HandPoseReceiver.Endpoint) {
        disconnectWebcamRunner()
        let receiver = HandPoseReceiver(endpoint)
        webcamReceiver = receiver
        let stabilizer = HandPoseStabilizer(configuration: webcamStabilization)
        webcamTask = Task { @MainActor in
            isWebcamConnected = true
            for await packet in receiver.packets() {
                apply(stabilizer.process(packet, at: Date.timeIntervalSinceReferenceDate))
            }
            isWebcamConnected = false
        }
    }

    /// Stop consuming webcam poses and return control to the on-screen joysticks.
    public func disconnectWebcamRunner() {
        webcamReceiver?.cancel()
        webcamReceiver = nil
        webcamTask?.cancel()
        webcamTask = nil
        isWebcamConnected = false
    }
}
