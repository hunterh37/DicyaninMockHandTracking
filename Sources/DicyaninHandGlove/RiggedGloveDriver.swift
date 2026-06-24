//
//  RiggedGloveDriver.swift
//  DicyaninHandGlove
//
//  Drives a rigged/skinned glove USDZ from ARKit hand-joint world transforms so
//  the glove's fingers articulate with real hand tracking — the skinned-mesh
//  equivalent of the per-joint-entity approach in Apple's hand-tracking sample.
//
//  The bundled gloves expose a 27-joint skeleton whose names mirror ARKit's
//  HandSkeleton (left_handIndex_1_joint, etc.). We map each model joint to an
//  ARKit joint, then each frame set the model's per-joint LOCAL transforms from
//  the ARKit world transforms so the skeleton (and the skin) follows the hand.
//

#if os(visionOS)
import RealityKit
import ARKit
import simd

final class RiggedGloveDriver {

    /// The skinned model whose skeleton we pose.
    let model: ModelEntity

    /// model.jointTransforms index -> ARKit joint it should follow.
    private var arkitForIndex: [Int: HandSkeleton.JointName] = [:]
    /// model.jointTransforms index -> parent index in the skeleton (or nil at root).
    private var parentForIndex: [Int: Int] = [:]
    /// The rig's bind/rest local transforms, captured once. We keep each joint's
    /// rest translation + scale (the glove's own proportions) and only drive the
    /// rotation from ARKit — otherwise the real-hand bone lengths stretch the
    /// skinned mesh.
    private var restLocals: [Transform] = []

    /// Builds a driver for the skinned model under `root`, if one exists.
    init?(root: Entity, chirality: AnchoringComponent.Target.Chirality) {
        guard let model = Self.findSkinned(root) else { return nil }
        let names = model.jointNames
        guard !names.isEmpty else { return nil }
        self.model = model
        self.restLocals = model.jointTransforms

        let table = Self.nameTable(chirality: chirality)

        // Path -> index, to resolve parents from the skeleton path hierarchy.
        var indexForPath: [String: Int] = [:]
        for (i, path) in names.enumerated() { indexForPath[path] = i }

        for (i, path) in names.enumerated() {
            let short = path.split(separator: "/").last.map(String.init) ?? path
            if let aj = table[short] { arkitForIndex[i] = aj }

            // Parent = path with the last component removed.
            if let slash = path.lastIndex(of: "/") {
                let parentPath = String(path[path.startIndex..<slash])
                parentForIndex[i] = indexForPath[parentPath]
            } else {
                parentForIndex[i] = nil
            }
        }
    }

    /// Poses the glove from a dictionary of ARKit joint world transforms and the
    /// wrist world transform. Returns false if the wrist isn't available.
    @discardableResult
    func pose(world: [HandSkeleton.JointName: simd_float4x4]) -> Bool {
        guard let wrist = world[.wrist] ?? world[.forearmWrist] else { return false }
        guard !restLocals.isEmpty else { return false }

        // Place the whole skeleton at the wrist (world placement of the rig root).
        model.setTransformMatrix(wrist, relativeTo: nil)

        var transforms = restLocals  // start from the rig's rest pose every frame
        for (i, aj) in arkitForIndex {
            guard i < transforms.count, let childWorld = world[aj] else { continue }

            // Parent world: the mapped ARKit joint of the skeleton parent, else
            // the wrist (skeleton root). Joints whose parent isn't tracked keep rest.
            let parentWorld: simd_float4x4
            if let p = parentForIndex[i], let paj = arkitForIndex[p], let pw = world[paj] {
                parentWorld = pw
            } else if parentForIndex[i] == nil {
                // Skeleton root (wrist): keep its rest local; the model entity is
                // already placed at the wrist in world space.
                continue
            } else {
                parentWorld = wrist
            }

            // World rotation of this joint relative to its parent, applied on top
            // of the rig's own rest translation + scale (preserves proportions).
            let localRotation = Transform(matrix: parentWorld.inverse * childWorld).rotation
            let rest = restLocals[i]
            transforms[i] = Transform(scale: rest.scale, rotation: localRotation, translation: rest.translation)
        }
        model.jointTransforms = transforms
        return true
    }

    // MARK: - Helpers

    private static func findSkinned(_ entity: Entity) -> ModelEntity? {
        if let m = entity as? ModelEntity, !m.jointNames.isEmpty { return m }
        for child in entity.children {
            if let m = findSkinned(child) { return m }
        }
        return nil
    }

    /// Maps the glove skeleton's short joint names to ARKit joints. The bundled
    /// gloves use `{side}_hand…_joint`; per finger the chain
    /// Start/_1/_2/_3/End maps to ARKit metacarpal/knuckle/intermediateBase/
    /// intermediateTip/tip (thumb has one fewer).
    private static func nameTable(chirality: AnchoringComponent.Target.Chirality) -> [String: HandSkeleton.JointName] {
        let p = (chirality == .left) ? "left" : "right"
        return [
            "\(p)_hand_joint": .wrist,

            "\(p)_handThumbStart_joint": .thumbKnuckle,
            "\(p)_handThumb_1_joint": .thumbIntermediateBase,
            "\(p)_handThumb_2_joint": .thumbIntermediateTip,
            "\(p)_handThumbEnd_joint": .thumbTip,

            "\(p)_handIndexStart_joint": .indexFingerMetacarpal,
            "\(p)_handIndex_1_joint": .indexFingerKnuckle,
            "\(p)_handIndex_2_joint": .indexFingerIntermediateBase,
            "\(p)_handIndex_3_joint": .indexFingerIntermediateTip,
            "\(p)_handIndexEnd_joint": .indexFingerTip,

            "\(p)_handMidStart_joint": .middleFingerMetacarpal,
            "\(p)_handMid_1_joint": .middleFingerKnuckle,
            "\(p)_handMid_2_joint": .middleFingerIntermediateBase,
            "\(p)_handMid_3_joint": .middleFingerIntermediateTip,
            "\(p)_handMidEnd_joint": .middleFingerTip,

            "\(p)_handRingStart_joint": .ringFingerMetacarpal,
            "\(p)_handRing_1_joint": .ringFingerKnuckle,
            "\(p)_handRing_2_joint": .ringFingerIntermediateBase,
            "\(p)_handRing_3_joint": .ringFingerIntermediateTip,
            "\(p)_handRingEnd_joint": .ringFingerTip,

            "\(p)_handPinkyStart_joint": .littleFingerMetacarpal,
            "\(p)_handPinky_1_joint": .littleFingerKnuckle,
            "\(p)_handPinky_2_joint": .littleFingerIntermediateBase,
            "\(p)_handPinky_3_joint": .littleFingerIntermediateTip,
            "\(p)_handPinkyEnd_joint": .littleFingerTip
        ]
    }
}
#endif
