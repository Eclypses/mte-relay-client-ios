import Foundation

struct HostPairingCoordinator {
    func setUpPairs(hostUrl: String,
                    hostUrlB64: String,
                    settings: RelayHostSettings,
                    currentClientId: String,
                    mteHelper: MteHelper,
                    updateClientId: @escaping @Sendable (String) async -> Void,
                    persistHostSession: @escaping @Sendable () -> Void) async throws -> HostStorageHelper {
        let storageHelper = try await HostStorageHelper(hostB64: hostUrlB64)

        let startingClientId: String
        if let storedHost = storageHelper.storedHost {
            startingClientId = currentClientId.isEmpty ? storedHost.clientId : currentClientId
        } else {
            startingClientId = currentClientId
        }

        let verifiedClientId = try await PairingHelper.initialPairingWithHost(hostUrl: hostUrl,
                                                                              pairCount: settings.basePairs,
                                                                              currentClientId: startingClientId,
                                                                              mteHelper: mteHelper)
        await updateClientId(verifiedClientId)
        persistHostSession()

        return storageHelper
    }

    func repairPairs(storageHelper: HostStorageHelper?,
                     setUpPairs: @escaping @Sendable () async throws -> HostStorageHelper) async throws -> HostStorageHelper {
        return try await setUpPairs()
    }
}
