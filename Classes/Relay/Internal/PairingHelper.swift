//// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


import Foundation
import os

class PairingHelper {
    
    static let keychainService = "key"
    private static let logger = PackageLogger.makeLogger(for: PairingHelper.self)

    private struct AuthResponse: Codable {
        let clientId: String
    }

    private struct PairingRequestEnvelope: Codable {
        let clientId: String
        let pairs: [PairingRequest]
    }
    
    static func initialPairingWithHost(hostUrl: String,
                                       pairCount: Int,
                                       currentClientId: String,
                                       mteHelper: MteHelper) async throws -> String {
        let verifiedClientId = try await verifyRelayServer(hostUrl: hostUrl,
                                                           currentClientId: currentClientId)
        let pairDictionary = try mteHelper.createPairDictionary(count: pairCount)
        try await pair(hostUrl: hostUrl,
                       clientId: verifiedClientId,
                       pairDictionary: pairDictionary,
                       mteHelper: mteHelper)
        return verifiedClientId
    }
    
    static func addPair(hostUrl: String,
                        clientId: String,
                        pair: Pair,
                        mteHelper: MteHelper) async throws {
        let pairDictionary: [String: Pair] = [pair.pairId: pair]
        try await PairingHelper.pair(hostUrl: hostUrl,
                                     clientId: clientId,
                                     pairDictionary: pairDictionary,
                                     mteHelper: mteHelper)
    }

    static func addPairs(hostUrl: String,
                         clientId: String,
                         pairs: [Pair],
                         mteHelper: MteHelper) async throws {
        let pairDictionary = Dictionary(uniqueKeysWithValues: pairs.map { ($0.pairId!, $0) })
        try await PairingHelper.pair(hostUrl: hostUrl,
                                     clientId: clientId,
                                     pairDictionary: pairDictionary,
                                     mteHelper: mteHelper)
    }
    
    //MARK: Verify Relay Server
    static func verifyRelayServer(hostUrl: String,
                                  currentClientId: String) async throws -> String {
        var route = RelayRoutes.RELAY_VERIFICATION
        if !currentClientId.isEmpty {
            let encodedClientId = currentClientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? currentClientId
            route += "?clientId=\(encodedClientId)"
        }
        let connectionModel = InternalConnectionModel(url: hostUrl,
                                                      method: RelayMethod.GET,
                                                      route: route,
                                                      payload: Data(),
                                                      contentType: "application/json; charset=utf-8",
                                                      relayHeaders: RelayHeaders())
        
        // Verify this is a valid MTE Relay server and acquire a clientId
        let callResult = await PairingHelper.call(connectionModel: connectionModel)
        switch callResult {
            
        case .failure(let code, let message):
            let errorMessage = "Relay server verification failed. Error Code: \(code). Error Message: \(message)"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError

        case .success(let data, _):
            do {
                let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
                return authResponse.clientId
            } catch {
                let errorMessage = "Unable to decode relay auth response. Error: \(error.localizedDescription)"
                logger.error("\(errorMessage)")
                throw errorMessage.relayError
            }
        }
    }
    
    private static func pair(hostUrl: String,
                             clientId: String,
                             pairDictionary: [String : Pair],
                             mteHelper: MteHelper) async throws {
        var pairingRequestArray = [PairingRequest]()
        for pair in pairDictionary {
            let pairKeys = PairingRequest(
                pairId: pair.key,
                encoderPublicKey: bytesToB64Str(publicKey: &pair.value.encMyPublicKey),
                encoderPersonalizationStr: pair.value.encPersStr,
                decoderPublicKey: bytesToB64Str(publicKey: &pair.value.decMyPublicKey),
                decoderPersonalizationStr: pair.value.decPersStr)
            pairingRequestArray.append(pairKeys)
        }
        let envelope = PairingRequestEnvelope(clientId: clientId,
                              pairs: pairingRequestArray)
        let payload = try JSONEncoder().encode(envelope)
        let connectionModel = InternalConnectionModel(url: hostUrl,
                                                           method:  RelayMethod.POST,
                                                           route: RelayRoutes.PAIRING,
                                                           payload: payload,
                                                           contentType: "application/json; charset=utf-8",
                                                           relayHeaders: RelayHeaders())
        // Make pairing call
        let callResult = await PairingHelper.call(connectionModel: connectionModel)
        switch callResult {
            
        case .failure(let code, let message):
            let errorMessage = "Pairing Request returned failure. Error Code: \(code). Error Message: \(message)"
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
            
        case .success(let data, _):
            logger.info("Pairing request with \(hostUrl) was successful! ClientId is \(clientId)")
            do {
                let response = try JSONDecoder().decode([PairingResponse].self, from: data)
                for p in response {
                    guard let pair = pairDictionary[p.pairId] else {
                        logger.error("Pair not found in Response")
                        return
                    }
                    logger.info("Server returned Pair Id \(pair.pairId!)")
                    pair.encPeerEncryptedSecret = b64StrToBytes(publicKeyStr: p.decoderSecret)
                    pair.encNonce = UInt64(p.decoderNonce)! & 0x7FFFFFFFFFFFFFFF
                    pair.decPeerEncryptedSecret = b64StrToBytes(publicKeyStr: p.encoderSecret)
                    pair.decNonce = UInt64(p.encoderNonce)! & 0x7FFFFFFFFFFFFFFF
                    try pair.createEncoderAndDecoder()
                }
            } catch {
                let errorMessage = "Pairing Request Error: \(error.localizedDescription)"
                logger.error("\(errorMessage)")
                throw errorMessage.relayError
            }
        }
    }
    
    private static func bytesToB64Str(publicKey: inout [UInt8]) -> String {
        return Data(publicKey).base64EncodedString()
    }
    
    private static func b64StrToBytes(publicKeyStr: String) -> [UInt8] {
        guard let pkData = Data(base64Encoded: publicKeyStr) else {
            let errorMessage = "Unable to convert public key to Data"
            logger.error("\(errorMessage)")
            return [UInt8]()
        }
        return [UInt8](pkData)
    }
    
    
    // MARK: Network Call
    static func call(connectionModel: InternalConnectionModel) async -> RelayApiResult<Data> {
        let url = URL(string: String(format: "%@%@", connectionModel.url, connectionModel.route))
        var request = URLRequest(url: url!)
        request.httpMethod = connectionModel.method
        request.httpBody = connectionModel.payload
        request.setValue(connectionModel.contentType, forHTTPHeaderField: "Content-Type")
        return await withCheckedContinuation { continuation in
            URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    continuation.resume(returning: RelayApiResult.failure(code: RelayConstants.RC_ERROR_ESTABLISHING_CONNECTION_WITH_SERVER, message: error.localizedDescription))
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(returning: RelayApiResult.failure(code: RelayConstants.RC_ERROR_ESTABLISHING_CONNECTION_WITH_SERVER, message: "No Response"))
                    return
                }
                let responseMessage = String(data: data ?? Data(), encoding: String.Encoding.utf8) ?? "No Response Message from the Server"
                let statusCode = httpResponse.statusCode
                if 200...226 ~= statusCode {
                    let responseData = data ?? Data()
                    continuation.resume(returning: RelayApiResult.success(data: responseData, headers: RelayHeaders())); return
                } else {
                    continuation.resume(returning: RelayApiResult.failure(code: String(statusCode), message: responseMessage)); return
                }
            }.resume()
        }
    }
    
    static func checkForRePair(statusCode: String) -> Bool {
        if let statusCodeInt = Int(statusCode), statusCodeInt == 566 {
            logger.info("Server doesn't recognize this Client. Re-pairing required")
            return true
        } else if let statusCodeInt = Int(statusCode), 559...569 ~= statusCodeInt {
            logger.info("Server doesn't recognize this Pair. Re-pairing required")
            return true
        } else {
            return false
        }
    }
}
