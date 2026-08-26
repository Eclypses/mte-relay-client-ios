import XCTest
@testable import Relay

/// Collects actions emitted from the handler's `@Sendable async` closures.
/// The closures cannot mutate a captured local `var` under Swift concurrency
/// checking, so recording goes through an actor (which is `Sendable`).
private actor ActionRecorder {
    private(set) var actions: [StreamingRelayStatusAction] = []
    func append(_ action: StreamingRelayStatusAction) { actions.append(action) }
    func snapshot() -> [StreamingRelayStatusAction] { actions }
}

final class StreamingRelayStatusHandlerTests: XCTestCase {
    func testPerPairReplacementReturnsReplacementErrorAndSkipsOtherActions() async {
        let handler = StreamingRelayStatusHandler()
        let recorder = ActionRecorder()

        let result = await handler.handle(
            context: StreamingRelayStatusContext(statusCode: 562,
                                                disposition: .perPairReplacement,
                                                message: "pair exhausted"),
            replacePair: { statusCode in
                await recorder.append(.replacePair)
                return .pairReplaced(statusCode)
            },
            performFullRepair: { statusCode in
                await recorder.append(.fullRepair)
                return .fullRepairSuccess(statusCode)
            },
            releasePair: {
                await recorder.append(.releasePair)
            }
        )

        let actions = await recorder.snapshot()
        XCTAssertEqual(actions, [.replacePair])
        guard case .pairReplaced(562) = result else {
            XCTFail("Expected pairReplaced(562), got \(result)")
            return
        }
    }

    func testFullRepairReturnsRepairErrorAndSkipsOtherActions() async {
        let handler = StreamingRelayStatusHandler()
        let recorder = ActionRecorder()

        let result = await handler.handle(
            context: StreamingRelayStatusContext(statusCode: 564,
                                                disposition: .fullRepair,
                                                message: nil),
            replacePair: { statusCode in
                await recorder.append(.replacePair)
                return .pairReplaced(statusCode)
            },
            performFullRepair: { statusCode in
                await recorder.append(.fullRepair)
                return .fullRepairSuccess(statusCode)
            },
            releasePair: {
                await recorder.append(.releasePair)
            }
        )

        let actions = await recorder.snapshot()
        XCTAssertEqual(actions, [.fullRepair])
        guard case .fullRepairSuccess(564) = result else {
            XCTFail("Expected fullRepairSuccess(564), got \(result)")
            return
        }
    }

    func testTransientBackoffReleasesPairAndSurfacesRelayStatus() async {
        let handler = StreamingRelayStatusHandler()
        let recorder = ActionRecorder()

        let result = await handler.handle(
            context: StreamingRelayStatusContext(statusCode: 565,
                                                disposition: .transientBackoff,
                                                message: "retry later"),
            replacePair: { statusCode in
                await recorder.append(.replacePair)
                return .pairReplaced(statusCode)
            },
            performFullRepair: { statusCode in
                await recorder.append(.fullRepair)
                return .fullRepairSuccess(statusCode)
            },
            releasePair: {
                await recorder.append(.releasePair)
            }
        )

        let actions = await recorder.snapshot()
        XCTAssertEqual(actions, [.releasePair])
        guard case let .relayStatus(statusCode, message) = result else {
            XCTFail("Expected relayStatus for transient backoff, got \(result)")
            return
        }
        XCTAssertEqual(statusCode, 565)
        XCTAssertEqual(message, "retry later")
    }

    func testSurfaceOnlyReleasesPairAndSurfacesRelayStatus() async {
        let handler = StreamingRelayStatusHandler()
        let recorder = ActionRecorder()

        let result = await handler.handle(
            context: StreamingRelayStatusContext(statusCode: 568,
                                                disposition: .surfaceOnly,
                                                message: nil),
            replacePair: { statusCode in
                await recorder.append(.replacePair)
                return .pairReplaced(statusCode)
            },
            performFullRepair: { statusCode in
                await recorder.append(.fullRepair)
                return .fullRepairSuccess(statusCode)
            },
            releasePair: {
                await recorder.append(.releasePair)
            }
        )

        let actions = await recorder.snapshot()
        XCTAssertEqual(actions, [.releasePair])
        guard case let .relayStatus(statusCode, message) = result else {
            XCTFail("Expected relayStatus for surface-only disposition, got \(result)")
            return
        }
        XCTAssertEqual(statusCode, 568)
        XCTAssertNil(message)
    }
}
