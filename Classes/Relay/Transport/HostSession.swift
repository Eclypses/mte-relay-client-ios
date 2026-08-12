import Foundation

final class HostSession {
    let hostKey: String
    let host: Host
    let createdAt: Date
    private(set) var lastAccessedAt: Date
    private(set) var accessCount: Int

    init(hostKey: String, host: Host, createdAt: Date = Date()) {
        self.hostKey = hostKey
        self.host = host
        self.createdAt = createdAt
        self.lastAccessedAt = createdAt
        self.accessCount = 1
    }

    func markAccessed(at date: Date = Date()) {
        lastAccessedAt = date
        accessCount += 1
    }
}

struct HostSessionSnapshot: Sendable {
    let hostKey: String
    let createdAt: Date
    let lastAccessedAt: Date
    let accessCount: Int
}
