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

    /// True while a live webcam runner is feeding this controller. When set,
    /// on-screen `MockHandControlView` joysticks should be treated as read-only
    /// (the network is the source of truth).
    @Published public private(set) var isWebcamConnected: Bool = false

    private var webcamReceiver: HandPoseReceiver?
    private var webcamTask: Task<Void, Never>?

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
        if packet.isPinching && !isPinching {
            simulatePinch()
        } else if !packet.isPinching {
            // Honor a held-open hand immediately rather than waiting on the
            // momentary-pinch timer.
            isPinching = false
        }
    }

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
        webcamTask = Task { @MainActor in
            isWebcamConnected = true
            for await packet in receiver.packets() {
                apply(packet)
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
