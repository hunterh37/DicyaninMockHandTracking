//
//  DicyaninGlove.swift
//  DicyaninHandGlove
//
//  Loader for the bundled rigged glove USDZs so an app can drive them with the
//  exact technique from Apple's "Animating hand models in visionOS" sample
//  (load the ModelEntity, then set each jointTransform's rotation from the hand
//  skeleton's parentFromJointTransform).
//

#if os(visionOS)
import Foundation
import RealityKit
import ARKit

public enum DicyaninGlove {

    /// URL of a bundled glove model ("LeftGlove" / "RightGlove"), without extension.
    public static func modelURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "usdz")
    }

    /// Loads a bundled rigged glove `ModelEntity`. Returns nil (with a log) if the
    /// model is missing or its joint count doesn't match the ARKit hand skeleton,
    /// mirroring the Apple sample's validation.
    @MainActor
    public static func load(_ name: String) async -> ModelEntity? {
        guard let url = modelURL(named: name) else {
            print("DicyaninGlove: model not found in bundle: \(name)")
            return nil
        }
        do {
            let glove = try await ModelEntity(contentsOf: url)
            let expected = HandSkeleton.JointName.allCases.count
            guard glove.jointNames.count == expected else {
                print("DicyaninGlove: joint count mismatch for \(name): model \(glove.jointNames.count), ARKit \(expected)")
                return nil
            }
            return glove
        } catch {
            print("DicyaninGlove: failed to load \(name): \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
