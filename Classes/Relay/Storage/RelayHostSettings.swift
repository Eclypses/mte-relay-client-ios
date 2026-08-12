import Foundation

public struct RelayHostSettings: Sendable, Equatable {
    public static let defaultMinPairs = 5
    public static let defaultBasePairs = 8
    public static let defaultMaxPairs = 15
    public static let defaultAcquisitionWaitTime: TimeInterval = 1.0
    public static let defaultKeepAliveInterval: TimeInterval = 300.0

    public var streamChunkSize: Int
    public var minPairs: Int
    public var basePairs: Int
    public var maxPairs: Int
    public var keepAliveInterval: TimeInterval
    public var acquisitionWaitTime: TimeInterval

    public init(streamChunkSize: Int = 1024 * 1024,
                minPairs: Int = RelayHostSettings.defaultMinPairs,
                basePairs: Int = RelayHostSettings.defaultBasePairs,
                maxPairs: Int = RelayHostSettings.defaultMaxPairs,
                keepAliveInterval: TimeInterval = RelayHostSettings.defaultKeepAliveInterval,
                acquisitionWaitTime: TimeInterval = RelayHostSettings.defaultAcquisitionWaitTime) {
        self.streamChunkSize = streamChunkSize
        self.minPairs = minPairs
        self.basePairs = basePairs
        self.maxPairs = maxPairs
        self.keepAliveInterval = keepAliveInterval
        self.acquisitionWaitTime = acquisitionWaitTime
    }
}

actor RelayHostSettingsStore {
    private let defaultSettings = RelayHostSettings()
    private var settingsByHost: [String: RelayHostSettings] = [:]

    func settings(for host: String) -> RelayHostSettings {
        settingsByHost[host] ?? defaultSettings
    }

    func updateSettings(_ settings: RelayHostSettings, for host: String) {
        settingsByHost[host] = settings
    }
}