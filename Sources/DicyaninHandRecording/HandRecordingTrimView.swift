#if canImport(SwiftUI)
import SwiftUI

/// A VR-friendly view for trimming hand recordings. Shows a visual timeline
/// with draggable start/end handles and a scrubber playhead. Dragging the
/// playhead (or tapping anywhere on the timeline) seeks the glove preview in
/// real time, so you can see the hand pose at every point and decide where
/// to trim.
///
/// Usage:
/// ```swift
/// HandRecordingTrimView(session: mySession)
/// ```
public struct HandRecordingTrimView: View {
    @ObservedObject private var manager: HandRecordingManager

    /// The original (unmodified) session being trimmed.
    public let session: HandRecordingSession

    // MARK: - State

    /// Trim range start, in seconds.
    @State private var trimStart: Double = 0
    /// Trim range end, in seconds.
    @State private var trimEnd: Double = 0
    /// Current playhead position, in seconds.
    @State private var playhead: Double = 0
    /// Whether the looping preview is playing.
    @State private var isPreviewing: Bool = false
    /// Whether the user is actively scrubbing (dragging the playhead).
    @State private var isScrubbing: Bool = false
    /// Which element the user is dragging.
    @State private var activeElement: DragElement? = nil
    /// Snapshot of the value when a drag began.
    @State private var dragOriginTime: Double = 0
    /// Which hands to keep.
    @State private var handFilter: HandRecordingSession.HandFilter = .both
    /// Editable name for the output recording.
    @State private var outputName: String = ""

    /// Dismiss callback.
    private var onDismiss: (() -> Void)?
    /// Callback after save.
    private var onSaved: ((HandRecordingSession) -> Void)?

    private enum DragElement {
        case trimStart, trimEnd, playhead
    }

    @MainActor
    public init(
        session: HandRecordingSession,
        manager: HandRecordingManager? = nil,
        onDismiss: (() -> Void)? = nil,
        onSaved: ((HandRecordingSession) -> Void)? = nil
    ) {
        self.session = session
        self.manager = manager ?? .shared
        self.onDismiss = onDismiss
        self.onSaved = onSaved
    }

    private var duration: Double { session.duration }

    private var trimmedDuration: Double { max(0, trimEnd - trimStart) }

    private var trimmedFrameCount: Int {
        session.frames.filter { $0.time >= trimStart && $0.time <= trimEnd }.count
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 20) {
            header
            scrubberRow
            timelineSection
            statsRow
            optionsSection
            controlButtons
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 540)
        .onAppear {
            trimStart = 0
            trimEnd = duration
            playhead = 0
            outputName = session.name
            // Show the first frame immediately so the gloves appear.
            manager.seekToFrame(in: session, at: 0)
        }
        .onDisappear {
            if isPreviewing { stopPreview() }
        }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Trim Recording")
                    .font(.title2.weight(.semibold))
                Text(session.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let onDismiss {
                Button("Cancel", role: .cancel) {
                    manager.cancelTrimming()
                    onDismiss()
                }
            }
        }
    }

    // MARK: - Scrubber (playhead slider)

    /// A full-width slider the user drags to scrub through the recording.
    /// The gloves update in real time as they drag.
    @ViewBuilder private var scrubberRow: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Scrub to preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTimePrecise(playhead))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isScrubbing ? .primary : .secondary)
            }

            GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = 36

                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 6)
                        .frame(maxHeight: .infinity, alignment: .center)

                    // Filled portion up to playhead
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.5))
                        .frame(width: xForTime(playhead, in: width), height: 6)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .allowsHitTesting(false)

                    // Playhead thumb
                    Circle()
                        .fill(Color.green)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        .offset(x: xForTime(playhead, in: width) - 11)
                        .gesture(playheadDrag(width: width))
                        .accessibilityLabel("Playhead scrubber")

                    // Invisible tap target for the whole track
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .frame(height: height)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let t = timeForX(value.location.x, in: width)
                                    let clamped = min(max(0, t), duration)
                                    playhead = clamped
                                    isScrubbing = true
                                    if isPreviewing { stopPreview() }
                                    manager.seekToFrame(in: session, at: clamped)
                                }
                                .onEnded { _ in
                                    isScrubbing = false
                                }
                        )
                }
                .frame(height: height)
            }
            .frame(height: 36)
        }
    }

    private func playheadDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if activeElement == nil {
                    activeElement = .playhead
                    dragOriginTime = playhead
                    isScrubbing = true
                    if isPreviewing { stopPreview() }
                }
                let delta = timeForX(value.translation.width, in: width)
                let t = min(max(0, dragOriginTime + delta), duration)
                playhead = t
                manager.seekToFrame(in: session, at: t)
            }
            .onEnded { _ in
                activeElement = nil
                isScrubbing = false
            }
    }

    // MARK: - Timeline (trim handles)

    @ViewBuilder private var timelineSection: some View {
        VStack(spacing: 8) {
            // Time labels for trim range
            HStack {
                Text(formatTime(trimStart))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.blue)
                Spacer()
                Text("Trim Range")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTime(trimEnd))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.blue)
            }

            // Visual timeline
            GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = 60

                ZStack(alignment: .leading) {
                    // Full duration background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: height)

                    // Frame density visualization
                    frameDensityView(width: width, height: height)

                    // Dimmed region: before trim start
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: xForTime(trimStart, in: width))
                        Spacer(minLength: 0)
                    }
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)

                    // Dimmed region: after trim end
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: width - xForTime(trimEnd, in: width))
                    }
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .allowsHitTesting(false)

                    // Selected region border
                    let sX = xForTime(trimStart, in: width)
                    let eX = xForTime(trimEnd, in: width)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.blue, lineWidth: 2)
                        .frame(width: max(0, eX - sX), height: height)
                        .offset(x: sX)
                        .allowsHitTesting(false)

                    // Playhead line on the timeline
                    let phX = xForTime(playhead, in: width)
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: 2, height: height + 10)
                        .offset(x: phX)
                        .allowsHitTesting(false)

                    // Start handle
                    trimHandle(color: .blue, height: height)
                        .offset(x: xForTime(trimStart, in: width) - 10)
                        .gesture(trimDrag(for: .trimStart, width: width))
                        .accessibilityLabel("Trim start")

                    // End handle
                    trimHandle(color: .blue, height: height)
                        .offset(x: xForTime(trimEnd, in: width) - 10)
                        .gesture(trimDrag(for: .trimEnd, width: width))
                        .accessibilityLabel("Trim end")
                }
                .frame(height: height)
            }
            .frame(height: 60)

            // Precise values
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Start:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTimePrecise(trimStart))
                        .font(.caption.monospacedDigit())
                }
                HStack(spacing: 4) {
                    Text("End:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTimePrecise(trimEnd))
                        .font(.caption.monospacedDigit())
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Selected:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formatTimePrecise(trimmedDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Frame Density Visualization

    @ViewBuilder
    private func frameDensityView(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard duration > 0 else { return }
            let bucketCount = max(1, Int(width / 3))
            let bucketWidth = duration / Double(bucketCount)

            var buckets = [Int](repeating: 0, count: bucketCount)
            for frame in session.frames {
                let idx = min(bucketCount - 1, Int(frame.time / bucketWidth))
                buckets[idx] += 1
            }

            let maxCount = buckets.max() ?? 1
            let barWidth = size.width / CGFloat(bucketCount)

            for (i, count) in buckets.enumerated() {
                let barHeight = size.height * CGFloat(count) / CGFloat(max(1, maxCount)) * 0.8
                let x = CGFloat(i) * barWidth
                let y = size.height - barHeight
                let rect = CGRect(x: x, y: y, width: max(1, barWidth - 0.5), height: barHeight)
                context.fill(Path(rect), with: .color(.blue.opacity(0.25)))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
    }

    // MARK: - Trim Handle View

    @ViewBuilder
    private func trimHandle(color: Color, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 20, height: 8)
            Rectangle()
                .fill(color)
                .frame(width: 3, height: height - 8)
        }
        .frame(width: 20, height: height)
        .contentShape(Rectangle().inset(by: -12))
    }

    // MARK: - Trim Handle Drag

    private func trimDrag(for element: DragElement, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard duration > 0 else { return }

                if activeElement == nil {
                    activeElement = element
                    switch element {
                    case .trimStart: dragOriginTime = trimStart
                    case .trimEnd: dragOriginTime = trimEnd
                    case .playhead: dragOriginTime = playhead
                    }
                }

                let delta = timeForX(value.translation.width, in: width)
                let newTime = dragOriginTime + delta

                switch element {
                case .trimStart:
                    trimStart = min(max(0, newTime), trimEnd - 0.05)
                    // Also seek so the gloves show this position
                    manager.seekToFrame(in: session, at: trimStart)
                    playhead = trimStart
                case .trimEnd:
                    trimEnd = max(min(duration, newTime), trimStart + 0.05)
                    manager.seekToFrame(in: session, at: trimEnd)
                    playhead = trimEnd
                case .playhead:
                    break
                }
            }
            .onEnded { _ in
                activeElement = nil
            }
    }

    // MARK: - Stats Row

    @ViewBuilder private var statsRow: some View {
        HStack(spacing: 24) {
            statItem(label: "Original", value: formatTimePrecise(duration), sub: "\(session.frameCount) frames")
            Divider().frame(height: 30)
            statItem(label: "Trimmed", value: formatTimePrecise(trimmedDuration), sub: "\(trimmedFrameCount) frames")
            Divider().frame(height: 30)
            statItem(label: "Removed", value: formatTimePrecise(duration - trimmedDuration), sub: "\(session.frameCount - trimmedFrameCount) frames")
        }
        .font(.caption)
    }

    @ViewBuilder
    private func statItem(label: String, value: String, sub: String) -> some View {
        VStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit().weight(.medium))
            Text(sub).foregroundStyle(.secondary).font(.caption2)
        }
    }

    // MARK: - Options (hand filter + rename)

    @ViewBuilder private var optionsSection: some View {
        VStack(spacing: 12) {
            // Hand filter
            HStack {
                Text("Hands:")
                    .font(.subheadline)
                Picker("", selection: $handFilter) {
                    ForEach(HandRecordingSession.HandFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Rename
            HStack {
                Text("Name:")
                    .font(.subheadline)
                TextField("Recording name", text: $outputName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Control Buttons

    @ViewBuilder private var controlButtons: some View {
        HStack(spacing: 12) {
            // Preview: plays the trimmed selection in a loop
            Button {
                if isPreviewing {
                    stopPreview()
                } else {
                    startPreview()
                }
            } label: {
                Label(
                    isPreviewing ? "Stop Preview" : "Preview Selection",
                    systemImage: isPreviewing ? "stop.fill" : "play.fill"
                )
            }

            Spacer()

            Button {
                let result = manager.saveTrimmed(
                    session, from: trimStart, to: trimEnd,
                    hand: handFilter, name: outputName
                )
                onSaved?(result)
                onDismiss?()
            } label: {
                Label("Save as Copy", systemImage: "doc.badge.plus")
            }
            .disabled(trimmedFrameCount == 0)

            Button {
                let result = manager.saveTrimmedOverOriginal(
                    session, from: trimStart, to: trimEnd,
                    hand: handFilter, name: outputName
                )
                onSaved?(result)
                onDismiss?()
            } label: {
                Label("Replace Original", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(trimmedFrameCount == 0)
        }
    }

    // MARK: - Preview

    private func startPreview() {
        isPreviewing = true
        manager.previewTrimRange(session, from: trimStart, to: trimEnd, loop: true)
    }

    private func stopPreview() {
        isPreviewing = false
        manager.stopPlayback()
    }

    // MARK: - Coordinate Helpers

    private func xForTime(_ time: Double, in width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func timeForX(_ x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * duration
    }

    // MARK: - Formatting

    private func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatTimePrecise(_ t: Double) -> String {
        String(format: "%.2fs", t)
    }
}
#endif
