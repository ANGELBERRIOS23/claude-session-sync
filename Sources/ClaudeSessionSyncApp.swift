import SwiftUI
import ServiceManagement

@main
struct ClaudeSessionSyncApp: App {
    @State private var store = SessionStore()
    @State private var vault = SessionVault()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                RootView(store: store, vault: vault)

                Divider()

                bottomBar
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .menuBarExtraStyle(.window)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("v1.1.1")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Button {
                restartClaude()
            } label: {
                Label(L10n.restartClaude, systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()

            Toggle(isOn: $launchAtLogin) {
                Label(L10n.launchAtLogin, systemImage: "power")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            Button(L10n.quit) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func restartClaude() {
        let bundleId = "com.anthropic.claudefordesktop"
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard let app = apps.first else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        let url = app.bundleURL
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let url {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            store.lastSyncMessage = L10n.restarted
            store.lastSyncSuccess = true
        }
    }

    init() {
        // launchd invokes the same binary with `--backup` for the daily pass. Handle it
        // and exit before any window or menu bar item is created, so the scheduled run
        // stays headless and leaves no stray icon behind.
        let stamp = ISO8601DateFormatter().string(from: Date())

        if CommandLine.arguments.contains("--compact") {
            let v = SessionVault()
            let c = v.compact()
            FileHandle.standardOutput.write(Data(
                "[\(stamp)] orphans=\(c.orphansDeleted) recompressed=\(c.recompressed) freed=\(c.total) remaining=\(v.onDiskBytes)\n".utf8
            ))
            exit(0)
        }

        if CommandLine.arguments.contains("--backup") {
            let v = SessionVault()
            let outcome = v.backupNow()
            FileHandle.standardOutput.write(Data(
                "[\(stamp)] saved=\(outcome.newEntries + outcome.updatedEntries) unchanged=\(outcome.unchanged) restored=\(outcome.restored) bytes=\(outcome.bytesWritten) freed=\(outcome.bytesFreed) errors=\(outcome.errors.count)\n".utf8
            ))
            exit(outcome.errors.isEmpty ? 0 : 1)
        }

        _store = State(initialValue: {
            let s = SessionStore()
            s.scan()
            return s
        }())
        _vault = State(initialValue: {
            let v = SessionVault()
            v.load()
            return v
        }())
    }
}
