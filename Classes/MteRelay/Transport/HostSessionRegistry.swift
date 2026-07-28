import Foundation

actor HostSessionRegistry {
    private var sessions: [String: HostSession] = [:]
    private var pendingHosts: [String: Task<Host, Error>] = [:]

    func existingHost(for hostKey: String) -> Host? {
        guard let session = sessions[hostKey] else {
            return nil
        }
        session.markAccessed()
        return session.host
    }

    func resolveHost(for hostKey: String, create: @escaping @Sendable () async throws -> Host) async throws -> Host {
        if let session = sessions[hostKey] {
            session.markAccessed()
            return session.host
        }

        if let pendingHost = pendingHosts[hostKey] {
            let host = try await pendingHost.value
            sessions[hostKey]?.markAccessed()
            return host
        }

        let pendingHost = Task {
            try await create()
        }
        pendingHosts[hostKey] = pendingHost

        defer {
            pendingHosts[hostKey] = nil
        }

        let host = try await pendingHost.value
        sessions[hostKey] = HostSession(hostKey: hostKey, host: host)
        return host
    }

    func snapshot(for hostKey: String) -> HostSessionSnapshot? {
        guard let session = sessions[hostKey] else {
            return nil
        }
        return HostSessionSnapshot(hostKey: session.hostKey,
                                   createdAt: session.createdAt,
                                   lastAccessedAt: session.lastAccessedAt,
                                   accessCount: session.accessCount)
    }

    func replaceHost(for hostKey: String, host: Host) {
        pendingHosts[hostKey] = nil
        sessions[hostKey] = HostSession(hostKey: hostKey, host: host)
    }
}
