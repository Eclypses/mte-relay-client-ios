import Foundation

public struct RelayServerSentEventOpenResult {
    public let streamId: UUID
    public let response: URLResponse

    public init(streamId: UUID, response: URLResponse) {
        self.streamId = streamId
        self.response = response
    }
}