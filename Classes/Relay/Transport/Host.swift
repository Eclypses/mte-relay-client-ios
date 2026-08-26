//// The MIT License (MIT)
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

private struct ActiveServerSentEventSession {
    let streamId: UUID
    let pairId: String
    let preparedRequest: RelayPreparedRequest
    let startedAt: Date
}

private actor HostPairRefillState {
    private var isRefilling = false

    func beginIfNeeded() -> Bool {
        guard !isRefilling else {
            return false
        }
        isRefilling = true
        return true
    }

    func finish() {
        isRefilling = false
    }
}

private actor HostClientSessionState {
    private var clientId = ""

    func currentClientId() -> String {
        clientId
    }

    func updateClientId(_ clientId: String) {
        self.clientId = clientId
    }

    func clearClientId() {
        clientId = ""
    }
}


class Host: RelayStreamCompletionDelegate, RelayStreamDelegate, FileUploadResultDelegate, FileDownloadResultDelegate, RelayServerSentEventResultDelegate, MteHelperDelegate, @unchecked Sendable {
    private static let relayTransientBackoffNanoseconds = HostRepairCoordinator.transientBackoffNanoseconds
    
    // MARK: Delegate methods
    func getRequestBodyStream(outputStream: OutputStream) {
        relayStreamDelegate?.getRequestBodyStream(outputStream: outputStream)
    }
    
    func streamCompletionPercentage(from relayServerUrl: String, bytesCompleted: Double, totalBytes: Double) {
        relayStreamCompletionDelegate?.streamCompletionPercentage(from: hostUrl, bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }
    
    func pairingNeeded(for newPair: Pair) async throws {
        try await PairingHelper.addPair(hostUrl: hostUrl,
                                        clientId: await currentClientId(),
                                        pair: newPair,
                                        mteHelper: mteHelper)
        mteHelper.registerNewPairedPair(newPair)
    }

    func pairRefillNeeded() {
        Task {
            await scheduleBackgroundPairRefillIfNeeded()
        }
    }
    
    // MARK: init
    init(hostUrl: String, relay: Relay, httpClient: RelayHTTPClient, settings: RelayHostSettings) async throws {
        self.hostUrl = hostUrl
        self.hostUrlB64 = hostUrl.toBase64()
        self.httpClient = httpClient
        self.settings = settings
        self.relayStreamResponseDelegate = relay
        self.relayStreamCompletionDelegate = relay
        self.relayStreamDelegate = relay
        self.relayServerSentEventDelegate = relay
        self.mteHelper = MteHelper(settings: settings)
        self.mteHelper.delegate = self
        _ = try await setUpPairs()
    }
    
    deinit {
        print(">>> deinit Host")
        mteHelper.cleanup()
    }
    
    // MARK: Class variables
    private let logger = PackageLogger.makeLogger(for: Host.self)
    weak var relayStreamDelegate: RelayStreamDelegate?
    weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    weak var relayStreamResponseDelegate: RelayStreamResponseDelegate?
    weak var relayServerSentEventDelegate: RelayServerSentEventDelegate?
    
    var hostUrl: String!
    var hostUrlB64: String!
    
    var hostStorageHelper: HostStorageHelper!
    var mteHelper: MteHelper!
    private let httpClient: RelayHTTPClient
    private let requestBuilder = RelayRequestBuilder()
    private let responseDecoder = RelayResponseDecoder()
    private let pairingCoordinator = HostPairingCoordinator()
    private let repairCoordinator = HostRepairCoordinator()
    private let pairRefillState = HostPairRefillState()
    private let clientSessionState = HostClientSessionState()
    private let settings: RelayHostSettings
    private let streamingRelayStatusHandler = StreamingRelayStatusHandler()
    var hostPaired = false
    private var activeUploads: [UUID: FileStreamUpload] = [:]
    private var activeDownloads: [UUID: FileStreamDownload] = [:]
    private var activeServerSentEventStreams: [UUID: RelayServerSentEventStream] = [:]
    private var activeUploadPairIds: [UUID: String] = [:]
    private var activeDownloadPairIds: [UUID: String] = [:]

    private var pendingUploadContinuations: [UUID: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    private var pendingDownloadContinuations: [UUID: CheckedContinuation<URLResponse, Error>] = [:]
    private var pendingServerSentEventContinuations: [UUID: CheckedContinuation<RelayServerSentEventOpenResult, Error>] = [:]
    private var cancelledUploadIds: Set<UUID> = []
    private var cancelledDownloadIds: Set<UUID> = []
    private var cancelledServerSentEventIds: Set<UUID> = []
    private var repairingReplacementPairIds: Set<String> = []
    private var activeServerSentEventSessions: [UUID: ActiveServerSentEventSession] = [:]
    // Per-operation delivery sinks for the unified `request()` streaming API. When a sink is
    // registered for a streamId, response/data/completion are delivered to it instead of the
    // shared `relayServerSentEventDelegate` (which serves the legacy openServerSentEventStream path).
    private var serverSentEventSinks: [UUID: AsyncThrowingStream<RelayResponseEvent, Error>.Continuation] = [:]
    private let continuationLock = NSLock()
    
    
    // MARK: Public functions
    /// Performs a true chunked-streaming upload using `FileStreamUpload` and
    /// the binary frame protocol.  The file is never loaded into memory; bytes
    /// are read from the app's `relayStreamDelegate`, encrypted chunk-by-chunk
    /// with MKE streaming encrypt, and piped directly to the network.
    ///
    /// Progress is reported incrementally via `relayStreamCompletionDelegate`.
    func uploadFileStream(origRequest: URLRequest,
                          headersToEncrypt: [String]?,
                          pathnamePrefix: String?,
                          uploadId providedUploadId: UUID? = nil) async throws -> (Data, URLResponse) {
        logger.info("\n\nStarting FileStream Upload")
        let uploadId = providedUploadId ?? UUID()

        let plan: RelayStreamingPlan
        do {
            plan = try await requestBuilder.prepareStreamingRequest(
                origRequest: origRequest,
                pathnamePrefix: pathnamePrefix,
                clientId: await currentClientId(),
                mteHelper: mteHelper
            )
        } catch {
            throw RelayClientError.from(error)
        }

        return try await withCheckedThrowingContinuation { continuation in
            storeUploadContinuation(continuation, for: uploadId)
            Task {
                do {
                    try await self.startStreamingUpload(plan: plan, uploadId: uploadId)
                } catch {
                    if let cont = self.clearUploadContinuation(for: uploadId) {
                        self.continuationLock.lock()
                        self.activeUploads.removeValue(forKey: uploadId)
                        self.continuationLock.unlock()
                        cont.resume(throwing: RelayClientError.from(error))
                    }
                }
            }
        }
    }

    // Delegate from RelayFileStreamUpload
    func fileUploadResult(data: Data?, response: URLResponse?, error: Error?, uploadId: UUID, pairId: String?) {
        continuationLock.lock()
        let wasCancelled = cancelledUploadIds.remove(uploadId) != nil
        activeUploads[uploadId] = nil
        let resolvedPairId = pairId ?? activeUploadPairIds.removeValue(forKey: uploadId)
        continuationLock.unlock()

        if wasCancelled {
            return
        }

        if error != nil,
           let relayResponse = response as? HTTPURLResponse,
           let resolvedPairId = resolvedPairId,
           let recoveryDisposition = repairCoordinator.recoveryDisposition(for: relayResponse.statusCode) {
            Task {
                let relayError = await self.streamingRelayStatusHandler.handle(
                    context: StreamingRelayStatusContext(statusCode: relayResponse.statusCode,
                                                        disposition: recoveryDisposition,
                                                        message: String(data: data ?? Data(), encoding: .utf8)),
                    replacePair: { statusCode in
                        await self.replaceFailedPair(pairId: resolvedPairId,
                                                     relayStatusCode: statusCode)
                    },
                    performFullRepair: { statusCode in
                        self.mteHelper.discardPair(pairId: resolvedPairId)
                        return await self.performFullRepair(relayStatusCode: statusCode)
                    },
                    releasePair: {
                        self.finalizeReservedStreamingPair(pairId: resolvedPairId,
                                                           shouldReusePair: true)
                    }
                )

                if let continuation = self.clearUploadContinuation(for: uploadId) {
                    continuation.resume(throwing: relayError)
                    return
                }
                self.relayStreamResponseDelegate?.relayStreamResponse(from: self.hostUrl,
                                                                      data: data,
                                                                      response: response,
                                                                      error: relayError)
            }
            return
        }

        if let resolvedPairId {
            finalizeReservedStreamingPair(pairId: resolvedPairId,
                                          shouldReusePair: error == nil)
        }

        if let continuation = clearUploadContinuation(for: uploadId) {
            if let error {
                continuation.resume(throwing: RelayClientError.from(error))
                return
            }
            guard let data, let response else {
                continuation.resume(throwing: RelayClientError.networkFailure)
                return
            }
            continuation.resume(returning: (data, response))
            return
        }

        relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl,
                                                         data: data,
                                                         response: response,
                                                         error: error)
    }

    func downloadFileStream(origRequest: URLRequest,
                            headersToEncrypt: [String]?,
                            pathnamePrefix: String?,
                            downloadUrl: URL,
                            downloadId providedDownloadId: UUID? = nil) async {
        logger.info("\n\nStarting FileStream download")
        do {
            let response = try await downloadFile(request: origRequest,
                                                  downloadUrl: downloadUrl,
                                                  headersToEncrypt: headersToEncrypt,
                                                  pathnamePrefix: pathnamePrefix)
            relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl,
                                                             data: nil,
                                                             response: response,
                                                             error: nil)
        } catch {
            relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl,
                                                             data: nil,
                                                             response: nil,
                                                             error: error)
        }
    }

    func downloadFile(request: URLRequest,
                      downloadUrl: URL,
                      headersToEncrypt: [String]?,
                      pathnamePrefix: String?,
                      downloadId providedDownloadId: UUID? = nil) async throws -> URLResponse {
        logger.info("\n\nStarting FileStream download")
        let downloadId = providedDownloadId ?? UUID()

        do {
            let parent = downloadUrl.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: downloadUrl.path) {
                try FileManager.default.removeItem(at: downloadUrl)
            }
            guard FileManager.default.createFile(atPath: downloadUrl.path, contents: nil) else {
                throw RelayClientError.fileWriteFailed(downloadUrl.path)
            }
        } catch {
            throw RelayClientError.fileWriteFailed(downloadUrl.path)
        }

        let preparedRequest: RelayPreparedRequest
        do {
            preparedRequest = try await requestBuilder.prepareRequest(origRequest: request,
                                                                      pathnamePrefix: pathnamePrefix,
                                                                      headersToEncrypt: headersToEncrypt,
                                                                      clientId: await currentClientId(),
                                                                      mteHelper: mteHelper,
                                                                      bodyEncodingStrategy: .forceUnencoded)
        } catch {
            throw RelayClientError.requestPreparationFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            storeDownloadContinuation(continuation, for: downloadId)
            self.startStreamingDownload(preparedRequest: preparedRequest,
                                        downloadUrl: downloadUrl,
                                        downloadId: downloadId)
        }
    }

    func openServerSentEventStream(request: URLRequest,
                                   headersToEncrypt: [String]?,
                                   pathnamePrefix: String?) async throws -> RelayServerSentEventOpenResult {
        let streamId = UUID()
        let session = try await reserveServerSentEventSession(request: request,
                                                              headersToEncrypt: headersToEncrypt,
                                                              pathnamePrefix: pathnamePrefix,
                                                              streamId: streamId)

        return try await withCheckedThrowingContinuation { continuation in
            storeServerSentEventContinuation(continuation, for: streamId)
            startServerSentEventStream(session: session, streamId: streamId)
        }
    }

    /// Unified streaming request: prepares + sends the request and delivers the response as
    /// `RelayResponseEvent`s to a per-operation sink. Shares the same pairing, frame decode,
    /// chunked MKE decrypt, and repair-on-open machinery as `openServerSentEventStream`.
    func requestStream(request: URLRequest,
                       headersToEncrypt: [String]?,
                       pathnamePrefix: String?,
                       preventStreaming: Bool = false) -> AsyncThrowingStream<RelayResponseEvent, Error> {
        AsyncThrowingStream { continuation in
            let streamId = UUID()
            storeServerSentEventSink(continuation, for: streamId)
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination {
                    _ = self?.takeServerSentEventSink(for: streamId)
                    self?.cancelServerSentEventStream(streamId: streamId)
                }
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let session = try await self.reserveServerSentEventSession(request: request,
                                                                               headersToEncrypt: headersToEncrypt,
                                                                               pathnamePrefix: pathnamePrefix,
                                                                               streamId: streamId,
                                                                               preventStreaming: preventStreaming)
                    self.startServerSentEventStream(session: session, streamId: streamId)
                } catch {
                    if let sink = self.takeServerSentEventSink(for: streamId) {
                        sink.finish(throwing: RelayClientError.from(error))
                    }
                }
            }
        }
    }

    func cancelServerSentEventStream(streamId: UUID) {
        guard let session = removeServerSentEventSession(for: streamId) else {
            return
        }
        cancelServerSentEventStream(streamId: streamId, pairId: session.pairId)
    }

    func relayServerSentEventOpened(response: URLResponse, streamId: UUID) {
        // Repair-on-open: a recoverable relay status heals the pool in the background and fails
        // the operation with a retryable error (e.g. .pairReplaced) — never a transparent resend.
        if let relayResponse = response as? HTTPURLResponse,
           let recoveryDisposition = repairCoordinator.recoveryDisposition(for: relayResponse.statusCode) {

            // Unified request() sink path.
            if let failure = takeServerSentEventSinkOpenFailure(for: streamId) {
                Task {
                    let relayError = await self.streamingRelayStatusHandler.handle(
                        context: StreamingRelayStatusContext(statusCode: relayResponse.statusCode,
                                                            disposition: recoveryDisposition,
                                                            message: nil),
                        replacePair: { statusCode in
                            await self.replaceFailedPair(pairId: failure.pairId, relayStatusCode: statusCode)
                        },
                        performFullRepair: { statusCode in
                            self.mteHelper.discardPair(pairId: failure.pairId)
                            return await self.performFullRepair(relayStatusCode: statusCode)
                        },
                        releasePair: {
                            self.finalizeServerSentEventSession(pairId: failure.pairId, shouldReusePair: true)
                        }
                    )
                    failure.sink.finish(throwing: relayError)
                }
                return
            }

            // Legacy openServerSentEventStream continuation path.
            if let failureContext = takeServerSentEventOpenFailureResources(for: streamId) {
                Task {
                    let relayError = await self.streamingRelayStatusHandler.handle(
                        context: StreamingRelayStatusContext(statusCode: relayResponse.statusCode,
                                                            disposition: recoveryDisposition,
                                                            message: nil),
                        replacePair: { statusCode in
                            await self.replaceFailedPair(pairId: failureContext.pairId,
                                                         relayStatusCode: statusCode)
                        },
                        performFullRepair: { statusCode in
                            self.mteHelper.discardPair(pairId: failureContext.pairId)
                            return await self.performFullRepair(relayStatusCode: statusCode)
                        },
                        releasePair: {
                            self.finalizeServerSentEventSession(pairId: failureContext.pairId,
                                                                shouldReusePair: true)
                        }
                    )

                    failureContext.continuation.resume(throwing: relayError)
                }
                return
            }
        }

        // Normal open: deliver to the request() sink if present, else the shared delegate.
        if let sink = peekServerSentEventSink(for: streamId) {
            if let httpResponse = response as? HTTPURLResponse {
                sink.yield(.response(httpResponse))
            }
            return
        }

        relayServerSentEventDelegate?.relayServerSentEventDidReceiveResponse(from: hostUrl,
                                                                             streamId: streamId,
                                                                             response: response)
        if let continuation = clearServerSentEventContinuation(for: streamId) {
            continuation.resume(returning: RelayServerSentEventOpenResult(streamId: streamId,
                                                                          response: response))
        }
    }

    func relayServerSentEventData(_ data: Data, streamId: UUID) {
        if let sink = peekServerSentEventSink(for: streamId) {
            sink.yield(.chunk(data))
            return
        }
        relayServerSentEventDelegate?.relayServerSentEventDidReceiveData(from: hostUrl,
                                                                         streamId: streamId,
                                                                         data: data)
    }

    func relayServerSentEventCompleted(response: URLResponse?,
                                       error: Error?,
                                       streamId: UUID,
                                       pairId: String?,
                                       didDeliverData: Bool) {
        continuationLock.lock()
        let wasCancelled = cancelledServerSentEventIds.remove(streamId) != nil
        activeServerSentEventStreams[streamId] = nil
        continuationLock.unlock()

        if let sink = takeServerSentEventSink(for: streamId) {
            if let error, !wasCancelled {
                sink.finish(throwing: RelayClientError.from(error))
            } else {
                sink.finish()
            }
        } else {
            if let response, !wasCancelled {
                relayServerSentEventDelegate?.relayServerSentEventDidComplete(from: hostUrl,
                                                                              streamId: streamId,
                                                                              response: response)
            }

            if let continuation = clearServerSentEventContinuation(for: streamId) {
                if let error {
                    continuation.resume(throwing: RelayClientError.from(error))
                } else if let response {
                    continuation.resume(returning: RelayServerSentEventOpenResult(streamId: streamId,
                                                                                  response: response))
                } else {
                    continuation.resume(throwing: RelayClientError.networkFailure)
                }
            }
        }

        let completedSession = removeServerSentEventSession(for: streamId)
        let resolvedPairId = pairId ?? completedSession?.pairId
        if let resolvedPairId {
            finalizeServerSentEventSession(pairId: resolvedPairId,
                                           shouldReusePair: error == nil && !wasCancelled)
        }
    }

    // Delegate from RelayFileStreamDownload
    func fileDownloadResult(storedFileUrl: URL?, response: URLResponse?, error: (any Error)?, downloadId: UUID, pairId: String?) {
        continuationLock.lock()
        let wasCancelled = cancelledDownloadIds.remove(downloadId) != nil
        activeDownloads[downloadId] = nil
        let resolvedPairId = pairId ?? activeDownloadPairIds.removeValue(forKey: downloadId)
        continuationLock.unlock()

        if wasCancelled {
            return
        }

        if error != nil,
           let relayResponse = response as? HTTPURLResponse,
           let resolvedPairId = resolvedPairId,
           let recoveryDisposition = repairCoordinator.recoveryDisposition(for: relayResponse.statusCode) {
            Task {
                let relayError = await self.streamingRelayStatusHandler.handle(
                    context: StreamingRelayStatusContext(statusCode: relayResponse.statusCode,
                                                        disposition: recoveryDisposition,
                                                        message: nil),
                    replacePair: { statusCode in
                        await self.replaceFailedPair(pairId: resolvedPairId,
                                                     relayStatusCode: statusCode)
                    },
                    performFullRepair: { statusCode in
                        self.mteHelper.discardPair(pairId: resolvedPairId)
                        return await self.performFullRepair(relayStatusCode: statusCode)
                    },
                    releasePair: {
                        self.finalizeReservedStreamingPair(pairId: resolvedPairId,
                                                           shouldReusePair: true)
                    }
                )

                if let continuation = self.clearDownloadContinuation(for: downloadId) {
                    continuation.resume(throwing: relayError)
                    return
                }
                self.relayStreamResponseDelegate?.relayStreamResponse(from: self.hostUrl,
                                                                      data: nil as Data?,
                                                                      response: response,
                                                                      error: relayError)
            }
            return
        }

        if let resolvedPairId {
            finalizeReservedStreamingPair(pairId: resolvedPairId,
                                          shouldReusePair: error == nil)
        }

        if let continuation = clearDownloadContinuation(for: downloadId) {
            if let error {
                continuation.resume(throwing: RelayClientError.from(error))
                return
            }
            guard let response else {
                continuation.resume(throwing: RelayClientError.networkFailure)
                return
            }
            continuation.resume(returning: response)
            return
        }

        let storedFilePath = storedFileUrl?.path ?? ""
        let jsonObject: [String: Any] = [
            "success": true,
            "downloadLocation": "\(storedFilePath)"
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted) {
            relayStreamResponseDelegate?.relayStreamResponse(from: hostUrl,
                                                             data: jsonData,
                                                             response: response,
                                                             error: error)
        }
    }

    func rePairHost() async throws {
        _ = mteHelper.discardAvailablePairs()
        defer {
            self.persistHostSession()
        }

        var clientId = await currentClientId()
        if clientId.isEmpty {
            clientId = try await PairingHelper.verifyRelayServer(hostUrl: hostUrl,
                                                                 currentClientId: clientId)
            await updateClientId(clientId)
        }

        var repairedPairs = try (0..<settings.basePairs).map { _ in try Pair() }

        do {
            try await PairingHelper.addPairs(hostUrl: hostUrl,
                                             clientId: clientId,
                                             pairs: repairedPairs,
                                             mteHelper: mteHelper)
        } catch {
            logger.info("Re-pair failed for existing client session. Refreshing relay client session for \(self.hostUrl!)")
            clientId = try await PairingHelper.verifyRelayServer(hostUrl: hostUrl,
                                                                 currentClientId: clientId)
            await updateClientId(clientId)
            repairedPairs = try (0..<settings.basePairs).map { _ in try Pair() }
            try await PairingHelper.addPairs(hostUrl: hostUrl,
                                             clientId: clientId,
                                             pairs: repairedPairs,
                                             mteHelper: mteHelper)
        }

        for pair in repairedPairs {
            mteHelper.registerNewPairedPair(pair)
            mteHelper.addRepairedPairToAvailable(pair)
        }
    }

    func cancelAllStreamingOperations() {
        continuationLock.lock()

        cancelledUploadIds.formUnion(activeUploads.keys)
        cancelledDownloadIds.formUnion(activeDownloads.keys)
        cancelledServerSentEventIds.formUnion(activeServerSentEventStreams.keys)

        let uploads = activeUploads.values
        let downloads = activeDownloads.values
        let serverSentEventStreams = activeServerSentEventStreams.values
        let uploadPairIds = Array(activeUploadPairIds.values)
        let downloadPairIds = Array(activeDownloadPairIds.values)
        activeUploads.removeAll()
        activeDownloads.removeAll()
        activeServerSentEventStreams.removeAll()
        activeUploadPairIds.removeAll()
        activeDownloadPairIds.removeAll()

        let uploadContinuations = pendingUploadContinuations.values
        let downloadContinuations = pendingDownloadContinuations.values
        let serverSentEventContinuations = pendingServerSentEventContinuations.values
        pendingUploadContinuations.removeAll()
        pendingDownloadContinuations.removeAll()
        pendingServerSentEventContinuations.removeAll()

        let serverSentEventSessions = activeServerSentEventSessions.values
        activeServerSentEventSessions.removeAll()

        continuationLock.unlock()

        uploads.forEach { $0.cancel() }
        downloads.forEach { $0.cancel() }
        serverSentEventStreams.forEach { $0.cancel() }

        uploadContinuations.forEach { $0.resume(throwing: RelayClientError.operationCancelled) }
        downloadContinuations.forEach { $0.resume(throwing: RelayClientError.operationCancelled) }
        serverSentEventContinuations.forEach { $0.resume(throwing: RelayClientError.operationCancelled) }

        for pairId in uploadPairIds {
            finalizeReservedStreamingPair(pairId: pairId,
                                          shouldReusePair: false)
        }

        for pairId in downloadPairIds {
            finalizeReservedStreamingPair(pairId: pairId,
                                          shouldReusePair: false)
        }

        for pairId in serverSentEventSessions.map(\ .pairId) {
            finalizeServerSentEventSession(pairId: pairId,
                                           shouldReusePair: false)
        }
    }
    
    
    //MARK: Private functions

    /// Creates a `FileStreamUpload`, wires its delegates to `self`, stores it
    /// in `activeUploads`, and starts the streaming upload.  Does NOT touch
    /// `pendingUploadContinuations` — continuation lifecycle is managed by the
    /// callers (`uploadFileStream` for fresh uploads, `fileUploadResult` retry
    /// for rePair retries).
    private func startStreamingUpload(plan: RelayStreamingPlan, uploadId: UUID) async throws {
        let fileUpload = FileStreamUpload(hostUrl: hostUrl, mteHelper: mteHelper, uploadId: uploadId)
        fileUpload.relayStreamDelegate        = self
        fileUpload.relayStreamCompletionDelegate = self
        fileUpload.fileUploadResultDelegate   = self

        continuationLock.lock()
        activeUploads[uploadId] = fileUpload
        activeUploadPairIds[uploadId] = plan.pairId
        continuationLock.unlock()

        try await fileUpload.uploadStream(plan: plan)
    }

    /// Creates a `FileStreamDownload`, wires delegates to `self`, stores it in
    /// `activeDownloads`, and starts chunked streaming download. Continuation
    /// lifecycle is managed by callers (`downloadFile` and retry flows).
    private func startStreamingDownload(preparedRequest: RelayPreparedRequest,
                                        downloadUrl: URL,
                                        downloadId: UUID) {
        let fileDownload = FileStreamDownload(hostUrl: hostUrl,
                                              mteHelper: mteHelper,
                                              downloadId: downloadId)
        fileDownload.relayStreamCompletionDelegate = self
        fileDownload.fileDownloadResultDelegate = self

        continuationLock.lock()
        activeDownloads[downloadId] = fileDownload
        activeDownloadPairIds[downloadId] = preparedRequest.pairId
        continuationLock.unlock()

        fileDownload.downloadStream(request: preparedRequest.request,
                                    downloadUrl: downloadUrl,
                                    pairId: preparedRequest.pairId)
    }

    private func startServerSentEventStream(session: ActiveServerSentEventSession,
                                            streamId: UUID) {
        let stream = RelayServerSentEventStream(hostUrl: hostUrl,
                                                mteHelper: mteHelper,
                                                streamId: streamId)
        stream.resultDelegate = self

        continuationLock.lock()
        activeServerSentEventStreams[streamId] = stream
        continuationLock.unlock()

        stream.openStream(request: session.preparedRequest.request,
                          pairId: session.pairId)
    }

    fileprivate func setUpPairs() async throws -> HostStorageHelper {
        do {
            let storageHelper = try await pairingCoordinator.setUpPairs(hostUrl: hostUrl,
                                                                        hostUrlB64: hostUrlB64,
                                                                        settings: settings,
                                                                        currentClientId: await currentClientId(),
                                                                        mteHelper: mteHelper,
                                                                        updateClientId: { [weak self] clientId in
                                                                            await self?.updateClientId(clientId)
                                                                        },
                                                                        persistHostSession: { [weak self] in
                                                                            self?.persistHostSession()
                                                                        })
            hostStorageHelper = storageHelper

            if let storedHost = hostStorageHelper.storedHost, !storedHost.clientId.isEmpty {
                logger.info("Successfully paired with persisted clientId for \(self.hostUrl!)")
            } else {
                logger.info("Successfully paired with \(self.hostUrl!)")
            }
            return storageHelper
        } catch {
            throw RelayClientError.pairingFailed("\(self.hostUrl!) pairing failed: \(error.localizedDescription)")
        }
    }
    
    private func persistHostSession() {
        Task {
            guard let hostStorageHelper else {
                return
            }

            do {
                try await hostStorageHelper.storeClientId(await currentClientId())
            } catch {
                logger.error("Unable to persist relay host session: \(error.localizedDescription)")
            }
        }
    }

    private func replaceFailedPair(pairId: String,
                                   relayStatusCode: Int) async -> RelayClientError {
        mteHelper.discardPair(pairId: pairId)

        do {
            let replacementPair = try Pair()
            try await PairingHelper.addPair(hostUrl: hostUrl,
                                            clientId: await currentClientId(),
                                            pair: replacementPair,
                                            mteHelper: mteHelper)
            mteHelper.registerNewPairedPair(replacementPair)
            mteHelper.addRepairedPairToAvailable(replacementPair)
            persistHostSession()
            return .pairReplaced(relayStatusCode)
        } catch {
            if parsedRelayStatusCode(from: error) == 564 {
                return await performFullRepair(relayStatusCode: 564)
            }
            return .pairReplaceFailed(relayStatusCode)
        }
    }

    private func performFullRepair(relayStatusCode: Int) async -> RelayClientError {
        await clearClientId()

        do {
            try await rePairHost()
            return .fullRepairSuccess(relayStatusCode)
        } catch {
            return .fullRepairCatastrophic(relayStatusCode)
        }
    }

    private func parsedRelayStatusCode(from error: Error) -> Int? {
        let description = error.localizedDescription
        guard let markerRange = description.range(of: "Error Code: ") else {
            return nil
        }

        let suffix = description[markerRange.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    private func writeFile(fileURL: URL, to outputStream: OutputStream) {
        guard let inputStream = InputStream(url: fileURL) else {
            outputStream.close()
            return
        }

        inputStream.open()
        defer {
            inputStream.close()
            outputStream.close()
        }

        var buffer = [UInt8](repeating: 0, count: settings.streamChunkSize)
        while inputStream.hasBytesAvailable {
            let readCount = inputStream.read(&buffer, maxLength: buffer.count)
            if readCount <= 0 {
                break
            }

            var totalWritten = 0
            while totalWritten < readCount {
                let wrote = buffer.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return -1
                    }
                    return outputStream.write(baseAddress.advanced(by: totalWritten),
                                              maxLength: readCount - totalWritten)
                }
                if wrote <= 0 {
                    return
                }
                totalWritten += wrote
            }
        }
    }

    private func storeUploadContinuation(_ continuation: CheckedContinuation<(Data, URLResponse), Error>, for uploadId: UUID) {
        continuationLock.lock()
        pendingUploadContinuations[uploadId] = continuation
        continuationLock.unlock()
    }

    private func clearUploadContinuation(for uploadId: UUID) -> CheckedContinuation<(Data, URLResponse), Error>? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        return pendingUploadContinuations.removeValue(forKey: uploadId)
    }

    private func storeDownloadContinuation(_ continuation: CheckedContinuation<URLResponse, Error>, for downloadId: UUID) {
        continuationLock.lock()
        pendingDownloadContinuations[downloadId] = continuation
        continuationLock.unlock()
    }

    private func clearDownloadContinuation(for downloadId: UUID) -> CheckedContinuation<URLResponse, Error>? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        return pendingDownloadContinuations.removeValue(forKey: downloadId)
    }

    private func storeServerSentEventContinuation(_ continuation: CheckedContinuation<RelayServerSentEventOpenResult, Error>, for streamId: UUID) {
        continuationLock.lock()
        pendingServerSentEventContinuations[streamId] = continuation
        continuationLock.unlock()
    }

    private func clearServerSentEventContinuation(for streamId: UUID) -> CheckedContinuation<RelayServerSentEventOpenResult, Error>? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        return pendingServerSentEventContinuations.removeValue(forKey: streamId)
    }

    private func takeServerSentEventOpenFailureResources(for streamId: UUID) -> (pairId: String, continuation: CheckedContinuation<RelayServerSentEventOpenResult, Error>)? {
        continuationLock.lock()
        cancelledServerSentEventIds.insert(streamId)
        let stream = activeServerSentEventStreams.removeValue(forKey: streamId)
        let continuation = pendingServerSentEventContinuations.removeValue(forKey: streamId)
        let session = activeServerSentEventSessions.removeValue(forKey: streamId)
        continuationLock.unlock()

        stream?.cancel()

        guard let continuation, let session else {
            return nil
        }

        return (session.pairId, continuation)
    }

    private func storeServerSentEventSink(_ sink: AsyncThrowingStream<RelayResponseEvent, Error>.Continuation,
                                          for streamId: UUID) {
        continuationLock.lock()
        serverSentEventSinks[streamId] = sink
        continuationLock.unlock()
    }

    private func peekServerSentEventSink(for streamId: UUID) -> AsyncThrowingStream<RelayResponseEvent, Error>.Continuation? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        return serverSentEventSinks[streamId]
    }

    private func takeServerSentEventSink(for streamId: UUID) -> AsyncThrowingStream<RelayResponseEvent, Error>.Continuation? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        return serverSentEventSinks.removeValue(forKey: streamId)
    }

    /// Sink analogue of `takeServerSentEventOpenFailureResources`: only mutates state when a
    /// request() sink is registered for `streamId`, so the legacy continuation path is untouched.
    private func takeServerSentEventSinkOpenFailure(for streamId: UUID)
        -> (pairId: String, sink: AsyncThrowingStream<RelayResponseEvent, Error>.Continuation)? {
        continuationLock.lock()
        guard let sink = serverSentEventSinks.removeValue(forKey: streamId) else {
            continuationLock.unlock()
            return nil
        }
        cancelledServerSentEventIds.insert(streamId)
        let stream = activeServerSentEventStreams.removeValue(forKey: streamId)
        let session = activeServerSentEventSessions.removeValue(forKey: streamId)
        continuationLock.unlock()

        stream?.cancel()

        guard let session else {
            sink.finish(throwing: RelayClientError.invalidRelayResponse)
            return nil
        }
        return (session.pairId, sink)
    }

    private func reserveServerSentEventSession(request: URLRequest,
                                               headersToEncrypt: [String]?,
                                               pathnamePrefix: String?,
                                               streamId: UUID,
                                               preventStreaming: Bool = false) async throws -> ActiveServerSentEventSession {
        let preparedRequest = try await requestBuilder.prepareRequest(origRequest: request,
                                                                      pathnamePrefix: pathnamePrefix,
                                                                      headersToEncrypt: headersToEncrypt,
                                                                      clientId: await currentClientId(),
                                                                      mteHelper: mteHelper,
                                                                      bodyEncodingStrategy: .detectFromRequestBody,
                                                                      preventStreaming: preventStreaming)

        let session = ActiveServerSentEventSession(streamId: streamId,
                                                   pairId: preparedRequest.pairId,
                                                   preparedRequest: preparedRequest,
                                                   startedAt: Date())

        storeServerSentEventSession(session)
        return session
    }

    private func removeServerSentEventSession(for streamId: UUID) -> ActiveServerSentEventSession? {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        return activeServerSentEventSessions.removeValue(forKey: streamId)
    }

    private func releaseServerSentEventSession(pairId: String, persistStates: Bool) {
        mteHelper.releasePair(pairId: pairId,
                              discardIfPoolIsAtCapacity: true)
        if persistStates {
            persistHostSession()
        }
    }

    private func finalizeServerSentEventSession(pairId: String,
                                                shouldReusePair: Bool) {
        let finalizer = ServerSentEventPairFinalizer(releasePair: { [weak self] pairId in
            self?.releaseServerSentEventSession(pairId: pairId, persistStates: false)
        }, discardPair: { [weak self] pairId in
            self?.mteHelper.discardPair(pairId: pairId)
        }, persistStates: { [weak self] in
            self?.persistHostSession()
        }, scheduleRepair: { [weak self] pairId in
            self?.scheduleReplacementPairRepair(replacedPairId: pairId)
        })

        finalizer.finalize(pairId: pairId, shouldReusePair: shouldReusePair)
    }

    private func finalizeReservedStreamingPair(pairId: String,
                                               shouldReusePair: Bool) {
        let finalizer = ReservedPairFinalizer(releasePair: { [weak self] pairId in
            self?.mteHelper.releasePair(pairId: pairId,
                                        discardIfPoolIsAtCapacity: true)
        }, discardPair: { [weak self] pairId in
            self?.mteHelper.discardPair(pairId: pairId)
        }, persistStates: { [weak self] in
            self?.persistHostSession()
        }, scheduleRepair: { [weak self] pairId in
            self?.scheduleReplacementPairRepair(replacedPairId: pairId)
        })

        finalizer.finalize(pairId: pairId, shouldReusePair: shouldReusePair)
    }

    private func scheduleReplacementPairRepair(replacedPairId pairId: String) {
        guard mteHelper.pairPoolInventory().availableCount < settings.minPairs else {
            return
        }

        guard markReplacementPairRepairStarted(pairId: pairId) else {
            return
        }

        Task {
            defer {
                self.markReplacementPairRepairFinished(pairId: pairId)
            }

            do {
                let repairedPair = try Pair()
                try await PairingHelper.addPair(hostUrl: self.hostUrl,
                                                clientId: await self.currentClientId(),
                                                pair: repairedPair,
                                                mteHelper: self.mteHelper)
                self.mteHelper.registerNewPairedPair(repairedPair)
                self.mteHelper.addRepairedPairToAvailable(repairedPair)
                self.persistHostSession()
            } catch {
                self.logger.error("Unable to repair replacement pair after terminal stream event: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleBackgroundPairRefillIfNeeded() async {
        guard await pairRefillState.beginIfNeeded() else {
            return
        }

        defer {
            Task {
                await self.pairRefillState.finish()
            }
        }

        let refillCount = mteHelper.pairRefillRequestCount()
        guard refillCount > 0 else {
            return
        }

        do {
            let newPairs = try (0..<refillCount).map { _ in try Pair() }
            try await PairingHelper.addPairs(hostUrl: hostUrl,
                                             clientId: await currentClientId(),
                                             pairs: newPairs,
                                             mteHelper: mteHelper)
            for pair in newPairs {
                mteHelper.addRepairedPairToAvailable(pair)
            }
            persistHostSession()
        } catch {
            logger.error("Unable to refill pair capacity for host \(hostUrl ?? "unknown"): \(error.localizedDescription)")
        }
    }

    private func markReplacementPairRepairStarted(pairId: String) -> Bool {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        return repairingReplacementPairIds.insert(pairId).inserted
    }

    private func markReplacementPairRepairFinished(pairId: String) {
        continuationLock.lock()
        repairingReplacementPairIds.remove(pairId)
        continuationLock.unlock()
    }

    private func currentClientId() async -> String {
        await clientSessionState.currentClientId()
    }

    private func updateClientId(_ clientId: String) async {
        await clientSessionState.updateClientId(clientId)
    }

    private func clearClientId() async {
        await clientSessionState.clearClientId()
        do {
            try hostStorageHelper?.clearStoredClientId()
        } catch {
            logger.error("Unable to clear persisted relay host session: \(error.localizedDescription)")
        }
    }

    private func cancelServerSentEventStream(streamId: UUID, pairId: String) {
        continuationLock.lock()
        cancelledServerSentEventIds.insert(streamId)
        let stream = activeServerSentEventStreams[streamId]
        let continuation = pendingServerSentEventContinuations.removeValue(forKey: streamId)
        continuationLock.unlock()

        stream?.cancel()
        continuation?.resume(throwing: RelayClientError.operationCancelled)
    }

    private func storeServerSentEventSession(_ session: ActiveServerSentEventSession) {
        continuationLock.lock()
        defer { continuationLock.unlock() }

        activeServerSentEventSessions[session.streamId] = session
    }

    private func cancelUploadOperation(uploadId: UUID) {
        continuationLock.lock()
        cancelledUploadIds.insert(uploadId)
        let upload = activeUploads.removeValue(forKey: uploadId)
        let continuation = pendingUploadContinuations.removeValue(forKey: uploadId)
        continuationLock.unlock()

        upload?.cancel()
        continuation?.resume(throwing: RelayClientError.operationCancelled)
    }

    private func cancelDownloadOperation(downloadId: UUID) {
        continuationLock.lock()
        cancelledDownloadIds.insert(downloadId)
        let download = activeDownloads.removeValue(forKey: downloadId)
        let continuation = pendingDownloadContinuations.removeValue(forKey: downloadId)
        continuationLock.unlock()

        download?.cancel()
        continuation?.resume(throwing: RelayClientError.operationCancelled)
    }
    
}
