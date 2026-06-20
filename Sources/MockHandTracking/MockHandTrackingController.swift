import Foundation
import simd
import Combine

/// Singleton that drives simulated hand positions for the visionOS simulator.
/// The HandGestureModel / HandTracker read from this in simulator builds instead of ARKit.
@MainActor
public final class MockHandTrackingController: ObservableObject {
    public static let shared = MockHandTrackingController()

    // World-space hand positions (head-relative; Y=0 is eye level, negative Z is in front).
    // Pushed forward (Z = -0.72) and pulled in/up slightly so the hand model + gun sit out
    // ahead of the camera where they're actually visible in the simulator.
    @Published public var leftHandPosition: SIMD3<Float> = [-0.22, -0.26, -0.72]
    @Published public var rightHandPosition: SIMD3<Float> = [0.22, -0.26, -0.72]

    // Per-hand yaw offset (radians, about the head-up axis). Lets the simulator operator
    // aim the gun left/right independently of where the head is looking. Driven by the
    // rotation sliders under each joystick (MockHandStickView).
    @Published public var leftHandYaw: Float = 0
    @Published public var rightHandYaw: Float = 0

    @Published public var isPinching: Bool = false

    private var pinchTask: Task<Void, Never>?

    private init() {}

    /// Fires a momentary pinch (60 ms), matching a real thumb-index gesture.
    public func simulatePinch() {
        isPinching = true
        pinchTask?.cancel()
        pinchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            self.isPinching = false
        }
    }

    /// 60 fps tick stream consumed by HandTracker in simulator builds.
    public func updates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in timer.invalidate() }
        }
    }
}
