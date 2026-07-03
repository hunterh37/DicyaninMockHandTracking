#if canImport(SwiftUI)
import SwiftUI

/// Drop-in control panel for capturing, browsing, and replaying glove
/// hand-tracking sessions.
///
/// Add it anywhere in your app (a window, an ornament, an attachment) and it
/// drives ``HandRecordingManager/shared``:
/// ```swift
/// HandRecordingControlView()
/// ```
public struct HandRecordingControlView: View {
    @ObservedObject private var manager: HandRecordingManager
    @State private var name: String = "Recording"
    @State private var loop: Bool = false
    @State private var trimTarget: HandRecordingSession?
    @State private var renameTarget: HandRecordingSession?
    @State private var renameText: String = ""

    @MainActor
    public init(manager: HandRecordingManager? = nil) {
        self.manager = manager ?? .shared
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hand Recording")
                .font(.headline)

            transport

            Divider()

            library
        }
        .padding()
        .frame(minWidth: 320)
        .onAppear { manager.refresh() }
        .sheet(item: $trimTarget) { session in
            HandRecordingTrimView(
                session: session,
                manager: manager,
                onDismiss: { trimTarget = nil },
                onSaved: { _ in trimTarget = nil }
            )
        }
        .alert("Rename Recording", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renameTarget {
                    manager.rename(target, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Enter a new name for this recording.")
        }
    }

    @ViewBuilder private var transport: some View {
        HStack(spacing: 12) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(manager.mode != .idle)

            if manager.isRecording {
                Button(role: .destructive) {
                    manager.stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                }
            } else {
                Button {
                    manager.startRecording(named: name.isEmpty ? "Recording" : name)
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .disabled(manager.mode != .idle)
            }
        }

        HStack {
            Toggle("Loop playback", isOn: $loop)
                .toggleStyle(.switch)
            Spacer()
            if manager.mode != .idle {
                Text(statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        let verb: String
        switch manager.mode {
        case .recording: verb = "REC"
        case .playing: verb = "PLAY"
        case .trimming: verb = "TRIM"
        case .idle: verb = ""
        }
        return String(format: "%@ %.1fs", verb, manager.elapsed)
    }

    @ViewBuilder private var library: some View {
        if manager.sessions.isEmpty {
            Text("No recordings yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ForEach(manager.sessions) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name).font(.subheadline.weight(.medium))
                        Text(String(format: "%.1fs, %d frames", session.duration, session.frameCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        manager.play(session, loop: loop)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .disabled(manager.mode != .idle)

                    if let url = try? manager.exportTemporaryFile(for: session) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Button {
                        renameText = session.name
                        renameTarget = session
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .disabled(manager.mode != .idle)

                    Button {
                        trimTarget = session
                        manager.startTrimming(session)
                    } label: {
                        Image(systemName: "timeline.selection")
                    }
                    .disabled(manager.mode != .idle)

                    Button {
                        manager.dumpToConsole(session)
                    } label: {
                        Image(systemName: "doc.plaintext")
                    }

                    Button(role: .destructive) {
                        manager.delete(session)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(manager.mode != .idle)
                }
                .padding(.vertical, 2)
            }

            if manager.isPlaying {
                Button("Stop playback") { manager.stopPlayback() }
            }
        }
    }
}
#endif
