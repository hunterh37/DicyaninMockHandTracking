import AVFoundation
import Vision
import simd
import SwiftUI
import Combine
import DicyaninHandTrackingTransport

/// A detected hand reduced to the few normalized image points we need, plus the
/// head-relative position we mapped it to. Used both for the wire packet and to
/// draw the on-screen overlay.
struct DetectedHand: Identifiable {
    let id = UUID()
    var headPosition: SIMD3<Float>
    var yaw: Float
    var isPinching: Bool
    /// Normalized (0...1, top-left origin) screen points for overlay drawing.
    var wrist: CGPoint
    var thumbTip: CGPoint
    var indexTip: CGPoint
    var isLeft: Bool
}

/// Owns the camera + Vision pipeline and the network sender, and publishes UI
/// state. Vision runs on a background queue; published mutations hop to the main
/// actor.
@MainActor
final class HandRunnerModel: ObservableObject {
    // Connection / status
    @Published var listenerState: String = "starting…"
    @Published var servingPort: UInt16 = HandPoseWire.defaultPort
    @Published var clientCount: Int = 0
    @Published var cameraAuthorized: Bool = true
    @Published var fps: Int = 0

    // Detected hands (for overlay + readout)
    @Published var hands: [DetectedHand] = []

    // Operator tuning
    @Published var mirrored: Bool = true {
        didSet { pipeline.mirrored = mirrored }
    }
    /// Horizontal/vertical reach in meters mapped from the full frame.
    @Published var horizontalSpan: Float = 0.45 {
        didSet { pipeline.horizontalSpan = horizontalSpan }
    }
    @Published var verticalSpan: Float = 0.35 {
        didSet { pipeline.verticalSpan = verticalSpan }
    }

    let session = AVCaptureSession()
    private let pipeline = HandVisionPipeline()
    private var sender: HandPoseSender?
    private var fpsCounter = 0
    private var fpsTimer: Timer?

    func start() async {
        startSender()
        pipeline.onFrame = { [weak self] hands in
            Task { @MainActor in self?.publish(hands) }
        }
        await configureCamera()
        startFPSTimer()
    }

    private func startSender() {
        do {
            let sender = try HandPoseSender(port: HandPoseWire.defaultPort)
            sender.onStateChange = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .setup: self?.listenerState = "starting…"
                    case .ready(let port):
                        self?.servingPort = port
                        self?.listenerState = "serving on port \(port)"
                    case .failed(let msg):
                        self?.listenerState = "failed: \(msg)"
                    }
                }
            }
            sender.onClientCountChange = { [weak self] count in
                Task { @MainActor in self?.clientCount = count }
            }
            sender.start()
            self.sender = sender
        } catch {
            listenerState = "failed: \(error.localizedDescription)"
        }
    }

    private func configureCamera() async {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .video)
        default: granted = false
        }
        cameraAuthorized = granted
        guard granted else { return }

        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(pipeline, queue: pipeline.queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        Task.detached { [session] in session.startRunning() }
    }

    private func publish(_ hands: [DetectedHand]) {
        self.hands = hands
        fpsCounter += 1

        // Build a packet, holding last position for any hand not seen.
        var left = hands.first(where: { $0.isLeft })
        var right = hands.first(where: { !$0.isLeft })
        // If two hands but mis-split, the headPosition ordering still holds.
        if hands.count == 1, let only = hands.first {
            if only.isLeft { right = nil } else { left = nil }
        }

        let anyPinch = (left?.isPinching ?? false) || (right?.isPinching ?? false)
        let packet = HandPosePacket(
            leftPosition: left?.headPosition ?? lastLeft,
            rightPosition: right?.headPosition ?? lastRight,
            leftYaw: left?.yaw ?? 0,
            rightYaw: right?.yaw ?? 0,
            isPinching: anyPinch,
            leftTracked: left != nil,
            rightTracked: right != nil)
        if let l = left { lastLeft = l.headPosition }
        if let r = right { lastRight = r.headPosition }
        sender?.broadcast(packet)
    }

    private var lastLeft: SIMD3<Float> = [-0.22, -0.26, -0.72]
    private var lastRight: SIMD3<Float> = [0.22, -0.26, -0.72]

    private func startFPSTimer() {
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.fps = self.fpsCounter
                self.fpsCounter = 0
            }
        }
    }
}
