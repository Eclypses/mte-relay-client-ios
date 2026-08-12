import Foundation

enum RelayStatusRecoveryDisposition: Equatable {
    case perPairReplacement
    case fullRepair
    case transientBackoff
    case surfaceOnly
}

struct HostRepairCoordinator {
    static let transientBackoffNanoseconds: UInt64 = 75_000_000

    func recoveryDisposition(for statusCode: Int) -> RelayStatusRecoveryDisposition? {
        switch statusCode {
        case 559...563:
            return .perPairReplacement
        case 564:
            return .fullRepair
        case 565:
            return .transientBackoff
        case 566...569:
            return .surfaceOnly
        default:
            return nil
        }
    }

    func shouldAttemptRepair(statusCode: Int) -> Bool {
        PairingHelper.checkForRePair(statusCode: String(statusCode))
    }

    func handleNonStreamingRepair(statusCode: Int,
                                  retryAvailable: inout Bool,
                                  invalidateClientSession: @escaping @Sendable () async -> Void,
                                  repair: @escaping @Sendable () async throws -> Void) async throws -> Bool {
        guard shouldAttemptRepair(statusCode: statusCode) else {
            return false
        }

        guard retryAvailable else {
            throw RelayClientError.networkFailure
        }

        await invalidateClientSession()
        try await repair()
        retryAvailable = false
        return true
    }

    func handleStreamingRepair(statusCode: Int,
                               hasPendingTask: Bool,
                               invalidateClientSession: @escaping @Sendable () async -> Void,
                               repair: @escaping @Sendable () async throws -> Void) async throws -> Bool {
        guard hasPendingTask, shouldAttemptRepair(statusCode: statusCode) else {
            return false
        }

        await invalidateClientSession()
        try await repair()
        return true
    }
}
