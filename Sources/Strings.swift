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

    // MARK: - Vault

    static var tabSync: String {
        current == .es ? "Sincronizar" : "Sync"
    }
    static var tabVault: String {
        current == .es ? "Respaldo" : "Vault"
    }
    static var vaultTitle: String {
        current == .es ? "Respaldo de sesiones" : "Session vault"
    }
    static var vaultEmpty: String {
        current == .es ? "Respaldo vacio" : "Vault is empty"
    }
    static var vaultEmptyDetail: String {
        current == .es
            ? "Corre un respaldo para guardar tus sesiones fuera del alcance de Claude"
            : "Run a backup to keep your sessions outside Claude's reach"
    }
    static var backupNow: String {
        current == .es ? "Respaldar ahora" : "Back up now"
    }
    static var restoreAll: String {
        current == .es ? "Restaurar faltantes" : "Restore missing"
    }
    static var restore: String {
        current == .es ? "Restaurar" : "Restore"
    }
    static var dailyBackup: String {
        current == .es ? "Respaldo diario" : "Daily backup"
    }
    static var autoRestore: String {
        current == .es ? "Auto-restaurar lo que Claude borre" : "Auto-restore what Claude deletes"
    }
    static var autoRestoreHelp: String {
        current == .es
            ? "En cada respaldo, devuelve al disco las sesiones que Claude haya eliminado"
            : "On every backup, puts back any session Claude has deleted"
    }
    static var changeLocation: String {
        current == .es ? "Cambiar ubicacion" : "Change location"
    }
    static var vaultLocation: String {
        current == .es ? "Ubicacion" : "Location"
    }
    static var neverBackedUp: String {
        current == .es ? "Sin respaldos aun" : "No backup yet"
    }
    static var gone: String {
        current == .es ? "Borrada por Claude" : "Deleted by Claude"
    }
    static var transcriptOnly: String {
        current == .es ? "Solo transcripcion" : "Transcript only"
    }
    static var indexOnly: String {
        current == .es ? "Solo indice" : "Index only"
    }

    static func backedUpCount(_ n: Int) -> String {
        current == .es ? "\(n) respaldadas" : "\(n) backed up"
    }
    static func recoverableCount(_ n: Int) -> String {
        current == .es ? "\(n) recuperable(s)" : "\(n) recoverable"
    }
    static func restoredCount(_ n: Int) -> String {
        if n == 0 { return current == .es ? "Nada que restaurar" : "Nothing to restore" }
        return current == .es ? "\(n) archivo(s) restaurado(s)" : "\(n) file(s) restored"
    }
    static func restoreSummary(_ restored: Int, _ recovered: Int) -> String {
        if restored == 0 && recovered == 0 {
            return current == .es ? "Nada que restaurar" : "Nothing to restore"
        }
        if recovered == 0 { return restoredCount(restored) }
        if restored == 0 {
            return current == .es
                ? "\(recovered) copia(s) completa(s) guardada(s) en el respaldo"
                : "\(recovered) fuller copy(ies) saved in the vault"
        }
        return current == .es
            ? "\(restored) restaurada(s), \(recovered) copia(s) completa(s) en el respaldo"
            : "\(restored) restored, \(recovered) fuller copy(ies) in the vault"
    }
    static var truncated: String {
        current == .es ? "Recortada en disco" : "Truncated on disk"
    }
    static var compact: String {
        current == .es ? "Liberar espacio" : "Reclaim space"
    }
    static func compacted(_ bytes: Int) -> String {
        if bytes <= 0 { return current == .es ? "Nada que liberar" : "Nothing to reclaim" }
        let s = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return current == .es ? "\(s) liberados" : "\(s) reclaimed"
    }
    static func backupDone(_ saved: Int, _ restored: Int) -> String {
        if restored > 0 {
            return current == .es
                ? "Respaldo listo: \(saved) guardada(s), \(restored) restaurada(s)"
                : "Backup done: \(saved) saved, \(restored) restored"
        }
        return current == .es ? "Respaldo listo: \(saved) guardada(s)" : "Backup done: \(saved) saved"
    }
    static func lastBackup(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        let rel = f.localizedString(for: date, relativeTo: .now)
        return current == .es ? "Ultimo respaldo \(rel)" : "Last backup \(rel)"
    }
}
