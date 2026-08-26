import Foundation

private struct RelayServerSentEventFrameMetadata {
    let statusCode: Int
    let pairId: String
    let encodedHeaders: [UInt8]?
    let bodyFlag: UInt8
}

private struct RelayServerSentEventFrameReader {
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

class RelayServerSentEventStream: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    init(hostUrl: String, mteHelper: MteHelper, streamId: UUID) {
        self.hostUrl = hostUrl
        self.mteHelper = mteHelper
        self.streamId = streamId
    }

    deinit {
        logger.info("Destroying RelayServerSentEventStream class\n")
    }

    private let logger = PackageLogger.makeLogger(for: RelayServerSentEventStream.self)

    weak var resultDelegate: RelayServerSentEventResultDelegate?
    var hostUrl: String!
    var mteHelper: MteHelper!
    var appResponse: HTTPURLResponse!
    var responsePairId: String!
    var requestPairId: String!
    var streamId: UUID!

    private var session: URLSession?
    private var didCleanup = false
    private var relayResponse: HTTPURLResponse?
    private var frameMetadataBuffer = [UInt8]()
    private var frameMetadataParsed = false
    private var didNotifyOpen = false
    private var didDeliverDecryptedData = false

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    func openStream(request: URLRequest, pairId: String) {
        requestPairId = pairId

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration,
                             delegate: self, delegateQueue: nil)

        session?.dataTask(with: request).resume()
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let relayResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            reportAndCleanup(response: nil, error: RelayClientError.invalidRelayResponse)
            return
        }

        if (200...299).contains(relayResponse.statusCode),
           let mimeType = response.mimeType,
           mimeType == "application/octet-stream" {
            self.relayResponse = relayResponse
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
            reportAndCleanup(response: relayResponse,
                             error: RelayClientError.serverSentEventsSetupFailed("Unexpected SSE relay response status: \(relayResponse.statusCode)"))
        }
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        do {
            if !frameMetadataParsed {
                try processFrameMetadataIfNeeded(with: data.bytes)
                return
            }

            try decryptAndEmitBodyChunk(data.bytes)
        } catch {
            reportAndCleanup(response: appResponse, error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            reportAndCleanup(response: appResponse, error: error)
            return
        }

        guard let responsePairId else {
            reportAndCleanup(response: appResponse, error: nil)
            return
        }

        do {
            let finishDecryptResult = try mteHelper.finishDecrypt(pairId: responsePairId)
            if !finishDecryptResult.decodedBytes.isEmpty {
                resultDelegate?.relayServerSentEventData(Data(finishDecryptResult.decodedBytes), streamId: streamId)
            }
            reportAndCleanup(response: appResponse, error: nil)
        } catch {
            reportAndCleanup(response: appResponse, error: error)
        }
    }

    private func reportAndCleanup(response: URLResponse?, error: Error?) {
        guard !didCleanup else { return }
        didCleanup = true

        resultDelegate?.relayServerSentEventCompleted(response: response,
                                                      error: error,
                                                      streamId: streamId,
                                                      pairId: responsePairId ?? requestPairId,
                                                      didDeliverData: didDeliverDecryptedData)

        session?.finishTasksAndInvalidate()
        session = nil
        relayResponse = nil
        frameMetadataBuffer = []
        frameMetadataParsed = false
        didDeliverDecryptedData = false
        appResponse = nil
        responsePairId = nil
        requestPairId = nil
        resultDelegate = nil
        mteHelper = nil
    }

    private func processFrameMetadataIfNeeded(with newBytes: [UInt8]) throws {
        frameMetadataBuffer.append(contentsOf: newBytes)

        guard frameMetadataBuffer.count >= 5 else {
            return
        }

        guard frameMetadataBuffer[0] == 0x4D,
              frameMetadataBuffer[1] == 0x54,
              frameMetadataBuffer[2] == 0x45 else {
            throw RelayClientError.invalidRelayResponse
        }

        let protoLen = Int((UInt16(frameMetadataBuffer[3]) << 8) | UInt16(frameMetadataBuffer[4]))
        let metadataEnd = 5 + protoLen
        guard frameMetadataBuffer.count >= metadataEnd else {
            return
        }

        let metadataBytes = Array(frameMetadataBuffer[0..<metadataEnd])
        let bodyRemainder = frameMetadataBuffer.count > metadataEnd
            ? Array(frameMetadataBuffer[metadataEnd..<frameMetadataBuffer.count])
            : []
        frameMetadataBuffer.removeAll(keepingCapacity: false)

        guard let parsed = parseFrameMetadata(metadataBytes: metadataBytes,
                                              fallbackPairId: requestPairId) else {
            throw RelayClientError.decodingFailed
        }

        var decodedHeadersDictionary = [String: String]()
        if let encodedHeaders = parsed.encodedHeaders, !encodedHeaders.isEmpty {
            let decodedHeadersResult = try mteHelper.decode(pairId: parsed.pairId, encoded: encodedHeaders)
            if !decodedHeadersResult.decodedBytes.isEmpty {
                decodedHeadersDictionary = try JSONDecoder().decode([String: String].self,
                                                                    from: Data(decodedHeadersResult.decodedBytes))
            }
        }

        guard let relayResponse else {
            throw RelayClientError.invalidRelayResponse
        }
        var transportHeaders = relayResponse.allHeaderFields as? [String: String] ?? [:]
        RelayHeaderNames.allCases.forEach {
            transportHeaders.removeValue(forKey: $0.rawValue)
        }
        let mergedHeaders = transportHeaders.merging(decodedHeadersDictionary, uniquingKeysWith: { (_, second) in second })

        guard let relayUrl = relayResponse.url else {
            throw RelayClientError.invalidRelayResponse
        }

        appResponse = HTTPURLResponse(url: relayUrl,
                                      statusCode: parsed.statusCode,
                                      httpVersion: nil,
                                      headerFields: mergedHeaders)

        responsePairId = parsed.pairId
        _ = try mteHelper.startDecrypt(pairId: responsePairId)
        frameMetadataParsed = true

        if !didNotifyOpen, let appResponse {
            didNotifyOpen = true
            resultDelegate?.relayServerSentEventOpened(response: appResponse, streamId: streamId)
        }

        if parsed.bodyFlag == 1, !bodyRemainder.isEmpty {
            try decryptAndEmitBodyChunk(bodyRemainder)
        }
    }

    private func parseFrameMetadata(metadataBytes: [UInt8], fallbackPairId: String) -> RelayServerSentEventFrameMetadata? {
        guard metadataBytes.count >= 5 else {
            return nil
        }

        var reader = RelayServerSentEventFrameReader(bytes: metadataBytes, startIndex: 5)
        guard reader.readUInt8() != nil else { return nil }
        guard reader.readUInt8() != nil else { return nil }
        guard let statusCodeRaw = reader.readUInt16BE() else { return nil }

        guard let clientIdLen = reader.readUInt16BE(),
              reader.readBytes(count: Int(clientIdLen)) != nil else { return nil }

        guard let pairIdLen = reader.readUInt16BE(),
              let pairIdBytes = reader.readBytes(count: Int(pairIdLen)) else { return nil }

        guard reader.readUInt8() != nil else { return nil }

        var resolvedPairId = String(bytes: pairIdBytes, encoding: .utf8) ?? ""
        if resolvedPairId.isEmpty {
            resolvedPairId = fallbackPairId
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
        guard reader.readUInt8() != nil else { return nil }

        return RelayServerSentEventFrameMetadata(statusCode: Int(statusCodeRaw),
                                                 pairId: resolvedPairId,
                                                 encodedHeaders: encodedHeaders,
                                                 bodyFlag: bodyFlag)
    }

    private func decryptAndEmitBodyChunk(_ encryptedChunk: [UInt8]) throws {
        guard !encryptedChunk.isEmpty else {
            return
        }

        let decryptChunkResult = try mteHelper.decryptChunk(pairId: responsePairId, bytes: encryptedChunk)
        if !decryptChunkResult.decodedBytes.isEmpty {
            didDeliverDecryptedData = true
            resultDelegate?.relayServerSentEventData(Data(decryptChunkResult.decodedBytes), streamId: streamId)
        }
    }
}