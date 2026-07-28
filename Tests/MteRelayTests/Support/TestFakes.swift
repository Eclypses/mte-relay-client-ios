import Foundation
@testable import MteRelay

struct NoopRelayHTTPClient: RelayHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url ?? URL(string: "https://example.invalid")!,
                                       statusCode: 200,
                                       httpVersion: nil,
                                       headerFields: nil)!
        return (Data(), response)
    }
}

final class RecordingRelayResponseDelegate: RelayStreamResponseDelegate {
    var shouldDropCallbacks = false
    private(set) var callCount = 0
    private(set) var capturedArguments: [(from: String, data: Data?, response: URLResponse?, error: Error?)] = []
    private(set) var callHistory: [String] = []

    func relayStreamResponse(from relayServerUrl: String, data: Data?, response: URLResponse?, error: Error?) {
        guard !shouldDropCallbacks else { return }
        callCount += 1
        capturedArguments.append((relayServerUrl, data, response, error))
        callHistory.append("relayStreamResponse")
    }

    func reset() {
        shouldDropCallbacks = false
        callCount = 0
        capturedArguments.removeAll()
        callHistory.removeAll()
    }

    func dispose() { reset() }
}

final class RecordingRelayStreamDelegate: RelayStreamDelegate {
    var shouldSimulateFailure = false
    private(set) var callCount = 0
    private(set) var capturedBytesWritten: [Int] = []
    private(set) var callHistory: [String] = []

    func getRequestBodyStream(outputStream: OutputStream) {
        callCount += 1
        callHistory.append("getRequestBodyStream")

        guard !shouldSimulateFailure else {
            capturedBytesWritten.append(0)
            return
        }

        let payload = TestFixtures.smallBinaryPayload
        let written = payload.withUnsafeBytes {
            outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: payload.count)
        }
        capturedBytesWritten.append(max(written, 0))
    }

    func reset() {
        shouldSimulateFailure = false
        callCount = 0
        capturedBytesWritten.removeAll()
        callHistory.removeAll()
    }

    func dispose() { reset() }
}

final class RecordingRelayStreamCompletionDelegate: RelayStreamCompletionDelegate {
    private(set) var callCount = 0
    private(set) var captured: [(from: String, bytesCompleted: Double, totalBytes: Double)] = []
    private(set) var callHistory: [String] = []

    func streamCompletionPercentage(from relayServerUrl: String, bytesCompleted: Double, totalBytes: Double) {
        callCount += 1
        captured.append((relayServerUrl, bytesCompleted, totalBytes))
        callHistory.append("streamCompletionPercentage")
    }

    func reset() {
        callCount = 0
        captured.removeAll()
        callHistory.removeAll()
    }

    func dispose() { reset() }
}

final class RecordingRelayServerSentEventDelegate: RelayServerSentEventDelegate {
    private(set) var responseCallCount = 0
    private(set) var dataCallCount = 0
    private(set) var completionCallCount = 0
    private(set) var responses: [(from: String, streamId: UUID, response: URLResponse)] = []
    private(set) var dataEvents: [(from: String, streamId: UUID, data: Data)] = []
    private(set) var completions: [(from: String, streamId: UUID, response: URLResponse?)] = []
    private(set) var callHistory: [String] = []

    func relayServerSentEventDidReceiveResponse(from relayServerUrl: String, streamId: UUID, response: URLResponse) {
        responseCallCount += 1
        responses.append((relayServerUrl, streamId, response))
        callHistory.append("relayServerSentEventDidReceiveResponse")
    }

    func relayServerSentEventDidReceiveData(from relayServerUrl: String, streamId: UUID, data: Data) {
        dataCallCount += 1
        dataEvents.append((relayServerUrl, streamId, data))
        callHistory.append("relayServerSentEventDidReceiveData")
    }

    func relayServerSentEventDidComplete(from relayServerUrl: String, streamId: UUID, response: URLResponse?) {
        completionCallCount += 1
        completions.append((relayServerUrl, streamId, response))
        callHistory.append("relayServerSentEventDidComplete")
    }

    func reset() {
        responseCallCount = 0
        dataCallCount = 0
        completionCallCount = 0
        responses.removeAll()
        dataEvents.removeAll()
        completions.removeAll()
        callHistory.removeAll()
    }

    func dispose() { reset() }
}

final class RelayCallbackBridge {
    weak var responseDelegate: RelayStreamResponseDelegate?
    weak var streamCompletionDelegate: RelayStreamCompletionDelegate?

    private(set) var callHistory: [String] = []
    var shouldEmitErrorEvent = false

    func emitResponse(success: Bool, response: String, error: String?) {
        callHistory.append("emitResponse")
        let data = response.data(using: .utf8)
        responseDelegate?.relayStreamResponse(from: TestFixtures.endpoint,
                                              data: data,
                                              response: nil,
                                              error: error.map { NSError(domain: "RelayCallbackBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: $0]) })
    }

    func emitStreamCompletion(from url: String, bytesCompleted: Double, totalBytes: Double) {
        callHistory.append("emitStreamCompletion")
        streamCompletionDelegate?.streamCompletionPercentage(from: url, bytesCompleted: bytesCompleted, totalBytes: totalBytes)
    }

    func simulateBurst(count: Int) {
        for index in 0..<count {
            if shouldEmitErrorEvent && index % 2 == 1 {
                emitResponse(success: false, response: "", error: "simulated-")
            } else {
                emitResponse(success: true, response: "ok-\(index)", error: nil)
            }
        }
    }

    func reset() {
        shouldEmitErrorEvent = false
        callHistory.removeAll()
    }

    func dispose() { reset() }
}

final class RelayServerSentEventCallbackBridge {
    weak var delegate: RelayServerSentEventDelegate?

    private(set) var callHistory: [String] = []

    func emitResponse(from relayServerUrl: String, streamId: UUID, response: URLResponse) {
        callHistory.append("emitResponse")
        delegate?.relayServerSentEventDidReceiveResponse(from: relayServerUrl,
                                                         streamId: streamId,
                                                         response: response)
    }

    func emitData(from relayServerUrl: String, streamId: UUID, text: String) {
        callHistory.append("emitData")
        delegate?.relayServerSentEventDidReceiveData(from: relayServerUrl,
                                                     streamId: streamId,
                                                     data: Data(text.utf8))
    }

    func emitCompletion(from relayServerUrl: String, streamId: UUID, response: URLResponse?) {
        callHistory.append("emitCompletion")
        delegate?.relayServerSentEventDidComplete(from: relayServerUrl,
                                                  streamId: streamId,
                                                  response: response)
    }

    func reset() {
        callHistory.removeAll()
    }

    func dispose() { reset() }
}

final class RecordingStreamDelegateTarget: NSObject, StreamDelegate {
    var shouldDropEvents = false
    private(set) var callCount = 0
    private(set) var events: [Stream.Event] = []
    private(set) var callHistory: [String] = []

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard !shouldDropEvents else { return }
        callCount += 1
        events.append(eventCode)
        callHistory.append("stream.handle")
    }

    func reset() {
        shouldDropEvents = false
        callCount = 0
        events.removeAll()
        callHistory.removeAll()
    }

    func dispose() { reset() }
}
