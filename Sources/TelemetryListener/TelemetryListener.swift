// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Network

public class TelemetryListener {
    public var listening: Bool = true
    public var messageReceived: Data?

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue.global(qos: .userInitiated)

    private let receivePort: NWEndpoint.Port = 33740
    private let sendPort: NWEndpoint.Port = 33739
    private let endpointHost: NWEndpoint.Host = NWEndpoint.Host("192.168.2.120")

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
            case .cancelled, .failed:
                print("Listener failed with error")
                self?.listening = false
            default:
                print("Listener state changed: \(state)")
            }
        }

        self.listener?.newConnectionHandler = { newConnection in // weak self
            print("Listener receiving new connection")
            self.createConnection(connection: newConnection)
        }

        self.listener?.start(queue: queue)
    }

    private func sendHeartbeat() {
        let heartbeatData = "A".data(using: .utf8)!
        let connection = NWConnection(host: endpointHost, port: sendPort, using: .udp)

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

        // connection receive logic goes here - What's the difference between receive and receiveMessage?
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, context, isComplete, error in
            if let data = data, !data.isEmpty {
                print("Received data: \(data)")
            }
            if let error = error {
                print("Failed to receive data: \(error)")
            }
        }

        self.connection?.stateUpdateHandler = { (newState) in
            switch (newState) {
            case .ready:
                print("Listener ready to receive message - \(connection)")
                self.receive()
            case .cancelled, .failed:
                print("Listener failed to receive message - \(connection)")
                self.listener?.cancel()
                self.listening = false
            default:
                print("Listener waiting to receive message - \(connection)")
            }
        }
        self.connection?.start(queue: .global())
    }

    private func receive() {
        print("receive called....")
        self.connection?.receiveMessage { data, context, isComplete, error in
            if let unwrappedError = error {
                print("Error: NWError received in \(#function) - \(unwrappedError)")
                return
            }
            guard isComplete, let data = data else {
                print("Error: Received nil Data with context - \(String(describing: context))")
                return
            }
            print("message received is updated")
            self.messageReceived = data
            if self.listening {
                self.receive()
            }
        }
    }

    public func stop() {
        print("listener stop called....")
        self.listening = false
        listener?.cancel()
        listener = nil
    }
}
