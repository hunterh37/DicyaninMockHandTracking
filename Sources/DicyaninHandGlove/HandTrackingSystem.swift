//
//  HandTrackingSystem.swift
//  DicyaninHandGlove
//
//  Adapted from Apple's "Tracking and visualizing hand movement" sample
//  (HandTrackingSystem.swift). The ARKit session, anchor collection, and the
//  per-joint transform update are kept faithful to Apple's sample. This version
//  adds: a filled-glove render style with bone segments, an optional rigged
//  USDZ glove model, and a visionOS-simulator bridge that drives the hand from
//  `MockHandTrackingController` (since ARKit hand tracking isn't available in
//  the simulator).
//

#if os(visionOS)
import RealityKit
import ARKit
import simd

@_exported import DicyaninMockHandTracking

/// A system that drives every entity carrying a ``HandTrackingComponent``.
public struct HandTrackingSystem: System {
    /// The active ARKit session.
    static var arSession = ARKitSession()

    /// The provider instance for hand-tracking.
    static let handTracking = HandTrackingProvider()

    /// The most recent anchor the provider detects on the left hand.
    static var latestLeftHand: HandAnchor?

    /// The most recent anchor the provider detects on the right hand.
    static var latestRightHand: HandAnchor?

    public init(scene: RealityKit.Scene) {
        #if !targetEnvironment(simulator)
        Task { await Self.runSession() }
        #endif
    }

    @MainActor
    static func runSession() async {
        guard HandTrackingProvider.isSupported else { return }
        do {
            try await arSession.run([handTracking])
        } catch let error as ARKitSession.Error {
            print("HandGlove: ARKit provider error: \(error.localizedDescription)")
            return
        } catch {
            print("HandGlove: unexpected ARKit error: \(error.localizedDescription)")
            return
        }

        for await update in handTracking.anchorUpdates {
            switch update.anchor.chirality {
            case .left: latestLeftHand = update.anchor
            case .right: latestRightHand = update.anchor
            }
        }
    }

    /// Finds every entity with a hand-tracking component.
    static let query = EntityQuery(where: .has(HandTrackingComponent.self))

    public func update(context: SceneUpdateContext) {
        let handEntities = context.entities(matching: Self.query, updatingSystemWhen: .rendering)

        for entity in handEntities {
            guard var hand = entity.components[HandTrackingComponent.self] else { continue }

            if !hand.isBuilt {
                build(&hand, on: entity)
                hand.isBuilt = true
                entity.components.set(hand)
            }

            #if targetEnvironment(simulator)
            driveFromMock(hand, root: entity)
            #else
            driveFromARKit(hand, root: entity)
            #endif
        }
    }

    // MARK: - Building the glove

    private func build(_ hand: inout HandTrackingComponent, on root: Entity) {
        let config = hand.configuration

        // Rigged-model style: load the USDZ and attach it; if it fails, fall back.
        if case let .model(left, right) = config.style {
            let name = (hand.chirality == .left) ? left : right
            if let model = (try? Entity.loadModel(named: name))
                ?? (try? Entity.loadModel(named: name, in: .module)) {
                root.addChild(model)
                return
            }
            print("HandGlove: couldn't load model '\(name)', falling back to procedural glove.")
        }

        let material = config.material

        for joint in HandJoints.all {
            // Knuckles read better a touch larger, like real glove seams.
            let isKnuckle = (joint.bone == .knuckle)
            let radius = config.jointRadius * (isKnuckle ? 1.25 : 1.0)
            let sphere = ModelEntity(
                mesh: .generateSphere(radius: radius),
                materials: [material]
            )
            root.addChild(sphere)
            hand.joints[joint.name] = sphere

            // Filled-glove style also gets a bone segment back to the parent joint.
            if case .glove = config.style, HandJoints.parents[joint.name] != nil {
                let bone = ModelEntity(
                    mesh: .generateBox(size: [config.boneRadius * 2, 1, config.boneRadius * 2]),
                    materials: [material]
                )
                root.addChild(bone)
                hand.bones[joint.name] = bone
            }
        }

        #if targetEnvironment(simulator)
        // No ARKit in the simulator: lay the joints out in a fixed open-hand rest
        // pose so the glove is visible and the whole hand follows the mock joystick.
        applyRestPose(hand, chirality: hand.chirality)
        updateBones(hand, worldSpace: false)
        #endif
    }

    // MARK: - Device: real ARKit hand tracking (Apple's path)

    #if !targetEnvironment(simulator)
    private func driveFromARKit(_ hand: HandTrackingComponent, root: Entity) {
        guard let anchor: HandAnchor = (hand.chirality == .left ? Self.latestLeftHand : Self.latestRightHand),
              let skeleton = anchor.handSkeleton
        else { return }

        for (jointName, jointEntity) in hand.joints {
            let anchorFromJoint = skeleton.joint(jointName).anchorFromJointTransform
            jointEntity.setTransformMatrix(
                anchor.originFromAnchorTransform * anchorFromJoint,
                relativeTo: nil
            )
        }
        updateBones(hand, worldSpace: true)
    }
    #endif

    // MARK: - Simulator: drive from MockHandTrackingController

    #if targetEnvironment(simulator)
    private func driveFromMock(_ hand: HandTrackingComponent, root: Entity) {
        MainActor.assumeIsolated {
            let mock = MockHandTrackingController.shared
            root.position = (hand.chirality == .left) ? mock.leftHandPosition : mock.rightHandPosition
            let yaw = (hand.chirality == .left) ? mock.leftHandYaw : mock.rightHandYaw
            root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
    }

    /// A static open-hand layout used in the simulator, where no live skeleton
    /// exists. Joints are placed in the hand's local space; the root entity is
    /// then moved by the mock controller.
    private func applyRestPose(_ hand: HandTrackingComponent, chirality: AnchoringComponent.Target.Chirality) {
        let side: HandRestPose.Chirality = (chirality == .left) ? .left : .right
        for joint in HandJoints.all {
            guard let entity = hand.joints[joint.name] else { continue }
            entity.position = HandRestPose.localPosition(for: joint, chirality: side)
        }
    }
    #endif

    // MARK: - Bones

    /// Stretches each bone segment to span its joint and that joint's parent.
    private func updateBones(_ hand: HandTrackingComponent, worldSpace: Bool) {
        for (childName, bone) in hand.bones {
            guard let parentName = HandJoints.parents[childName],
                  let child = hand.joints[childName],
                  let parent = hand.joints[parentName]
            else { continue }

            let a = worldSpace ? parent.position(relativeTo: nil) : parent.position
            let b = worldSpace ? child.position(relativeTo: nil) : child.position
            let delta = b - a
            let length = simd_length(delta)
            guard length > 1e-5 else { continue }

            let midpoint = (a + b) / 2
            let direction = delta / length
            let orientation = simd_quatf(from: [0, 1, 0], to: direction)

            if worldSpace {
                bone.setPosition(midpoint, relativeTo: nil)
                bone.setOrientation(orientation, relativeTo: nil)
            } else {
                bone.position = midpoint
                bone.orientation = orientation
            }
            // The box is 1 m tall in Y; scale to the gap between joints.
            bone.scale = [1, length, 1]
        }
    }
}
#endif
