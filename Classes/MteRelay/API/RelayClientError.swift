import Foundation

public enum RelayClientError: Error, LocalizedError {
    case licenseCheckFailed
    case invalidServerURL
    case invalidRequestURL
    case invalidURLComponents
    case hostResolutionFailed
    case requestPreparationFailed
    case pairCapacityExhausted(Int)
    case encodingFailed
    case decodingFailed
    case networkFailure
    case invalidRelayResponse
    case fileWriteFailed(String)
    case operationCancelled
    case operationTimedOut(TimeInterval)
    case pairingFailed(String)
    case statePersistenceFailed(String)
    case pairReplaced(Int)
    case pairReplaceFailed(Int)
    case fullRepairSuccess(Int)
    case fullRepairCatastrophic(Int)
    case relayStatus(Int, String?)
    case serverSentEventsSetupFailed(String)
    case serverSentEventsAlreadyActive
    case serverSentEventsMalformedStream
    case serverSentEventsBufferLimitExceeded
    case logReadFailed
    case underlying(String)

    public var errorDescription: String? {
        switch self {
        case .licenseCheckFailed:
            return "MTE license check failed."
        case .invalidServerURL:
            return "Server URL is invalid."
        case .invalidRequestURL:
            return "Request URL is invalid."
        case .invalidURLComponents:
            return "Unable to create URL components."
        case .hostResolutionFailed:
            return "Unable to resolve relay host from request."
        case .requestPreparationFailed:
            return "Unable to prepare relay request."
        case .pairCapacityExhausted(let maxPairs):
            return "No relay pairs became available before the capacity wait expired. Host is saturated at \(maxPairs) pairs."
        case .encodingFailed:
            return "Unable to encode relay payload."
        case .decodingFailed:
            return "Unable to decode relay payload."
        case .networkFailure:
            return "Network request failed."
        case .invalidRelayResponse:
            return "Relay response is missing required metadata."
        case .fileWriteFailed(let path):
            return "Unable to write downloaded file to \(path)."
        case .operationCancelled:
            return "Operation was cancelled."
        case .operationTimedOut(let seconds):
            return "Operation timed out after \(seconds) seconds."
        case .pairingFailed(let reason):
            return "Pairing failed: \(reason)"
        case .statePersistenceFailed(let reason):
            return "Unable to persist MTE state: \(reason)"
        case .pairReplaced(let statusCode):
            return "Relay pair was replaced after relay status \(statusCode). Caller may retry the request."
        case .pairReplaceFailed(let statusCode):
            return "Relay pair replacement failed after relay status \(statusCode). Pool may be degraded until a later recovery succeeds."
        case .fullRepairSuccess(let statusCode):
            return "Relay full repair completed after relay status \(statusCode). Caller may retry the request."
        case .fullRepairCatastrophic(let statusCode):
            return "Relay full repair failed catastrophically after relay status \(statusCode)."
        case .relayStatus(let statusCode, let message):
            return message.map { "Relay returned status \(statusCode): \($0)" } ?? "Relay returned status \(statusCode)."
        case .serverSentEventsSetupFailed(let reason):
            return "Unable to start server-sent events: \(reason)"
        case .serverSentEventsAlreadyActive:
            return "A server-sent events stream is already active for this relay host."
        case .serverSentEventsMalformedStream:
            return "Server-sent events stream was malformed."
        case .serverSentEventsBufferLimitExceeded:
            return "Server-sent events stream exceeded the internal pending-buffer limit."
        case .logReadFailed:
            return "No log file found."
        case .underlying(let reason):
            return reason
        }
    }

    static func from(_ error: Error) -> RelayClientError {
        if let relayError = error as? RelayClientError {
            return relayError
        }
        if let legacyError = error as? MteRelayError {
            switch legacyError {
            case .updateRequestError:
                return .requestPreparationFailed
            case .mteEncodeError:
                return .encodingFailed
            case .mteDecodeError:
                return .decodingFailed
            case .networkError:
                return .networkFailure
            case .storeStateError:
                return .statePersistenceFailed("storeStateError")
            default:
                return .underlying(legacyError.localizedDescription)
            }
        }
        return .underlying(error.localizedDescription)
    }
}
