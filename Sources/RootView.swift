import SwiftUI

struct RootView: View {
    @Bindable var store: SessionStore
    @Bindable var vault: SessionVault
    @State private var tab: Tab = .sync
    @State private var langRefresh = UUID()

    enum Tab: Hashable { case sync, vault }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker
            Divider()

            switch tab {
            case .sync: SessionListView(store: store)
            case .vault: VaultView(vault: vault)
            }
        }
        .frame(width: 520, height: 580)
        .id(langRefresh)
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
            Text(L10n.appTitle)
                .font(.headline)

            Spacer()

            langToggle

            Button {
                store.scan()
                vault.load()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.refresh)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var tabPicker: some View {
        Picker("", selection: $tab) {
            Text(L10n.tabSync).tag(Tab.sync)
            // Surfaces the count of sessions the vault can put back, so the tab is
            // actionable without opening it.
            Text(vault.recoverableCount > 0
                 ? "\(L10n.tabVault) (\(vault.recoverableCount))"
                 : L10n.tabVault).tag(Tab.vault)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var langToggle: some View {
        Button {
            L10n.current = L10n.current == .es ? .en : .es
            langRefresh = UUID()
        } label: {
            Text(L10n.current.flag)
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.borderless)
        .help(L10n.language)
    }
}
