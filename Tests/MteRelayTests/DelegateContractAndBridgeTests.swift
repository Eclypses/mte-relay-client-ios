import XCTest
@testable import MteRelay

final class DelegateContractAndBridgeTests: XCTestCase {
    private func makeHTTPResponse(urlString: String = TestFixtures.endpoint,
                                  statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: urlString)!,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    func testRelayResponseContractWithArgumentCaptureAndHistory() {
        let responseDelegate = RecordingRelayResponseDelegate()
        let bridge = RelayCallbackBridge()
        bridge.responseDelegate = responseDelegate

        bridge.emitResponse(success: true, response: "paired", error: nil)
        bridge.emitResponse(success: false, response: "", error: "network")

        XCTAssertEqual(responseDelegate.callCount, 2)
        XCTAssertEqual(String(data: responseDelegate.capturedArguments.first?.data ?? Data(), encoding: .utf8), "paired")
        XCTAssertEqual(responseDelegate.capturedArguments.last?.error?.localizedDescription, "network")
        XCTAssertEqual(bridge.callHistory, ["emitResponse", "emitResponse"])
    }

    func testRelayStreamCompletionContract() {
        let completionDelegate = RecordingRelayStreamCompletionDelegate()
        let bridge = RelayCallbackBridge()
        bridge.streamCompletionDelegate = completionDelegate

        bridge.emitStreamCompletion(from: TestFixtures.endpoint, bytesCompleted: 20, totalBytes: 100)

        XCTAssertEqual(completionDelegate.callCount, 1)
        XCTAssertEqual(completionDelegate.captured.first?.from, TestFixtures.endpoint)
        XCTAssertEqual(completionDelegate.captured.first?.bytesCompleted, 20)
        XCTAssertEqual(completionDelegate.captured.first?.totalBytes, 100)
    }

    func testBurstCallbackSimulationWithFailureToggle() {
        let responseDelegate = RecordingRelayResponseDelegate()
        let bridge = RelayCallbackBridge()
        bridge.responseDelegate = responseDelegate
        bridge.shouldEmitErrorEvent = true

        bridge.simulateBurst(count: 50)

        XCTAssertEqual(responseDelegate.callCount, 50)
        XCTAssertEqual(responseDelegate.capturedArguments.filter { $0.error != nil }.count, 25)
        XCTAssertEqual(responseDelegate.capturedArguments.filter { $0.error == nil }.count, 25)
    }

    func testFakeResetAndDisposeLifecycleHelpers() {
        let responseDelegate = RecordingRelayResponseDelegate()
        responseDelegate.relayStreamResponse(from: TestFixtures.endpoint,
                             data: Data("ok".utf8),
                             response: nil,
                             error: nil)
        XCTAssertEqual(responseDelegate.callCount, 1)

        responseDelegate.reset()
        XCTAssertEqual(responseDelegate.callCount, 0)

        responseDelegate.relayStreamResponse(from: TestFixtures.endpoint,
                             data: Data("ok".utf8),
                             response: nil,
                             error: nil)
        responseDelegate.dispose()
        XCTAssertEqual(responseDelegate.callCount, 0)
    }

    func testDeterministicAsyncBurst() async {
        let responseDelegate = RecordingRelayResponseDelegate()
        let bridge = RelayCallbackBridge()
        bridge.responseDelegate = responseDelegate

        for index in 0..<100 {
            await Task.yield()
            bridge.emitResponse(success: true, response: "ok-\(index)", error: nil)
        }

        XCTAssertEqual(responseDelegate.callCount, 100)
        XCTAssertEqual(bridge.callHistory.count, 100)
    }

    func testRelayServerSentEventDelegateCapturesStreamScopedCallbacks() {
        let delegate = RecordingRelayServerSentEventDelegate()
        let bridge = RelayServerSentEventCallbackBridge()
        bridge.delegate = delegate

        let streamA = UUID()
        let streamB = UUID()
        let response = makeHTTPResponse()

        bridge.emitResponse(from: TestFixtures.endpoint, streamId: streamA, response: response)
        bridge.emitData(from: TestFixtures.endpoint, streamId: streamA, text: "first")
        bridge.emitData(from: TestFixtures.endpoint, streamId: streamB, text: "second")
        bridge.emitCompletion(from: TestFixtures.endpoint, streamId: streamA, response: response)

        XCTAssertEqual(delegate.responseCallCount, 1)
        XCTAssertEqual(delegate.dataCallCount, 2)
        XCTAssertEqual(delegate.completionCallCount, 1)
        XCTAssertEqual(delegate.responses.first?.streamId, streamA)
        XCTAssertEqual(String(data: delegate.dataEvents.first?.data ?? Data(), encoding: .utf8), "first")
        XCTAssertEqual(delegate.dataEvents.last?.streamId, streamB)
        XCTAssertEqual(delegate.completions.first?.streamId, streamA)
        XCTAssertEqual(delegate.callHistory, [
            "relayServerSentEventDidReceiveResponse",
            "relayServerSentEventDidReceiveData",
            "relayServerSentEventDidReceiveData",
            "relayServerSentEventDidComplete"
        ])
    }

    func testRelayServerSentEventOpenResultRetainsStreamIdentityAndResponse() {
        let streamId = UUID()
        let response = makeHTTPResponse(statusCode: 202)

        let result = RelayServerSentEventOpenResult(streamId: streamId, response: response)

        XCTAssertEqual(result.streamId, streamId)
        XCTAssertEqual((result.response as? HTTPURLResponse)?.statusCode, 202)
    }

    func testRelayForwardsInterleavedServerSentEventCallbacksByStreamId() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())
        let delegate = RecordingRelayServerSentEventDelegate()
        relay.relayServerSentEventDelegate = delegate

        let streamA = UUID()
        let streamB = UUID()
        let response = makeHTTPResponse()

        relay.relayServerSentEventDidReceiveResponse(from: TestFixtures.endpoint,
                                                     streamId: streamA,
                                                     response: response)
        relay.relayServerSentEventDidReceiveData(from: TestFixtures.endpoint,
                                                 streamId: streamA,
                                                 data: Data("A1".utf8))
        relay.relayServerSentEventDidReceiveData(from: TestFixtures.endpoint,
                                                 streamId: streamB,
                                                 data: Data("B1".utf8))
        relay.relayServerSentEventDidComplete(from: TestFixtures.endpoint,
                                              streamId: streamB,
                                              response: response)

        XCTAssertEqual(delegate.responses.map(\.streamId), [streamA])
        XCTAssertEqual(delegate.dataEvents.map(\.streamId), [streamA, streamB])
        XCTAssertEqual(delegate.completions.map(\.streamId), [streamB])
        XCTAssertEqual(String(data: delegate.dataEvents[0].data, encoding: .utf8), "A1")
        XCTAssertEqual(String(data: delegate.dataEvents[1].data, encoding: .utf8), "B1")
    }
}
