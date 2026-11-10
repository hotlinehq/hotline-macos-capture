import Foundation
import Network
import NetworkExtension

/// Copies bytes both ways between an app's connection and the connection to Hotline.
/// It never looks inside the bytes.
enum Copier {
    static func run(flow: NEAppProxyTCPFlow, connection: NWConnection) {
        appToHotline(flow: flow, connection: connection)
        hotlineToApp(flow: flow, connection: connection)
    }

    private static func appToHotline(flow: NEAppProxyTCPFlow, connection: NWConnection) {
        flow.readData { data, error in
            if error == nil, let data = data, !data.isEmpty {
                connection.send(content: data, completion: .contentProcessed { sendError in
                    if sendError == nil {
                        appToHotline(flow: flow, connection: connection)
                    } else {
                        close(flow: flow, connection: connection, error: sendError)
                    }
                })
            } else {
                // The app finished sending. Tell Hotline, then close.
                connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                    close(flow: flow, connection: connection, error: error)
                })
            }
        }
    }

    private static func hotlineToApp(flow: NEAppProxyTCPFlow, connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                flow.write(data) { writeError in
                    if writeError == nil {
                        hotlineToApp(flow: flow, connection: connection)
                    } else {
                        close(flow: flow, connection: connection, error: writeError)
                    }
                }
            } else if isComplete || error != nil {
                close(flow: flow, connection: connection, error: error)
            } else {
                hotlineToApp(flow: flow, connection: connection)
            }
        }
    }

    private static func close(flow: NEAppProxyTCPFlow, connection: NWConnection, error: Error?) {
        connection.cancel()
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
    }
}
