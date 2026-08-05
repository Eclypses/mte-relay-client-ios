import XCTest
@testable import MteRelay

final class RelayHostSettingsTests: XCTestCase {
    func testRelayReturnsDefaultSettingsForUnknownHost() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        let settings = try await relay.relaySettings(serverUrl: "https://relay.example.invalid")

        XCTAssertEqual(settings, RelayHostSettings())
    }

    func testStoreReturnsDefaultSettingsForUnknownHost() async {
        let store = RelayHostSettingsStore()

        let settings = await store.settings(for: "https://relay.example.invalid")

        XCTAssertEqual(settings, RelayHostSettings())
        XCTAssertEqual(settings.minPairs, RelayHostSettings.defaultMinPairs)
        XCTAssertEqual(settings.basePairs, RelayHostSettings.defaultBasePairs)
        XCTAssertEqual(settings.maxPairs, RelayHostSettings.defaultMaxPairs)
    }

    func testStoreMaintainsHostSpecificOverrides() async {
        let store = RelayHostSettingsStore()
        let hostA = "https://relay-a.example.invalid"
        let hostB = "https://relay-b.example.invalid"

        await store.updateSettings(RelayHostSettings(streamChunkSize: 8192,
                                                     minPairs: 6,
                                                     basePairs: 8,
                                                     maxPairs: 20,
                                                     keepAliveInterval: 240,
                                                     acquisitionWaitTime: 0.5),
                                   for: hostA)

        let hostASettings = await store.settings(for: hostA)
        let hostBSettings = await store.settings(for: hostB)

        XCTAssertEqual(hostASettings.streamChunkSize, 8192)
        XCTAssertEqual(hostASettings.minPairs, 6)
        XCTAssertEqual(hostASettings.basePairs, 8)
        XCTAssertEqual(hostASettings.maxPairs, 20)
        XCTAssertEqual(hostASettings.keepAliveInterval, 240)
        XCTAssertEqual(hostASettings.acquisitionWaitTime, 0.5)

        XCTAssertEqual(hostBSettings, RelayHostSettings())
    }

    func testAdjustRelaySettingsRejectsInvalidStructuredSettingsBeforeRepair() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        do {
            try await relay.adjustRelaySettings(serverUrl: "https://relay.example.invalid",
                                                settings: RelayHostSettings(minPairs: 4,
                                                                            basePairs: 3,
                                                                            maxPairs: 6))
            XCTFail("Expected structured settings validation failure")
        } catch let error as RelayStringError {
            XCTAssertTrue(error.message.contains("basePairs must be greater than or equal to minPairs"))
        }
    }

    func testAdjustRelaySettingsRejectsOutOfRangeKeepAliveInterval() async throws {
        let relay = try await Relay(httpClient: NoopRelayHTTPClient())

        do {
            try await relay.adjustRelaySettings(serverUrl: "https://relay.example.invalid",
                                                settings: RelayHostSettings(keepAliveInterval: 30))
            XCTFail("Expected keepAliveInterval validation failure")
        } catch let error as RelayStringError {
            XCTAssertTrue(error.message.contains("keepAliveInterval must be between 60 and 600 seconds"))
        }
    }
}