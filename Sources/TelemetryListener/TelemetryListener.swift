// The Swift Programming Language
// https://docs.swift.org/swift-book

import Network

class UDPListener {
    private var listener: NWListener?

    init() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        do {
            listener = try NWListener(using: params, on: 33740)
        } catch {
            print("Failed to create listener: \(error)")
        }
    }

    func start() {
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Listening on port 33740")
            case .failed(let error):
                print("Listener failed with error: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] newConnection in
            self?.handleConnection(newConnection)
        }

        listener?.start(queue: .main)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Ready to receive data from \(connection.endpoint)")
                self.receive(on: connection)
            case .failed(let error):
                print("Connection failed: \(error)")
            case .cancelled:
                print("Connection cancelled")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            if let data = data, !data.isEmpty {
                let remoteEndpoint = connection.endpoint
                // Check if the packet comes from the expected source
                if case let NWEndpoint.hostPort(host: .ipv4(address), port: sourcePort) = remoteEndpoint,
                   address == IPv4Address("192.168.2.120"),
                   sourcePort == 57083 {
                    let message = String(decoding: data, as: UTF8.self)
                    print("Received message from \(address):\(sourcePort) - \(message)")
                }
                // Continue receiving
                self?.receive(on: connection)
            } else if let error = error {
                print("Error receiving message: \(error)")
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}