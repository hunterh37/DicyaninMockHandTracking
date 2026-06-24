import Foundation
import Network

/// Broadcasts `HandPosePacket`s to every connected consumer over TCP.
///
/// The webcam runner owns one of these. It listens on a fixed port (and
/// advertises a Bonjour service for LAN discovery), accepts any number of
/// clients — typically the one live visionOS app — and fans each packet out to
/// all of them. Packets are newline-framed JSON; a slow or dead client is
/// dropped without blocking the others.
///
/// Thread-safe: all connection bookkeeping happens on a private serial queue.
public final class HandPoseSender: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case setup
        case ready(port: UInt16)
        case failed(String)
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dicyanin.handpose.sender")
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let advertiseBonjour: Bool

    /// Called on the sender's queue whenever the listener state changes.
    public var onStateChange: ((State) -> Void)?
    /// Called on the sender's queue when the connected-client count changes.
    public var onClientCountChange: ((Int) -> Void)?

    public init(port: UInt16 = HandPoseWire.defaultPort,
                advertiseBonjour: Bool = true) throws {
        self.advertiseBonjour = advertiseBonjour
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "HandPoseSender", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "invalid port \(port)"])
        }
        listener = try NWListener(using: params, on: nwPort)
        if advertiseBonjour {
            listener.service = NWListener.Service(type: HandPoseWire.bonjourServiceType)
        }
    }

    public func start() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let port = self.listener.port?.rawValue ?? 0
                self.onStateChange?(.ready(port: port))
            case .failed(let error):
                self.onStateChange?(.failed(error.localizedDescription))
            case .setup, .waiting, .cancelled:
                break
            @unknown default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        onStateChange?(.setup)
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async {
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
            self.listener.cancel()
        }
    }

    /// Encode and fan a packet out to all connected clients.
    public func broadcast(_ packet: HandPosePacket) {
        guard let frame = try? HandPoseWire.frame(packet) else { return }
        queue.async {
            for connection in self.connections.values {
                connection.send(content: frame, completion: .contentProcessed { _ in })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled, .failed:
                self.queue.async {
                    if self.connections.removeValue(forKey: id) != nil {
                        self.onClientCountChange?(self.connections.count)
                    }
                }
            default:
                break
            }
        }
        queue.async {
            self.connections[id] = connection
            self.onClientCountChange?(self.connections.count)
        }
        connection.start(queue: queue)
    }
}
