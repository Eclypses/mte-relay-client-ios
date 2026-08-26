import XCTest
@testable import Relay

final class RelayClientErrorTests: XCTestCase {

    // MARK: - from(_:) legacy conversion

    func testFromUpdateRequestErrorMapsToRequestPreparationFailed() {
        let converted = RelayClientError.from(RelayError.updateRequestError)
        guard case .requestPreparationFailed = converted else {
            XCTFail("Expected .requestPreparationFailed, got \(converted)")
            return
        }
    }

    func testFromMteEncodeErrorMapsToEncodingFailed() {
        let converted = RelayClientError.from(RelayError.mteEncodeError)
        guard case .encodingFailed = converted else {
            XCTFail("Expected .encodingFailed, got \(converted)")
            return
        }
    }

    func testFromMteDecodeErrorMapsToDecodingFailed() {
        let converted = RelayClientError.from(RelayError.mteDecodeError)
        guard case .decodingFailed = converted else {
            XCTFail("Expected .decodingFailed, got \(converted)")
            return
        }
    }

    func testFromNetworkErrorMapsToNetworkFailure() {
        let converted = RelayClientError.from(RelayError.networkError)
        guard case .networkFailure = converted else {
            XCTFail("Expected .networkFailure, got \(converted)")
            return
        }
    }

    func testFromStoreStateErrorMapsToStatePersistenceFailed() {
        let converted = RelayClientError.from(RelayError.storeStateError)
        guard case .statePersistenceFailed = converted else {
            XCTFail("Expected .statePersistenceFailed, got \(converted)")
            return
        }
    }

    func testFromRelayClientErrorIsPassThrough() {
        let original = RelayClientError.encodingFailed
        let converted = RelayClientError.from(original)
        guard case .encodingFailed = converted else {
            XCTFail("Expected .encodingFailed pass-through, got \(converted)")
            return
        }
    }

    func testFromArbitraryErrorReturnsUnderlying() {
        struct SyntheticError: Error, LocalizedError {
            var errorDescription: String? { "synthetic-detail" }
        }
        let converted = RelayClientError.from(SyntheticError())
        guard case .underlying = converted else {
            XCTFail("Expected .underlying for unknown error type, got \(converted)")
            return
        }
    }

    func testFromRelayErrorNoneReturnsUnderlying() {
        // `.none` falls through to the default branch, yielding `.underlying`
        let converted = RelayClientError.from(RelayError.none)
        guard case .underlying = converted else {
            XCTFail("Expected .underlying for RelayError.none, got \(converted)")
            return
        }
    }

    // MARK: - errorDescription coverage

    func testAllCasesHaveNonNilErrorDescription() {
        let cases: [RelayClientError] = [
            .licenseCheckFailed,
            .invalidServerURL,
            .invalidRequestURL,
            .invalidURLComponents,
            .hostResolutionFailed,
            .requestPreparationFailed,
            .pairCapacityExhausted(25),
            .encodingFailed,
            .decodingFailed,
            .networkFailure,
            .invalidRelayResponse,
            .fileWriteFailed("/tmp/test"),
            .operationCancelled,
            .operationTimedOut(5.0),
            .pairingFailed("test-reason"),
            .statePersistenceFailed("test-reason"),
            .pairReplaced(562),
            .pairReplaceFailed(563),
            .fullRepairSuccess(564),
            .fullRepairCatastrophic(564),
            .relayStatus(566, "bad request"),
            .logReadFailed,
            .underlying("raw message"),
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription,
                            "Expected non-nil errorDescription for \(error)")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                           "Expected non-empty errorDescription for \(error)")
        }
    }

    func testAssociatedValuesCapturedInErrorDescription() {
        XCTAssertTrue(
            RelayClientError.pairCapacityExhausted(25).errorDescription?
                .contains("25") ?? false,
            "pairCapacityExhausted description should contain the max pair count"
        )
        XCTAssertTrue(
            RelayClientError.fileWriteFailed("/tmp/relay-download").errorDescription?
                .contains("/tmp/relay-download") ?? false,
            "fileWriteFailed description should contain the path"
        )
        XCTAssertTrue(
            RelayClientError.operationTimedOut(3.5).errorDescription?
                .contains("3.5") ?? false,
            "operationTimedOut description should contain the duration"
        )
        XCTAssertTrue(
            RelayClientError.pairingFailed("bad-nonce").errorDescription?
                .contains("bad-nonce") ?? false,
            "pairingFailed description should contain the reason"
        )
        XCTAssertTrue(
            RelayClientError.statePersistenceFailed("disk full").errorDescription?
                .contains("disk full") ?? false,
            "statePersistenceFailed description should contain the reason"
        )
        XCTAssertTrue(
            RelayClientError.pairReplaced(562).errorDescription?
                .contains("562") ?? false,
            "pairReplaced description should contain the status code"
        )
        XCTAssertTrue(
            RelayClientError.fullRepairSuccess(564).errorDescription?
                .contains("564") ?? false,
            "fullRepairSuccess description should contain the status code"
        )
        XCTAssertTrue(
            RelayClientError.relayStatus(566, "bad request").errorDescription?
                .contains("bad request") ?? false,
            "relayStatus description should contain the server message"
        )
        XCTAssertTrue(
            RelayClientError.underlying("raw detail").errorDescription?
                .contains("raw detail") ?? false,
            "underlying description should echo the raw message"
        )
    }

    // MARK: - Fixture errors interop

    func testFixtureErrorsCanBeConvertedToRelayClientError() {
        for error in TestFixtures.fixtureErrors {
            // Should not crash for any error type in the fixture set
            let converted = RelayClientError.from(error)
            XCTAssertNotNil(converted.errorDescription)
        }
    }
}
