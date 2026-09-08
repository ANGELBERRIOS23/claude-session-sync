import Foundation

enum Lang: String, CaseIterable {
    case en = "en"
    case es = "es"

    var displayName: String {
        switch self {
        case .en: return "English"
        case .es: return "Espanol"
        }
    }

    var flag: String {
        switch self {
        case .en: return "EN"
        case .es: return "ES"
        }
    }
}

enum L10n {
    nonisolated(unsafe) static var current: Lang = {
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        return locale == "es" ? .es : .en
    }()

    static var appTitle: String { "Claude Session Sync" }

    static var refresh: String {
        current == .es ? "Refrescar" : "Refresh"
    }
    static var scanning: String {
        current == .es ? "Escaneando..." : "Scanning..."
    }
    static var noSessions: String {
        current == .es ? "Sin sesiones" : "No sessions"
    }
    static var noSessionsDetail: String {
        current == .es ? "No se encontraron sesiones de Claude Code" : "No Claude Code sessions found"
    }
    static var syncSelected: String {
        current == .es ? "Sync seleccionadas" : "Sync selected"
    }
    static var syncAll: String {
        current == .es ? "Sync todas" : "Sync all"
    }
    static var quit: String {
        current == .es ? "Salir" : "Quit"
    }
    static var syncedBadge: String {
        current == .es ? "Sincronizada en ambas apps" : "Synced across apps"
    }
    static var noTitle: String {
        current == .es ? "Sin titulo" : "Untitled"
    }
    static var remove: String {
        current == .es ? "Quitar sync" : "Remove sync"
    }
    static var removeConfirm: String {
        current == .es ? "Quitar de la otra app?" : "Remove from other app?"
    }
    static var language: String {
        current == .es ? "Idioma" : "Language"
    }
    static var launchAtLogin: String {
        current == .es ? "Abrir al iniciar" : "Launch at login"
    }
    static var restartClaude: String {
        current == .es ? "Reiniciar Claude" : "Restart Claude"
    }
    static var restarted: String {
        current == .es ? "Claude reiniciado" : "Claude restarted"
    }

    static func sessions(_ n: Int) -> String {
        current == .es ? "\(n) sesiones" : "\(n) sessions"
    }
    static func unsynced(_ n: Int) -> String {
        current == .es ? "\(n) sin sincronizar" : "\(n) unsynced"
    }
    static func syncedCount(_ n: Int) -> String {
        current == .es ? "\(n) sesion(es) sincronizada(s)" : "\(n) session(s) synced"
    }
    static func removedCount(_ n: Int) -> String {
        current == .es ? "\(n) sesion(es) removida(s)" : "\(n) session(s) removed"
    }
    static var allSynced: String {
        current == .es ? "Todo sincronizado" : "All synced"
    }
    static var nothingToSync: String {
        current == .es ? "Nada nuevo que sincronizar" : "Nothing new to sync"
    }
    static func syncError(_ msg: String) -> String { "Error: \(msg)" }

    static var personalLabel: String {
        current == .es ? "Claude (Personal)" : "Claude (Personal)"
    }
    static var bedrockLabel: String { "Claude-3p (Bedrock)" }
}
