import Foundation
import simd

/// Fruit varieties shared by every renderer (3D visionOS scene, 2D webcam
/// overlay). Geometry and color live here so both scenes stay consistent.
public enum FruitKind: String, CaseIterable, Codable, Sendable {
    case apple
    case orange
    case lemon
    case plum

    /// Physical radius in meters.
    public var radius: Float {
        switch self {
        case .apple: return 0.045
        case .orange: return 0.05
        case .lemon: return 0.035
        case .plum: return 0.03
        }
    }

    /// Base color as linear RGBA (0...1), renderer-agnostic.
    public var colorRGBA: SIMD4<Float> {
        switch self {
        case .apple: return SIMD4(0.85, 0.15, 0.15, 1)
        case .orange: return SIMD4(1.0, 0.55, 0.10, 1)
        case .lemon: return SIMD4(0.95, 0.85, 0.20, 1)
        case .plum: return SIMD4(0.55, 0.25, 0.60, 1)
        }
    }
}

/// One hand's contribution to the simulation for a frame. Positions are
/// head-relative meters, matching `HandPosePacket`'s convention (x right,
/// y up, z forward with negative in front of the viewer).
public struct FruitHandInput: Sendable {
    public var isLeft: Bool
    /// Thumb-to-index midpoint. `nil` when the hand is not tracked this frame.
    public var pinchPoint: SIMD3<Float>?
    public var isPinching: Bool

    public init(isLeft: Bool, pinchPoint: SIMD3<Float>?, isPinching: Bool) {
        self.isLeft = isLeft
        self.pinchPoint = pinchPoint
        self.isPinching = isPinching
    }
}

/// Snapshot of one fruit for rendering.
public struct FruitState: Identifiable, Sendable {
    public let id: Int
    public let kind: FruitKind
    /// The hover spot this fruit floats back to when released.
    public let home: SIMD3<Float>
    public var position: SIMD3<Float>
    public var velocity: SIMD3<Float>
    /// `true`/`false` for the holding hand's side, `nil` when free.
    public var heldByLeftHand: Bool?

    public var isHeld: Bool { heldByLeftHand != nil }
}

/// Deterministic pinch-grab-and-throw fruit simulation shared by the visionOS
/// immersive scene and the macOS webcam runner overlay. Both scenes feed it
/// the same head-relative hand stream, so the fruit behaves identically in
/// each. Not thread-safe: call `update` from a single actor or queue.
public final class FruitSceneModel {
    public struct Configuration: Sendable {
        /// Max pinch-point distance from a fruit's center that still grabs it.
        public var grabRadius: Float = 0.16
        /// Spring acceleration pulling a free fruit back to its home spot
        /// (1/s^2). With `hoverDamping` this makes released fruit float back
        /// instead of falling, so both scenes always converge to the same
        /// layout no matter how their frame timing drifts apart.
        public var hoverStiffness: Float = 12
        /// Velocity damping on a free fruit (1/s). Higher settles faster.
        public var hoverDamping: Float = 4
        /// Simulation box the fruit is clamped inside.
        public var boundsMin = SIMD3<Float>(-0.30, -0.54, -1.15)
        public var boundsMax = SIMD3<Float>(0.30, 0.60, -0.45)

        public init() {}
    }

    public let configuration: Configuration
    public private(set) var fruits: [FruitState]

    /// Held fruit index and grab offset, keyed by hand side.
    private var heldIndex: [Bool: Int] = [:]
    private var heldOffset: [Bool: SIMD3<Float>] = [:]
    private var lastHeldPosition: [Bool: SIMD3<Float>] = [:]

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.fruits = Self.defaultLayout(configuration: configuration)
    }

    /// One fruit of each kind floating in a row. Heights and depths are a
    /// fixed scattered pattern (not runtime-random): both the visionOS scene
    /// and the webcam runner build the exact same layout independently, which
    /// is what keeps the two views showing the fruit in the same places. The
    /// depth spread also gives the 2D overlay visible near/far size steps.
    private static func defaultLayout(configuration: Configuration) -> [FruitState] {
        let xs: [Float] = [-0.18, -0.06, 0.06, 0.18]
        let ys: [Float] = [-0.06, -0.34, -0.16, -0.42]
        let zs: [Float] = [-0.78, -0.90, -0.72, -0.86]
        return FruitKind.allCases.enumerated().map { index, kind in
            let home = SIMD3(xs[index % xs.count],
                             ys[index % ys.count],
                             zs[index % zs.count])
            return FruitState(
                id: index,
                kind: kind,
                home: home,
                position: home,
                velocity: .zero,
                heldByLeftHand: nil)
        }
    }

    public func reset() {
        fruits = Self.defaultLayout(configuration: configuration)
        heldIndex.removeAll()
        heldOffset.removeAll()
        lastHeldPosition.removeAll()
    }

    /// Advance the simulation one frame.
    public func update(hands: [FruitHandInput], deltaTime: Float) {
        let dt = min(max(deltaTime, 0.001), 0.1)
        for hand in hands {
            step(hand: hand, dt: dt)
        }
        // A hand absent from the input entirely drops whatever it held.
        for side in [true, false] where heldIndex[side] != nil {
            if !hands.contains(where: { $0.isLeft == side }) {
                release(side: side)
            }
        }
        integrateFreeFruit(dt: dt)
    }

    private func step(hand: FruitHandInput, dt: Float) {
        let side = hand.isLeft
        guard hand.isPinching, let point = hand.pinchPoint else {
            release(side: side)
            return
        }
        if heldIndex[side] == nil {
            tryGrab(side: side, at: point)
        }
        guard let index = heldIndex[side], let offset = heldOffset[side] else { return }
        let previous = lastHeldPosition[side] ?? fruits[index].position
        fruits[index].position = clamp(point + offset)
        fruits[index].velocity = (fruits[index].position - previous) / dt
        lastHeldPosition[side] = fruits[index].position
    }

    private func tryGrab(side: Bool, at point: SIMD3<Float>) {
        var best: (index: Int, distance: Float)?
        for (index, fruit) in fruits.enumerated() where !fruit.isHeld {
            let distance = simd_distance(point, fruit.position)
            if distance < configuration.grabRadius, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        guard let best else { return }
        heldIndex[side] = best.index
        heldOffset[side] = fruits[best.index].position - point
        lastHeldPosition[side] = fruits[best.index].position
        fruits[best.index].heldByLeftHand = side
        fruits[best.index].velocity = .zero
    }

    private func release(side: Bool) {
        guard let index = heldIndex[side] else { return }
        fruits[index].heldByLeftHand = nil
        heldIndex[side] = nil
        heldOffset[side] = nil
        lastHeldPosition[side] = nil
    }

    /// Free fruit floats: a damped spring pulls it back to its home spot, so a
    /// thrown fruit drifts, slows, and glides home instead of falling.
    private func integrateFreeFruit(dt: Float) {
        let config = configuration
        for index in fruits.indices where !fruits[index].isHeld {
            var fruit = fruits[index]
            let acceleration = (fruit.home - fruit.position) * config.hoverStiffness
                - fruit.velocity * config.hoverDamping
            fruit.velocity += acceleration * dt
            fruit.position += fruit.velocity * dt

            let clamped = clamp(fruit.position)
            if clamped.x != fruit.position.x { fruit.velocity.x = 0 }
            if clamped.z != fruit.position.z { fruit.velocity.z = 0 }
            if clamped.y != fruit.position.y { fruit.velocity.y = 0 }
            fruit.position = clamped
            fruits[index] = fruit
        }
    }

    private func clamp(_ p: SIMD3<Float>) -> SIMD3<Float> {
        simd_clamp(p, configuration.boundsMin, configuration.boundsMax)
    }
}
