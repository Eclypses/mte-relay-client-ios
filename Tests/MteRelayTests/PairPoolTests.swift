import XCTest
@testable import MteRelay

final class PairPoolTests: XCTestCase {
    private func makeLicensedPool(settings: RelayHostSettings) async throws -> PairPool {
        _ = try await Relay(httpClient: NoopRelayHTTPClient())
        return PairPool(settings: settings)
    }

    func testInventorySignalsRefillWhenAvailableDropsBelowMinPairs() async throws {
        var pool = try await makeLicensedPool(settings: RelayHostSettings(minPairs: 1,
                                                                         basePairs: 2,
                                                                         maxPairs: 4))

        try pool.createNew(count: 2)
        _ = try pool.getNextAvailablePair()

        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 1,
                                                           inUseCount: 1,
                                                           totalCount: 2))
        XCTAssertFalse(pool.shouldTriggerRefill())

        _ = try pool.getNextAvailablePair()

        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 0,
                                                           inUseCount: 2,
                                                           totalCount: 2))
        XCTAssertTrue(pool.shouldTriggerRefill())
    }

    func testMoveToAvailableRetainsBurstCapacityByDefault() async throws {
        var pool = try await makeLicensedPool(settings: RelayHostSettings(minPairs: 1,
                                                                         basePairs: 2,
                                                                         maxPairs: 4))

        try pool.createNew(count: 2)
        let (firstPair, _) = try XCTUnwrap(try pool.getNextAvailablePair())
        let (secondPair, _) = try XCTUnwrap(try pool.getNextAvailablePair())
        let (thirdPair, wasCreated) = try XCTUnwrap(try pool.getNextAvailablePair())

        XCTAssertTrue(wasCreated)

        XCTAssertEqual(pool.moveToAvailable(pairId: firstPair.pairId), .returnedToAvailable)
        XCTAssertEqual(pool.moveToAvailable(pairId: secondPair.pairId), .returnedToAvailable)
        XCTAssertEqual(pool.moveToAvailable(pairId: thirdPair.pairId), .returnedToAvailable)
        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 3,
                                                           inUseCount: 0,
                                                           totalCount: 3))
    }

    func testMoveToAvailableCanDiscardSuccessfulReturnAtMaxCapacity() async throws {
        var pool = try await makeLicensedPool(settings: RelayHostSettings(minPairs: 1,
                                                                         basePairs: 2,
                                                                         maxPairs: 3))

        try pool.createNew(count: 2)
        _ = try XCTUnwrap(try pool.getNextAvailablePair())
        _ = try XCTUnwrap(try pool.getNextAvailablePair())
        let (thirdPair, wasCreated) = try XCTUnwrap(try pool.getNextAvailablePair())

        XCTAssertTrue(wasCreated)
        XCTAssertEqual(pool.moveToAvailable(pairId: thirdPair.pairId,
                                            discardIfPoolIsAtCapacity: true),
                       .discardedExcessCapacity)
        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 0,
                                                           inUseCount: 2,
                                                           totalCount: 2))
    }

    func testRefillPairCountTargetsMinPairsWithinMaxHeadroom() async throws {
        var pool = try await makeLicensedPool(settings: RelayHostSettings(minPairs: 2,
                                                                         basePairs: 4,
                                                                         maxPairs: 5))

        try pool.createNew(count: 3)
        _ = try XCTUnwrap(try pool.getNextAvailablePair())
        _ = try XCTUnwrap(try pool.getNextAvailablePair())

        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 1,
                                                           inUseCount: 2,
                                                           totalCount: 3))
        XCTAssertEqual(pool.refillPairCount(), 1)
    }

    func testRefillPairCountRespectsMaxHeadroom() async throws {
        var pool = try await makeLicensedPool(settings: RelayHostSettings(minPairs: 2,
                                                                         basePairs: 4,
                                                                         maxPairs: 4))

        try pool.createNew(count: 4)
        _ = try XCTUnwrap(try pool.getNextAvailablePair())

        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 3,
                                                           inUseCount: 1,
                                                           totalCount: 4))
        XCTAssertEqual(pool.refillPairCount(), 0)
    }

    func testGetNextAvailablePairReturnsNilWhenPoolIsAtMaxAndNoPairsAreAvailable() async throws {
        var pool = try await makeLicensedPool(settings: RelayHostSettings(minPairs: 1,
                                                                         basePairs: 2,
                                                                         maxPairs: 2,
                                                                         acquisitionWaitTime: 0))

        try pool.createNew(count: 2)
        _ = try pool.getNextAvailablePair()
        _ = try pool.getNextAvailablePair()

        let saturatedAcquire = try pool.getNextAvailablePair()

        XCTAssertNil(saturatedAcquire)
        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 0,
                                                           inUseCount: 2,
                                                           totalCount: 2))
    }

    func testRemoveAvailablePairsPreservesInUsePairs() async throws {
        var pool = try await makeLicensedPool(settings: RelayHostSettings(minPairs: 1,
                                                                         basePairs: 3,
                                                                         maxPairs: 5))

        try pool.createNew(count: 3)
        _ = try XCTUnwrap(try pool.getNextAvailablePair())

        let removedCount = pool.removeAvailablePairs()

        XCTAssertEqual(removedCount, 2)
        XCTAssertEqual(pool.inventory(), PairPoolInventory(availableCount: 0,
                                                           inUseCount: 1,
                                                           totalCount: 1))
    }
}