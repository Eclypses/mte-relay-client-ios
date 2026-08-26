import XCTest
@testable import Relay

/// The invariant that matters: `contentLength` must equal the bytes actually
/// written. `uploadFileStream` requires Content-Length to match the unencrypted
/// body, and a mismatch is the documented failure mode.
final class RelayMultipartWriterTests: XCTestCase {

    private func makeTempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpw-\(UUID().uuidString).bin")
        try Data((0..<bytes).map { UInt8($0 % 251) }).write(to: url)
        return url
    }

    /// Drains everything written so the total can be compared against contentLength.
    private func drain(_ writer: RelayMultipartWriter) throws -> Data {
        let output = OutputStream.toMemory()
        output.open()
        defer { output.close() }
        try writer.write(to: output)
        return output.property(forKey: .dataWrittenToMemoryStreamKey) as? Data ?? Data()
    }

    func testContentLengthMatchesBytesWritten() throws {
        for size in [0, 1, 64 * 1024 - 1, 64 * 1024, 64 * 1024 + 1, 200_000] {
            let url = try makeTempFile(bytes: size)
            defer { try? FileManager.default.removeItem(at: url) }

            let writer = try RelayMultipartWriter(fileURL: url)
            let written = try drain(writer)

            XCTAssertEqual(writer.contentLength, written.count,
                           "contentLength disagreed with bytes written for a \(size)-byte file")
        }
    }

    func testBodyFramesTheFileBetweenBoundaries() throws {
        let url = try makeTempFile(bytes: 32)
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try RelayMultipartWriter(fileURL: url, fieldName: "upload", fileName: "payload.bin")
        let body = try drain(writer)
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("--\(writer.boundary)\r\n"))
        XCTAssertTrue(text.contains(#"name="upload"; filename="payload.bin""#))
        XCTAssertTrue(text.hasSuffix("\r\n--\(writer.boundary)--\r\n"))
        XCTAssertEqual(writer.contentType, "multipart/form-data; boundary=\(writer.boundary)")
    }

    func testFileContentSurvivesChunking() throws {
        // Larger than one chunk, so the loop runs more than once.
        let size = 64 * 1024 + 777
        let url = try makeTempFile(bytes: size)
        defer { try? FileManager.default.removeItem(at: url) }

        let original = try Data(contentsOf: url)
        let writer = try RelayMultipartWriter(fileURL: url, chunkSize: 4096)
        let body = try drain(writer)

        // The file bytes sit between the framing: everything after the prefix and
        // before the closing boundary must be the original, byte for byte.
        let postfixLength = "\r\n--\(writer.boundary)--\r\n".utf8.count
        let fileStart = body.count - postfixLength - original.count
        let extracted = body.subdata(in: fileStart..<(fileStart + original.count))
        XCTAssertEqual(extracted, original, "file bytes were corrupted or reordered by chunking")
    }

    func testMissingFileThrows() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).bin")
        XCTAssertThrowsError(try RelayMultipartWriter(fileURL: missing))
    }

    func testBoundariesAreUnique() throws {
        let url = try makeTempFile(bytes: 8)
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try RelayMultipartWriter(fileURL: url)
        let b = try RelayMultipartWriter(fileURL: url)
        XCTAssertNotEqual(a.boundary, b.boundary)
    }
}
