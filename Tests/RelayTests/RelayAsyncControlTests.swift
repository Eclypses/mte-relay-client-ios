import Foundation
import XCTest
@testable import Relay

final class RelayAsyncControlTests: XCTestCase {
    private func makeRequest(contentLength: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://relay.example.invalid/api")!)
        request.httpMethod = "POST"
        if let contentLength {
            request.setValue(contentLength, forHTTPHeaderField: "Content-Length")
        }
        return request
    }

    private func assertTimedOut(_ error: RelayClientError,
                                expectedSeconds: TimeInterval,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        guard case let .operationTimedOut(seconds) = error else {
            XCTFail("Expected operationTimedOut, got \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(seconds, expectedSeconds, file: file, line: line)
    }

    func testRunWithOptionalTimeoutThrowsTimedOutForSlowOperation() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        do {
            _ = try await relay.runWithOptionalTimeout(0.01) {
                try await Task.sleep(nanoseconds: 200_000_000)
                return 1
            }
            XCTFail("Expected timeout error")
        } catch let error as RelayClientError {
            guard case .operationTimedOut = error else {
                XCTFail("Expected operationTimedOut, got \(error)")
                return
            }
        }
    }

    func testRunWithOptionalTimeoutReturnsValueBeforeDeadline() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        let result = try await relay.runWithOptionalTimeout(1.0) {
            try await Task.sleep(nanoseconds: 10_000_000)
            return "ok"
        }

        XCTAssertEqual(result, "ok")
    }

    func testCancelStreamingOperationsWithUnknownHostIsNoop() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        try await relay.cancelStreamingOperations(relayServerUrlString: "https://relay.example.invalid")
    }

    func testCancelServerSentEventStreamWithUnknownHostIsNoop() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        try await relay.cancelServerSentEventStream(relayServerUrlString: "https://relay.example.invalid",
                                                    streamId: UUID())
    }

    func testRunWithOptionalTimeoutPropagatesCancellation() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        let task = Task {
            try await relay.runWithOptionalTimeout(5.0) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            if error is CancellationError {
                return
            }
            if let relayError = error as? RelayClientError,
               case .operationCancelled = relayError {
                return
            }
            XCTFail("Expected cancellation-related error, got \(error)")
        }
    }

    // MARK: - uploadFileStream (current streaming upload API)

    /// `uploadFileStream` requires a paired relay host; a NoopHTTPClient that
    /// returns empty data cannot complete the pairing handshake, so the call
    /// must propagate a RelayClientError (not crash or silently succeed).
    func testUploadFileStreamThrowsRelayClientErrorWhenPairingFails() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())
        let request = makeRequest(contentLength: "1024")

        do {
            _ = try await relay.uploadFileStream(request: request)
            XCTFail("Expected error when relay server cannot complete pairing")
        } catch let error as RelayClientError {
            XCTAssertNotNil(error.errorDescription,
                            "Propagated error should have a non-nil description")
        }
    }

    // MARK: - runWithOptionalTimeout edge cases

    func testRunWithOptionalTimeoutNilRunsWithNoDeadline() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())
        let result = try await relay.runWithOptionalTimeout(nil) { return 99 }
        XCTAssertEqual(result, 99)
    }

    func testRunWithOptionalTimeoutZeroThrowsOperationTimedOut() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())
        do {
            _ = try await relay.runWithOptionalTimeout(0.0) { return 0 }
            XCTFail("Expected operationTimedOut for timeout == 0")
        } catch let error as RelayClientError {
            assertTimedOut(error, expectedSeconds: 0.0)
        }
    }

    func testRunWithOptionalTimeoutNegativeThrowsOperationTimedOut() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())
        do {
            _ = try await relay.runWithOptionalTimeout(-3.0) { return 0 }
            XCTFail("Expected operationTimedOut for negative timeout")
        } catch let error as RelayClientError {
            assertTimedOut(error, expectedSeconds: -3.0)
        }
    }

    // MARK: - validateTimeout positive-value pass-through

    func testDownloadFilePositiveTimeoutDoesNotThrowTimedOutBeforeHostResolution() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())
        let request = makeRequest(contentLength: "1")
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("relay-dl-positive-timeout-test.bin")
        do {
            _ = try await relay.downloadFile(with: request, to: dst, timeout: 60.0)
            XCTFail("Expected a non-timeout error from pairing failure")
        } catch let error as RelayClientError {
            if case .operationTimedOut = error {
                XCTFail("Positive timeout should not cause immediate .operationTimedOut")
            }
            // Any other RelayClientError is acceptable (pairing failed as expected)
        }
    }

    func testDownloadFileThrowsTimedOutForNonPositiveTimeoutBeforeHostResolution() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())
        let request = makeRequest(contentLength: "1")
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent("relay-download-timeout-test.bin")

        do {
            _ = try await relay.downloadFile(with: request,
                                             to: destinationURL,
                                             timeout: 0)
            XCTFail("Expected operation timed out error")
        } catch let error as RelayClientError {
            assertTimedOut(error, expectedSeconds: 0)
        }
    }
}
