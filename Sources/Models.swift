import Foundation

struct SessionInfo: Identifiable, Hashable {
    let sessionId: String
    let cliSessionId: String?
    let title: String
    let model: String
    let cwd: String
    let createdAt: Date?
    let lastActivityAt: Date?
    let isArchived: Bool
    let sourceFile: URL

    var id: String { sessionId }

    var modelShort: String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("fable") { return "Fable" }
        if m.contains("deepseek") { return "DeepSeek" }
        return model.components(separatedBy: ".").last ?? model
    }

    var cwdShort: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    var lastActivityFormatted: String {
        guard let date = lastActivityAt ?? createdAt else { return "?" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

struct AccountGroup: Identifiable {
    let appLabel: String
    let appBase: URL
    let accountUUID: String
    let orgUUID: String
    let orgPath: URL
    var sessions: [SessionInfo]

    var id: String { "\(appLabel)/\(accountUUID)/\(orgUUID)" }
}

enum AppSource: String, CaseIterable {
    case claude = "Claude"
    case claude3p = "Claude-3p"

    var label: String {
        switch self {
        case .claude: return L10n.personalLabel
        case .claude3p: return L10n.bedrockLabel
        }
    }

    var baseURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(rawValue).appendingPathComponent("claude-code-sessions")
    }

    #if os(Windows)
    var baseURLWindows: URL {
        let appData = ProcessInfo.processInfo.environment["APPDATA"] ?? ""
        return URL(fileURLWithPath: appData)
            .appendingPathComponent(rawValue)
            .appendingPathComponent("claude-code-sessions")
    }
    #endif
}

func parseSession(from url: URL) -> SessionInfo? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    guard let sessionId = dict["sessionId"] as? String else { return nil }

    let createdMs = dict["createdAt"] as? Double
    let activityMs = dict["lastActivityAt"] as? Double

    return SessionInfo(
        sessionId: sessionId,
        cliSessionId: dict["cliSessionId"] as? String,
        title: dict["title"] as? String ?? L10n.noTitle,
        model: dict["model"] as? String ?? "?",
        cwd: dict["cwd"] as? String ?? "?",
        createdAt: createdMs.map { Date(timeIntervalSince1970: $0 / 1000) },
        lastActivityAt: activityMs.map { Date(timeIntervalSince1970: $0 / 1000) },
        isArchived: dict["isArchived"] as? Bool ?? false,
        sourceFile: url
    )
}
