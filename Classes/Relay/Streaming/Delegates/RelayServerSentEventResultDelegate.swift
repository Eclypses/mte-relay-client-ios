import Foundation

protocol RelayServerSentEventResultDelegate: AnyObject {
    func relayServerSentEventOpened(response: URLResponse, streamId: UUID)
    func relayServerSentEventData(_ data: Data, streamId: UUID)
    func relayServerSentEventCompleted(response: URLResponse?,
                                       error: Error?,
                                       streamId: UUID,
                                       pairId: String?,
                                       didDeliverData: Bool)
}