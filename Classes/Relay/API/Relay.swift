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
import os
import Mte
#if canImport(UIKit)
import UIKit
#endif

/// A single event in a relay response stream. Every response — an ordinary buffered
/// reply or a long-lived event stream — is delivered as `.response` (once, when the
/// status/headers are known) followed by zero or more `.chunk` values as decrypted body
/// bytes arrive. Normal completion is the stream finishing; failure throws.
public enum RelayResponseEvent: @unchecked Sendable {
    case response(HTTPURLResponse)
    case chunk(Data)
}

public class Relay: ObservableObject, RelayStreamDelegate, RelayStreamCompletionDelegate, RelayStreamResponseDelegate, RelayServerSentEventDelegate {
    
    // MARK: Class Variables
    
    private let logger = PackageLogger.makeLogger(for: Relay.self)
    public var relayStreamDelegate: RelayStreamDelegate? // This delegate variable cannot be 'weak' or we lose the reference before we are finished with it.
    public weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    public weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    public weak var relayServerSentEventDelegate: RelayServerSentEventDelegate?
    private let httpClient: RelayHTTPClient
    private let hostRegistry = HostSessionRegistry()
    private let settingsStore = RelayHostSettingsStore()
    
    // MARK: Callbacks
    // Receives fileStream Responses
    public func relayStreamResponse(from relayServerUrl: String, data: Data?, response: URLResponse?, error: (any Error)?) {
        if let error = error, String(describing: error) != "" {
            logger.error("RelayStreamResponse Error: \(String(describing: error))")
        }
        relayStreamResponseDelegate?.relayStreamResponse(from: relayServerUrl, data: data, response: response, error: error)
    }
    
    // Called periodically to return stream upload/download completion percentage values
    public func streamCompletionPercentage(from relayServerUrl: String, bytesCompleted: Double, totalBytes: Double) {
        self.relayStreamCompletionDelegate?.streamCompletionPercentage(from: relayServerUrl, bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    // Used to call back into app to retrieve file for upload
    public func getRequestBodyStream(outputStream: OutputStream) {
        relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream)
    }

    public func relayServerSentEventDidReceiveResponse(from relayServerUrl: String, streamId: UUID, response: URLResponse) {
        relayServerSentEventDelegate?.relayServerSentEventDidReceiveResponse(from: relayServerUrl,
                                                                             streamId: streamId,
                                                                             response: response)
    }

    public func relayServerSentEventDidReceiveData(from relayServerUrl: String, streamId: UUID, data: Data) {
        relayServerSentEventDelegate?.relayServerSentEventDidReceiveData(from: relayServerUrl,
                                                                         streamId: streamId,
                                                                         data: data)
    }

    public func relayServerSentEventDidComplete(from relayServerUrl: String, streamId: UUID, response: URLResponse?) {
        relayServerSentEventDelegate?.relayServerSentEventDidComplete(from: relayServerUrl,
                                                                      streamId: streamId,
                                                                      response: response)
    }
    
    // MARK: init
    public init(httpClient: RelayHTTPClient = URLSessionRelayHTTPClient()) async throws {
        self.httpClient = httpClient
        
        // Check MTE licensing
        if !MteBase.initLicense(Settings.licCompanyName, Settings.licCompanyKey) {
            logger.error("License Check failed.")
            throw RelayClientError.licenseCheckFailed
        }
        logger.info("Using iOS Relay Version \(Settings.relayVersion) and MTE Version \(MteBase.getVersion())")
    }
    
    // MARK: Public Functions
    /// The unified request core.
    /// rigRequest` through the relay and streams the
    /// response back as `RelayResponseEvent`s: `.response` once the status/headers are known,
    /// then `.chunk` for each decrypted body segment as it arrives. Works for any HTTP method
    /// (with or without a body) and for both ordinary replies and long-lived event streams.
    ///
    /// Recovery is handled at stream open: if the relay signals a pairing desync the pool is
    /// healed in the background and the stream fails with a retryable error (e.g. `.pairReplaced`
    /// / `.fullRepairSuccess`) — the request is not transparently resent.
    public func request(with origRequest: URLRequest,
                        headersToEncrypt: [String]? = nil,
                        pathnamePrefix: String? = nil,
                        preventStreaming: Bool = false) -> AsyncThrowingStream<RelayResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let host = try await retrieveHost(origRequest: origRequest, pathnamePrefix: pathnamePrefix) else {
                        logger.error("Unable to retrieve Relay Server URL from request")
                        throw RelayClientError.hostResolutionFailed
                    }
                    for try await event in host.requestStream(request: origRequest,
                                                              headersToEncrypt: headersToEncrypt,
                                                              pathnamePrefix: pathnamePrefix,
                                                              preventStreaming: preventStreaming) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: RelayClientError.from(error))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Buffered convenience over `request(with:)`: accumulates every chunk and resolves once,
    /// when the stream completes. A single-shot reply is just a stream that finishes quickly.
    public func dataTask(with origRequest: URLRequest,
                         headersToEncrypt: [String]? = nil,
                         pathnamePrefix: String? = nil,
                         preventStreaming: Bool = false) async throws -> (Data, URLResponse) {
        var body = Data()
        var response: HTTPURLResponse?
        for try await event in request(with: origRequest,
                                       headersToEncrypt: headersToEncrypt,
                                       pathnamePrefix: pathnamePrefix,
                                       preventStreaming: preventStreaming) {
            switch event {
            case .response(let httpResponse):
                response = httpResponse
            case .chunk(let data):
                body.append(data)
            }
        }
        guard let response else {
            throw RelayClientError.invalidRelayResponse
        }
        return (body, response)
    }

    /// Uploads a file using true chunked streaming — the file is never loaded
    /// into memory.  Bytes are read from `relayStreamDelegate`, encrypted
    /// chunk-by-chunk with MKE streaming encrypt, and sent using a binary frame
    /// transport.
    ///
    /// Progress is reported incrementally through `relayStreamCompletionDelegate`
    /// as the upload proceeds.
    ///
    /// - Parameters:
    ///   - request: The outbound `URLRequest`.  Must include a positive
    ///     `Content-Length` header specifying the unencrypted file size.
    ///   - headersToEncrypt: Reserved for future per-header encryption; pass
    ///     `nil` for the default behaviour (all metadata is MTE-encoded).
    ///   - pathnamePrefix: Optional path prefix used when locating the relay
    ///     proxy endpoint.
    /// - Returns: The decoded response `Data` and `URLResponse` from the server.
    @discardableResult
    public func uploadFileStream(request: URLRequest,
                                 headersToEncrypt: [String]? = nil,
                                 pathnamePrefix: String? = nil) async throws -> (Data, URLResponse) {
        guard let host = try await retrieveHost(origRequest: request, pathnamePrefix: pathnamePrefix) else {
            throw RelayClientError.hostResolutionFailed
        }
        return try await host.uploadFileStream(origRequest: request,
                                               headersToEncrypt: headersToEncrypt,
                                               pathnamePrefix: pathnamePrefix)
    }

    @discardableResult
    public func downloadFile(with request: URLRequest,
                             to destinationURL: URL,
                             headersToEncrypt: [String]? = nil,
                             pathnamePrefix: String? = nil,
                             timeout: TimeInterval? = nil) async throws -> URLResponse {
        try validateTimeout(timeout)
        guard let host = try await retrieveHost(origRequest: request, pathnamePrefix: pathnamePrefix) else {
            throw RelayClientError.hostResolutionFailed
        }
        return try await runWithOptionalTimeout(timeout) {
            try await host.downloadFile(request: request,
                                        downloadUrl: destinationURL,
                                        headersToEncrypt: headersToEncrypt,
                                        pathnamePrefix: pathnamePrefix)
        }
    }

    @discardableResult
    public func openServerSentEventStream(with request: URLRequest,
                                          headersToEncrypt: [String]? = nil,
                                          pathnamePrefix: String? = nil,
                                          timeout: TimeInterval? = nil) async throws -> RelayServerSentEventOpenResult {
        try validateTimeout(timeout)
        guard let host = try await retrieveHost(origRequest: request, pathnamePrefix: pathnamePrefix) else {
            throw RelayClientError.hostResolutionFailed
        }
        return try await runWithOptionalTimeout(timeout) {
            try await host.openServerSentEventStream(request: request,
                                                     headersToEncrypt: headersToEncrypt,
                                                     pathnamePrefix: pathnamePrefix)
        }
    }

    public func cancelServerSentEventStream(relayServerUrlString: String,
                                            streamId: UUID,
                                            pathnamePrefix: String? = nil) async throws {
        let serverUrlPath = try buildHostUrl(serverUrl: relayServerUrlString, pathnamePrefix: pathnamePrefix)
        guard let host = await hostRegistry.existingHost(for: serverUrlPath) else {
            return
        }
        host.cancelServerSentEventStream(streamId: streamId)
    }
    
    public func rePairwithRelayServer(relayServerUrlString: String) async throws {
        try await rePairwithRelayServer(relayServerUrlString: relayServerUrlString, pathnamePrefix: nil)
    }
    
    public func rePairwithRelayServer(relayServerUrlString: String, pathnamePrefix: String?) async throws {
        
        let serverUrlPath = try buildHostUrl(serverUrl: relayServerUrlString, pathnamePrefix: pathnamePrefix)
        if let host = await hostRegistry.existingHost(for: serverUrlPath) {
            try await host.rePairHost()
        } else {
            _ = try await instantiateHost(hostStr: serverUrlPath)
        }
    }

    public func cancelStreamingOperations(relayServerUrlString: String,
                                          pathnamePrefix: String? = nil) async throws {
        let serverUrlPath = try buildHostUrl(serverUrl: relayServerUrlString, pathnamePrefix: pathnamePrefix)
        guard let host = await hostRegistry.existingHost(for: serverUrlPath) else {
            return
        }
        host.cancelAllStreamingOperations()
    }

    public func relaySettings(serverUrl: String,
                              pathnamePrefix: String? = nil) async throws -> RelayHostSettings {
        let updatedServerUrl = try buildHostUrl(serverUrl: serverUrl, pathnamePrefix: pathnamePrefix)
        return await settingsStore.settings(for: updatedServerUrl)
    }

    public func adjustRelaySettings(serverUrl: String,
                                    settings: RelayHostSettings) async throws {
        try await adjustRelaySettings(serverUrl: serverUrl,
                                      pathnamePrefix: nil,
                                      settings: settings)
    }
    
    public func adjustRelaySettings(serverUrl: String,
                                    pathnamePrefix: String?,
                                    settings: RelayHostSettings) async throws {
        let updatedServerUrl = try buildHostUrl(serverUrl: serverUrl, pathnamePrefix: pathnamePrefix)
        let validatedSettings = try validateHostSettings(settings)
        let currentSettings = await settingsStore.settings(for: updatedServerUrl)

        guard validatedSettings != currentSettings else {
            logger.info("\nNo Relay Settings were changed based on arguments and existing RelaySettings")
            return
        }

        await settingsStore.updateSettings(validatedSettings, for: updatedServerUrl)
        let host = try await recreateHost(hostStr: updatedServerUrl)
        try await host.rePairHost()
        logger.info("\nRelay settings adjusted for \(updatedServerUrl) and Relay was Re-Paired")
    }
    
    // MARK: Public static functions
    public static func enableFileLogging(_ enabled: Bool) {
        PackageLogger.loggingEnabled = enabled
    }

    public static func readLogFile() throws -> String? {
        guard let url = PackageLogger.logFileURL else { return nil }
        var contents: String = ""
        do {
            contents = try String(contentsOf: url)
        } catch {
            throw RelayClientError.logReadFailed
        }
        return contents
    }

    public static func clearLogFile() {
        guard let url = PackageLogger.logFileURL else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            PackageLogger.log(from: String(describing: self.self), level: .info, message: "Failed to clear log file. Likely no log file exists.")
        }
        
    }

    
    // MARK: Private functions
    private func buildHostUrl(serverUrl: String, pathnamePrefix: String?) throws -> String {
        if serverUrl.isEmpty {
            let errorMessage = "Server Url is required"
            logger.error("\(errorMessage)")
            throw RelayClientError.invalidServerURL
        }
        var modifiedUrl = serverUrl
        if modifiedUrl.hasSuffix("/") {
            modifiedUrl.removeLast()
        }
        
        if let pathnamePrefix = pathnamePrefix, !pathnamePrefix.isEmpty {
            let normalizedPath = pathnamePrefix.hasPrefix("/") ? pathnamePrefix : "/" + pathnamePrefix
            if !modifiedUrl.hasSuffix(normalizedPath) {
                return modifiedUrl + normalizedPath
            }
        }
        return modifiedUrl
    }
    
    private func retrieveHost(origRequest: URLRequest, pathnamePrefix: String?) async throws -> Host? {
        guard let relayUrl = origRequest.url else {
            let errorMessage = "Unable to create URL from relayPath"
            logger.error("\(errorMessage)")
            throw RelayClientError.invalidRequestURL
        }

        var components = URLComponents()
        components.scheme = relayUrl.scheme
        components.host = relayUrl.host
        components.port = relayUrl.port

        guard let hostStr = components.string else {
            let errorMessage = "Unable to create String from URL components"
            logger.error("\(errorMessage)")
            throw RelayClientError.invalidURLComponents
        }
        
        let updatedHostStr = try buildHostUrl(serverUrl: hostStr, pathnamePrefix: pathnamePrefix)
        return try await instantiateHost(hostStr: updatedHostStr)
    }
    
    private func instantiateHost(hostStr: String) async throws -> Host {
        let hostSettings = await settingsStore.settings(for: hostStr)
        return try await hostRegistry.resolveHost(for: hostStr) {
            try await Host(hostUrl: hostStr,
                           relay: self,
                           httpClient: self.httpClient,
                           settings: hostSettings)
        }
    }

    private func recreateHost(hostStr: String) async throws -> Host {
        let hostSettings = await settingsStore.settings(for: hostStr)
        let host = try await Host(hostUrl: hostStr,
                                  relay: self,
                                  httpClient: self.httpClient,
                                  settings: hostSettings)
        await hostRegistry.replaceHost(for: hostStr, host: host)
        return host
    }
    
    private func validateStreamChunkSize(_ size: Int) throws -> Int {
        if size < 4096 || size > 1024 * 1024 * 10 {
            let errorMessage = "Stream chunk size must be between 4096 (4 KB) and 10485760 (1024 * 1024 * 10) (10 MB)"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
        }
        return size
    }

    private func validateHostSettings(_ settings: RelayHostSettings) throws -> RelayHostSettings {
        guard settings.minPairs > 0 else {
            let errorMessage = "minPairs must be greater than 0"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
        }
        guard settings.basePairs >= settings.minPairs else {
            let errorMessage = "basePairs must be greater than or equal to minPairs"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
        }
        guard settings.maxPairs >= settings.basePairs else {
            let errorMessage = "maxPairs must be greater than or equal to basePairs"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
        }
        guard settings.acquisitionWaitTime >= 0 else {
            let errorMessage = "acquisitionWaitTime must be greater than or equal to 0"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
        }
        guard (60...600).contains(settings.keepAliveInterval) else {
            let errorMessage = "keepAliveInterval must be between 60 and 600 seconds"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
        }

        return RelayHostSettings(streamChunkSize: try validateStreamChunkSize(settings.streamChunkSize),
                                 minPairs: settings.minPairs,
                                 basePairs: settings.basePairs,
                                 maxPairs: settings.maxPairs,
                                 keepAliveInterval: settings.keepAliveInterval,
                                 acquisitionWaitTime: settings.acquisitionWaitTime)
    }

    func runWithOptionalTimeout<T>(_ timeout: TimeInterval?,
                                   operation: @escaping @Sendable () async throws -> T) async throws -> T {
        guard let timeout else {
            return try await operation()
        }

        guard timeout > 0 else {
            throw RelayClientError.operationTimedOut(timeout)
        }

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                let nanoseconds = UInt64(timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw RelayClientError.operationTimedOut(timeout)
            }

            defer { group.cancelAll() }

            guard let firstResult = try await group.next() else {
                throw RelayClientError.networkFailure
            }
            return firstResult
        }
    }
    
    private func validateTimeout(_ timeout: TimeInterval?) throws {
        if let timeout, timeout <= 0 {
            throw RelayClientError.operationTimedOut(timeout)
        }
    }
}




