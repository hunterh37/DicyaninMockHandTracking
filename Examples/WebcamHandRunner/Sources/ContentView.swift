import SwiftUI

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
                    HandOverlay(hands: model.hands, size: geo.size)
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Mirror (selfie view)", isOn: $model.mirrored)
            slider("Horizontal reach", value: $model.horizontalSpan, range: 0.2...0.8, unit: "m")
            slider("Vertical reach", value: $model.verticalSpan, range: 0.2...0.6, unit: "m")
            Text("In your visionOS app (simulator), call `MockHandTrackingController.shared.connectToWebcamRunner()` once at launch. Hold your hands up — pinch thumb-to-index to fire.")
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

    var body: some View {
        Canvas { ctx, _ in
            for hand in hands {
                let color: Color = hand.isLeft ? .blue : .orange
                marker(ctx, hand.wrist, color, radius: 10, filled: false)
                marker(ctx, hand.thumbTip, color, radius: 6, filled: hand.isPinching)
                marker(ctx, hand.indexTip, color, radius: 6, filled: hand.isPinching)
                if hand.isPinching {
                    var path = Path()
                    path.move(to: point(hand.thumbTip))
                    path.addLine(to: point(hand.indexTip))
                    ctx.stroke(path, with: .color(.yellow), lineWidth: 3)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func point(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
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
