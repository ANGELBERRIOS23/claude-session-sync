import Foundation
import CryptoKit
import Compression
import Observation

/// Blobs are deflated on the way in. Transcripts are JSONL and compress about 2x overall,
/// though the ratio collapses on sessions carrying base64 image attachments, so a blob is
/// only stored compressed when that actually wins.
///
/// A compressed blob is `<digest>.z`: an 8-byte little-endian original length followed by a
/// raw DEFLATE stream. The digest stays the SHA-256 of the *uncompressed* bytes, so dedupe
/// and verification are unaffected by how a blob happens to be stored.
enum BlobCodec {
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 4096
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(d, capacity, s, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        var framed = Data(capacity: written + 8)
        var size = UInt64(data.count).littleEndian
        withUnsafeBytes(of: &size) { framed.append(contentsOf: $0) }
        framed.append(out.prefix(written))
        return framed
    }

    static func inflate(_ framed: Data) -> Data? {
        guard framed.count > 8 else { return nil }
        let size = framed.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        guard size > 0, size < 4_000_000_000 else { return nil }
        let body = framed.dropFirst(8)
        let capacity = Int(size)
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            body.withUnsafeBytes { src -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, capacity, s, body.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == capacity else { return nil }
        return out
    }
}

/// One session preserved in the vault.
///
/// A session has two halves that Claude stores in different places and prunes on
/// different clocks: the index row (`local_*.json`, what the sidebar lists) and the
/// transcript (`~/.claude/projects/<slug>/<cliSessionId>.jsonl`, the actual content).
/// Either half can disappear while the other survives, so both are captured
/// independently and either can be restored on its own.
/// One captured revision of a file. Kept as a list per entry because a backup that only
/// tracks the newest copy is not a backup: if Claude truncates or recreates a transcript,
/// the next pass would adopt the stub as the current version and the full copy would no
/// longer be referenced by anything.
struct BlobVersion: Codable, Hashable {
    var digest: String
    var bytes: Int
    var capturedAt: Date
}

struct VaultEntry: Codable, Identifiable, Hashable {
    var key: String
    var sessionId: String?
    var cliSessionId: String?
    var title: String
    var cwd: String
    var model: String

    /// Folder name under `~/.claude/projects`. Derived from `cwd` by Claude, so it is
    /// captured verbatim rather than recomputed — the slug rules are not ours to guess.
    var projectSlug: String?

    /// Path of the transcript relative to `~/.claude/projects`, recorded verbatim so the
    /// file is restored exactly where Claude had it. Top-level sessions sit at
    /// `<slug>/<cliSessionId>.jsonl`, but subagent transcripts live one level deeper at
    /// `<slug>/<parentSessionId>/subagents/agent-*.jsonl`, and a slug-plus-id guess cannot
    /// reach those.
    var transcriptRelPath: String?

    /// Set on subagent transcripts: the session whose run spawned them.
    var parentSessionId: String?

    var appRaw: String?
    var accountUUID: String?
    var orgUUID: String?
    var indexFileName: String?

    var indexBlob: String?
    var transcriptBlob: String?
    var transcriptBytes: Int
    var indexBytes: Int

    /// Optional so manifests written before versioning still decode.
    var transcriptHistory: [BlobVersion]?
    var indexHistory: [BlobVersion]?

    var lastActivityAt: Date?
    var firstSeenAt: Date
    var lastBackupAt: Date

    var id: String { key }

    var isSubagent: Bool {
        transcriptRelPath?.contains("/subagents/") ?? false
    }

    var transcriptLiveURL: URL? {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
        if let rel = transcriptRelPath, !rel.isEmpty {
            return projects.appendingPathComponent(rel)
        }
        guard let projectSlug, let cliSessionId, !cliSessionId.isEmpty else { return nil }
        return projects
            .appendingPathComponent(projectSlug)
            .appendingPathComponent("\(cliSessionId).jsonl")
    }

    var indexLiveURL: URL? {
        guard let appRaw, let app = AppSource(rawValue: appRaw),
              let accountUUID, let orgUUID, let indexFileName else { return nil }
        return app.baseURL
            .appendingPathComponent(accountUUID)
            .appendingPathComponent(orgUUID)
            .appendingPathComponent(indexFileName)
    }

    var transcriptAlive: Bool {
        guard let url = transcriptLiveURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var indexAlive: Bool {
        guard let url = indexLiveURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The most complete transcript ever captured. Recovery restores this rather than the
    /// newest one, because the newest may be a stub Claude wrote after wiping the file.
    var fullestTranscript: BlobVersion? {
        (transcriptHistory ?? []).max { $0.bytes < $1.bytes }
    }

    var fullestIndex: BlobVersion? {
        (indexHistory ?? []).max { $0.bytes < $1.bytes }
    }

    var liveTranscriptBytes: Int? {
        guard let url = transcriptLiveURL,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize
    }

    /// The live file is present but materially smaller than a copy the vault holds — the
    /// content is not gone from disk, it is gone from the file the user can reach.
    var isTruncated: Bool {
        guard let fullest = fullestTranscript, let live = liveTranscriptBytes else { return false }
        return live < fullest.bytes
    }

    /// True when the vault holds something the live install has lost.
    var isRecoverable: Bool {
        (transcriptBlob != nil && !transcriptAlive)
            || (indexBlob != nil && !indexAlive)
            || isTruncated
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(transcriptBytes + indexBytes), countStyle: .file)
    }
}

struct VaultManifest: Codable {
    var version: Int = 1
    var lastBackupAt: Date?
    var entries: [VaultEntry] = []
}

struct BackupOutcome {
    var newEntries = 0
    var updatedEntries = 0
    var unchanged = 0
    var bytesWritten = 0
    /// Files put back where Claude had them.
    var restored = 0
    /// Fuller copies written beside the vault because a live file was in the way.
    var recovered = 0
    var recoveredPaths: [String] = []
    var bytesFreed = 0
    var errors: [String] = []
}

@Observable
final class SessionVault: @unchecked Sendable {
    var entries: [VaultEntry] = []
    var lastBackupAt: Date?
    var lastMessage: String?
    var lastSuccess = true
    var isWorking = false

    private let fm = FileManager.default
    private let iso = ISO8601DateFormatter()

    // MARK: - Settings

    private enum Keys {
        static let vaultPath = "vaultPath"
        static let autoRestore = "autoRestoreOnBackup"
        static let dailyEnabled = "dailyBackupEnabled"
    }

    /// User-chosen vault location. Defaults to a directory Claude never touches, and can
    /// be pointed at an external drive or a synced folder so a wiped Mac is not fatal.
    var vaultRoot: URL {
        if let custom = UserDefaults.standard.string(forKey: Keys.vaultPath), !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return defaultVaultRoot
    }

    var defaultVaultRoot: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeSessionSync")
            .appendingPathComponent("Vault")
    }

    var isUsingCustomLocation: Bool {
        let custom = UserDefaults.standard.string(forKey: Keys.vaultPath)
        return !(custom ?? "").isEmpty
    }

    func setVaultRoot(_ url: URL?) {
        UserDefaults.standard.set(url?.path ?? "", forKey: Keys.vaultPath)
        load()
    }

    /// When on, every backup pass puts back anything Claude has deleted since the last run.
    /// This is what actually reverses the automatic pruning rather than just observing it.
    var autoRestore: Bool {
        get { UserDefaults.standard.object(forKey: Keys.autoRestore) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoRestore) }
    }

    var dailyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.dailyEnabled) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Keys.dailyEnabled) }
    }

    private var blobsRoot: URL { vaultRoot.appendingPathComponent("blobs") }
    private var manifestURL: URL { vaultRoot.appendingPathComponent("manifest.json") }

    // MARK: - Stats

    var recoverableCount: Int { entries.filter(\.isRecoverable).count }
    var totalBytes: Int { entries.reduce(0) { $0 + $1.transcriptBytes + $1.indexBytes } }
    var totalBytesFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    // MARK: - Manifest I/O

    func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(VaultManifest.self, from: data) else {
            entries = []
            lastBackupAt = nil
            return
        }
        entries = manifest.entries.sorted {
            ($0.lastActivityAt ?? $0.lastBackupAt) > ($1.lastActivityAt ?? $1.lastBackupAt)
        }
        lastBackupAt = manifest.lastBackupAt
    }

    private func save() throws {
        try fm.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        var manifest = VaultManifest()
        manifest.lastBackupAt = lastBackupAt
        manifest.entries = entries
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Blob store

    private func blobURL(_ digest: String) -> URL {
        blobsRoot
            .appendingPathComponent(String(digest.prefix(2)))
            .appendingPathComponent(digest)
    }

    private func compressedBlobURL(_ digest: String) -> URL {
        blobURL(digest).appendingPathExtension("z")
    }

    private func blobExists(_ digest: String) -> Bool {
        fm.fileExists(atPath: compressedBlobURL(digest).path) || fm.fileExists(atPath: blobURL(digest).path)
    }

    /// Stores file contents under their SHA-256. Repeated daily runs over an unchanged
    /// transcript therefore cost nothing beyond the first copy.
    @discardableResult
    private func putBlob(_ data: Data) throws -> (digest: String, wrote: Bool) {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if blobExists(digest) { return (digest, false) }
        let dest = blobURL(digest)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Sessions carrying base64 attachments barely deflate; storing those compressed
        // would cost CPU on every read for nothing.
        if let packed = BlobCodec.deflate(data), packed.count < data.count * 9 / 10 {
            try packed.write(to: compressedBlobURL(digest), options: .atomic)
        } else {
            try data.write(to: dest, options: .atomic)
        }
        return (digest, true)
    }

    private func readBlob(_ digest: String) -> Data? {
        if let framed = try? Data(contentsOf: compressedBlobURL(digest)) {
            return BlobCodec.inflate(framed)
        }
        return try? Data(contentsOf: blobURL(digest))
    }

    // MARK: - Backup

    @discardableResult
    func backupNow() -> BackupOutcome {
        isWorking = true
        defer { isWorking = false }

        var outcome = BackupOutcome()
        load()
        var byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })
        let now = Date()

        // Half one: index rows, which carry the metadata (title, cwd, model).
        var slugByCli: [String: String] = [:]
        for app in AppSource.allCases {
            let base = app.baseURL
            guard fm.fileExists(atPath: base.path) else { continue }
            guard let accountDirs = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }

            for accountDir in accountDirs where accountDir.hasDirectoryPath {
                guard let orgDirs = try? fm.contentsOfDirectory(at: accountDir, includingPropertiesForKeys: nil) else { continue }

                for orgDir in orgDirs where orgDir.hasDirectoryPath {
                    guard let files = try? fm.contentsOfDirectory(at: orgDir, includingPropertiesForKeys: nil) else { continue }

                    for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                        guard let session = parseSession(from: file),
                              let data = try? Data(contentsOf: file) else { continue }

                        let key = session.cliSessionId?.isEmpty == false ? session.cliSessionId! : session.sessionId
                        if let cli = session.cliSessionId, !cli.isEmpty {
                            slugByCli[cli] = slugForCwd(session.cwd)
                        }

                        do {
                            let (digest, wrote) = try putBlob(data)
                            if wrote { outcome.bytesWritten += data.count }

                            var entry = byKey[key] ?? VaultEntry(
                                key: key,
                                title: session.title,
                                cwd: session.cwd,
                                model: session.model,
                                transcriptBytes: 0,
                                indexBytes: 0,
                                firstSeenAt: now,
                                lastBackupAt: now
                            )
                            let hadIndex = entry.indexBlob
                            entry.sessionId = session.sessionId
                            entry.cliSessionId = session.cliSessionId
                            entry.title = session.title
                            entry.cwd = session.cwd
                            entry.model = session.model
                            entry.appRaw = app.rawValue
                            entry.accountUUID = accountDir.lastPathComponent
                            entry.orgUUID = orgDir.lastPathComponent
                            entry.indexFileName = file.lastPathComponent
                            entry.indexBlob = digest
                            entry.indexBytes = data.count
                            entry.indexHistory = appendVersion(
                                to: entry.indexHistory, digest: digest, bytes: data.count, at: now
                            )
                            entry.lastActivityAt = session.lastActivityAt ?? session.createdAt
                            entry.lastBackupAt = now
                            if byKey[key] == nil {
                                outcome.newEntries += 1
                            } else if hadIndex != digest {
                                outcome.updatedEntries += 1
                            } else {
                                outcome.unchanged += 1
                            }
                            byKey[key] = entry
                        } catch {
                            outcome.errors.append(error.localizedDescription)
                        }
                    }
                }
            }
        }

        // Half two: transcripts on disk. Most of these are orphans with no index row left
        // pointing at them, so they are captured on their own terms rather than only when
        // an index row happens to mention them.
        let projectsRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")

        let rootPrefix = projectsRoot.standardizedFileURL.path + "/"
        if let walker = fm.enumerator(at: projectsRoot, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let file as URL in walker where file.pathExtension == "jsonl" {
                let full = file.standardizedFileURL.path
                guard full.hasPrefix(rootPrefix) else { continue }
                let rel = String(full.dropFirst(rootPrefix.count))
                let parts = rel.split(separator: "/").map(String.init)
                guard parts.count >= 2 else { continue }

                let stem = file.deletingPathExtension().lastPathComponent
                // A top-level `<slug>/<cliSessionId>.jsonl` shares its key with the index
                // row so both halves land on one entry. Anything deeper is a subagent
                // transcript with no index row of its own, so its path is the key.
                let isTopLevel = parts.count == 2
                let key = isTopLevel ? stem : rel

                guard let data = try? Data(contentsOf: file) else { continue }

                do {
                    let (digest, wrote) = try putBlob(data)
                    if wrote { outcome.bytesWritten += data.count }

                    var entry = byKey[key] ?? VaultEntry(
                        key: key,
                        title: titleFromTranscript(file) ?? stem,
                        cwd: cwdFromTranscript(file) ?? "?",
                        model: "?",
                        transcriptBytes: 0,
                        indexBytes: 0,
                        firstSeenAt: now,
                        lastBackupAt: now
                    )
                    let hadTranscript = entry.transcriptBlob
                    if isTopLevel {
                        entry.cliSessionId = stem
                    } else {
                        entry.parentSessionId = parts[1]
                    }
                    entry.projectSlug = parts[0]
                    entry.transcriptRelPath = rel
                    entry.transcriptBlob = digest
                    entry.transcriptBytes = data.count
                    entry.transcriptHistory = appendVersion(
                        to: entry.transcriptHistory, digest: digest, bytes: data.count, at: now
                    )
                    entry.lastBackupAt = now
                    if entry.lastActivityAt == nil {
                        entry.lastActivityAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    }
                    if byKey[key] == nil {
                        outcome.newEntries += 1
                    } else if hadTranscript != digest {
                        outcome.updatedEntries += 1
                    } else {
                        outcome.unchanged += 1
                    }
                    byKey[key] = entry
                } catch {
                    outcome.errors.append(error.localizedDescription)
                }
            }
        }

        // An index row backed up before its transcript vanished has no slug recorded.
        // Fill it in from the cwd so a later restore knows where the file belongs.
        for (key, var entry) in byKey where entry.projectSlug == nil {
            if let cli = entry.cliSessionId, let slug = slugByCli[cli] {
                entry.projectSlug = slug
                byKey[key] = entry
            }
        }

        entries = Array(byKey.values).sorted {
            ($0.lastActivityAt ?? $0.lastBackupAt) > ($1.lastActivityAt ?? $1.lastBackupAt)
        }
        lastBackupAt = now

        do {
            try save()
        } catch {
            outcome.errors.append(error.localizedDescription)
        }

        if autoRestore {
            outcome.restored = restoreAllMissing().restored
        }

        // Trimming version history leaves blobs nothing points at. Collecting them here
        // keeps the vault from growing on every run for revisions already discarded.
        outcome.bytesFreed = compact().total

        lastSuccess = outcome.errors.isEmpty
        lastMessage = outcome.errors.isEmpty
            ? L10n.backupDone(outcome.newEntries + outcome.updatedEntries, outcome.restored)
            : L10n.syncError(outcome.errors.first!)
        return outcome
    }

    // MARK: - Restore

    /// Puts back whichever halves are missing, always from the fullest captured version.
    ///
    /// A live file is never overwritten. Claude Code appends to an open handle, and an
    /// atomic write swaps the inode underneath it — that would strand every line the
    /// running session writes afterwards. So when a live file exists but is shorter than
    /// what the vault holds, the recovered copy is written beside the vault instead, out
    /// of Claude's directories where it cannot be mistaken for a live session.
    @discardableResult
    func restore(_ entry: VaultEntry) -> BackupOutcome {
        var outcome = BackupOutcome()

        if let version = entry.fullestTranscript ?? entry.transcriptBlob.map({
            BlobVersion(digest: $0, bytes: entry.transcriptBytes, capturedAt: entry.lastBackupAt)
        }), let url = entry.transcriptLiveURL, let data = readBlob(version.digest) {
            if !fm.fileExists(atPath: url.path) {
                do {
                    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    outcome.restored += 1
                } catch {
                    outcome.errors.append(error.localizedDescription)
                }
            } else if (entry.liveTranscriptBytes ?? 0) < version.bytes {
                do {
                    let dest = try recoveredSidecarURL(for: entry)
                    if !fm.fileExists(atPath: dest.path) {
                        try data.write(to: dest, options: .atomic)
                        outcome.recovered += 1
                        outcome.recoveredPaths.append(dest.path)
                    }
                } catch {
                    outcome.errors.append(error.localizedDescription)
                }
            }
        }

        if let version = entry.fullestIndex ?? entry.indexBlob.map({
            BlobVersion(digest: $0, bytes: entry.indexBytes, capturedAt: entry.lastBackupAt)
        }), let url = entry.indexLiveURL,
           !fm.fileExists(atPath: url.path),
           let data = readBlob(version.digest) {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                outcome.restored += 1
            } catch {
                outcome.errors.append(error.localizedDescription)
            }
        }

        lastSuccess = outcome.errors.isEmpty
        lastMessage = outcome.errors.isEmpty
            ? L10n.restoreSummary(outcome.restored, outcome.recovered)
            : L10n.syncError(outcome.errors.first!)
        return outcome
    }

    /// Recovered copies land under the vault, never under `~/.claude/projects`, so Claude
    /// does not index them as extra sessions.
    private func recoveredSidecarURL(for entry: VaultEntry) throws -> URL {
        let dir = vaultRoot
            .appendingPathComponent("recovered")
            .appendingPathComponent(entry.projectSlug ?? "unknown")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = (entry.transcriptRelPath as NSString?)?.lastPathComponent
            ?? "\(entry.cliSessionId ?? entry.key).jsonl"
        let base = (stem as NSString).deletingPathExtension
        let stamp = fileStampFormatter.string(from: Date())
        return dir.appendingPathComponent("\(base)-recovered-\(stamp).jsonl")
    }

    private var fileStampFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }

    @discardableResult
    func restoreAllMissing() -> BackupOutcome {
        var total = BackupOutcome()
        for entry in entries where entry.isRecoverable {
            let r = restore(entry)
            total.restored += r.restored
            total.recovered += r.recovered
            total.recoveredPaths.append(contentsOf: r.recoveredPaths)
            total.errors.append(contentsOf: r.errors)
        }
        lastSuccess = total.errors.isEmpty
        lastMessage = total.errors.isEmpty
            ? L10n.restoreSummary(total.restored, total.recovered)
            : L10n.syncError(total.errors.first!)
        return total
    }

    // MARK: - Compaction

    struct CompactOutcome {
        var orphansDeleted = 0
        var orphanBytes = 0
        var recompressed = 0
        var compressionSaved = 0
        var total: Int { orphanBytes + compressionSaved }
    }

    /// Reclaims space without touching anything the manifest still points at: drops blobs
    /// no entry references any more, and deflates blobs written before compression existed.
    @discardableResult
    func compact() -> CompactOutcome {
        isWorking = true
        defer { isWorking = false }

        load()
        var outcome = CompactOutcome()

        var referenced = Set<String>()
        for entry in entries {
            entry.transcriptBlob.map { referenced.insert($0) }
            entry.indexBlob.map { referenced.insert($0) }
            for v in entry.transcriptHistory ?? [] { referenced.insert(v.digest) }
            for v in entry.indexHistory ?? [] { referenced.insert(v.digest) }
        }

        guard let walker = fm.enumerator(at: blobsRoot, includingPropertiesForKeys: [.fileSizeKey]) else {
            return outcome
        }

        for case let file as URL in walker where file.hasDirectoryPath == false {
            let name = file.lastPathComponent
            let digest = file.pathExtension == "z" ? file.deletingPathExtension().lastPathComponent : name
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

            if !referenced.contains(digest) {
                if (try? fm.removeItem(at: file)) != nil {
                    outcome.orphansDeleted += 1
                    outcome.orphanBytes += size
                }
                continue
            }

            guard file.pathExtension != "z",
                  let raw = try? Data(contentsOf: file),
                  let packed = BlobCodec.deflate(raw),
                  packed.count < raw.count * 9 / 10 else { continue }

            do {
                try packed.write(to: compressedBlobURL(digest), options: .atomic)
                try fm.removeItem(at: file)
                outcome.recompressed += 1
                outcome.compressionSaved += raw.count - packed.count
            } catch {
                try? fm.removeItem(at: compressedBlobURL(digest))
            }
        }

        lastSuccess = true
        lastMessage = L10n.compacted(outcome.total)
        return outcome
    }

    var onDiskBytes: Int {
        guard let walker = fm.enumerator(at: vaultRoot, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let file as URL in walker where file.hasDirectoryPath == false {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return total
    }

    var onDiskFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(onDiskBytes), countStyle: .file)
    }

    // MARK: - Daily schedule (launchd)

    private var agentLabel: String { "com.angelberrios.claude-session-sync.backup" }

    private var agentPlistURL: URL {
        fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(agentLabel).plist")
    }

    var isDailyInstalled: Bool { fm.fileExists(atPath: agentPlistURL.path) }

    /// Registers a launchd agent that runs the binary headlessly with `--backup`.
    /// `StartCalendarInterval` fires at 12:00 and, unlike a timer, catches up after a
    /// reboot or a closed lid, which matters for a backup that must not silently lapse.
    func installDailyAgent(hour: Int = 12) throws {
        let exec = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments[0]
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [exec, "--backup"],
            "StartCalendarInterval": ["Hour": hour, "Minute": 0],
            "RunAtLoad": false,
            "StandardOutPath": vaultRoot.appendingPathComponent("backup.log").path,
            "StandardErrorPath": vaultRoot.appendingPathComponent("backup.log").path
        ]
        try fm.createDirectory(at: agentPlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentPlistURL, options: .atomic)
        runLaunchctl(["bootout", "gui/\(getuid())/\(agentLabel)"])
        runLaunchctl(["bootstrap", "gui/\(getuid())", agentPlistURL.path])
        dailyEnabled = true
    }

    func removeDailyAgent() {
        runLaunchctl(["bootout", "gui/\(getuid())/\(agentLabel)"])
        try? fm.removeItem(at: agentPlistURL)
        dailyEnabled = false
    }

    @discardableResult
    private func runLaunchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: - Helpers

    /// Records a revision, keeping the newest ones plus the largest ever seen. The largest
    /// is pinned explicitly: it is the copy recovery depends on, and a run of truncated
    /// captures must not be able to push it out of the window.
    private func appendVersion(
        to existing: [BlobVersion]?, digest: String, bytes: Int, at date: Date, keep: Int = 20
    ) -> [BlobVersion] {
        var history = existing ?? []
        if let idx = history.firstIndex(where: { $0.digest == digest }) {
            history[idx].capturedAt = date
        } else {
            history.append(BlobVersion(digest: digest, bytes: bytes, capturedAt: date))
        }
        guard history.count > keep else { return history }

        let largest = history.max { $0.bytes < $1.bytes }
        var trimmed = Array(history.sorted { $0.capturedAt > $1.capturedAt }.prefix(keep))
        if let largest, !trimmed.contains(largest) {
            trimmed.append(largest)
        }
        return trimmed
    }

    /// Mirrors Claude's folder naming: the absolute cwd with separators and underscores
    /// flattened to hyphens. Only used as a fallback when no transcript revealed the slug.
    private func slugForCwd(_ cwd: String) -> String? {
        guard cwd != "?" && !cwd.isEmpty else { return nil }
        return cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private func firstLine(of url: URL) -> [String: Any]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty else { return nil }
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let d = line.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                return obj
            }
        }
        return nil
    }

    private func cwdFromTranscript(_ url: URL) -> String? {
        firstLine(of: url)?["cwd"] as? String
    }

    private func titleFromTranscript(_ url: URL) -> String? {
        guard let obj = firstLine(of: url) else { return nil }
        if let summary = obj["summary"] as? String, !summary.isEmpty { return summary }
        if let message = obj["message"] as? [String: Any] {
            if let content = message["content"] as? String, !content.isEmpty {
                return String(content.prefix(80))
            }
            if let parts = message["content"] as? [[String: Any]] {
                for part in parts where part["type"] as? String == "text" {
                    if let text = part["text"] as? String, !text.isEmpty {
                        return String(text.prefix(80))
                    }
                }
            }
        }
        return nil
    }
}
