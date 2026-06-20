import SwiftUI
import AppKit

// Renders the MockHandTracking control views to PNG files for the README.
// Uses ImageRenderer so no Screen-Recording permission or simulator is needed.

@MainActor
func writePNG<V: View>(_ view: V, scale: CGFloat, to url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("render failed: \(url.lastPathComponent)\n".utf8))
        return
    }
    do {
        try png.write(to: url)
        print("wrote \(url.path)")
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    }
}

/// Dark backdrop so the translucent panel reads well in the README.
struct Backdrop<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(48)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.10, blue: 0.14),
                             Color(red: 0.02, green: 0.02, blue: 0.05)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
    }
}

@MainActor
func run() {
    let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                     ? CommandLine.arguments[1]
                     : FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let controller = MockHandTrackingController.shared

    // 1) Default resting pose.
    writePNG(Backdrop { MockHandControlView() }, scale: 2,
             to: outDir.appendingPathComponent("control-panel.png"))

    // 2) Aimed pose with active pinch highlight.
    controller.leftHandPosition  = [-0.40, -0.10, -0.62]
    controller.rightHandPosition = [ 0.34,  0.05, -0.55]
    controller.leftHandYaw  =  0.35
    controller.rightHandYaw = -0.45
    controller.isPinching = true
    writePNG(Backdrop { MockHandControlView() }, scale: 2,
             to: outDir.appendingPathComponent("control-panel-active.png"))
}

MainActor.assumeIsolated { run() }
