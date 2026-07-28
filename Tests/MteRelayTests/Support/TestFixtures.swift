import Foundation
@testable import MteRelay

enum TestFixtures {
    static let endpoint = "https://relay.example.com"
    static let verificationRoute = "/api/mte-relay"
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

    /// A generic error that is neither `RelayClientError` nor `MteRelayError`, so it exercises
    /// `RelayClientError.from(_:)`'s `.underlying` fallback. This was previously a bare `String`,
    /// which relied on a `String: Error` conformance the V5 lib no longer has.
    struct SyntheticError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // Legacy MteRelayError variants (bridged via RelayClientError.from(_:))
    static let fixtureErrors: [Error] = [
        MteRelayError.networkError,
        MteRelayError.mteDecodeError,
        SyntheticError(message: "synthetic failure")
    ]

    // current RelayClientError variants covering all associated-value cases
    static let relayClientErrors: [RelayClientError] = [
        .licenseCheckFailed,
        .invalidServerURL,
        .invalidRequestURL,
        .invalidURLComponents,
        .hostResolutionFailed,
        .requestPreparationFailed,
        .encodingFailed,
        .decodingFailed,
        .networkFailure,
        .invalidRelayResponse,
        .fileWriteFailed("/tmp/relay-test"),
        .operationCancelled,
        .operationTimedOut(10.0),
        .pairingFailed("fixture-reason"),
        .statePersistenceFailed("fixture-reason"),
        .logReadFailed,
        .underlying("fixture-raw-error"),
    ]
}
