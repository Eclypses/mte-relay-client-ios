import XCTest
@testable import Relay

final class ModelAndFixtureTests: XCTestCase {
    func testRelayHeadersCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(TestFixtures.relayHeaders)
        let decoded = try JSONDecoder().decode(RelayHeaders.self, from: encoded)

        XCTAssertEqual(decoded.clientId, TestFixtures.relayHeaders.clientId)
        XCTAssertEqual(decoded.pairId, TestFixtures.relayHeaders.pairId)
        XCTAssertEqual(decoded.encryptedDecryptedHeaders, TestFixtures.relayHeaders.encryptedDecryptedHeaders)
    }

    func testPairingModelsCodableRoundTrip() throws {
        let request = PairingRequest(
            pairId: "pair-01",
            encoderPublicKey: "enc-pub",
            encoderPersonalizationStr: "enc-pers",
            decoderPublicKey: "dec-pub",
            decoderPersonalizationStr: "dec-pers"
        )
        let requestDecoded = try JSONDecoder().decode(PairingRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(requestDecoded.pairId, "pair-01")

        let response = PairingResponse(
            pairId: "pair-01",
            encoderSecret: "es",
            encoderNonce: "en",
            decoderSecret: "ds",
            decoderNonce: "dn"
        )
        let responseDecoded = try JSONDecoder().decode(PairingResponse.self, from: JSONEncoder().encode(response))
        XCTAssertEqual(responseDecoded.decoderNonce, "dn")
    }

    func testInternalConnectionModelCodableWithBinaryPayload() throws {
        let model = InternalConnectionModel(
            url: TestFixtures.endpoint,
            method: RelayMethod.POST,
            route: TestFixtures.pairingRoute,
            payload: TestFixtures.smallBinaryPayload,
            contentType: "application/octet-stream",
            encryptedHeaders: ["Authorization"],
            relayHeaders: TestFixtures.relayHeaders
        )

        let decoded = try JSONDecoder().decode(InternalConnectionModel.self, from: JSONEncoder().encode(model))
        XCTAssertEqual(decoded.url, TestFixtures.endpoint)
        XCTAssertEqual(decoded.payload, TestFixtures.smallBinaryPayload)
        XCTAssertEqual(decoded.relayHeaders.clientId, TestFixtures.relayHeaders.clientId)
    }

    func testEncodeDecodeResultDefaultsAndMutation() {
        let encode = EncodeResult()
        encode.pairId = "pair-a"
        encode.encodedStr = "encoded"
        encode.encodedBytes = [1, 2, 3]

        XCTAssertEqual(encode.pairId, "pair-a")
        XCTAssertEqual(encode.encodedStr, "encoded")
        XCTAssertEqual(encode.encodedBytes, [1, 2, 3])

        let decode = DecodeResult()
        XCTAssertEqual(decode.pairId, "")
        XCTAssertEqual(decode.decodedStr, "")
        XCTAssertEqual(decode.decodedBytes, [])
    }

    func testFixturesContainRequiredVariants() {
        XCTAssertEqual(TestFixtures.verificationRoute, RelayRoutes.RELAY_VERIFICATION)
        XCTAssertEqual(TestFixtures.pairingRoute, RelayRoutes.PAIRING)
        XCTAssertTrue(TestFixtures.emptyTextPayload.isEmpty)
        XCTAssertFalse(TestFixtures.smallTextPayload.isEmpty)
        XCTAssertGreaterThan(TestFixtures.largeTextPayload.count, TestFixtures.smallTextPayload.count)
        XCTAssertEqual(TestFixtures.emptyBinaryPayload.count, 0)
        XCTAssertGreaterThan(TestFixtures.largeBinaryPayload.count, TestFixtures.smallBinaryPayload.count)
        XCTAssertFalse(TestFixtures.fixtureErrors.isEmpty)
    }
}
