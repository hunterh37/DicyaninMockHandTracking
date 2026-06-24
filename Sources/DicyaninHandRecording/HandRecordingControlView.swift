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
                .disabled(manager.isPlaying)
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
        let verb = manager.isRecording ? "REC" : "PLAY"
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
