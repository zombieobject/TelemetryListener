// The Swift Programming Language
// https://docs.swift.org/swift-book

import Network

public class TelemetryListener {
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue.global(qos: .userInitiated)

    private let receivePort: NWEndpoint.Port = 33740
    private let sendPort: NWEndpoint.Port = 33739

    public init() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.allowFastOpen = true

        do {
            self.listener = try NWListener(using: params, on: receivePort)
        } catch {
            print("Failed to create listener: \(error)")
        }
    }

    public func start() {
        self.listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Listening for UDP packets on port 33740")
                self?.sendHeartbeat()
            case .failed(let error):
                print("Listener failed with error: \(error)")
            default:
                print("Listener state changed: \(state)")
            }
        }

        self.listener?.newConnectionHandler = { newConnection in // weak self
            print("Listener receiving new connection")
            //self?.receiveData(on: newConnection)
            self.createConnection(connection: newConnection)
        }

        self.listener?.start(queue: queue)
    }

    private func sendHeartbeat() {
        let heartbeatData = "A".data(using: .utf8)!
        let host = NWEndpoint.Host("192.168.2.120")
        let connection = NWConnection(host: host, port: sendPort, using: .udp)
        
        connection.stateUpdateHandler = { state in
            if state == .ready {
                connection.send(content: heartbeatData, completion: .contentProcessed { error in
                    if let error = error {
                        print("Error sending heartbeat: \(error)")
                    } else {
                        print("Heartbeat sent successfully")
                    }
                    connection.cancel()
                })
            } else if case .failed(let error) = state {
                print("Heartbeat connection failed: \(error)")
                connection.cancel()
            }
        }
        
        connection.start(queue: queue)
    }

    private func createConnection(connection: NWConnection) {
        print("create connection called....")
        self.connection = connection
        // connection receive logic goes here

        // connection state update handler
        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                print("Listener ready to receive message - \(connection)")
                //self.receive()
            case .cancelled, .failed:
                print("Listener failed to receive message - \(connection)")
                // Cancel the listener, something went wrong
                self.listener?.cancel()
                // Announce we are no longer able to listen
                //self.listening = false
            default:
                print("Listener waiting to receive message - \(connection)")
            }
        }
        self.connection?.start(queue: .global())
    }

//    private func receiveData(on connection: NWConnection) {
//        connection.receiveMessage { [weak self] content, context, isComplete, error in
//            if let data = content, !data.isEmpty {
//                let message = String(decoding: data, as: UTF8.self)
//                print("Received UDP packet: \(message)")
//                
//                // Check source address and port if needed
//                if let endpoint = connection.currentPath?.remoteEndpoint,
//                   case let NWEndpoint.hostPort(host, port) = endpoint,
//                   host.debugDescription == "192.168.2.120",
//                   port == 57083 {
//                    print("Packet is from the expected source")
//                }
//            }
//            if let error = error {
//                print("Error receiving UDP packet: \(error)")
//            }
//            // Continue receiving
//            self?.receiveData(on: connection)
//        }
//        
//        connection.start(queue: queue)
//    }

    public func stop() {
        print("listener stop called....")
        listener?.cancel()
        listener = nil
    }
}
