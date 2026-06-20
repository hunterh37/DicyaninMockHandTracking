import SwiftUI
import AppKit

// Launches a real macOS window hosting the MockHandTracking control views and
// captures it with `screencapture -l <windowID>`, so SwiftUI materials, blur,
// and controls composite through the WindowServer exactly as they do on screen.
//
// Requires Screen Recording permission for the launching terminal
// (System Settings > Privacy & Security > Screen Recording).

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1]
                 : FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Screenshots", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Dark backdrop so the translucent panel reads well in the README.
struct Backdrop<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(48)
            .frame(width: 600, height: 600)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.09, green: 0.10, blue: 0.14),
                             Color(red: 0.02, green: 0.02, blue: 0.05)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
    }
}

/// Borderless windows return false for canBecomeKey by default, which makes
/// AppKit draw controls (e.g. the prominent PINCH button) in their grey,
/// inactive state. Allow key/main so tints render at full saturation.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    let window = KeyableWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
        styleMask: [.borderless],
        backing: .buffered, defer: false)
    let controller = MockHandTrackingController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.contentView = NSHostingView(rootView: Backdrop { MockHandControlView() })
        window.isOpaque = true
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let the WindowServer composite a couple of frames, then capture.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.captureResting() }
    }

    func captureResting() {
        capture(to: "control-panel.png")
        // Mutate to the aiming + active-pinch state and re-render.
        controller.leftHandPosition  = [-0.40, -0.10, -0.62]
        controller.rightHandPosition = [ 0.34,  0.05, -0.55]
        controller.leftHandYaw  =  0.35
        controller.rightHandYaw = -0.45
        controller.isPinching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.capture(to: "control-panel-active.png")
            NSApp.terminate(nil)
        }
    }

    func capture(to name: String) {
        let url = outDir.appendingPathComponent(name)
        let id = window.windowNumber
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-o", "-x", "-l", String(id), url.path]
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               (try? url.checkResourceIsReachable()) == true {
                print("wrote \(url.path)")
            } else {
                let msg = "screencapture failed (status \(proc.terminationStatus)). " +
                    "Grant Screen Recording permission to your terminal.\n"
                FileHandle.standardError.write(Data(msg.utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("screencapture error: \(error)\n".utf8))
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppController()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
