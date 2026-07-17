import SwiftUI
import DicyaninFruitScene

/// Draws the shared fruit simulation as 2D sprites over the live camera
/// preview. Sprite size folds in both the fruit's physical radius and its
/// simulated depth, so fruit nearer the viewer reads slightly bigger. A held
/// fruit gets a yellow grab ring, mirroring the visionOS scene's highlight.
struct FruitOverlayView: View {
    let fruit: [FruitDisplay]
    let size: CGSize
    let videoSize: CGSize

    var body: some View {
        Canvas { ctx, _ in
            for item in fruit {
                draw(item, in: ctx)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ item: FruitDisplay, in ctx: GraphicsContext) {
        let center = point(item.center)
        let drawnWidth = drawnSize().width
        let radius = max(item.radiusNorm * drawnWidth * item.depthScale, 6)
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        let body = Path(ellipseIn: rect)

        let base = color(item.kind.colorRGBA)
        // Shaded fill: light source up-left, like the 3D scene's lighting.
        ctx.fill(body, with: .radialGradient(
            Gradient(colors: [base.opacity(0.95), base, shaded(item.kind.colorRGBA)]),
            center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35),
            startRadius: radius * 0.1,
            endRadius: radius * 1.4))
        ctx.stroke(body, with: .color(shaded(item.kind.colorRGBA)), lineWidth: 1)

        // Stem.
        var stem = Path()
        stem.move(to: CGPoint(x: center.x, y: center.y - radius))
        stem.addLine(to: CGPoint(x: center.x + radius * 0.15, y: center.y - radius * 1.35))
        ctx.stroke(stem, with: .color(Color(red: 0.35, green: 0.22, blue: 0.10)),
                   lineWidth: max(radius * 0.14, 1.5))

        if item.isHeld {
            let ring = Path(ellipseIn: rect.insetBy(dx: -radius * 0.25, dy: -radius * 0.25))
            ctx.stroke(ring, with: .color(.yellow), lineWidth: 3)
        }
    }

    private func color(_ rgba: SIMD4<Float>) -> Color {
        Color(red: Double(rgba.x), green: Double(rgba.y), blue: Double(rgba.z))
    }

    private func shaded(_ rgba: SIMD4<Float>) -> Color {
        Color(red: Double(rgba.x) * 0.55, green: Double(rgba.y) * 0.55,
              blue: Double(rgba.z) * 0.55)
    }

    /// Size of the aspect-filled video inside the view.
    private func drawnSize() -> CGSize {
        guard videoSize.width > 0, videoSize.height > 0,
              size.width > 0, size.height > 0 else { return size }
        let scale = max(size.width / videoSize.width, size.height / videoSize.height)
        return CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
    }

    /// Maps a normalized (0...1, top-left origin) video point into view space,
    /// matching the preview layer's `.resizeAspectFill` scale and crop.
    private func point(_ p: CGPoint) -> CGPoint {
        let drawn = drawnSize()
        let offset = CGPoint(x: (size.width - drawn.width) / 2,
                             y: (size.height - drawn.height) / 2)
        return CGPoint(x: offset.x + p.x * drawn.width,
                       y: offset.y + p.y * drawn.height)
    }
}
