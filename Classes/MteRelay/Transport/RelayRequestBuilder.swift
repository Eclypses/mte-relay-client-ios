import Foundation

struct RelayPreparedRequest {
    let pairId: String
    var request: URLRequest
    let bodyBytes: [UInt8]
    let shouldEncodeBody: Bool
}

/// All information needed to start a chunked-streaming upload.
/// The `framePreamble` contains every byte of the binary frame BEFORE the
/// encrypted body — the URLSession stream writer appends body chunks directly
/// after this preamble.
struct RelayStreamingPlan {
    let pairId: String
    let proxyURL: URL
    /// Binary frame header + encoded metadata, excluding encrypted body bytes.
    let framePreamble: [UInt8]
    let originalContentLength: Int
    let method: String
}

enum RelayBodyEncodingStrategy {
    case detectFromRequestBody
    case forceEncoded
    case forceUnencoded
}

struct RelayRequestBuilder {
    func prepareRequest(origRequest: URLRequest,
                        pathnamePrefix: String?,
                        headersToEncrypt: [String]?,
                        clientId: String,
                        mteHelper: MteHelper,
                        bodyEncodingStrategy: RelayBodyEncodingStrategy,
                        preventStreaming: Bool = false) async throws -> RelayPreparedRequest {
        let proxyURL = try createProxyURL(origRequest: origRequest, pathnamePrefix: pathnamePrefix)
        let metadataPayload = try buildMetadataPayload(from: origRequest)

        let encodedMetadataResult = try await mteHelper.encode(pairId: nil, bytes: metadataPayload)
        guard let pairId = encodedMetadataResult.pairId else {
            throw RelayClientError.requestPreparationFailed
        }

        let originalBodyBytes: [UInt8]
        let shouldEncodeBody: Bool

        switch bodyEncodingStrategy {
        case .detectFromRequestBody:
            originalBodyBytes = origRequest.httpBody?.bytes ?? []
            shouldEncodeBody = !originalBodyBytes.isEmpty
        case .forceEncoded:
            originalBodyBytes = origRequest.httpBody?.bytes ?? []
            shouldEncodeBody = true
        case .forceUnencoded:
            originalBodyBytes = []
            shouldEncodeBody = false
        }

        let encodedBodyBytes: [UInt8]
        if shouldEncodeBody && !originalBodyBytes.isEmpty {
            let encodedBodyResult = try await mteHelper.encode(pairId: pairId, bytes: originalBodyBytes)
            encodedBodyBytes = encodedBodyResult.encodedBytes
        } else {
            encodedBodyBytes = []
        }

        let frame = try buildRequestFrame(method: origRequest.httpMethod ?? RelayMethod.GET,
                                          clientId: clientId,
                                          pairId: pairId,
                                          encodedMetadata: encodedMetadataResult.encodedBytes,
                                          encodedBody: encodedBodyBytes,
                                          preventStreaming: preventStreaming)

        var relayRequest = URLRequest(url: proxyURL)
        relayRequest.httpMethod = RelayMethod.POST
        relayRequest.httpBody = Data(frame)
        relayRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        return RelayPreparedRequest(pairId: pairId,
                                    request: relayRequest,
                                    bodyBytes: [],
                                    shouldEncodeBody: false)
    }

    /// Prepares a streaming upload by encoding the request metadata and building
    /// the binary frame preamble (everything before the encrypted body bytes).
    /// The caller must call `mteHelper.startEncrypt(pairId:)` after receiving
    /// the plan if they want to use chunked MKE streaming on the body.
    func prepareStreamingRequest(origRequest: URLRequest,
                                 pathnamePrefix: String?,
                                 clientId: String,
                                 mteHelper: MteHelper) async throws -> RelayStreamingPlan {
        let proxyURL = try createProxyURL(origRequest: origRequest, pathnamePrefix: pathnamePrefix)
        let metadataPayload = try buildMetadataPayload(from: origRequest)

        let encodedMetadataResult = try await mteHelper.encode(pairId: nil, bytes: metadataPayload)
        guard let pairId = encodedMetadataResult.pairId else {
            throw RelayClientError.requestPreparationFailed
        }

        let method = origRequest.httpMethod ?? RelayMethod.POST
        let preamble = buildStreamingFramePreamble(method: method,
                                                   clientId: clientId,
                                                   pairId: pairId,
                                                   encodedMetadata: encodedMetadataResult.encodedBytes)

        let originalContentLength = origRequest.value(forHTTPHeaderField: "Content-Length")
            .flatMap(Int.init) ?? origRequest.httpBody?.count ?? 0

        return RelayStreamingPlan(pairId: pairId,
                                  proxyURL: proxyURL,
                                  framePreamble: preamble,
                                  originalContentLength: originalContentLength,
                                  method: method)
    }

    private func createProxyURL(origRequest: URLRequest,
                                pathnamePrefix: String?) throws -> URL {
        guard let relayUrl = origRequest.url else {
            throw RelayClientError.invalidRequestURL
        }

        var components = URLComponents()
        components.scheme = relayUrl.scheme
        components.host = relayUrl.host
        components.port = relayUrl.port
        components.path = normalizedPrefix(pathnamePrefix)

        guard let newRelayPath = components.string, let newRelayURL = URL(string: newRelayPath) else {
            throw RelayClientError.requestPreparationFailed
        }
        return newRelayURL
    }

    private func buildMetadataPayload(from request: URLRequest) throws -> [UInt8] {
        guard let requestURL = request.url else {
            throw RelayClientError.requestPreparationFailed
        }

        var pathAndQuery = requestURL.path
        if let query = requestURL.query, !query.isEmpty {
            pathAndQuery += "?\(query)"
        }

        let normalizedPath = pathAndQuery.hasPrefix("/") ? String(pathAndQuery.dropFirst()) : pathAndQuery
        let pathBytes = [UInt8](normalizedPath.utf8)

        let headers = request.allHTTPHeaderFields ?? [:]
        let headersData = try JSONEncoder().encode(headers)
        let headersBytes = [UInt8](headersData)

        var metadata = [UInt8]()
        appendUInt16(UInt16(pathBytes.count), to: &metadata)
        metadata.append(contentsOf: pathBytes)
        appendUInt16(UInt16(headersBytes.count), to: &metadata)
        metadata.append(contentsOf: headersBytes)

        return metadata
    }

    private func buildRequestFrame(method: String,
                                   clientId: String,
                                   pairId: String,
                                   encodedMetadata: [UInt8],
                                   encodedBody: [UInt8],
                                   preventStreaming: Bool) throws -> [UInt8] {
        let methodByte = methodByte(for: method)
        let clientIdBytes = [UInt8](clientId.utf8)
        let pairIdBytes = [UInt8](pairId.utf8)

        var frame = [UInt8]()
        frame.append(contentsOf: [0x4D, 0x54, 0x45])
        frame.append(contentsOf: [0x00, 0x00])

        let metadataStartIndex = frame.count

        frame.append(0x01)
        frame.append(methodByte)
        frame.append(contentsOf: [0x00, 0x00])

        appendUInt16(UInt16(clientIdBytes.count), to: &frame)
        frame.append(contentsOf: clientIdBytes)

        appendUInt16(UInt16(pairIdBytes.count), to: &frame)
        frame.append(contentsOf: pairIdBytes)

        frame.append(0x01)
        frame.append(0x01)
        appendUInt16(UInt16(encodedMetadata.count), to: &frame)
        frame.append(contentsOf: encodedMetadata)

        frame.append(0x00)
        frame.append(encodedBody.isEmpty ? 0x00 : 0x01)
        // Trailing flag byte: asks the relay to disable its normal streaming handling of the
        // upstream request. A directive about how the relay talks to the origin — unrelated to how
        // this client reads the response. Implicitly false for streaming uploads/downloads.
        frame.append(preventStreaming ? 0x01 : 0x00)

        let protoLen = frame.count - metadataStartIndex
        frame[3] = UInt8((protoLen >> 8) & 0xFF)
        frame[4] = UInt8(protoLen & 0xFF)

        if !encodedBody.isEmpty {
            frame.append(contentsOf: encodedBody)
        }

        return frame
    }

    /// Builds the binary frame bytes for a streaming upload — identical layout
    /// to `buildRequestFrame` except the body section is always marked as
    /// present (`hasBody = 0x01`) and no body bytes are appended.  The
    /// encrypted body bytes are written directly after this preamble by the
    /// URLSession stream delegate.
    private func buildStreamingFramePreamble(method: String,
                                              clientId: String,
                                              pairId: String,
                                              encodedMetadata: [UInt8]) -> [UInt8] {
        let methodByte = methodByte(for: method)
        let clientIdBytes = [UInt8](clientId.utf8)
        let pairIdBytes = [UInt8](pairId.utf8)

        var frame = [UInt8]()
        frame.append(contentsOf: [0x4D, 0x54, 0x45])
        frame.append(contentsOf: [0x00, 0x00])

        let metadataStartIndex = frame.count

        frame.append(0x01)
        frame.append(methodByte)
        frame.append(contentsOf: [0x00, 0x00])

        appendUInt16(UInt16(clientIdBytes.count), to: &frame)
        frame.append(contentsOf: clientIdBytes)

        appendUInt16(UInt16(pairIdBytes.count), to: &frame)
        frame.append(contentsOf: pairIdBytes)

        frame.append(0x01)
        frame.append(0x01)
        appendUInt16(UInt16(encodedMetadata.count), to: &frame)
        frame.append(contentsOf: encodedMetadata)

        frame.append(0x00) // separator
        frame.append(0x01) // hasBody = 1 (streaming upload always has a body)
        frame.append(0x00) // reserved

        // Write proto-section length (bytes 3–4 in the frame)
        let protoLen = frame.count - metadataStartIndex
        frame[3] = UInt8((protoLen >> 8) & 0xFF)
        frame[4] = UInt8(protoLen & 0xFF)

        return frame
    }

    private func methodByte(for method: String) -> UInt8 {
        switch method.uppercased() {
        case "GET": return 0
        case "POST": return 1
        case "PUT": return 2
        case "PATCH": return 3
        case "DELETE": return 4
        case "HEAD": return 5
        case "OPTIONS": return 6
        case "TRACE": return 7
        case "CONNECT": return 8
        default: return 0
        }
    }

    private func normalizedPrefix(_ pathnamePrefix: String?) -> String {
        guard let pathnamePrefix, !pathnamePrefix.isEmpty else {
            return ""
        }
        return pathnamePrefix.hasPrefix("/") ? pathnamePrefix : "/\(pathnamePrefix)"
    }

    private func appendUInt16(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8(value & 0xFF))
    }

    private func shortPairId(_ pairId: String) -> String {
        String(pairId.prefix(8))
    }
}
