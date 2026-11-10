import CaptureCore
import Foundation
import Network
import NetworkExtension

/// Small helpers around NWConnection for the connections to Hotline.
enum SocketError: Error {
    case closed
}

extension NWConnection {
    /// Waits until the connection is ready, or throws if it fails.
    func establish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            self.stateUpdateHandler = { state in
                guard !finished else { return }
                switch state {
                case .ready:
                    finished = true
                    continuation.resume()
                case .failed(let error):
                    finished = true
                    continuation.resume(throwing: error)
                case .waiting(let error):
                    // Hotline is not listening (connection refused). Network keeps retrying a
                    // waiting connection and would never report a failure, so give up now.
                    finished = true
                    self.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    finished = true
                    continuation.resume(throwing: SocketError.closed)
                default:
                    break
                }
            }
            self.start(queue: .global())
        }
    }

    func sendBytes(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Returns the next bytes, or nil when the other side has closed.
    func receiveBytes(maximum: Int = 16 * 1024) async throws -> Data? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            self.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    /// Reads Hotline's answer to the CONNECT and returns the bytes that came
    /// after it, which belong to the app. Throws when Hotline refuses or
    /// closes first.
    func readConnectReply() async throws -> Data {
        var reply = ConnectReply()
        while true {
            guard let bytes = try await receiveBytes() else { throw SocketError.closed }
            if let rest = try reply.append(bytes) {
                return rest
            }
        }
    }
}

extension NEAppProxyTCPFlow {
    func writeBytes(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.write(data) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
