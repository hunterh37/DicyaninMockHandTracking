import SwiftUI
import RealityKit
import ARKit
import DicyaninMockHandTracking
import DicyaninFruitScene

/// 3D fruit you can pinch-grab, carry, and throw with either hand. Runs the
/// shared `FruitSceneModel` (the same simulation the macOS webcam runner draws
/// as a 2D overlay) against the hand state published by
/// `MockHandTrackingController` (webcam bridge, joysticks, or device ARKit).
struct FruitSceneView: View {
    private static let floorPosition: SIMD3<Float> = [0, -0.55, -0.85]
    private static let floorSize: SIMD3<Float> = [0.6, 0.02, 0.6]

    var body: some View {
        RealityView { content in
            // The simulation runs in head-relative space (matching the hand
            // sources and the Mac runner's overlay); only rendering is lifted,
            // via this root, so it sits above the room floor.
            let root = Entity()
            root.name = "fruitRoot"
            root.position = SceneSpace.lift
            content.add(root)

            let floor = ModelEntity(
                mesh: .generateBox(size: Self.floorSize, cornerRadius: 0.005),
                materials: [SimpleMaterial(color: .blue, isMetallic: false)])
            floor.name = "floor"
            floor.position = Self.floorPosition
            root.addChild(floor)

            let model = FruitSceneModel()
            var entities: [Int: ModelEntity] = [:]
            for fruit in model.fruits {
                let entity = Self.makeFruitEntity(fruit.kind)
                entity.position = fruit.position
                entities[fruit.id] = entity
                root.addChild(entity)
            }
            Task { await Self.runFruitLoop(model: model, entities: entities) }
        }
    }

    /// Sphere body tinted per kind, with a small stem so it reads as fruit.
    @MainActor
    private static func makeFruitEntity(_ kind: FruitKind) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: kind.radius),
            materials: [SimpleMaterial(color: uiColor(kind.colorRGBA), isMetallic: false)])
        entity.name = "fruit-\(kind.rawValue)"

        let stem = ModelEntity(
            mesh: .generateCylinder(height: kind.radius * 0.5, radius: kind.radius * 0.08),
            materials: [SimpleMaterial(color: UIColor(red: 0.35, green: 0.22, blue: 0.10,
                                                      alpha: 1), isMetallic: false)])
        stem.position = [0, kind.radius * 1.1, 0]
        entity.addChild(stem)
        return entity
    }

    private static func uiColor(_ rgba: SIMD4<Float>) -> UIColor {
        UIColor(red: CGFloat(rgba.x), green: CGFloat(rgba.y),
                blue: CGFloat(rgba.z), alpha: CGFloat(rgba.w))
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
    private static func runFruitLoop(
        model: FruitSceneModel,
        entities: [Int: ModelEntity]
    ) async {
        let hands = MockHandTrackingController.shared
        let heldScale: Float = 1.12

        while !Task.isCancelled, entities.values.first?.parent != nil {
            let inputs = [
                FruitHandInput(isLeft: true,
                               pinchPoint: pinchPoint(hands.leftHandJoints),
                               isPinching: hands.isPinching),
                FruitHandInput(isLeft: false,
                               pinchPoint: pinchPoint(hands.rightHandJoints),
                               isPinching: hands.isPinching),
            ]
            model.update(hands: inputs, deltaTime: 1 / 60)

            for fruit in model.fruits {
                guard let entity = entities[fruit.id] else { continue }
                entity.position = fruit.position
                entity.scale = SIMD3(repeating: fruit.isHeld ? heldScale : 1)
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }
}
