import SwiftUI
import AVFoundation

/// Live camera preview backed by `AVCaptureVideoPreviewLayer`, mirrored to match
/// the operator's expectation of a selfie view.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        if let conn = nsView.previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = mirrored
        }
    }

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = previewLayer
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}
