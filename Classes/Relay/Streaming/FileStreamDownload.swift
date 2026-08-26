// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


import Foundation

private struct RelayStreamFrameMetadata {
    let statusCode: Int
    let pairId: String
    let encodedHeaders: [UInt8]?
    let bodyFlag: UInt8
}

private struct RelayStreamFrameReader {
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

class FileStreamDownload: NSObject, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    
    // MARK: init
    init(hostUrl: String, mteHelper: MteHelper, downloadId: UUID) {
        self.downloadId = downloadId
        self.hostUrl = hostUrl
        self.mteHelper = mteHelper
    }
    
    deinit {
        logger.info("Destroying RelayFileStreamDownload class\n")
    }
    
    // MARK: Class variables
    private let logger = PackageLogger.makeLogger(for: FileStreamDownload.self)
    weak var fileDownloadResultDelegate: FileDownloadResultDelegate?
    weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    var hostUrl: String!
    var mteHelper: MteHelper!
    var downloadedFilename: String = ""
    var newFileHandle: FileHandle!
    var storedFileUrl: URL!
    var appResponse: HTTPURLResponse!
    var responsePairId: String!
    var requestPairId: String!
    var downloadedBytesSoFar: Int = 0
    var contentLength = Double(0)
    var downloadId: UUID!
    
    var startTime: Date!
    var endTime: Date!

    
    private var session: URLSession?
    private var didCleanup = false
    private var relayResponse: HTTPURLResponse?
    private var frameMetadataBuffer = [UInt8]()
    private var frameMetadataParsed = false
    
    // MARK: Public functions
    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }
    
    func downloadStream(request: URLRequest, downloadUrl: URL, pairId: String) {
        self.requestPairId = pairId
        self.storedFileUrl = downloadUrl
        self.downloadedFilename = storedFileUrl.lastPathComponent
        do {
            newFileHandle = try FileHandle(forWritingTo: storedFileUrl)
            
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            session = URLSession(configuration: configuration,
                                 delegate: self, delegateQueue: nil)
            
            session?.dataTask(with: request).resume()
        } catch {
            reportAndCleanup(response: nil, error: "Unable to create fileHandle for downloaded file. Error: \(error.localizedDescription)".relayError)
        }
    }
    
    
    // MARK: delegate methods
    
    // Called when download starts to confirm mime type and response code
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        startTime = Date()
        Task {
            guard let relayResponse = response as? HTTPURLResponse else {
                reportAndCleanup(response: nil, error: "Unable to retrieve download response.".relayError)
                return
            }
            if (200...299).contains(relayResponse.statusCode),
               let mimeType = response.mimeType,
               mimeType == "application/octet-stream" {
                if let contentLengthStr = relayResponse.value(forHTTPHeaderField: "Content-Length"),
                   let contentLength = Double(contentLengthStr) {
                    self.contentLength = contentLength
                }

                self.relayResponse = relayResponse
                completionHandler(.allow)
            } else {
                // Check for rePair / reSend possibility
                completionHandler(.cancel)
                reportAndCleanup(response: relayResponse, error: "ResponseCode: \(relayResponse.statusCode)".relayError)
                return
            }
        }
    }
    
    // Called periodically throughout download stream
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        do {
            if !frameMetadataParsed {
                try processFrameMetadataIfNeeded(with: data.bytes)
                return
            }

            try decryptAndWriteBodyChunk(data.bytes)
        } catch {
            reportAndCleanup(response: nil, error: "Unable to download \(downloadedFilename). Error: \(error.localizedDescription)".relayError)
        }
    }
    
    // Called when download is complete
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            reportAndCleanup(response: nil, error: "Download \(downloadedFilename) response error. Error: \(error.localizedDescription)".relayError)
        } else {
            do {
                guard frameMetadataParsed,
                      let responsePairId,
                      let newFileHandle,
                      let appResponse else {
                    throw RelayClientError.invalidRelayResponse
                }

                let finishDecryptResult = try self.mteHelper.finishDecrypt(pairId: responsePairId)
                self.relayStreamCompletionDelegate = nil
                
                // Append whatever we got from the finishDecrypt call to the file
                try newFileHandle.seekToEnd()
                try newFileHandle.write(contentsOf: finishDecryptResult.decodedBytes)
                downloadedBytesSoFar += finishDecryptResult.decodedBytes.count
                try newFileHandle.close()

                let ending = Date()
                let duration = ending.timeIntervalSince(self.startTime)
                logger.info("\(self.downloadedFilename) of \(self.downloadedBytesSoFar) bytes has been has been downloaded and decrypted successfully in \(String(format: "%.3f", duration * 1000)) milliseconds!")

                reportAndCleanup(response: appResponse, error: nil)
            } catch {
                reportAndCleanup(response: nil, error: "Unable to finishDecrypt. Error: \(error.localizedDescription)".relayError)
            }
        }
        
    }
    
    func reportAndCleanup(response: URLResponse?, error: Error?) {
        guard !didCleanup else { return }
        didCleanup = true
        
        if error != nil {
            logger.error("\(error?.localizedDescription ?? "Unknown error")")
            if let fileHandle = try? FileHandle(forWritingTo: storedFileUrl) {
                try? fileHandle.truncate(atOffset: 0)
                try? fileHandle.close()
            }
        }
        
        fileDownloadResultDelegate?.fileDownloadResult(storedFileUrl: storedFileUrl,
                                                       response: response,
                                                       error: error,
                                                       downloadId: downloadId,
                                                       pairId: responsePairId ?? requestPairId)

        session?.finishTasksAndInvalidate()
        session = nil
        
        try? newFileHandle?.close()
        newFileHandle = nil
        relayResponse = nil
        frameMetadataBuffer = []
        frameMetadataParsed = false
        storedFileUrl = nil
        appResponse = nil
        responsePairId = nil
        requestPairId = nil
        relayStreamCompletionDelegate = nil
        fileDownloadResultDelegate = nil
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
                        throw "Invalid relay response frame: missing MTE magic.".relayError
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
        logger.info("Using pairId: \(responsePairId ?? "unknown") to decrypt download response body")
        _ = try mteHelper.startDecrypt(pairId: responsePairId)
        frameMetadataParsed = true

        if parsed.bodyFlag == 1, !bodyRemainder.isEmpty {
            try decryptAndWriteBodyChunk(bodyRemainder)
        }
    }

    private func parseFrameMetadata(metadataBytes: [UInt8], fallbackPairId: String) -> RelayStreamFrameMetadata? {
        guard metadataBytes.count >= 5 else {
            return nil
        }

        var reader = RelayStreamFrameReader(bytes: metadataBytes, startIndex: 5)
        guard reader.readUInt8() != nil else { return nil } // strType
        guard reader.readUInt8() != nil else { return nil } // method
        guard let statusCodeRaw = reader.readUInt16BE() else { return nil }

        guard let clientIdLen = reader.readUInt16BE(),
              reader.readBytes(count: Int(clientIdLen)) != nil else { return nil }

        guard let pairIdLen = reader.readUInt16BE(),
              let pairIdBytes = reader.readBytes(count: Int(pairIdLen)) else { return nil }

        guard reader.readUInt8() != nil else { return nil } // mte type

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
        guard reader.readUInt8() != nil else { return nil } // stream flag

        return RelayStreamFrameMetadata(statusCode: Int(statusCodeRaw),
                                        pairId: resolvedPairId,
                                        encodedHeaders: encodedHeaders,
                                        bodyFlag: bodyFlag)
    }

    private func decryptAndWriteBodyChunk(_ encryptedChunk: [UInt8]) throws {
        guard !encryptedChunk.isEmpty else {
            return
        }
        let decryptChunkResult = try mteHelper.decryptChunk(pairId: responsePairId, bytes: encryptedChunk)
        downloadedBytesSoFar += decryptChunkResult.decodedBytes.count
        relayStreamCompletionDelegate?.streamCompletionPercentage(from: hostUrl,
                                                                  bytesCompleted: Double(downloadedBytesSoFar),
                                                                  totalBytes: contentLength)
        try newFileHandle.write(contentsOf: decryptChunkResult.decodedBytes)
    }
    
}
