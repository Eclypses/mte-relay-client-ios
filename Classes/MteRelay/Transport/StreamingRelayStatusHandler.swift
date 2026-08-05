import Foundation

enum StreamingRelayStatusAction: Equatable {
    case replacePair
    case fullRepair
    case releasePair
}

struct StreamingRelayStatusContext {
    let statusCode: Int
    let disposition: RelayStatusRecoveryDisposition
    let message: String?
}

struct StreamingRelayStatusHandler {
    func handle(context: StreamingRelayStatusContext,
                replacePair: @escaping @Sendable (Int) async -> RelayClientError,
                performFullRepair: @escaping @Sendable (Int) async -> RelayClientError,
                releasePair: @escaping @Sendable () async -> Void) async -> RelayClientError {
        switch context.disposition {
        case .perPairReplacement:
            return await replacePair(context.statusCode)
        case .fullRepair:
            return await performFullRepair(context.statusCode)
        case .transientBackoff:
            await releasePair()
            try? await Task.sleep(nanoseconds: HostRepairCoordinator.transientBackoffNanoseconds)
            return .relayStatus(context.statusCode, context.message)
        case .surfaceOnly:
            await releasePair()
            return .relayStatus(context.statusCode, context.message)
        }
    }
}