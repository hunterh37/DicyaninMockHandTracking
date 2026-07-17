import SwiftUI
import DicyaninHandTrackingTransport

struct ContentView: View {
    @EnvironmentObject private var model: HandRunnerModel

    var body: some View {
        VStack(spacing: 0) {
            preview
            controls
        }
        .background(Color.black)
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                if model.cameraAuthorized {
                    CameraPreview(session: model.session, mirrored: model.mirrored)
                    FruitOverlayView(fruit: model.fruit, size: geo.size,
                                     videoSize: model.videoSize)
                    HandOverlay(hands: model.hands, size: geo.size, videoSize: model.videoSize)
                } else {
                    cameraDeniedNotice
                }
                VStack { Spacer(); statusBar }
            }
        }
        .frame(minHeight: 380)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label(model.listenerState, systemImage: "antenna.radiowaves.left.and.right")
            Divider().frame(height: 14)
            Label("\(model.clientCount) app\(model.clientCount == 1 ? "" : "s")",
                  systemImage: "visionpro")
                .foregroundStyle(model.clientCount > 0 ? .green : .secondary)
            Divider().frame(height: 14)
            Text("\(model.fps) fps")
            Spacer()
            ForEach(model.hands) { hand in
                Text(hand.isLeft ? "L" : "R")
                    .fontWeight(.bold)
                    .foregroundStyle(hand.isPinching ? .yellow : (hand.isLeft ? .blue : .orange))
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @State private var copied = false

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.clientCount > 0 ? "App connected" : "Waiting for a visionOS app",
                      systemImage: model.clientCount > 0 ? "checkmark.circle.fill" : "hourglass")
                    .foregroundStyle(model.clientCount > 0 ? .green : .secondary)
                    .font(.caption)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(model.diagnosticsReport(), forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy errors / warnings",
                          systemImage: copied ? "checkmark" : "doc.on.clipboard")
                }
            }
            HStack {
                Toggle("Mirror (selfie view)", isOn: $model.mirrored)
                Spacer()
                Button {
                    model.resetFruit()
                } label: {
                    Label("Reset fruit", systemImage: "arrow.counterclockwise")
                }
            }
            slider("Horizontal reach", value: $model.horizontalSpan, range: 0.2...0.8, unit: "m")
            slider("Vertical reach", value: $model.verticalSpan, range: 0.2...0.6, unit: "m")
            Text("In your visionOS app (simulator), call `MockHandTrackingController.shared.connectToWebcamRunner()` once at launch. Hold your hands up, pinch thumb-to-index on a fruit to grab it, move it, and let go to throw. The same fruit scene runs in 3D in the visionOS app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.background)
    }

    private func slider(_ title: String, value: Binding<Float>,
                        range: ClosedRange<Float>, unit: String) -> some View {
        HStack {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f %@", value.wrappedValue, unit))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var cameraDeniedNotice: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash").font(.largeTitle)
            Text("Camera access denied")
            Text("Enable it in System Settings ▸ Privacy & Security ▸ Camera.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Draws wrist / thumb / index markers over the live preview.
private struct HandOverlay: View {
    let hands: [DetectedHand]
    let size: CGSize
    let videoSize: CGSize

    /// Wrist-to-fingertip chains for skeleton lines.
    private static let chains: [[HandJointID]] = [
        [.wrist, .thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip],
        [.wrist, .indexKnuckle, .indexIntermediateBase, .indexIntermediateTip, .indexTip],
        [.wrist, .middleKnuckle, .middleIntermediateBase, .middleIntermediateTip, .middleTip],
        [.wrist, .ringKnuckle, .ringIntermediateBase, .ringIntermediateTip, .ringTip],
        [.wrist, .littleKnuckle, .littleIntermediateBase, .littleIntermediateTip, .littleTip],
    ]
    private static let tips: Set<HandJointID> = [
        .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip,
    ]

    var body: some View {
        Canvas { ctx, _ in
            for hand in hands {
                let color: Color = hand.isLeft ? .blue : .orange

                // Bones: connect consecutive detected joints along each finger.
                for chain in Self.chains {
                    var path = Path()
                    var started = false
                    for id in chain {
                        guard let p = hand.overlay[id] else { continue }
                        if started { path.addLine(to: point(p)) }
                        else { path.move(to: point(p)); started = true }
                    }
                    ctx.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 2)
                }

                // Joints: ring for the wrist, dots for everything else.
                for (id, p) in hand.overlay {
                    if id == .wrist {
                        marker(ctx, p, color, radius: 9, filled: false)
                    } else {
                        marker(ctx, p, color, radius: Self.tips.contains(id) ? 5 : 3.5,
                               filled: true)
                    }
                }

                if hand.isPinching,
                   let thumb = hand.overlay[.thumbTip], let index = hand.overlay[.indexTip] {
                    var path = Path()
                    path.move(to: point(thumb))
                    path.addLine(to: point(index))
                    ctx.stroke(path, with: .color(.yellow), lineWidth: 3)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Maps a normalized (0...1, top-left origin) video point into view space,
    /// matching the preview layer's `.resizeAspectFill` scale and crop.
    private func point(_ p: CGPoint) -> CGPoint {
        guard videoSize.width > 0, videoSize.height > 0,
              size.width > 0, size.height > 0 else {
            return CGPoint(x: p.x * size.width, y: p.y * size.height)
        }
        let scale = max(size.width / videoSize.width, size.height / videoSize.height)
        let drawn = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        let offset = CGPoint(x: (size.width - drawn.width) / 2,
                             y: (size.height - drawn.height) / 2)
        return CGPoint(x: offset.x + p.x * drawn.width,
                       y: offset.y + p.y * drawn.height)
    }

    private func marker(_ ctx: GraphicsContext, _ p: CGPoint, _ color: Color,
                        radius: CGFloat, filled: Bool) {
        let c = point(p)
        let rect = CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)
        let path = Path(ellipseIn: rect)
        if filled {
            ctx.fill(path, with: .color(color))
        } else {
            ctx.stroke(path, with: .color(color), lineWidth: 3)
        }
    }
}
