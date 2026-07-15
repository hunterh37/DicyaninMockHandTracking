import SwiftUI
import RealityKit
import ARKit
import DicyaninMockHandTracking

/// Demo interaction: a red sphere you can pinch-grab and drag with either hand.
/// Reads the pinch state and full-joint skeletons published by
/// `MockHandTrackingController` (webcam bridge, joysticks, or device ARKit).
struct PinchSphereView: View {
    private static let restPosition: SIMD3<Float> = [0, -0.15, -0.85]
    private static let grabRadius: Float = 0.16

    private static let floorPosition: SIMD3<Float> = [0, -0.55, -0.85]
    private static let floorSize: SIMD3<Float> = [0.6, 0.02, 0.6]

    var body: some View {
        RealityView { content in
            let floor = ModelEntity(
                mesh: .generateBox(size: Self.floorSize, cornerRadius: 0.005),
                materials: [SimpleMaterial(color: .blue, isMetallic: false)])
            floor.name = "floor"
            floor.position = Self.floorPosition
            floor.components.set(CollisionComponent(
                shapes: [.generateBox(size: Self.floorSize)]))
            floor.components.set(PhysicsBodyComponent(
                massProperties: .default,
                material: .generate(friction: 0.6, restitution: 0.7),
                mode: .static))
            content.add(floor)

            let sphere = ModelEntity(
                mesh: .generateSphere(radius: 0.06),
                materials: [SimpleMaterial(color: .red, isMetallic: false)])
            sphere.name = "pinchSphere"
            sphere.position = Self.restPosition
            sphere.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: 0.06)]))
            content.add(sphere)
            Task { await Self.runGrabLoop(sphere: sphere) }
        }
    }

    /// Dynamic body applied on release so the ball falls and bounces.
    private static func dynamicBody() -> PhysicsBodyComponent {
        var body = PhysicsBodyComponent(
            massProperties: .init(mass: 0.2),
            material: .generate(friction: 0.4, restitution: 0.75),
            mode: .dynamic)
        body.isAffectedByGravity = true
        return body
    }

    /// Midpoint between thumb tip and index tip: where a pinch "holds".
    @MainActor
    private static func pinchPoint(
        _ joints: [HandSkeleton.JointName: simd_float4x4]
    ) -> SIMD3<Float>? {
        guard let t = joints[.thumbTip], let i = joints[.indexFingerTip] else { return nil }
        let tp = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let ip = SIMD3(i.columns.3.x, i.columns.3.y, i.columns.3.z)
        return (tp + ip) * 0.5
    }

    @MainActor
    private static func runGrabLoop(sphere: ModelEntity) async {
        let hands = MockHandTrackingController.shared
        let redMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let heldMaterial = SimpleMaterial(color: .yellow, isMetallic: false)

        // While grabbing: which hand holds the sphere and the pinch-to-center
        // offset captured at grab time (so the sphere doesn't snap).
        var heldByLeft: Bool?
        var heldOffset: SIMD3<Float> = .zero
        // Recent positions to estimate a throw velocity on release.
        var lastPosition = sphere.position
        var lastVelocity: SIMD3<Float> = .zero

        while !Task.isCancelled, sphere.parent != nil {
            let left = pinchPoint(hands.leftHandJoints)
            let right = pinchPoint(hands.rightHandJoints)

            if hands.isPinching {
                if heldByLeft == nil {
                    // Grab with whichever pinching hand is close enough (nearest wins).
                    let candidates: [(isLeft: Bool, point: SIMD3<Float>)] =
                        [(true, left), (false, right)]
                            .compactMap { isLeft, p in p.map { (isLeft, $0) } }
                    if let best = candidates
                        .min(by: {
                            simd_distance($0.point, sphere.position)
                                < simd_distance($1.point, sphere.position)
                        }),
                       simd_distance(best.point, sphere.position) < grabRadius {
                        heldByLeft = best.isLeft
                        heldOffset = sphere.position - best.point
                        sphere.model?.materials = [heldMaterial]
                        // Kinematic while held: the hand owns the motion.
                        sphere.components.remove(PhysicsBodyComponent.self)
                        sphere.components.remove(PhysicsMotionComponent.self)
                    }
                }
                if let isLeft = heldByLeft, let p = (isLeft ? left : right) {
                    sphere.position = p + heldOffset
                    lastVelocity = (sphere.position - lastPosition) * 60 // frames -> m/s
                    lastPosition = sphere.position
                }
            } else if heldByLeft != nil {
                heldByLeft = nil
                sphere.model?.materials = [redMaterial]
                // Release: hand the ball to physics so it falls and bounces,
                // carrying the hand's velocity for a throw.
                sphere.components.set(dynamicBody())
                sphere.components.set(PhysicsMotionComponent(
                    linearVelocity: lastVelocity))
            }

            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }
}
