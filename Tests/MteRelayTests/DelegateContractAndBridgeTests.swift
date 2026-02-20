import XCTest
@testable import MteRelay

final class DelegateContractAndBridgeTests: XCTestCase {
    func testRelayResponseContractWithArgumentCaptureAndHistory() {
        let responseDelegate = RecordingRelayResponseDelegate()
        let bridge = RelayCallbackBridge()
        bridge.responseDelegate = responseDelegate

        bridge.emitResponse(success: true, response: "paired", error: nil)
        bridge.emitResponse(success: false, response: "", error: "network")

        XCTAssertEqual(responseDelegate.callCount, 2)
        XCTAssertEqual(responseDelegate.capturedArguments.first?.response, "paired")
        XCTAssertEqual(responseDelegate.capturedArguments.last?.error, "network")
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
        XCTAssertEqual(responseDelegate.capturedArguments.filter { $0.success }.count, 25)
    }

    func testFakeResetAndDisposeLifecycleHelpers() {
        let responseDelegate = RecordingRelayResponseDelegate()
        responseDelegate.relayResponse(success: true, responseStr: "ok", errorMessage: nil)
        XCTAssertEqual(responseDelegate.callCount, 1)

        responseDelegate.reset()
        XCTAssertEqual(responseDelegate.callCount, 0)

        responseDelegate.relayResponse(success: true, responseStr: "ok", errorMessage: nil)
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
}
