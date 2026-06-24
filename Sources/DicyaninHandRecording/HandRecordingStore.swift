import Foundation

/// Persists ``HandRecordingSession`` values to disk as JSON and lists them back.
///
/// Sessions live as one `.json` file per session under a directory in
/// Application Support, so they survive app launches and can be shipped or
/// shared. The store is intentionally simple and synchronous: recordings are
/// small (a few hundred KB at most) and saved on stop, not per frame.
public struct HandRecordingStore: Sendable {
    /// Directory the sessions are read from and written to.
    public let directory: URL

    private let encoder: JSONEncoder = {
        // Default (deferredToDate) date handling keeps full precision so a saved
        // session round trips exactly equal to the captured one.
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    private let decoder = JSONDecoder()

    /// Which sandbox directory a default store keeps recordings in.
    public enum Location: Sendable {
        /// `Application Support` (default). Survives launches, hidden from users.
        case applicationSupport
        /// `Documents`. Choose this so recordings appear in the Files app and
        /// can be pulled off the device. Requires the host app's Info.plist to
        /// set `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`
        /// to `YES`.
        case documents
    }

    /// Creates a store rooted at `directory`, defaulting to
    /// `Application Support/DicyaninHandRecording`.
    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("DicyaninHandRecording", isDirectory: true)
        }
    }

    /// Creates a store in a well-known sandbox ``Location``. Use `.documents`
    /// to make recordings reachable from the Files app for easy off-device
    /// export.
    public init(location: Location) {
        let dir: FileManager.SearchPathDirectory
        switch location {
        case .applicationSupport: dir = .applicationSupportDirectory
        case .documents: dir = .documentDirectory
        }
        let base = FileManager.default.urls(for: dir, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.directory = base.appendingPathComponent("DicyaninHandRecording", isDirectory: true)
    }

    /// The on-disk URL a session is stored at. Hand this to a `ShareLink` or a
    /// document picker to export the raw file.
    public func fileURL(for id: UUID) -> URL { url(for: id) }

    /// Writes a session to a temporary `.json` file named after the session and
    /// returns its URL, ready to share or hand to a document exporter. Safe to
    /// call repeatedly; the temp file is overwritten.
    public func exportTemporaryFile(for session: HandRecordingSession) throws -> URL {
        let safe = session.name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "-")
        let name = safe.isEmpty ? session.id.uuidString : "\(safe)-\(session.id.uuidString.prefix(8))"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).json", isDirectory: false)
        try encoder.encode(session).write(to: url, options: .atomic)
        return url
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    /// Writes a session to disk, overwriting any existing file with the same id.
    public func save(_ session: HandRecordingSession) throws {
        try ensureDirectory()
        let data = try encoder.encode(session)
        try data.write(to: url(for: session.id), options: .atomic)
    }

    /// Loads a single session by id.
    public func load(id: UUID) throws -> HandRecordingSession {
        let data = try Data(contentsOf: url(for: id))
        return try decoder.decode(HandRecordingSession.self, from: data)
    }

    /// Loads every saved session, most recent first. Unreadable files are
    /// skipped rather than aborting the whole list.
    public func loadAll() -> [HandRecordingSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(HandRecordingSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Deletes a saved session. Missing files are ignored.
    public func delete(id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Decodes a session from raw JSON data (for example one shipped inside an
    /// app bundle as a resource).
    public func decode(from data: Data) throws -> HandRecordingSession {
        try decoder.decode(HandRecordingSession.self, from: data)
    }

    /// Encodes a session to raw JSON data for export or bundling.
    public func encode(_ session: HandRecordingSession) throws -> Data {
        try encoder.encode(session)
    }

    /// Encodes a session to pretty-printed JSON data for human-readable export.
    public func encodePretty(_ session: HandRecordingSession) throws -> Data {
        try prettyEncoder.encode(session)
    }
}
