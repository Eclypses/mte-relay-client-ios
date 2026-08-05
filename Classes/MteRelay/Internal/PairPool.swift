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

private let logger = PackageLogger.makeLogger(for: PairPool.self)

struct PairPoolInventory: Equatable {
    let availableCount: Int
    let inUseCount: Int
    let totalCount: Int
}

enum PairReturnDisposition: Equatable {
    case returnedToAvailable
    case discardedExcessCapacity
    case pairNotFound
}

struct PairPool {
    private let settings: RelayHostSettings
    private var availablePairs: [(key: String, value: Pair)] = []
    private var inUsePairs: [String: Pair] = [:]

    init(settings: RelayHostSettings = RelayHostSettings()) {
        self.settings = settings
    }

    mutating func refill(with pairs: [String: Pair]) {
        availablePairs = pairs.map { ($0.key, $0.value) }
        inUsePairs.removeAll()
    }

    mutating func createNew(count: Int) throws {
        availablePairs.removeAll()
        inUsePairs.removeAll()
        for _ in 0..<count {
            let pair = try Pair()
            availablePairs.append((key: pair.pairId, value: pair))
        }
    }

    mutating func getNextAvailablePair() throws -> (Pair, Bool)? {
        if !availablePairs.isEmpty {
            let pairTuple = availablePairs.removeFirst()
            inUsePairs[pairTuple.key] = pairTuple.value
            return (pairTuple.value, false)
        } else if inventory().totalCount >= settings.maxPairs {
            return nil
        } else {
            let newPair = try Pair()
            inUsePairs[newPair.pairId] = newPair
            return (newPair, true)
        }
    }

    func pair(for id: String) -> Pair? {
        return inUsePairs[id] ?? availablePairs.first(where: { $0.key == id })?.value
    }

    func inventory() -> PairPoolInventory {
        PairPoolInventory(availableCount: availablePairs.count,
                          inUseCount: inUsePairs.count,
                          totalCount: availablePairs.count + inUsePairs.count)
    }

    func shouldTriggerRefill() -> Bool {
        refillPairCount() > 0
    }

    func refillPairCount() -> Int {
        let currentInventory = inventory()
        guard currentInventory.availableCount < settings.minPairs,
              currentInventory.totalCount < settings.maxPairs else {
            return 0
        }

        let pairsNeededToReachMin = max(settings.minPairs - currentInventory.availableCount, 0)
        let headroom = max(settings.maxPairs - currentInventory.totalCount, 0)
        return min(pairsNeededToReachMin, headroom)
    }

    mutating func moveToAvailable(pairId: String,
                                  discardIfPoolIsAtCapacity: Bool = false) -> PairReturnDisposition {
        let wasAtCapacity = inventory().totalCount >= settings.maxPairs
        if let pair = inUsePairs.removeValue(forKey: pairId) {
            availablePairs.removeAll { $0.key == pairId }

            if discardIfPoolIsAtCapacity && wasAtCapacity {
                logger.info("Discarding Pair \(pairId) because total capacity was already at the maxPairs setting of \(settings.maxPairs).")
                return .discardedExcessCapacity
            }

            availablePairs.append((key: pairId, value: pair))
            logger.info("Placing Pair \(pairId) in availablePairs. Count: \(inventory().totalCount) total, \(inventory().availableCount) available.")
            return .returnedToAvailable
        }

        return .pairNotFound
    }

    mutating func removePair(pairId: String) {
        let removedInUse = inUsePairs.removeValue(forKey: pairId) != nil
        let originalCount = availablePairs.count
        availablePairs.removeAll { $0.key == pairId }

        if removedInUse || availablePairs.count != originalCount {
            logger.info("Removing Pair \(pairId) from PairPool")
        }
    }

    mutating func removeAvailablePairs() -> Int {
        let removedCount = availablePairs.count
        if removedCount > 0 {
            logger.info("Removing \(removedCount) available pairs from PairPool")
        }
        availablePairs.removeAll()
        return removedCount
    }

    mutating func moveToAvailable(_ pair: Pair) -> PairReturnDisposition {
        inUsePairs.removeValue(forKey: pair.pairId)
        availablePairs.removeAll { $0.key == pair.pairId }

        availablePairs.append((key: pair.pairId, value: pair))
        logger.info("Placing Pair \(pair.pairId ?? "") in availablePairs")
        return .returnedToAvailable
    }

    func allPairs() -> [String: Pair] {
        var dict = Dictionary(uniqueKeysWithValues: availablePairs)
        for (key, value) in inUsePairs {
            dict[key] = value
        }
        return dict
    }

    mutating func insertIntoInUse(_ pair: Pair) {
        inUsePairs[pair.pairId] = pair
    }
}
