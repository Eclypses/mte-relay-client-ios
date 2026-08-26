import Foundation

/// An **opt-in** `multipart/form-data` writer for streamed file uploads.
///
/// `uploadFileStream(request:…)` hands your `relayStreamDelegate` an `OutputStream`
/// and chunks and encrypts whatever you write to it. What that body *contains* is
/// yours to decide — exactly as it would be without the relay, since `URLSession`
/// would also have required you to build it. The relay imposes no body format.
///
/// This type exists for callers uploading to an endpoint that expects
/// `multipart/form-data` and who don't already have a writer for it — it is never
/// used by the transport.
///
/// It owns the boundary, the framing, and the content length together, because
/// they have to agree: `uploadFileStream` requires a `Content-Length` equal to the
/// total **unencrypted** body, and that total includes the multipart framing, not
/// just the file. Computing it separately from the framing is the usual way this
/// goes wrong.
///
/// The file is read incrementally and never loaded into memory in full.
///
/// ```swift
/// let writer = try RelayMultipartWriter(fileURL: fileURL)
///
/// var request = URLRequest(url: uploadURL)
/// request.httpMethod = "POST"
/// request.setValue(writer.contentType, forHTTPHeaderField: "Content-Type")
/// request.setValue(String(writer.contentLength), forHTTPHeaderField: "Content-Length")
///
/// relay.relayStreamDelegate = self          // your delegate
/// let (data, response) = try await relay.uploadFileStream(request: request)
///
/// // in your RelayStreamDelegate:
/// func getRequestBodyStream(outputStream: OutputStream) {
///     try? writer.write(to: outputStream)
/// }
/// ```
public struct RelayMultipartWriter {

    /// Errors specific to assembling the multipart body.
    public enum WriterError: LocalizedError {
        case fileNotFound(URL)
        case fileNotReadable(URL)
        case streamWriteFailed

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):    return "No file exists at \(url.path)"
            case .fileNotReadable(let url): return "Could not determine the size of \(url.path)"
            case .streamWriteFailed:        return "Writing the multipart body to the output stream failed"
            }
        }
    }

    /// The generated boundary token.
    public let boundary: String

    /// The value to set on the `Content-Type` header.
    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// The total unencrypted body size — framing plus file. Set this as
    /// `Content-Length`; `uploadFileStream` requires it and it must match.
    public let contentLength: Int

    private let fileURL: URL
    private let prefix: Data
    private let postfix: Data
    private let chunkSize: Int

    /// - Parameters:
    ///   - fileURL: the file to upload. Must exist and be readable.
    ///   - fieldName: the form field name. Defaults to `"file"`.
    ///   - fileName: the filename sent to the server. Defaults to the URL's last component.
    ///   - mimeType: defaults to `"application/octet-stream"`.
    ///   - chunkSize: bytes read from disk at a time. Defaults to 64 KB.
    public init(fileURL: URL,
                fieldName: String = "file",
                fileName: String? = nil,
                mimeType: String = "application/octet-stream",
                chunkSize: Int = 64 * 1024) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WriterError.fileNotFound(fileURL)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = (attributes?[.size] as? NSNumber)?.intValue else {
            throw WriterError.fileNotReadable(fileURL)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let name = fileName ?? fileURL.lastPathComponent

        // CRLF line endings are required by RFC 7578; LF alone breaks strict parsers.
        let prefix = Data(
            ("--\(boundary)\r\n"
             + "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(name)\"\r\n"
             + "Content-Type: \(mimeType)\r\n\r\n").utf8
        )
        let postfix = Data("\r\n--\(boundary)--\r\n".utf8)

        self.boundary = boundary
        self.fileURL = fileURL
        self.prefix = prefix
        self.postfix = postfix
        self.chunkSize = max(1, chunkSize)
        self.contentLength = prefix.count + fileSize + postfix.count
    }

    /// Writes the complete multipart body to `outputStream`, reading the file in
    /// chunks. Call this from your delegate's `getRequestBodyStream(outputStream:)`.
    ///
    /// The stream is not opened or closed here — the caller owns its lifecycle.
    public func write(to outputStream: OutputStream) throws {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw WriterError.fileNotFound(fileURL)
        }
        defer { try? handle.close() }

        try writeFully(prefix, to: outputStream)
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            try writeFully(chunk, to: outputStream)
        }
        try writeFully(postfix, to: outputStream)
    }

    /// `OutputStream.write` may accept fewer bytes than offered, so keep going
    /// until the buffer is drained.
    private func writeFully(_ data: Data, to outputStream: OutputStream) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { raw in
            guard var pointer = raw.bindMemory(to: UInt8.self).baseAddress else {
                throw WriterError.streamWriteFailed
            }
            var remaining = data.count
            while remaining > 0 {
                let written = outputStream.write(pointer, maxLength: remaining)
                guard written > 0 else { throw WriterError.streamWriteFailed }
                pointer += written
                remaining -= written
            }
        }
    }
}
