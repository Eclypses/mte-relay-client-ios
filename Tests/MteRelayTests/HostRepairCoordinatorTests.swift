import XCTest
@testable import MteRelay

final class HostRepairCoordinatorTests: XCTestCase {
    func testReturnsNilForNonRelayStatusCodes() {
        let coordinator = HostRepairCoordinator()

        XCTAssertNil(coordinator.recoveryDisposition(for: 200))
        XCTAssertNil(coordinator.recoveryDisposition(for: 404))
    }

    func testMapsPerPairReplacementStatuses() {
        let coordinator = HostRepairCoordinator()

        XCTAssertEqual(coordinator.recoveryDisposition(for: 559), .perPairReplacement)
        XCTAssertEqual(coordinator.recoveryDisposition(for: 560), .perPairReplacement)
        XCTAssertEqual(coordinator.recoveryDisposition(for: 561), .perPairReplacement)
        XCTAssertEqual(coordinator.recoveryDisposition(for: 562), .perPairReplacement)
        XCTAssertEqual(coordinator.recoveryDisposition(for: 563), .perPairReplacement)
    }

    func testMapsFullRepairStatus() {
        let coordinator = HostRepairCoordinator()

        XCTAssertEqual(coordinator.recoveryDisposition(for: 564), .fullRepair)
    }

    func testMapsTransientBackoffStatus() {
        let coordinator = HostRepairCoordinator()

        XCTAssertEqual(coordinator.recoveryDisposition(for: 565), .transientBackoff)
    }

    func testMapsSurfaceOnlyStatuses() {
        let coordinator = HostRepairCoordinator()

        XCTAssertEqual(coordinator.recoveryDisposition(for: 566), .surfaceOnly)
        XCTAssertEqual(coordinator.recoveryDisposition(for: 567), .surfaceOnly)
        XCTAssertEqual(coordinator.recoveryDisposition(for: 568), .surfaceOnly)
        XCTAssertEqual(coordinator.recoveryDisposition(for: 569), .surfaceOnly)
    }
}