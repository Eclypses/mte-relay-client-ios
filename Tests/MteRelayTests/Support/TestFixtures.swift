import Foundation
@testable import MteRelay

enum TestFixtures {
    static let endpoint = "https://relay.example.com"
    static let healthRoute = "/api/mte-relay"
    static let pairingRoute = "/api/mte-pair"

    static let headerMetadata: [String: String] = [
        "Authorization": "Bearer test-token",
        "Content-Type": "application/json",
        "X-Trace-Id": "trace-1234"
    ]

    static let relayHeaders = RelayHeaders(
        clientId: "client-123",
        pairId: "pair-456",
        encryptedDecryptedHeaders: "enc"
    )

    static let emptyTextPayload = ""
    static let smallTextPayload = "hello relay"
    static let largeTextPayload = String(repeating: "relay-payload-", count: 2048)

    static let emptyBinaryPayload = Data()
    static let smallBinaryPayload = Data([0, 1, 2, 3, 4])
    static let largeBinaryPayload = Data(repeating: 0xAB, count: 256 * 1024)

    static let fixtureErrors: [Error] = [
        MteRelayError.networkError,
        MteRelayError.mteDecodeError,
        "synthetic failure"
    ]
}
