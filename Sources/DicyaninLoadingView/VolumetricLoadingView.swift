//
//  VolumetricLoadingView.swift
//  DicyaninLoadingView
//
//  Reusable volumetric loading view for long-running mode loads (e.g. the
//  advanced game mode, which takes several seconds to spin up). Renders a 3D
//  extruded text logo with an orbiting ring of loading dots.
//

#if os(visionOS)
import SwiftUI
import RealityKit

/// Configuration for ``VolumetricLoadingView``.
public struct VolumetricLoadingConfiguration: Sendable {
    /// The 3D logo text shown at the center of the volume.
    public var logo: String
    /// Optional caption rendered under the logo (2D SwiftUI text).
    public var caption: String?
    /// Extruded text color.
    public var logoColor: Color
    /// Accent color for the orbiting loading dots.
    public var accentColor: Color

    public init(
        logo: String = "CODEBLUE SIM",
        caption: String? = "Loading",
        logoColor: Color = .white,
        accentColor: Color = Color(red: 0.20, green: 0.55, blue: 1.0)
    ) {
        self.logo = logo
        self.caption = caption
        self.logoColor = logoColor
        self.accentColor = accentColor
    }

    public static let advancedMode = VolumetricLoadingConfiguration()
}

/// Drop-in volumetric loading view. Present it from a `WindowGroup` with a
/// `.volumetric` window style while the heavy mode loads, then dismiss it.
///
/// ```swift
/// WindowGroup(id: "Loading") {
///     VolumetricLoadingView()
/// }
/// .windowStyle(.volumetric)
/// .defaultSize(width: 0.6, height: 0.4, depth: 0.3, in: .meters)
/// ```
public struct VolumetricLoadingView: View {
    private let configuration: VolumetricLoadingConfiguration

    public init(configuration: VolumetricLoadingConfiguration = .advancedMode) {
        self.configuration = configuration
    }

    public var body: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)

            root.addChild(VolumetricLoadingView.makeLogo(
                text: configuration.logo,
                color: configuration.logoColor
            ))

            let dots = VolumetricLoadingView.makeDotRing(color: configuration.accentColor)
            root.addChild(dots)
            VolumetricLoadingView.spin(dots)
        }
        .overlay(alignment: .bottom) {
            if let caption = configuration.caption {
                Text(caption)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }

    @MainActor
    private static func makeLogo(text: String, color: Color) -> Entity {
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.02,
            font: .systemFont(ofSize: 0.09, weight: .heavy),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(color))
        material.metallic = 0.1
        material.roughness = 0.35
        material.emissiveColor = .init(color: UIColor(color))
        material.emissiveIntensity = 0.35

        let entity = ModelEntity(mesh: mesh, materials: [material])
        let bounds = entity.model?.mesh.bounds ?? .init()
        entity.position = [-bounds.extents.x / 2 - bounds.center.x, 0, 0]
        return entity
    }

    @MainActor
    private static func makeDotRing(color: Color) -> Entity {
        let ring = Entity()
        let count = 8
        let radius: Float = 0.14
        for i in 0..<count {
            let angle = Float(i) / Float(count) * 2 * .pi
            var material = UnlitMaterial(color: UIColor(color))
            material.blending = .transparent(opacity: .init(floatLiteral: 1.0 - Float(i) / Float(count) * 0.7))
            let dot = ModelEntity(
                mesh: .generateSphere(radius: 0.008),
                materials: [material]
            )
            dot.position = [radius * cos(angle), -0.09, radius * sin(angle)]
            ring.addChild(dot)
        }
        return ring
    }

    @MainActor
    private static func spin(_ entity: Entity) {
        let spin = FromToByAnimation(
            by: Transform(rotation: simd_quatf(angle: .pi, axis: [0, 1, 0])),
            duration: 1.0,
            bindTarget: .transform
        )
        if let animation = try? AnimationResource.generate(with: spin) {
            entity.playAnimation(animation.repeat(), transitionDuration: 0, startsPaused: false)
        }
    }
}
#endif
