//
//  HandSkeleton+Joints.swift
//  DicyaninHandGlove
//
//  The joint map, finger, and bone definitions are adapted from Apple's
//  official sample "Tracking and visualizing hand movement"
//  (RealityKit-HandTracking). See:
//  https://developer.apple.com/documentation/visionos/tracking-and-visualizing-hand-movement
//
//  Apple sample code is licensed under Apple's Sample Code License. This file
//  reproduces the joint topology so the glove can map every hand-skeleton
//  joint to a rendered entity exactly the way the Apple sample does.
//

#if os(visionOS)
import ARKit.hand_skeleton

/// Which finger (or the forearm) a joint belongs to.
///
/// Vendored from Apple's "Tracking and visualizing hand movement" sample.
public enum Finger: Int, CaseIterable, Sendable {
    case forearm
    case thumb
    case index
    case middle
    case ring
    case little
}

/// Which segment along a finger a joint represents, from the arm out to the tip.
///
/// Vendored from Apple's "Tracking and visualizing hand movement" sample.
public enum Bone: Int, CaseIterable, Sendable {
    case arm
    case wrist
    case metacarpal
    case knuckle
    case intermediateBase
    case intermediateTip
    case tip
}

/// The full hand-skeleton topology used to drive the glove.
///
/// This is the same 27-joint table Apple uses in its hand-tracking sample. The
/// system maps each `HandSkeleton.JointName` to a rendered entity every frame.
public enum HandJoints {
    /// Every joint, tagged with the finger and bone it belongs to. The order is
    /// significant: joints within a finger are listed from the hand outward,
    /// which lets the glove connect consecutive joints with bone segments.
    public static let all: [(name: HandSkeleton.JointName, finger: Finger, bone: Bone)] = [
        // Thumb
        (.thumbKnuckle, .thumb, .knuckle),
        (.thumbIntermediateBase, .thumb, .intermediateBase),
        (.thumbIntermediateTip, .thumb, .intermediateTip),
        (.thumbTip, .thumb, .tip),

        // Index finger
        (.indexFingerMetacarpal, .index, .metacarpal),
        (.indexFingerKnuckle, .index, .knuckle),
        (.indexFingerIntermediateBase, .index, .intermediateBase),
        (.indexFingerIntermediateTip, .index, .intermediateTip),
        (.indexFingerTip, .index, .tip),

        // Middle finger
        (.middleFingerMetacarpal, .middle, .metacarpal),
        (.middleFingerKnuckle, .middle, .knuckle),
        (.middleFingerIntermediateBase, .middle, .intermediateBase),
        (.middleFingerIntermediateTip, .middle, .intermediateTip),
        (.middleFingerTip, .middle, .tip),

        // Ring finger
        (.ringFingerMetacarpal, .ring, .metacarpal),
        (.ringFingerKnuckle, .ring, .knuckle),
        (.ringFingerIntermediateBase, .ring, .intermediateBase),
        // NOTE: Apple's sample has a copy-paste bug here that tags this joint as
        // `.intermediateBase`. We use the correct `.intermediateTip` so the ring
        // finger articulates like every other finger.
        (.ringFingerIntermediateTip, .ring, .intermediateTip),
        (.ringFingerTip, .ring, .tip),

        // Little finger
        (.littleFingerMetacarpal, .little, .metacarpal),
        (.littleFingerKnuckle, .little, .knuckle),
        (.littleFingerIntermediateBase, .little, .intermediateBase),
        (.littleFingerIntermediateTip, .little, .intermediateTip),
        (.littleFingerTip, .little, .tip),

        // Wrist and arm
        (.forearmWrist, .forearm, .wrist),
        (.forearmArm, .forearm, .arm)
    ]

    /// For each joint, the joint that precedes it along the same finger (toward
    /// the wrist), if any. Used to draw bone segments between joints.
    static let parents: [HandSkeleton.JointName: HandSkeleton.JointName] = {
        var map: [HandSkeleton.JointName: HandSkeleton.JointName] = [:]
        var lastByFinger: [Finger: HandSkeleton.JointName] = [:]
        for joint in all {
            // The forearm pair isn't a finger chain we want to bridge visually.
            if joint.finger != .forearm, let parent = lastByFinger[joint.finger] {
                map[joint.name] = parent
            }
            lastByFinger[joint.finger] = joint.name
        }
        return map
    }()
}
#endif
