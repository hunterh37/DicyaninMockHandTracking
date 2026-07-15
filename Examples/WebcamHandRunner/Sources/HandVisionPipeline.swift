import AVFoundation
import Vision
import simd
import CoreGraphics
import DicyaninHandTrackingTransport

/// Runs `VNDetectHumanHandPoseRequest` on each camera frame and maps the result
/// into head-relative `DetectedHand`s. Lives off the main actor: the capture
/// delegate fires on `queue`, and results are handed back via `onFrame`.
///
/// Hands are assigned to left/right by their mapped head-space X (smaller X =
/// left), which stays correct regardless of mirroring instead of fighting
/// Vision's image-space chirality.
final class HandVisionPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "dicyanin.handpose.vision")

    /// Called on `queue` with the hands found in a frame (0, 1, or 2) and the
    /// pixel size of that frame (needed to undo aspect-fill cropping in the overlay).
    var onFrame: (([DetectedHand], CGSize) -> Void)?

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
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let aspect = CGFloat(w) / CGFloat(max(h, 1))
        let observations = request.results ?? []
        var hands = observations.compactMap { map($0, aspect: aspect) }
        // Stable left/right split by mapped X.
        hands.sort { $0.headPosition.x < $1.headPosition.x }
        if hands.count == 2 {
            hands[0].isLeft = true
            hands[1].isLeft = false
        } else if let only = hands.first {
            hands[0].isLeft = only.headPosition.x < 0
        }
        let frameSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                               height: CVPixelBufferGetHeight(pixelBuffer))
        onFrame?(hands, frameSize)
    }

    /// Vision joint for each canonical wire joint, in `HandJointID.allCases` order.
    private static let visionJoint: [HandJointID: VNHumanHandPoseObservation.JointName] = [
        .wrist: .wrist,
        .thumbKnuckle: .thumbCMC, .thumbIntermediateBase: .thumbMP,
        .thumbIntermediateTip: .thumbIP, .thumbTip: .thumbTip,
        .indexKnuckle: .indexMCP, .indexIntermediateBase: .indexPIP,
        .indexIntermediateTip: .indexDIP, .indexTip: .indexTip,
        .middleKnuckle: .middleMCP, .middleIntermediateBase: .middlePIP,
        .middleIntermediateTip: .middleDIP, .middleTip: .middleTip,
        .ringKnuckle: .ringMCP, .ringIntermediateBase: .ringPIP,
        .ringIntermediateTip: .ringDIP, .ringTip: .ringTip,
        .littleKnuckle: .littleMCP, .littleIntermediateBase: .littlePIP,
        .littleIntermediateTip: .littleDIP, .littleTip: .littleTip,
    ]

    /// Real-world palm length (wrist to middle knuckle) the skeleton is scaled to.
    private let palmLength: Float = 0.09

    private func map(_ observation: VNHumanHandPoseObservation, aspect: CGFloat) -> DetectedHand? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        func pt(_ name: VNHumanHandPoseObservation.JointName, min: Float = 0.3) -> CGPoint? {
            guard let p = points[name], p.confidence > min else { return nil }
            return CGPoint(x: p.location.x, y: p.location.y) // bottom-left origin, y up
        }
        guard let wrist = pt(.wrist) else { return nil }
        let middleMCP = pt(.middleMCP) ?? wrist
        let thumbTip = pt(.thumbTip) ?? wrist
        let indexTip = pt(.indexTip) ?? wrist

        // Depth proxy: a bigger hand (wrist→middleMCP span) reads as closer.
        let handSpan = hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y)
        let depthScale = Float(min(max(handSpan, 0.05), 0.30) - 0.05) / 0.25 // 0…1
        let headZ = baseZ + 0.18 * (0.5 - depthScale) // closer hand → less negative Z

        // Shared image → head-relative mapping. All joints of a hand share the
        // depth proxy; x/y come from where the joint sits in the frame.
        func project(_ p: CGPoint) -> SIMD3<Float> {
            let nx = mirrored ? (1.0 - p.x) : p.x
            let headX = Float(nx - 0.5) * 2 * horizontalSpan
            let headY = baseY + Float(p.y - 0.5) * 2 * verticalSpan
            return SIMD3(headX, headY, headZ)
        }
        // Overlay points in top-left origin for SwiftUI drawing.
        func flip(_ p: CGPoint) -> CGPoint {
            CGPoint(x: mirrored ? 1 - p.x : p.x, y: 1 - p.y)
        }

        // Full skeleton. Gross hand travel uses the amplified reach mapping
        // (project), but finger articulation must not: reusing that scale makes
        // fingers meters long. Instead, joints are wrist-relative offsets scaled
        // so the palm (wrist to middle knuckle) is a realistic `palmLength`,
        // with the frame aspect folded in so proportions survive the
        // normalized-coordinate squash.
        let wristHead = project(wrist)
        let palmNorm = Float(hypot((middleMCP.x - wrist.x) * aspect, middleMCP.y - wrist.y))
        let metersPerNorm = palmLength / max(palmNorm, 0.02)
        func jointPosition(_ p: CGPoint) -> SIMD3<Float> {
            let dx = Float((p.x - wrist.x) * aspect) * (mirrored ? -1 : 1) * metersPerNorm
            let dy = Float(p.y - wrist.y) * metersPerNorm
            return wristHead + SIMD3(dx, dy, 0)
        }

        var joints: [HandJointID: SIMD3<Float>] = [:]
        var overlay: [HandJointID: CGPoint] = [:]
        for (id, vn) in Self.visionJoint {
            guard let p = pt(vn, min: 0.15) else { continue }
            joints[id] = jointPosition(p)
            overlay[id] = flip(p)
        }
        joints[.wrist] = wristHead
        overlay[.wrist] = flip(wrist)

        // Yaw from the wrist→middleMCP direction in the image plane.
        let dirX = Float(middleMCP.x - wrist.x) * (mirrored ? -1 : 1)
        let dirY = Float(middleMCP.y - wrist.y)
        let yaw = atan2(dirX, max(dirY, 0.001))

        // Pinch when thumb and index tips are close relative to hand size.
        let pinchDist = hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y)
        let isPinching = handSpan > 0.04 && pinchDist < handSpan * 0.45

        let headPosition = wristHead
        return DetectedHand(
            headPosition: headPosition,
            yaw: yaw,
            isPinching: isPinching,
            joints: joints,
            overlay: overlay,
            isLeft: headPosition.x < 0)
    }
}
