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

// MARK: EncryptorActor
actor EncryptorActor {
    private unowned let parent: FileStreamUpload
    private var isEncrypting = false
    private var pendingSignal = false

    init(parent: FileStreamUpload) {
        self.parent = parent
    }

    func signalEncryptChunk() async {
        if isEncrypting {
            pendingSignal = true
            return
        }
        isEncrypting = true
        await performEncryptChunk()
    }

    private func performEncryptChunk() async {
        do {
            try await parent.encryptChunk()
        } catch {
            parent.reportAndCleanup(data: nil,
                                    response: nil,
                                    error: "File upload failed. Error: \(error.localizedDescription)".relayError)
        }

        if pendingSignal {
            pendingSignal = false
            await performEncryptChunk()
        } else {
            isEncrypting = false
        }
    }
}

class FileStreamUpload: NSObject, URLSessionDelegate, StreamDelegate, URLSessionStreamDelegate, URLSessionDataDelegate {
    
    // MARK: init
    init(hostUrl: String, mteHelper: MteHelper, uploadId: UUID) {
        self.uploadId = uploadId
        self.hostUrl = hostUrl
        self.mteHelper = mteHelper
    }
    
    deinit {
        logger.info("Destroying FileStreamUpload class\n")
        
    }
    
    // MARK: Class variables
    private let logger = PackageLogger.makeLogger(for: FileStreamUpload.self)
    weak var relayStreamCompletionDelegate: RelayStreamCompletionDelegate?
    weak var relayStreamDelegate: RelayStreamDelegate?
    weak var fileUploadResultDelegate: FileUploadResultDelegate?
    weak var mteHelper: MteHelper!
    var hostUrl: String!
    var pairId: String!
    var originalContentLength = 0
    var relayContentLength = 0
    var encryptedByteCount = 0
    var fileBuffer = [UInt8](repeating: 0, count: Settings.streamChunkSize)
    var uploadState: UploadState = .notStarted
    var uploadId: UUID!
    /// The binary frame preamble (header + encoded metadata) written to the
    /// network stream before the first encrypted body chunk.
    private var framePreamble: [UInt8] = []
    
    private var session: URLSession?
    private lazy var encryptorActor = EncryptorActor(parent: self)
    private var responseBuffer = Data()
    
    var startTime: Date!
    var endTime: Date!
    
    enum UploadState {
        case notStarted
        case getFileStarted
        case allBytesUploading
        case encryptInProgress
        case encryptFinished
        case uploadInProgress
        case uploadComplete
    }
    
    // MARK: Bound Streams
    struct FileBoundStreams {
        var input: InputStream
        var output: OutputStream
    }
    
    // Single lazy property to initialize bound streams and proxy
    private lazy var fileBoundStreams: FileBoundStreams = {
        var inputOrNil: InputStream? = nil
        var outputOrNil: OutputStream? = nil
        
        // Set up bound streams
        Stream.getBoundStreams(withBufferSize: Settings.streamChunkSize,
                               inputStream: &inputOrNil,
                               outputStream: &outputOrNil)
        guard let input = inputOrNil, let output = outputOrNil else {
            fatalError("Failed to create bound streams.")
        }
        
        // Create proxy delegate to avoid retain cycle
        proxy = StreamDelegateProxy(target: self)
        
        // Configure output stream with the proxy
        output.delegate = proxy
        output.schedule(in: .current, forMode: .default)
        output.open()
        
        input.delegate = proxy
        input.schedule(in: .main, forMode: .default)
        input.open()
        
        return FileBoundStreams(input: input, output: output)
    }()
    
    private var proxy: StreamDelegateProxy?  // Retain proxy for later cleanup
    
    private func cleanupFileBoundStreams() {
        
        // Ensure fileBoundStreams are initialized
        let streams = fileBoundStreams
        
        // Close and remove streams
        streams.input.close()
        streams.input.remove(from: .current, forMode: .default)
        
        streams.output.close()
        streams.output.remove(from: .main, forMode: .default)
        
        // Release references to allow deinitialization
        proxy = nil  // Break retain cycle by clearing proxy reference
    }
    
    
    struct NetworkBoundStreams {
        let input: InputStream
        let output: OutputStream
    }
    
    lazy var networkBoundStreams: NetworkBoundStreams = {
        var inputOrNil: InputStream? = nil
        var outputOrNil: OutputStream? = nil
        Stream.getBoundStreams(withBufferSize: Settings.streamChunkSize,
                               inputStream: &inputOrNil,
                               outputStream: &outputOrNil)
        guard let input = inputOrNil, let output = outputOrNil else {
            fatalError("On return of `getBoundStreams`, both `inputStream` and `outputStream` will contain non-nil streams.")
        }
        // configure and open output stream
        output.delegate = self
        output.schedule(in: .current, forMode: .default)
        output.open()
        return NetworkBoundStreams(input: input, output: output)
    }()
    
    private func cleanupNetworkBoundStreams() {
        
        // Ensure networkBoundStreams are initialized
        let streams = networkBoundStreams
        
        // Close and remove streams
        streams.input.close()
        streams.input.remove(from: .current, forMode: .default)
        
        streams.output.close()
        streams.output.remove(from: .current, forMode: .default)
        
    }
    
    // MARK: Public Functions
    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    /// Starts a true chunked-streaming upload using the binary frame protocol.
    ///
    /// The `plan` is produced by `RelayRequestBuilder.prepareStreamingRequest`
    /// and contains the pre-built frame preamble and the pairId that was
    /// acquired when the request metadata was encoded.  This method:
    ///  1. Initialises MKE streaming encrypt on the already-acquired pair.
    ///  2. Writes the binary frame preamble into the network pipe so it
    ///     arrives at the server before any encrypted body bytes.
    ///  3. Kicks off the URLSession streamed upload task.
    ///  4. Signals the app delegate to start writing file bytes.
    func uploadStream(plan: RelayStreamingPlan) async throws {
        self.pairId        = plan.pairId
        self.framePreamble = plan.framePreamble
        originalContentLength = plan.originalContentLength

        guard originalContentLength > 0 else {
            let msg = "uploadStream requires a positive Content-Length in the request"
            logger.error("\(msg)")
            throw msg.relayError
        }

        let finishBytes   = mteHelper.getFinishEncryptBytes(pairId: pairId)
        relayContentLength = framePreamble.count + originalContentLength + finishBytes

        // Initialise MKE streaming encrypt for the body.
        _ = try await mteHelper.startEncrypt(pairId: pairId)

        // Force the lazy networkBoundStreams initialiser to run (opens streams,
        // registers delegate) then synchronously write the frame preamble into
        // the pipe buffer.  The preamble is small (<1 KB) so it fits within the
        // bound-stream buffer without blocking.
        _ = writeToOutputStream(outputStream: networkBoundStreams.output,
                                buffer: Data(framePreamble))

        var relayRequest = URLRequest(url: plan.proxyURL)
        relayRequest.httpMethod = RelayMethod.POST
        relayRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        relayRequest.setValue(String(relayContentLength), forHTTPHeaderField: "Content-Length")

        uploadState = .encryptInProgress
        startTime   = Date()

        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session?.uploadTask(withStreamedRequest: relayRequest).resume()
        getFileStream()
    }
    
    // MARK: Stream Delegate Methods
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {

        switch eventCode {
        case .hasBytesAvailable, .hasSpaceAvailable:
            Task {
                await encryptorActor.signalEncryptChunk()
            }
        case .errorOccurred:
            logger.error("Error occurred. Closing Streams")
            reportAndCleanup(data: nil,
                             response: nil,
                             error: "File upload failed. NetworkBoundStream returned error.".relayError)
        default:
            return
        }

    }
    
    func encryptChunk() async throws {
        if uploadState == .encryptInProgress {
            if fileBoundStreams.input.hasBytesAvailable {
                let bytesRead = fileBoundStreams.input.read(&fileBuffer, maxLength: Settings.streamChunkSize)
                if bytesRead > 0 {
                    var bufferToEncrypt = Array(fileBuffer.prefix(bytesRead))
                    _ = try await self.mteHelper.encryptChunk(pairId: self.pairId, buffer: &bufferToEncrypt)
                    let bytesWritten = writeToOutputStream(outputStream: networkBoundStreams.output, buffer: Data(bufferToEncrypt))
                    encryptedByteCount += bytesWritten
                    if allBytesEncrypted() {
                        try await finishEncrypt()
                    }
                }
            }
        }
    }
    
    func finishEncrypt() async throws {
        if networkBoundStreams.output.hasSpaceAvailable {
            uploadState = .encryptFinished
            let finishEncryptResult = try await self.mteHelper.finishEncrypt(pairId: self.pairId)
            let bytesWritten = writeToOutputStream(outputStream: networkBoundStreams.output, buffer: Data(finishEncryptResult.encodedBytes))
            self.encryptedByteCount += bytesWritten
            uploadState = .uploadComplete

            let ending = Date()
            let duration = ending.timeIntervalSince(self.startTime)
            logger.info("Finished reading and encrypting \(self.encryptedByteCount) bytes in \(String(format: "%.3f", duration * 1000)) milliseconds")

            self.networkBoundStreams.output.close()
        }
    }
    
    func allBytesEncrypted() -> Bool {
        self.relayStreamCompletionDelegate?.streamCompletionPercentage(from: hostUrl, bytesCompleted: Double(encryptedByteCount),
                                                                       totalBytes: Double(originalContentLength))
        if encryptedByteCount == originalContentLength {
            cleanupFileBoundStreams()
            return true
        }
        return false
    }
    
    func writeToOutputStream(outputStream: OutputStream, buffer: Data) -> Int {
        var bytesLeft = buffer.count
        var totalBytesWritten = 0
        
        while bytesLeft > 0 {
            // Calculate the range of data to write
            let range = totalBytesWritten..<totalBytesWritten + bytesLeft
            let chunk = buffer.subdata(in: range)
            
            // Write data to the output stream
            let bytesWritten = chunk.withUnsafeBytes { outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: bytesLeft) }
            
            // Check for errors
            if bytesWritten < 0 {
                if let streamError = outputStream.streamError {
                    reportAndCleanup(data: nil,
                                     response: nil,
                                     error: "writeToOutputStream failed. Error: \(streamError.localizedDescription)".relayError)
                }
                break
            }
            
            // Update counters
            totalBytesWritten += bytesWritten
            bytesLeft -= bytesWritten
        }
        return totalBytesWritten
    }
    
    // Attach networkBoundStream.input to URLSession.dataTask
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    needNewBodyStream completionHandler: @escaping (InputStream?) -> Void) {
        completionHandler(networkBoundStreams.input)
    }
    
    // Per-chunk upload progress: trace only. This fires for every chunk, so it
    // must never log at info — the aggregate is logged once on completion below.
    // See dev_docs/LOGGING_CONVENTION.md §1.
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        logger.trace("Bytes sent: \(bytesSent), total: \(totalBytesSent)/\(totalBytesExpectedToSend)")
    }
    
    // Called when upload is complete to get the http response
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        Task {
            // Access the HTTP response
            if let relayResponse = response as? HTTPURLResponse {
                logger.info("Upload of \(self.relayContentLength) bytes completed.")
                logger.info("FileUpload Response Code: \(relayResponse.statusCode)")
                completionHandler(.allow)
            }
        }
    }
    
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseBuffer.append(data)
        logger.info("Received response of: \(data.count) bytes")
        endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        logger.info("File upload and response received in \(String(format: "%.3f", duration * 1000)) milliseconds")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            reportAndCleanup(data: nil, response: task.response, error: error)
            return
        }

        guard let relayResponse = task.response as? HTTPURLResponse else {
            reportAndCleanup(data: nil,
                             response: task.response,
                             error: RelayClientError.invalidRelayResponse)
            return
        }

        if 200...226 ~= relayResponse.statusCode {
            processResponse(relayResponse, responseBuffer)
        } else {
            reportAndCleanup(data: nil,
                             response: relayResponse,
                             error: String(relayResponse.statusCode).relayError)
        }
    }
    
    //MARK: Private functions
    private func getFileStream() {
        DispatchQueue.global().async {
            self.fileBoundStreams.input.open()
            self.relayStreamDelegate?.getRequestBodyStream(outputStream: self.fileBoundStreams.output)
        }
    }
    
    fileprivate func processResponse(_ relayResponse: HTTPURLResponse, _ data: Data) {
        do {
            // The relay server now returns a binary frame for every response.
            // RelayResponseDecoder handles frame parsing, header decryption,
            // and body decryption in one step — the same path as dataTask.
            let responseDecoder = RelayResponseDecoder()
            let (decodedData, appResponse) = try responseDecoder.decode(
                relayResponse: relayResponse,
                relayPayload: data,
                fallbackURL: relayResponse.url!,
                requestPairId: pairId,
                mteHelper: mteHelper
            )
            reportAndCleanup(data: decodedData, response: appResponse, error: nil)
        } catch {
            reportAndCleanup(data: nil, response: nil, error: error)
        }
    }
    
    private var didCleanup = false
    func reportAndCleanup(data: Data?, response: URLResponse?, error: Error?) {
        if error != nil {
            logger.error("\(error?.localizedDescription ?? "Unknown error")")
        }
        guard !didCleanup else { return }
        didCleanup = true

        fileUploadResultDelegate?.fileUploadResult(data: data,
                                                   response: response,
                                                   error: error,
                                                   uploadId: uploadId,
                                                   pairId: pairId)
        session?.finishTasksAndInvalidate()
        session = nil
        cleanupFileBoundStreams()
        cleanupNetworkBoundStreams()
        relayStreamDelegate = nil
        relayStreamCompletionDelegate = nil
        fileUploadResultDelegate = nil
        mteHelper = nil
        fileBuffer = []
        responseBuffer = Data()
        pairId = nil
        hostUrl = nil
        uploadId = nil
    }
}
