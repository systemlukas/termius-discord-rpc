import XCTest
@testable import TermiusRPC

final class DiscordIPCTests: XCTestCase {
    func testEncodeFrame() throws {
        let payload = #"{"v":1,"client_id":"123"}"#
        let data = payload.data(using: .utf8)!
        let frame = DiscordFrame.encode(opcode: .handshake, payload: data)

        XCTAssertEqual(frame.count, 8 + data.count)

        let opcode = frame.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(opcode, 0)

        let length = frame.withUnsafeBytes {
            $0.load(fromByteOffset: 4, as: UInt32.self).littleEndian
        }
        XCTAssertEqual(length, UInt32(data.count))

        let extractedPayload = frame.suffix(from: 8)
        XCTAssertEqual(String(data: extractedPayload, encoding: .utf8), payload)
    }

    func testDecodeFrame() throws {
        let payload = #"{"cmd":"DISPATCH","evt":"READY"}"#
        let payloadData = payload.data(using: .utf8)!
        let frame = DiscordFrame.encode(opcode: .frame, payload: payloadData)

        let (opcode, decoded) = try DiscordFrame.decode(frame)
        XCTAssertEqual(opcode, .frame)
        XCTAssertEqual(String(data: decoded, encoding: .utf8), payload)
    }

    func testPresencePayload() throws {
        let activity = DiscordActivity(
            state: "SSH to homelab",
            details: "Connected via Termius",
            timestamps: DiscordActivity.Timestamps(start: 1700000000),
            assets: DiscordActivity.Assets(
                largeImage: "termius",
                largeText: "Termius SSH Client",
                smallImage: "ssh_icon",
                smallText: "SSH"
            )
        )

        let payload = try DiscordPayload.setActivity(activity, pid: 1234)
        let json = try JSONSerialization.jsonObject(with: payload) as! [String: Any]

        XCTAssertEqual(json["cmd"] as? String, "SET_ACTIVITY")
        XCTAssertNotNil(json["nonce"] as? String)

        let args = json["args"] as! [String: Any]
        XCTAssertEqual(args["pid"] as? Int, 1234)

        let act = args["activity"] as! [String: Any]
        XCTAssertEqual(act["state"] as? String, "SSH to homelab")
        XCTAssertEqual(act["details"] as? String, "Connected via Termius")
    }

    func testClearPresencePayload() throws {
        let payload = try DiscordPayload.clearActivity(pid: 1234)
        let json = try JSONSerialization.jsonObject(with: payload) as! [String: Any]

        XCTAssertEqual(json["cmd"] as? String, "SET_ACTIVITY")
        let args = json["args"] as! [String: Any]
        XCTAssertEqual(args["pid"] as? Int, 1234)
        XCTAssertNil(args["activity"])
    }
}
