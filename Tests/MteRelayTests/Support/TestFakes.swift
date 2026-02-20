import Foundation
@testable import MteRelay

final class RecordingRelayResponseDelegate: RelayResponseDelegate {
    var shouldDropCallbacks = false
    private(set) var callCount = 0
    private(set) var capturedArguments: [(success: Bool, response: String, error: String?)] = []
    private(set) var callHistory: [String] = []

    func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        guard !shouldDropCallbacks else { return }
        callCount += 1
        capturedArguments.append((success, responseStr, errorMessage))
        callHistory.append("relayResponse")
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

final class RelayCallbackBridge {
    weak var responseDelegate: RelayResponseDelegate?
    weak var streamCompletionDelegate: RelayStreamCompletionDelegate?

    private(set) var callHistory: [String] = []
    var shouldEmitErrorEvent = false

    func emitResponse(success: Bool, response: String, error: String?) {
        callHistory.append("emitResponse")
        responseDelegate?.relayResponse(success: success, responseStr: response, errorMessage: error)
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
