import SwiftUI

struct SessionListView: View {
    @Bindable var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            if store.isScanning {
                ProgressView(L10n.scanning)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.groups.allSatisfy({ $0.sessions.isEmpty }) {
                ContentUnavailableView(
                    L10n.noSessions,
                    systemImage: "tray",
                    description: Text(L10n.noSessionsDetail)
                )
            } else {
                sessionList
            }

            Divider()
            footer
        }
    }

    private var sessionList: some View {
        List {
            ForEach(store.groups) { group in
                Section {
                    ForEach(group.sessions) { session in
                        let synced = store.isSyncedAnywhere(session, inGroup: group)
                        SessionRow(
                            session: session,
                            isSynced: synced,
                            isSelected: store.selectedIds.contains(session.sessionId),
                            onToggle: {
                                if store.selectedIds.contains(session.sessionId) {
                                    store.selectedIds.remove(session.sessionId)
                                } else {
                                    store.selectedIds.insert(session.sessionId)
                                }
                            },
                            onUnsync: synced ? {
                                store.unsync(session, from: group)
                            } : nil
                        )
                    }
                } header: {
                    HStack {
                        Image(systemName: group.appLabel.contains("Bedrock") ? "cloud" : "person")
                        Text(group.appLabel)
                            .font(.subheadline.bold())
                        // Several accounts share the same app label; the folder id tells them apart.
                        Text(String(group.accountUUID.prefix(8)))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L10n.sessions(group.sessions.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let msg = store.lastSyncMessage {
                HStack(spacing: 4) {
                    Image(systemName: store.lastSyncSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.lastSyncSuccess ? .green : .red)
                        .font(.caption)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            HStack {
                Text(L10n.unsynced(store.unsyncedCount))
                    .font(.caption)
                    .foregroundStyle(store.unsyncedCount > 0 ? .orange : .green)

                Spacer()

                Button(L10n.syncSelected) {
                    store.syncSelected()
                }
                .disabled(store.selectedIds.isEmpty || store.isSyncing)

                Button(L10n.syncAll) {
                    store.syncAll()
                }
                .disabled(store.isSyncing)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: store.lastSyncMessage)
    }
}

struct SessionRow: View {
    let session: SessionInfo
    let isSynced: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onUnsync: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if !isSynced {
                Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.body)
                        .lineLimit(1)

                    Text(session.modelShort)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(modelColor.opacity(0.15))
                        .foregroundStyle(modelColor)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    Label(session.cwdShort, systemImage: "folder")
                    Label(session.lastActivityFormatted, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            if isSynced {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    if let unsync = onUnsync {
                        Button {
                            unsync()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.remove)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isSynced { onToggle() } }
        .opacity(session.isArchived ? 0.5 : 1)
    }

    private var modelColor: Color {
        switch session.modelShort {
        case "Opus": return .purple
        case "Sonnet": return .blue
        case "Haiku": return .teal
        case "Fable": return .orange
        default: return .gray
        }
    }
}
