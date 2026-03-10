import XCTest
@testable import MteRelay

final class HeaderExtensionsAndThroughputTests: XCTestCase {
    func testRelayHeaderFormatParseRoundTrip() {
        let options = RelayOptions(
            clientId: "client-1",
            pairId: "pair-1",
            encodeType: EncoderType.MTE.rawValue,
            urlIsEncoded: true,
            headersAreEncoded: true,
            bodyIsEncoded: false,
            preventStreaming: false
        )

        let header = formatMteRelayHeader(options: options)
        let parsed = parseMteRelayHeader(header: header)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.clientId, "client-1")
        XCTAssertEqual(parsed?.pairId, "pair-1")
        XCTAssertEqual(parsed?.encodeType, EncoderType.MTE.rawValue)
        XCTAssertEqual(parsed?.urlIsEncoded, true)
        XCTAssertEqual(parsed?.headersAreEncoded, true)
        XCTAssertEqual(parsed?.bodyIsEncoded, false)
        XCTAssertEqual(parsed?.preventStreaming, false)
    }

    func testPreventStreamingFlagRoundTrip() {
        // true should encode as "1" and parse back as true
        let enabledOptions = RelayOptions(
            clientId: "c", pairId: "p",
            encodeType: EncoderType.MKE.rawValue,
            urlIsEncoded: false, headersAreEncoded: false, bodyIsEncoded: false,
            preventStreaming: true
        )
        let enabledParsed = parseMteRelayHeader(header: formatMteRelayHeader(options: enabledOptions))
        XCTAssertEqual(enabledParsed?.preventStreaming, true)

        // false should encode as "0" and parse back as false
        let disabledOptions = RelayOptions(
            clientId: "c", pairId: "p",
            encodeType: EncoderType.MKE.rawValue,
            urlIsEncoded: false, headersAreEncoded: false, bodyIsEncoded: false,
            preventStreaming: false
        )
        let disabledParsed = parseMteRelayHeader(header: formatMteRelayHeader(options: disabledOptions))
        XCTAssertEqual(disabledParsed?.preventStreaming, false)
    }

    func testRelayHeaderParseSingleClientId() {
        let parsed = parseMteRelayHeader(header: "client-only")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.clientId, "client-only")
        XCTAssertEqual(parsed?.pairId, "")
        XCTAssertEqual(parsed?.encodeType, "")
    }

    func testRelayHeaderParseInvalidEmptyString() {
        XCTAssertNil(parseMteRelayHeader(header: ""))
    }

    func testBase64RoundTripAndDataBytesVariants() {
        XCTAssertEqual(TestFixtures.emptyTextPayload.toBase64().fromBase64(), TestFixtures.emptyTextPayload)
        XCTAssertEqual(TestFixtures.smallTextPayload.toBase64().fromBase64(), TestFixtures.smallTextPayload)
        XCTAssertEqual(TestFixtures.largeTextPayload.toBase64().fromBase64(), TestFixtures.largeTextPayload)

        XCTAssertEqual(TestFixtures.smallBinaryPayload.bytes, [0, 1, 2, 3, 4])
        XCTAssertEqual(TestFixtures.emptyBinaryPayload.bytes, [])
    }

    func testFileManagerSizeOfFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0xA5, count: 1024).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let fileSize = FileManager.default.sizeOfFile(atPath: tempURL.path)
        XCTAssertEqual(fileSize, 1024)
    }

    func testRapidLoopAndBurstSerializationMixedPayloads() {
        let payloads = [
            TestFixtures.emptyTextPayload,
            TestFixtures.smallTextPayload,
            TestFixtures.largeTextPayload,
            String(decoding: TestFixtures.smallBinaryPayload, as: UTF8.self),
            String(decoding: TestFixtures.largeBinaryPayload.prefix(1024), as: UTF8.self)
        ]

        for iteration in 0..<500 {
            let payload = payloads[iteration % payloads.count]
            let encoded = payload.toBase64()
            let decoded = encoded.fromBase64()
            XCTAssertEqual(decoded, payload)

            let options = RelayOptions(
                clientId: "client-\(iteration)",
                pairId: "pair-\(iteration)",
                encodeType: iteration % 2 == 0 ? EncoderType.MTE.rawValue : EncoderType.MKE.rawValue,
                urlIsEncoded: iteration % 2 == 0,
                headersAreEncoded: iteration % 3 == 0,
                bodyIsEncoded: iteration % 5 == 0
            )
            let parsed = parseMteRelayHeader(header: formatMteRelayHeader(options: options))
            XCTAssertEqual(parsed?.clientId, options.clientId)
            XCTAssertEqual(parsed?.pairId, options.pairId)
        }
    }
}
