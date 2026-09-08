import Foundation
import Observation

@Observable
final class SessionStore: @unchecked Sendable {
    var groups: [AccountGroup] = []
    var selectedIds: Set<String> = []
    var lastSyncMessage: String?
    var lastSyncSuccess = false
    var isScanning = false
    var isSyncing = false

    private let fm = FileManager.default

    var unsyncedCount: Int {
        var count = 0
        for group in groups {
            for session in group.sessions where !isSyncedAnywhere(session, inGroup: group) {
                count += 1
            }
        }
        return count
    }

    func scan() {
        isScanning = true
        defer { isScanning = false }

        var result: [AccountGroup] = []

        for app in AppSource.allCases {
            let base = app.baseURL
            guard fm.fileExists(atPath: base.path) else { continue }
            guard let accountDirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }

            for accountDir in accountDirs where accountDir.hasDirectoryPath {
                guard let orgDirs = try? fm.contentsOfDirectory(at: accountDir, includingPropertiesForKeys: nil) else { continue }

                for orgDir in orgDirs where orgDir.hasDirectoryPath {
                    guard let files = try? fm.contentsOfDirectory(at: orgDir, includingPropertiesForKeys: nil) else { continue }

                    let sessionFiles = files.filter {
                        $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json"
                    }

                    let sessions = sessionFiles.compactMap { parseSession(from: $0) }
                        .sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }

                    if !sessions.isEmpty {
                        result.append(AccountGroup(
                            appLabel: app.label,
                            appBase: base,
                            accountUUID: accountDir.lastPathComponent,
                            orgUUID: orgDir.lastPathComponent,
                            orgPath: orgDir,
                            sessions: sessions
                        ))
                    }
                }
            }
        }

        groups = result
        selectedIds = []
        lastSyncMessage = nil
    }

    func isSyncedAnywhere(_ session: SessionInfo, inGroup group: AccountGroup) -> Bool {
        let others = groups.filter { $0.id != group.id }
        return others.contains { g in
            g.sessions.contains { $0.sessionId == session.sessionId }
        }
    }

    func targetsForSync(_ session: SessionInfo, from sourceGroup: AccountGroup) -> [AccountGroup] {
        groups.filter { $0.id != sourceGroup.id }
            .filter { target in
                !target.sessions.contains { $0.sessionId == session.sessionId }
            }
    }

    func syncSelected() {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var copied = 0
        var errors: [String] = []
        let snap = groups

        let selected = snap.flatMap { group in
            group.sessions.filter { selectedIds.contains($0.sessionId) }
                .map { (session: $0, sourceGroup: group) }
        }

        for (session, sourceGroup) in selected {
            let targets = snap.filter { $0.id != sourceGroup.id }
            for target in targets {
                let destFile = target.orgPath.appendingPathComponent(session.sourceFile.lastPathComponent)
                guard !fm.fileExists(atPath: destFile.path) else { continue }
                do {
                    try fm.copyItem(at: session.sourceFile, to: destFile)
                    copied += 1
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
        }

        if !errors.isEmpty {
            lastSyncMessage = L10n.syncError(errors.first!)
            lastSyncSuccess = false
        } else if copied > 0 {
            lastSyncMessage = L10n.syncedCount(copied)
            lastSyncSuccess = true
        } else {
            lastSyncMessage = L10n.nothingToSync
            lastSyncSuccess = true
        }

        scan()
    }

    func syncAll() {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var copied = 0
        var errors: [String] = []
        let snap = groups

        for sourceGroup in snap {
            let targets = snap.filter { $0.id != sourceGroup.id }
            for session in sourceGroup.sessions {
                for target in targets {
                    let destFile = target.orgPath.appendingPathComponent(session.sourceFile.lastPathComponent)
                    guard !fm.fileExists(atPath: destFile.path) else { continue }
                    do {
                        try fm.copyItem(at: session.sourceFile, to: destFile)
                        copied += 1
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
            }
        }

        if !errors.isEmpty {
            lastSyncMessage = L10n.syncError(errors.first!)
            lastSyncSuccess = false
        } else if copied > 0 {
            lastSyncMessage = L10n.syncedCount(copied)
            lastSyncSuccess = true
        } else {
            lastSyncMessage = L10n.allSynced
            lastSyncSuccess = true
        }

        scan()
    }

    func unsync(_ session: SessionInfo, from group: AccountGroup) {
        var removed = 0
        let others = groups.filter { $0.id != group.id }

        for other in others {
            let file = other.orgPath.appendingPathComponent(session.sourceFile.lastPathComponent)
            if fm.fileExists(atPath: file.path) {
                do {
                    try fm.removeItem(at: file)
                    removed += 1
                } catch {
                    lastSyncMessage = L10n.syncError(error.localizedDescription)
                    lastSyncSuccess = false
                    return
                }
            }
        }

        if removed > 0 {
            lastSyncMessage = L10n.removedCount(removed)
            lastSyncSuccess = true
            scan()
        }
    }
}
