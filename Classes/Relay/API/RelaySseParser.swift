import Foundation

/// An **opt-in** `text/event-stream` parser.
///
/// The relay transport deliberately does not parse SSE: `request(with:)` yields the decrypted body
/// bytes exactly as the server sent them, because that is what `URLSession` would have handed you
/// without the relay. A caller streaming events therefore keeps whatever parser they already use.
///
/// This type exists for callers who *don't* already have one — it is never used by the transport.
///
/// ```swift
/// var parser = RelaySseParser()
/// for try await event in relay.request(with: request) {
///     guard case .chunk(let data) = event else { continue }
///     for sseEvent in parser.append(data) {
///         print(sseEvent.id ?? "-", sseEvent.event ?? "message", sseEvent.data)
///     }
/// }
/// for sseEvent in parser.finish() { … }   // flush a trailing event at end of stream
/// ```
public struct RelaySseParser {

    /// One dispatched server-sent event. Unlike the parsers this replaces, `id`, `event`, and
    /// `retry` survive — a reconnecting consumer needs `id` for `Last-Event-ID`, and typed
    /// consumers dispatch on `event`.
    public struct Event: Equatable {
        public let data: String
        public let id: String?
        public let event: String?
        public let retry: Int?
    }

    private var buffer: [UInt8] = []
    private var pendingData: [String] = []
    private var pendingId: String?
    private var pendingEvent: String?
    private var pendingRetry: Int?

    public init() {}

    /// Feeds a chunk of raw bytes and returns every event completed by it. A chunk may split a line
    /// (relay chunk boundaries are MKE-chunk boundaries — just as TCP reads split lines without the
    /// relay), so an incomplete tail is carried over to the next call.
    public mutating func append(_ chunk: Data) -> [Event] {
        buffer.append(contentsOf: chunk)
        var events: [Event] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineBytes = Array(buffer[0..<newlineIndex])
            buffer.removeSubrange(0...newlineIndex)
            process(line: decode(lineBytes), into: &events)
        }
        return events
    }

    /// Flushes a trailing line and any event still pending at end of stream.
    public mutating func finish() -> [Event] {
        var events: [Event] = []
        if !buffer.isEmpty {
            let lineBytes = buffer
            buffer.removeAll()
            process(line: decode(lineBytes), into: &events)
        }
        dispatch(into: &events)
        return events
    }

    private func decode(_ bytes: [UInt8]) -> String {
        var b = bytes
        if b.last == 0x0D { b.removeLast() }  // strip a trailing CR
        return String(decoding: b, as: UTF8.self)
    }

    private mutating func process(line: String, into events: inout [Event]) {
        // A blank line dispatches the event accumulated so far.
        if line.isEmpty {
            dispatch(into: &events)
            return
        }
        // A leading colon marks a comment.
        if line.hasPrefix(":") { return }

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }  // one optional leading space
        } else {
            field = line
            value = ""
        }

        switch field {
        case "data":  pendingData.append(value)
        case "id":    pendingId = value
        case "event": pendingEvent = value
        case "retry": pendingRetry = Int(value)
        default:      break  // unknown fields are ignored, per the SSE spec
        }
    }

    private mutating func dispatch(into events: inout [Event]) {
        guard !pendingData.isEmpty else {
            pendingEvent = nil
            return
        }
        events.append(
            Event(
                data: pendingData.joined(separator: "\n"),
                id: pendingId,
                event: pendingEvent,
                retry: pendingRetry
            )
        )
        pendingData.removeAll()
        pendingEvent = nil
        // `id` and `retry` persist across events, per the SSE spec.
    }
}
