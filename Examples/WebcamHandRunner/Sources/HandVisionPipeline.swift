import AVFoundation
import Vision
import simd
import CoreGraphics

/// Runs `VNDetectHumanHandPoseRequest` on each camera frame and maps the result
/// into head-relative `DetectedHand`s. Lives off the main actor: the capture
/// delegate fires on `queue`, and results are handed back via `onFrame`.
///
/// Hands are assigned to left/right by their mapped head-space X (smaller X =
/// left), which stays correct regardless of mirroring instead of fighting
/// Vision's image-space chirality.
final class HandVisionPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "dicyanin.handpose.vision")

    /// Called on `queue` with the hands found in a frame (0, 1, or 2).
    var onFrame: (([DetectedHand]) -> Void)?

    // Operator tuning (read on `queue`).
    var mirrored = true
    var horizontalSpan: Float = 0.45
    var verticalSpan: Float = 0.35

    // Resting center of the mapped volume (matches the mock controller defaults).
    private let baseY: Float = -0.20
    private let baseZ: Float = -0.72

    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }
        let observations = request.results ?? []
        var hands = observations.compactMap { map($0) }
        // Stable left/right split by mapped X.
        hands.sort { $0.headPosition.x < $1.headPosition.x }
        if hands.count == 2 {
            hands[0].isLeft = true
            hands[1].isLeft = false
        } else if let only = hands.first {
            hands[0].isLeft = only.headPosition.x < 0
        }
        onFrame?(hands)
    }

    private func map(_ observation: VNHumanHandPoseObservation) -> DetectedHand? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        func pt(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p = points[name], p.confidence > 0.3 else { return nil }
            return CGPoint(x: p.location.x, y: p.location.y) // bottom-left origin, y up
        }
        guard let wrist = pt(.wrist) else { return nil }
        let middleMCP = pt(.middleMCP) ?? wrist
        let thumbTip = pt(.thumbTip) ?? wrist
        let indexTip = pt(.indexTip) ?? wrist

        // Apply mirror to the horizontal axis so a selfie view feels natural.
        let nx = mirrored ? (1.0 - wrist.x) : wrist.x
        let ny = wrist.y // already up-positive

        let headX = Float(nx - 0.5) * 2 * horizontalSpan
        let headY = baseY + Float(ny - 0.5) * 2 * verticalSpan

        // Depth proxy: a bigger hand (wrist→middleMCP span) reads as closer.
        let handSpan = hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y)
        let depthScale = Float(min(max(handSpan, 0.05), 0.30) - 0.05) / 0.25 // 0…1
        let headZ = baseZ + 0.18 * (0.5 - depthScale) // closer hand → less negative Z

        // Yaw from the wrist→middleMCP direction in the image plane.
        let dirX = Float(middleMCP.x - wrist.x) * (mirrored ? -1 : 1)
        let dirY = Float(middleMCP.y - wrist.y)
        let yaw = atan2(dirX, max(dirY, 0.001))

        // Pinch when thumb and index tips are close relative to hand size.
        let pinchDist = hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y)
        let isPinching = handSpan > 0.04 && pinchDist < handSpan * 0.45

        // Overlay points in top-left origin for SwiftUI drawing.
        func flip(_ p: CGPoint) -> CGPoint {
            CGPoint(x: mirrored ? 1 - p.x : p.x, y: 1 - p.y)
        }

        return DetectedHand(
            headPosition: SIMD3(headX, headY, headZ),
            yaw: yaw,
            isPinching: isPinching,
            wrist: flip(wrist),
            thumbTip: flip(thumbTip),
            indexTip: flip(indexTip),
            isLeft: headX < 0)
    }
}
