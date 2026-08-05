import Foundation

private struct RelayFrameParseResult {
    let statusCode: Int
    let pairId: String
    let pairFromFrame: Bool
    let encodedHeaders: [UInt8]?
    let encodedBody: [UInt8]?
}

private struct RelayFrameReader {
    private let bytes: [UInt8]
    private(set) var index: Int

    init(bytes: [UInt8], startIndex: Int = 0) {
        self.bytes = bytes
        self.index = startIndex
    }

    mutating func readUInt8() -> UInt8? {
        guard index < bytes.count else { return nil }
        let value = bytes[index]
        index += 1
        return value
    }

    mutating func readUInt16BE() -> UInt16? {
        guard index + 1 < bytes.count else { return nil }
        let value = (UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1])
        index += 2
        return value
    }

    mutating func readBytes(count: Int) -> [UInt8]? {
        guard count >= 0, index + count <= bytes.count else { return nil }
        let value = Array(bytes[index..<(index + count)])
        index += count
        return value
    }
}

struct RelayResponseDecoder {
    func decode(relayResponse: HTTPURLResponse,
                relayPayload: Data,
                fallbackURL: URL,
                requestPairId: String,
                mteHelper: MteHelper) throws -> (Data, URLResponse) {
        let payloadBytes = relayPayload.bytes

        guard payloadBytes.count >= 5,
              payloadBytes[0] == 0x4D,
              payloadBytes[1] == 0x54,
              payloadBytes[2] == 0x45 else {
            guard let passthrough = HTTPURLResponse(url: relayResponse.url ?? fallbackURL,
                                                    statusCode: relayResponse.statusCode,
                                                    httpVersion: nil,
                                                    headerFields: relayResponse.allHeaderFields as? [String: String]) else {
                throw RelayClientError.invalidRelayResponse
            }
            return (relayPayload, passthrough)
        }

        guard let parseResult = parseFrame(payloadBytes: payloadBytes,
                                           requestPairId: requestPairId) else {
            throw RelayClientError.decodingFailed
        }

        var mergedHeaders: [String: String] = [:]
        if let encodedHeaders = parseResult.encodedHeaders, !encodedHeaders.isEmpty {
            let decodedHeaders = try mteHelper.decode(pairId: parseResult.pairId, encoded: encodedHeaders)
            if !decodedHeaders.decodedBytes.isEmpty {
                mergedHeaders = try JSONDecoder().decode([String: String].self, from: Data(decodedHeaders.decodedBytes))
            }
        }

        let decodedBody: Data
        if let encodedBody = parseResult.encodedBody, !encodedBody.isEmpty {
            let decoded = try mteHelper.decode(pairId: parseResult.pairId, encoded: encodedBody)
            decodedBody = Data(decoded.decodedBytes)
        } else {
            decodedBody = Data()
        }

        guard let appResponse = HTTPURLResponse(url: relayResponse.url ?? fallbackURL,
                                                statusCode: parseResult.statusCode,
                                                httpVersion: nil,
                                                headerFields: mergedHeaders) else {
            throw RelayClientError.invalidRelayResponse
        }

        return (decodedBody, appResponse)
    }

    private func parseFrame(payloadBytes: [UInt8], requestPairId: String) -> RelayFrameParseResult? {
        let protoLen = Int((UInt16(payloadBytes[3]) << 8) | UInt16(payloadBytes[4]))
        let metadataEnd = 5 + protoLen
        guard metadataEnd <= payloadBytes.count else {
            return nil
        }

        var reader = RelayFrameReader(bytes: payloadBytes, startIndex: 5)

        guard reader.readUInt8() != nil else { return nil } // StrType
        guard reader.readUInt8() != nil else { return nil } // Method
        guard let statusCodeRaw = reader.readUInt16BE() else { return nil }

        guard let clientIdLen = reader.readUInt16BE(),
              reader.readBytes(count: Int(clientIdLen)) != nil else { return nil }

        guard let pairIdLen = reader.readUInt16BE(),
              let pairIdBytes = reader.readBytes(count: Int(pairIdLen)) else { return nil }

        guard reader.readUInt8() != nil else { return nil } // mte type

        var resolvedPairId = String(bytes: pairIdBytes, encoding: .utf8) ?? ""
        let pairFromFrame = !resolvedPairId.isEmpty
        if resolvedPairId.isEmpty {
            resolvedPairId = requestPairId
        }

        guard !resolvedPairId.isEmpty else { return nil }

        guard let pathFlag = reader.readUInt8() else { return nil }
        if pathFlag == 1 {
            guard let pathLen = reader.readUInt16BE(),
                  reader.readBytes(count: Int(pathLen)) != nil else { return nil }
        }

        guard let headFlag = reader.readUInt8() else { return nil }
        var encodedHeaders: [UInt8]? = nil
        if headFlag == 1 {
            guard let headerLen = reader.readUInt16BE(),
                  let headerBytes = reader.readBytes(count: Int(headerLen)) else { return nil }
            encodedHeaders = headerBytes
        }

        guard let bodyFlag = reader.readUInt8() else { return nil }
        guard reader.readUInt8() != nil else { return nil } // stream flag

        let encodedBody: [UInt8]?
        if bodyFlag == 1 {
            encodedBody = metadataEnd < payloadBytes.count ? Array(payloadBytes[metadataEnd...]) : []
        } else {
            encodedBody = nil
        }

        return RelayFrameParseResult(statusCode: Int(statusCodeRaw),
                                     pairId: resolvedPairId,
                                     pairFromFrame: pairFromFrame,
                                     encodedHeaders: encodedHeaders,
                                     encodedBody: encodedBody)
    }

    private func shortPairId(_ pairId: String) -> String {
        String(pairId.prefix(8))
    }
}
