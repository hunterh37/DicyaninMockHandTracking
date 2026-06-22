import simd
import DicyaninMockHandTracking
#if !targetEnvironment(simulator)
import ARKit
#endif

/// One hand-pose source for the whole app. App code calls `start()` once, then
/// consumes the `poses()` stream and never branches on environment: in the
/// simulator each pose comes from the mock controller (driven by
/// `MockHandControlView`); on device each pose comes from a live ARKit anchor
/// update. The stream carries the pose itself, so consumers never poll.
///
/// This is the recommended integration pattern from the package README.
struct HandPose {
    var position: SIMD3<Float>
    var isPinching: Bool

    static let untracked = HandPose(position: .zero, isPinching: false)
}

@MainActor
final class HandSource {
    #if targetEnvironment(simulator)
    // --- Simulator: driven by MockHandControlView ---
    private let mock = MockHandTrackingController.shared

    /// No ARKit session to run in the simulator.
    func start() async throws {}

    /// Right-hand poses, emitted whenever the operator moves the mock joystick
    /// or fires a pinch. Event-driven via the controller's `@Published` state
    func poses() -> AsyncStream<HandPose> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let stream = mock.$rightHandPosition
                    .combineLatest(mock.$isPinching)
                    .values
                for await (position, isPinching) in stream {
                    continuation.yield(HandPose(position: position, isPinching: isPinching))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #else
    // --- Device: real ARKit hand tracking ---
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()

    func start() async throws {
        try await session.run([provider])
    }

    /// Right-hand poses, emitted on ARKit's own cadence via `anchorUpdates`.
    /// Each element corresponds to a real tracking update, so there is no
    /// polling, no fixed timer, and nothing emitted while the hand is unseen
    /// beyond a single "untracked" pose when tracking drops.
    func poses() -> AsyncStream<HandPose> {
        AsyncStream { continuation in
            let task = Task {
                for await update in provider.anchorUpdates {
                    let anchor = update.anchor
                    guard anchor.chirality == .right else { continue }

                    if update.event == .removed || !anchor.isTracked {
                        continuation.yield(.untracked)
                        continue
                    }
                    guard let wrist = anchor.handSkeleton?.joint(.wrist), wrist.isTracked else {
                        continuation.yield(.untracked)
                        continue
                    }

                    let transform = anchor.originFromAnchorTransform * wrist.anchorFromJointTransform
                    let position = SIMD3<Float>(transform.columns.3.x,
                                                transform.columns.3.y,
                                                transform.columns.3.z)
                    continuation.yield(HandPose(position: position, isPinching: false))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif
}
