import simd
import DicyaninMockHandTracking
#if !targetEnvironment(simulator)
import ARKit
#endif

/// One hand-pose source for the whole app. App code calls `rightHand()` and
/// never branches on environment: in the simulator it reads the mock controller
/// (driven by `MockHandControlView`); on device it reads live ARKit anchors.
///
/// This is the recommended integration pattern from the package README.
struct HandPose {
    var position: SIMD3<Float>
    var isPinching: Bool
}

@MainActor
final class HandSource {
    #if targetEnvironment(simulator)
    // --- Simulator: driven by MockHandControlView ---
    private let mock = MockHandTrackingController.shared

    func rightHand() -> HandPose {
        HandPose(position: mock.rightHandPosition, isPinching: mock.isPinching)
    }

    /// 60 fps tick stream you can await in your update loop.
    func updates() -> AsyncStream<Void> { mock.updates() }

    #else
    // --- Device: real ARKit hand tracking ---
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()

    func start() async throws {
        try await session.run([provider])
    }

    func rightHand() -> HandPose {
        guard let anchor = provider.latestAnchors.rightHand,
              anchor.isTracked,
              let wrist = anchor.handSkeleton?.joint(.wrist) else {
            return HandPose(position: .zero, isPinching: false)
        }
        let m = anchor.originFromAnchorTransform * wrist.anchorFromJointTransform
        let position = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        return HandPose(position: position, isPinching: false)
    }

    /// On device, drive updates from your render loop / anchor updates.
    func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    continuation.yield()
                    try? await Task.sleep(for: .milliseconds(16))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif
}
