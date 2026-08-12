// The MIT License (MIT)
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


class MteHelper {
    
    private let logger = PackageLogger.makeLogger(for: MteHelper.self)
    private let settings: RelayHostSettings
    
    private var pairPool: PairPool
    private let pairPoolLock = NSLock()
    private let cryptoOperationLock = NSLock()
    
    weak var delegate: MteHelperDelegate?

    init(settings: RelayHostSettings = RelayHostSettings()) {
        self.settings = settings
        self.pairPool = PairPool(settings: settings)
    }
    
    func createPairDictionary(count: Int) throws -> [String: Pair] {
        logger.info("Creating new pair dictionary")
        return try withPairPoolLock {
            try pairPool.createNew(count: count)
            return pairPool.allPairs()
        }
    }
    
    func registerNewPairedPair(_ pair: Pair) {
        withPairPoolLock {
            pairPool.insertIntoInUse(pair)
        }
    }
    
    // MARK: Encode Functions
    
    func encode(pairId: String?, plaintext: String) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        encodeResult.encodedStr = try withCryptoOperationLock {
            try pair.encode(plaintext: plaintext)
        }
        return encodeResult
    }
    
    func encode(pairId: String?, bytes: [UInt8]) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        encodeResult.encodedBytes = try withCryptoOperationLock {
            try pair.encode(bytes: bytes)
        }
        return encodeResult
    }
    
    // MARK: Encode Stream Chunking Functions
    
    func startEncrypt(pairId: String?) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        try withCryptoOperationLock {
            try pair.startEncrypt()
        }
        return encodeResult
    }
    
    func encryptChunk(pairId: String, buffer: inout [UInt8]) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        try withCryptoOperationLock {
            try pair.encryptChunk(buffer: &buffer)
        }
        return encodeResult
    }
    
    func finishEncrypt(pairId: String) async throws -> EncodeResult {
        let (pair, encodeResult) = try await resolveEncodePair(pairId: pairId)
        encodeResult.encodedBytes = try withCryptoOperationLock {
            try pair.finishEncrypt()
        }
        return encodeResult
    }
    
    
    // MARK: Decode Functions
    
    func decode(pairId: String, encoded: String) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedStr = try withCryptoOperationLock {
            try pair.decode(encoded: encoded)
        }
        return decodeResult
    }
    
    func decode(pairId: String, encoded: [UInt8]) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedBytes = try withCryptoOperationLock {
            try pair.decode(encoded: encoded)
        }
        return decodeResult
    }
    
    
    // MARK: Decode Stream Chunking Functions
    
    func startDecrypt(pairId: String) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        try withCryptoOperationLock {
            try pair.startDecrypt()
        }
        return decodeResult
    }
    
    func decryptChunk(pairId: String, bytes: [UInt8]) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedBytes = try withCryptoOperationLock {
            try pair.decryptChunk(buffer: bytes)
        }
        return decodeResult
    }
    
    func finishDecrypt(pairId: String) throws -> DecodeResult {
        let (pair, decodeResult) = try resolveDecodePair(pairId: pairId)
        decodeResult.decodedBytes = try withCryptoOperationLock {
            try pair.finishDecrypt()
        }
        return decodeResult
    }
    
    // MARK: Public Cleanup Function
    
    func releasePair(pairId: String,
                     discardIfPoolIsAtCapacity: Bool = false) {
        withPairPoolLock {
            _ = pairPool.moveToAvailable(pairId: pairId,
                                         discardIfPoolIsAtCapacity: discardIfPoolIsAtCapacity)
        }
    }

    func discardPair(pairId: String) {
        withPairPoolLock {
            pairPool.removePair(pairId: pairId)
        }
    }

    func discardAvailablePairs() -> Int {
        withPairPoolLock {
            pairPool.removeAvailablePairs()
        }
    }

    func addRepairedPairToAvailable(_ pair: Pair) {
        withPairPoolLock {
            _ = pairPool.moveToAvailable(pair)
        }
    }

    func pairPoolInventory() -> PairPoolInventory {
        withPairPoolLock {
            pairPool.inventory()
        }
    }

    func shouldTriggerPairRefill() -> Bool {
        withPairPoolLock {
            pairPool.shouldTriggerRefill()
        }
    }

    func pairRefillRequestCount() -> Int {
        withPairPoolLock {
            pairPool.refillPairCount()
        }
    }
    
    // MARK: private Functions
    
    private func getNextPair() async throws -> Pair {
        if let resolvedPair = try acquireAvailableOrNewPair() {
            return try await finalizeAcquiredPair(resolvedPair)
        }

        let waitInterval = settings.acquisitionWaitTime
        if waitInterval > 0 {
            try await Task.sleep(nanoseconds: UInt64(waitInterval * 1_000_000_000))
            if let resolvedPair = try acquireAvailableOrNewPair() {
                return try await finalizeAcquiredPair(resolvedPair)
            }
        }

        throw RelayClientError.pairCapacityExhausted(settings.maxPairs)
    }

    private func acquireAvailableOrNewPair() throws -> (Pair, Bool)? {
        try withPairPoolLock {
            try pairPool.getNextAvailablePair()
        }
    }

    private func finalizeAcquiredPair(_ resolvedPair: (Pair, Bool)) async throws -> Pair {
        let (pair, isNew) = resolvedPair
        if isNew {
            logger.info("Requesting pairing for new pair \(String(describing: pair.pairId))")
            try await delegate?.pairingNeeded(for: pair)
        }
        if shouldTriggerPairRefill() {
            delegate?.pairRefillNeeded()
        }
        return pair
    }
    
    private func resolveEncodePair(pairId: String?) async throws -> (Pair, EncodeResult) {
        let encodeResult = EncodeResult()
        var pair: Pair!
        if let id = pairId {
            guard let resolved = withPairPoolLock({ pairPool.pair(for: id) }) else {
                let errorMessage = "Pair \(id) not found. Unable to continue."
                logger.error("\(errorMessage)")
                throw errorMessage.relayError
            }
            pair = resolved
        } else {
            pair = try await getNextPair()
        }
        encodeResult.pairId = pair.pairId
        return (pair, encodeResult)
    }
    
    private func resolveDecodePair(pairId: String) throws -> (Pair, DecodeResult) {
        let decodeResult = DecodeResult()
        guard let pair = withPairPoolLock({ pairPool.pair(for: pairId) }) else {
            let errorMessage = "Pair \(pairId) not found. Unable to continue."
            logger.error("\(errorMessage)")
            throw errorMessage.relayError
        }
        decodeResult.pairId = pair.pairId
        return (pair, decodeResult)
    }
    
    // MARK: Utility Functions
    
    func getPairDictionaryStates() async throws -> [StoredPair] {
        var pairsToStore = [StoredPair]()
        let allPairs = withPairPoolLock { pairPool.allPairs() }
        for pair in allPairs {
            var pairToStore = StoredPair()
            pairToStore.pairId = pair.value.pairId
            pair.value.getEncoderState(state: &pairToStore.encState)
            pair.value.getDecoderState(state: &pairToStore.decState)
            pairsToStore.append(pairToStore)
        }
        return pairsToStore
    }
    
    func getFinishEncryptBytes(pairId: String) -> Int {
        let pair = withPairPoolLock { pairPool.pair(for: pairId) }
        return pair?.getFinishEncryptBytes() ?? 0
    }
    
    // MARK: Cleanup Function
    func cleanup() {
        delegate = nil
        withPairPoolLock {
            pairPool = PairPool()
        }
    }

    private func withPairPoolLock<T>(_ action: () throws -> T) rethrows -> T {
        pairPoolLock.lock()
        defer { pairPoolLock.unlock() }
        return try action()
    }

    private func withCryptoOperationLock<T>(_ action: () throws -> T) rethrows -> T {
        cryptoOperationLock.lock()
        defer { cryptoOperationLock.unlock() }
        return try action()
    }

    private func shortPairId(_ pairId: String) -> String {
        String(pairId.prefix(8))
    }

}

