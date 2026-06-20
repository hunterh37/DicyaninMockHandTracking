import SwiftUI
import simd

/// Full-screen panel for controlling simulated hand positions in the visionOS simulator.
/// Show this as a sheet or separate window; drag the pads to move each hand in the scene.
public struct MockHandControlView: View {
    @ObservedObject private var controller = MockHandTrackingController.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            Text("Mock Hand Tracking")
                .font(.title2.bold())
                .foregroundStyle(.white)

            HStack(spacing: 32) {
                MockHandStickView(title: "LEFT HAND", color: .blue,
                                  position: $controller.leftHandPosition,
                                  yaw: $controller.leftHandYaw,
                                  showYSlider: true)
                MockHandStickView(title: "RIGHT HAND", color: .orange,
                                  position: $controller.rightHandPosition,
                                  yaw: $controller.rightHandYaw,
                                  showYSlider: true)
            }

            Button(action: { controller.simulatePinch() }) {
                Label("PINCH (Shoot)", systemImage: "hand.pinch.fill")
                    .font(.headline)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.isPinching ? .yellow : .red)
            .animation(.easeOut(duration: 0.1), value: controller.isPinching)

            positionReadout
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var positionReadout: some View {
        HStack(spacing: 24) {
            posVec("L", controller.leftHandPosition)
            posVec("R", controller.rightHandPosition)
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
    }

    private func posVec(_ label: String, _ v: SIMD3<Float>) -> Text {
        Text("\(label): (\(fmt(v.x)), \(fmt(v.y)), \(fmt(v.z)))")
    }

    private func fmt(_ f: Float) -> String { String(format: "%.2f", f) }
}

// MARK: - Reusable Hand Stick (joystick + rotation slider)

/// A single hand controller: a 2D joystick driving X/Z position, a rotation (yaw)
/// slider, and optionally a Y (up/down) slider. Binds directly to the values exposed
/// by `MockHandTrackingController` so the in-hand gun follows in the simulator.
public struct MockHandStickView: View {
    let title: String
    let color: Color
    @Binding var position: SIMD3<Float>
    @Binding var yaw: Float
    let showYSlider: Bool

    public init(title: String, color: Color,
                position: Binding<SIMD3<Float>>,
                yaw: Binding<Float>,
                showYSlider: Bool = false) {
        self.title = title
        self.color = color
        self._position = position
        self._yaw = yaw
        self.showYSlider = showYSlider
    }

    public var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline.weight(.black))
                .foregroundStyle(color)

            MockHandJoystickPad(color: color,
                                xz: Binding(
                                    get: { SIMD2(position.x, position.z) },
                                    set: { v in position.x = v.x; position.z = v.y }
                                ))

            VStack(spacing: 4) {
                Text("ROTATION  \(Int(yaw * 180 / .pi))°")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.7))
                Slider(value: Binding(get: { Double(yaw) },
                                      set: { yaw = Float($0) }),
                       in: Double(-Float.pi)...Double(Float.pi))
                .tint(color)
                .frame(width: 180)
            }

            if showYSlider {
                VStack(spacing: 4) {
                    Text("Y \(String(format: "%.2f", position.y))m")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(position.y) },
                                          set: { position.y = Float($0) }),
                           in: -1.0...0.5)
                    .tint(color)
                    .frame(width: 180)
                }
            }
        }
        .padding(18)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Joystick Pad

public struct MockHandJoystickPad: View {
    let color: Color
    @Binding var xz: SIMD2<Float>

    private let padSize: CGFloat = 160
    private let dotSize: CGFloat = 32
    // ±0.8 m range mapped to the pad
    private let range: Float = 0.8

    public init(color: Color, xz: Binding<SIMD2<Float>>) {
        self.color = color
        self._xz = xz
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )

            Path { p in
                p.move(to: CGPoint(x: padSize / 2, y: 4))
                p.addLine(to: CGPoint(x: padSize / 2, y: padSize - 4))
                p.move(to: CGPoint(x: 4, y: padSize / 2))
                p.addLine(to: CGPoint(x: padSize - 4, y: padSize / 2))
            }
            .stroke(color.opacity(0.2), lineWidth: 1)

            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: color.opacity(0.5), radius: 6)
                .offset(dotOffset)
        }
        .frame(width: padSize, height: padSize)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let half = Float(padSize / 2)
                    let nx = Float(value.location.x) - half
                    let nz = Float(value.location.y) - half
                    xz.x = (nx / half * range).clamped(to: -range...range)
                    xz.y = (nz / half * range).clamped(to: -range...range)
                }
        )
    }

    private var dotOffset: CGSize {
        let half = Double(padSize / 2 - dotSize / 2)
        let fx = Double(xz.x / range) * half
        let fz = Double(xz.y / range) * half
        return CGSize(width: fx, height: fz)
    }
}

// MARK: - Helpers

extension Float {
    fileprivate func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
