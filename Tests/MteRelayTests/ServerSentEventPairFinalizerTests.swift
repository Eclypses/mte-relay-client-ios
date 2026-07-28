import XCTest
@testable import MteRelay

final class ServerSentEventPairFinalizerTests: XCTestCase {
    func testFinalizeReusesPairOnCleanCompletion() {
        var releasedPairIds: [String] = []
        var discardedPairIds: [String] = []
        var repairedPairIds: [String] = []
        var persistCount = 0

        let finalizer = ServerSentEventPairFinalizer(releasePair: { releasedPairIds.append($0) },
                                                     discardPair: { discardedPairIds.append($0) },
                                                     persistStates: { persistCount += 1 },
                                                     scheduleRepair: { repairedPairIds.append($0) })

        finalizer.finalize(pairId: "pair-clean", shouldReusePair: true)

        XCTAssertEqual(releasedPairIds, ["pair-clean"])
        XCTAssertTrue(discardedPairIds.isEmpty)
        XCTAssertTrue(repairedPairIds.isEmpty)
        XCTAssertEqual(persistCount, 1)
    }

    func testFinalizeDiscardsAndRepairsPairOnTerminalFailure() {
        var releasedPairIds: [String] = []
        var discardedPairIds: [String] = []
        var repairedPairIds: [String] = []
        var operations: [String] = []
        var persistCount = 0

        let finalizer = ServerSentEventPairFinalizer(releasePair: {
            releasedPairIds.append($0)
            operations.append("release:\($0)")
        }, discardPair: {
            discardedPairIds.append($0)
            operations.append("discard:\($0)")
        }, persistStates: {
            persistCount += 1
            operations.append("persist")
        }, scheduleRepair: {
            repairedPairIds.append($0)
            operations.append("repair:\($0)")
        })

        finalizer.finalize(pairId: "pair-failed", shouldReusePair: false)

        XCTAssertTrue(releasedPairIds.isEmpty)
        XCTAssertEqual(discardedPairIds, ["pair-failed"])
        XCTAssertEqual(repairedPairIds, ["pair-failed"])
        XCTAssertEqual(persistCount, 1)
        XCTAssertEqual(operations, ["discard:pair-failed", "persist", "repair:pair-failed"])
    }
}