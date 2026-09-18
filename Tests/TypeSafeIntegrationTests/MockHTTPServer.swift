import Foundation
import Network

actor MockHTTPServer {
    struct Request: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    enum Reply: Sendable {
        case http(Int, headers: [String: String] = [:], body: Data, bodyDelay: UInt64 = 0)
        case truncatedBody
        case stall
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "TypeSafeTests.HTTPServer")
    private let replies: [Reply]
    private var connections: [NWConnection] = []
    private var tasks: [Task<Void, Never>] = []
    private var recorded: [Request] = []
    private var startup: CheckedContinuation<URL, any Error>?
    private var stopped = false

    init(replies: [Reply]) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.replies = replies
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            startup = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { await self?.stateChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }
            listener.start(queue: queue)
        }
    }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener.port,
               let url = URL(string: "http://127.0.0.1:\(port.rawValue)") {
                startup?.resume(returning: url)
                startup = nil
            }
        case .failed(let error):
            startup?.resume(throwing: error)
            startup = nil
        default: break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else { connection.cancel(); return }
        connections.append(connection)
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task {
                await self?.received(connection, buffer: buffer, data: data, complete: complete, failed: error != nil)
            }
        }
    }

    private func received(_ connection: NWConnection, buffer: Data, data: Data?, complete: Bool, failed: Bool) {
        guard !stopped else { return }
        var buffer = buffer
        if let data { buffer.append(data) }
        guard buffer.count < 1_048_576 else { connection.cancel(); return }
        if let request = parse(buffer) {
            let index = recorded.count
            recorded.append(request)
            let reply = index < replies.count ? replies[index] : .http(500, body: Data("Unexpected request".utf8))
            tasks.append(Task { await self.respond(connection, reply: reply) })
        } else if complete || failed {
            connection.cancel()
        } else {
            receive(connection, buffer: buffer)
        }
    }

    private func parse(_ data: Data) -> Request? {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
              let text = String(data: data[..<boundary.lowerBound], encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2 {
                headers[String(pair[0]).lowercased()] = pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, data.count - boundary.upperBound >= length else { return nil }
        return Request(method: String(first[0]), path: String(first[1]), headers: headers,
                       body: Data(data[boundary.upperBound..<(boundary.upperBound + length)]))
    }

    private func respond(_ connection: NWConnection, reply: Reply) async {
        switch reply {
        case .truncatedBody:
            let data = Data("HTTP/1.1 200 OK\r\nContent-Length: 1000\r\nConnection: close\r\n\r\n{\"incomplete\":".utf8)
            try? await send(data, connection: connection)
            connection.cancel()
        case .stall: break
        case .http(let status, let headers, let body, let bodyDelay):
            var head = "HTTP/1.1 \(status) Mock\r\nContent-Length: \(body.count)\r\nConnection: close\r\nContent-Type: application/json\r\n"
            for (name, value) in headers { head += "\(name): \(value)\r\n" }
            head += "\r\n"
            do {
                try await send(Data(head.utf8), connection: connection)
                if bodyDelay > 0 { try await Task.sleep(nanoseconds: bodyDelay) }
                try Task.checkCancellation()
                try await send(body, connection: connection)
            } catch {}
            connection.cancel()
        }
    }

    private func send(_ data: Data, connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    func requests() -> [Request] { recorded }

    func waitForRequests(_ count: Int) async throws {
        for _ in 0..<300 {
            if recorded.count >= count { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw ServerError.requestNotReceived
    }

    func stop() async {
        stopped = true
        listener.cancel()
        startup?.resume(throwing: CancellationError())
        startup = nil
        for task in tasks { task.cancel() }
        for connection in connections { connection.cancel() }
        for task in tasks { await task.value }
        connections.removeAll()
        tasks.removeAll()
    }

    enum ServerError: Error { case requestNotReceived }
}

func withServer(
    _ replies: [MockHTTPServer.Reply],
    operation: (MockHTTPServer, URL) async throws -> Void
) async throws {
    let server = try MockHTTPServer(replies: replies)
    do {
        let url = try await server.start()
        try await operation(server, url)
        await server.stop()
    } catch {
        await server.stop()
        throw error
    }
}
