import Foundation

// MARK: - Types

enum DiscordOpcode: UInt32 {
    case handshake = 0
    case frame     = 1
    case close     = 2
    case ping      = 3
    case pong      = 4
}

struct DiscordActivity: Encodable {
    var state: String?
    var details: String?
    var timestamps: Timestamps?
    var assets: Assets?

    struct Timestamps: Encodable {
        var start: Int?
        var end: Int?
    }

    struct Assets: Encodable {
        var largeImage: String?
        var largeText: String?
        var smallImage: String?
        var smallText: String?

        enum CodingKeys: String, CodingKey {
            case largeImage = "large_image"
            case largeText  = "large_text"
            case smallImage = "small_image"
            case smallText  = "small_text"
        }
    }
}

// MARK: - Frame encoding/decoding

enum DiscordFrame {
    static func encode(opcode: DiscordOpcode, payload: Data) -> Data {
        var buffer = Data(capacity: 8 + payload.count)
        var op = opcode.rawValue.littleEndian
        var len = UInt32(payload.count).littleEndian
        buffer.append(Data(bytes: &op, count: 4))
        buffer.append(Data(bytes: &len, count: 4))
        buffer.append(payload)
        return buffer
    }

    static func decode(_ data: Data) throws -> (DiscordOpcode, Data) {
        guard data.count >= 8 else {
            throw DiscordIPCError.readFailed
        }
        let opValue = data.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let length = data.withUnsafeBytes {
            $0.load(fromByteOffset: 4, as: UInt32.self).littleEndian
        }
        guard let opcode = DiscordOpcode(rawValue: opValue) else {
            throw DiscordIPCError.invalidOpcode(opValue)
        }
        guard data.count >= 8 + Int(length) else {
            throw DiscordIPCError.readFailed
        }
        let payload = data.subdata(in: 8..<(8 + Int(length)))
        return (opcode, payload)
    }
}

// MARK: - Payload builders

enum DiscordPayload {
    static func handshake(clientID: String) throws -> Data {
        let obj: [String: Any] = ["v": 1, "client_id": clientID]
        return try JSONSerialization.data(withJSONObject: obj)
    }

    static func setActivity(_ activity: DiscordActivity, pid: Int32) throws -> Data {
        struct Command: Encodable {
            let cmd = "SET_ACTIVITY"
            let args: Args
            let nonce: String

            struct Args: Encodable {
                let pid: Int32
                let activity: DiscordActivity
            }
        }
        let command = Command(
            args: Command.Args(pid: pid, activity: activity),
            nonce: UUID().uuidString
        )
        return try JSONEncoder().encode(command)
    }

    static func clearActivity(pid: Int32) throws -> Data {
        let obj: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": pid],
            "nonce": UUID().uuidString
        ]
        return try JSONSerialization.data(withJSONObject: obj)
    }
}

// MARK: - Errors

enum DiscordIPCError: Error, CustomStringConvertible {
    case connectionFailed
    case notConnected
    case handshakeFailed
    case writeFailed
    case readFailed
    case invalidOpcode(UInt32)

    var description: String {
        switch self {
        case .connectionFailed: return "Could not connect to Discord IPC socket"
        case .notConnected: return "Not connected to Discord"
        case .handshakeFailed: return "Discord handshake failed"
        case .writeFailed: return "Failed to write to Discord socket"
        case .readFailed: return "Failed to read from Discord socket"
        case .invalidOpcode(let op): return "Invalid Discord opcode: \(op)"
        }
    }
}

// MARK: - IPC Client

final class DiscordIPCClient {
    private let clientID: String
    private var fd: Int32 = -1

    var isConnected: Bool { fd >= 0 }

    init(clientID: String) {
        self.clientID = clientID
    }

    func connect() throws {
        let tmpDir = NSTemporaryDirectory()

        for i in 0..<10 {
            let path = "\(tmpDir)discord-ipc-\(i)"
            let sock = socket(AF_UNIX, SOCK_STREAM, 0)
            guard sock >= 0 else { continue }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)

            let pathBytes = path.utf8CString
            guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
                Darwin.close(sock)
                continue
            }

            _ = withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                pathBytes.withUnsafeBufferPointer { buf in
                    memcpy(sunPath, buf.baseAddress!, buf.count)
                }
            }

            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.connect(sock, sockPtr, addrLen)
                }
            }

            if result == 0 {
                self.fd = sock
                try performHandshake()
                return
            }
            Darwin.close(sock)
        }

        throw DiscordIPCError.connectionFailed
    }

    private func performHandshake() throws {
        let payload = try DiscordPayload.handshake(clientID: clientID)
        try sendFrame(opcode: .handshake, payload: payload)

        let (op, _) = try readFrame()
        guard op == .frame else {
            disconnect()
            throw DiscordIPCError.handshakeFailed
        }
    }

    func setPresence(_ activity: DiscordActivity) throws {
        let payload = try DiscordPayload.setActivity(
            activity,
            pid: ProcessInfo.processInfo.processIdentifier
        )
        try sendFrame(opcode: .frame, payload: payload)
    }

    func clearPresence() throws {
        let payload = try DiscordPayload.clearActivity(
            pid: ProcessInfo.processInfo.processIdentifier
        )
        try sendFrame(opcode: .frame, payload: payload)
    }

    func disconnect() {
        guard fd >= 0 else { return }
        Darwin.close(fd)
        fd = -1
    }

    // MARK: - Frame I/O

    private func sendFrame(opcode: DiscordOpcode, payload: Data) throws {
        guard fd >= 0 else { throw DiscordIPCError.notConnected }

        let frame = DiscordFrame.encode(opcode: opcode, payload: payload)
        let written = frame.withUnsafeBytes { ptr in
            Darwin.write(fd, ptr.baseAddress!, ptr.count)
        }
        guard written == frame.count else {
            throw DiscordIPCError.writeFailed
        }
    }

    private func readFrame() throws -> (DiscordOpcode, Data) {
        guard fd >= 0 else { throw DiscordIPCError.notConnected }

        var header = Data(count: 8)
        let headerRead = header.withUnsafeMutableBytes { ptr in
            Darwin.read(fd, ptr.baseAddress!, 8)
        }
        guard headerRead == 8 else { throw DiscordIPCError.readFailed }

        let length = header.withUnsafeBytes {
            $0.load(fromByteOffset: 4, as: UInt32.self).littleEndian
        }

        var payload = Data(count: Int(length))
        let payloadRead = payload.withUnsafeMutableBytes { ptr in
            Darwin.read(fd, ptr.baseAddress!, Int(length))
        }
        guard payloadRead == Int(length) else { throw DiscordIPCError.readFailed }

        let opValue = header.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        guard let opcode = DiscordOpcode(rawValue: opValue) else {
            throw DiscordIPCError.invalidOpcode(opValue)
        }

        return (opcode, payload)
    }

    deinit { disconnect() }
}
