import Foundation

struct ReservedPairFinalizer {
    let releasePair: (String) -> Void
    let discardPair: (String) -> Void
    let persistStates: () -> Void
    let scheduleRepair: (String) -> Void

    func finalize(pairId: String, shouldReusePair: Bool) {
        if shouldReusePair {
            releasePair(pairId)
            persistStates()
            return
        }

        discardPair(pairId)
        persistStates()
        scheduleRepair(pairId)
    }
}