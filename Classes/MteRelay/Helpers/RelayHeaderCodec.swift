import Foundation

struct RelayOptions {
    var clientId: String
    var pairId: String
    var encodeType: String
    var urlIsEncoded: Bool
    var headersAreEncoded: Bool
    var bodyIsEncoded: Bool
    var preventStreaming: Bool = false
}

func formatMteRelayHeader(options: RelayOptions) -> String {
    var args = [String]()
    args.append(options.clientId)
    args.append(options.pairId)
    args.append(options.encodeType == "MTE" ? "0" : "1")
    args.append(options.urlIsEncoded ? "1" : "0")
    args.append(options.headersAreEncoded ? "1" : "0")
    args.append(options.bodyIsEncoded ? "1" : "0")
    args.append(options.preventStreaming ? "1" : "0")

    return args.joined(separator: ",")
}

func parseMteRelayHeader(header: String) -> RelayOptions? {
    let args = header.split(separator: ",").map { String($0) }

    guard args.count > 0 else {
        return nil
    }

    if args.count > 1 {
        return RelayOptions(clientId: args[0],
                            pairId: args[1],
                            encodeType: args[2] == "0" ? "MTE" : "MKE",
                            urlIsEncoded: args[3] == "1",
                            headersAreEncoded: args[4] == "1",
                            bodyIsEncoded: args[5] == "1",
                            preventStreaming: args[6] == "1")
    } else {
        return RelayOptions(clientId: args[0],
                            pairId: "",
                            encodeType: "",
                            urlIsEncoded: false,
                            headersAreEncoded: false,
                            bodyIsEncoded: false,
                            preventStreaming: false)
    }
}

enum EncoderType: String {
    case MTE = "MTE"
    case MKE = "MKE"
}
