import SwiftUI
import AppKit

struct VaultView: View {
    @Bindable var vault: SessionVault
    @State private var autoRestore: Bool
    @State private var dailyOn: Bool
    /// Cached because measuring it walks the whole vault.
    @State private var diskSize: String

    init(vault: SessionVault) {
        self.vault = vault
        _autoRestore = State(initialValue: vault.autoRestore)
        _dailyOn = State(initialValue: vault.isDailyInstalled)
        _diskSize = State(initialValue: vault.onDiskFormatted)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsBar
            Divider()

            if vault.entries.isEmpty {
                ContentUnavailableView(
                    L10n.vaultEmpty,
                    systemImage: "archivebox",
                    description: Text(L10n.vaultEmptyDetail)
                )
            } else {
                entryList
            }

            Divider()
            footer
        }
    }

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $dailyOn) {
                Text(L10n.dailyBackup).font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: dailyOn) { _, on in
                if on {
                    do { try vault.installDailyAgent() } catch { dailyOn = false }
                } else {
                    vault.removeDailyAgent()
                }
            }

            Toggle(isOn: $autoRestore) {
                Text(L10n.autoRestore).font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(L10n.autoRestoreHelp)
            .onChange(of: autoRestore) { _, on in vault.autoRestore = on }

            HStack(spacing: 6) {
                Image(systemName: "externaldrive")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(shortPath(vault.vaultRoot))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Button(L10n.changeLocation) { chooseLocation() }
                    .buttonStyle(.borderless)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var entryList: some View {
        List {
            ForEach(vault.entries) { entry in
                VaultRow(entry: entry) {
                    vault.restore(entry)
                    vault.load()
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let msg = vault.lastMessage {
                HStack(spacing: 4) {
                    Image(systemName: vault.lastSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(vault.lastSuccess ? .green : .red)
                        .font(.caption)
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    // Shows what the vault actually occupies, which is below the sum of the
                    // original file sizes once blobs are deflated.
                    Text("\(L10n.backedUpCount(vault.entries.count)) · \(diskSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vault.lastBackupAt.map { L10n.lastBackup($0) } ?? L10n.neverBackedUp)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(L10n.compact) {
                    vault.compact()
                    diskSize = vault.onDiskFormatted
                }
                .disabled(vault.isWorking)

                if vault.recoverableCount > 0 {
                    Button(L10n.restoreAll) {
                        vault.restoreAllMissing()
                        vault.load()
                    }
                    .disabled(vault.isWorking)
                }

                Button(L10n.backupNow) {
                    vault.backupNow()
                }
                .disabled(vault.isWorking)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.changeLocation
        panel.directoryURL = vault.vaultRoot.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            vault.setVaultRoot(url)
        }
    }
}

struct VaultRow: View {
    let entry: VaultEntry
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isRecoverable ? "exclamationmark.arrow.circlepath" : "checkmark.shield")
                .foregroundStyle(entry.isRecoverable ? .orange : .green)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(cwdShort, systemImage: "folder")
                    Label(entry.sizeFormatted, systemImage: "internaldrive")
                    if entry.isTruncated {
                        Text(L10n.truncated)
                            .foregroundStyle(.orange)
                    } else if entry.isRecoverable {
                        Text(L10n.gone)
                            .foregroundStyle(.orange)
                    } else if entry.transcriptBlob != nil && entry.indexBlob == nil {
                        Text(L10n.transcriptOnly)
                    } else if entry.indexBlob != nil && entry.transcriptBlob == nil {
                        Text(L10n.indexOnly)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if entry.isRecoverable {
                Button(L10n.restore, action: onRestore)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
    }

    private var cwdShort: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if entry.cwd.hasPrefix(home) { return "~" + entry.cwd.dropFirst(home.count) }
        return entry.cwd
    }
}
