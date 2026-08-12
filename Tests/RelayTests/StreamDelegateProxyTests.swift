import XCTest
@testable import Relay

final class StreamDelegateProxyTests: XCTestCase {
    func testStreamDelegateProxyForwardsOrderedEvents() {
        let target = RecordingStreamDelegateTarget()
        let proxy = StreamDelegateProxy(target: target)
        let inputStream = InputStream(data: TestFixtures.smallBinaryPayload)

        let events: [Stream.Event] = [.openCompleted, .hasBytesAvailable, .hasSpaceAvailable, .endEncountered]
        events.forEach { proxy.stream(inputStream, handle: $0) }

        XCTAssertEqual(target.callCount, events.count)
        XCTAssertEqual(target.events, events)
        XCTAssertEqual(target.callHistory.count, events.count)
    }

    func testStreamDelegateProxyHonorsDropToggleAndLifecycleReset() {
        let target = RecordingStreamDelegateTarget()
        let proxy = StreamDelegateProxy(target: target)
        let inputStream = InputStream(data: TestFixtures.smallBinaryPayload)

        target.shouldDropEvents = true
        proxy.stream(inputStream, handle: .errorOccurred)
        XCTAssertEqual(target.callCount, 0)

        target.reset()
        proxy.stream(inputStream, handle: .errorOccurred)
        XCTAssertEqual(target.callCount, 1)

        target.dispose()
        XCTAssertEqual(target.callCount, 0)
    }

    func testRelayStreamDelegateFakeCapturesBytesAndFailureSimulation() {
        let fake = RecordingRelayStreamDelegate()
        let outputStream = OutputStream.toMemory()
        outputStream.open()
        defer { outputStream.close() }

        fake.getRequestBodyStream(outputStream: outputStream)
        XCTAssertEqual(fake.callCount, 1)
        XCTAssertEqual(fake.capturedBytesWritten.first, TestFixtures.smallBinaryPayload.count)

        fake.shouldSimulateFailure = true
        fake.getRequestBodyStream(outputStream: outputStream)
        XCTAssertEqual(fake.callCount, 2)
        XCTAssertEqual(fake.capturedBytesWritten.last, 0)
    }
}
