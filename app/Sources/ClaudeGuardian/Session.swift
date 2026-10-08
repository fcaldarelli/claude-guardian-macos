import Foundation

/// Stato di una sessione Claude Code, come scritto dall'hook.
enum SessionState: String, Decodable {
    case working, waiting, stalled, idle, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionState(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .working: return "Working"
        case .waiting: return "Waiting for you"
        case .stalled: return "No activity"
        case .idle:    return "Idle"
        case .unknown: return "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .working: return "gearshape.2.fill"
        case .waiting: return "hand.raised.fill"
        case .stalled: return "pause.circle"
        case .idle:    return "moon.zzz"
        case .unknown: return "questionmark.circle"
        }
    }

    var emoji: String {
        switch self {
        case .working: return "⚙️"
        case .waiting: return "✋"
        case .stalled: return "⏸️"
        case .idle:    return "💤"
        case .unknown: return "❔"
        }
    }

    /// Ordine nel menu: prima chi aspetta te, poi chi lavora, poi le inattive.
    var sortOrder: Int {
        switch self {
        case .waiting: return 0
        case .working: return 1
        case .stalled: return 2
        case .idle:    return 3
        case .unknown: return 4
        }
    }
}

struct Session: Identifiable, Decodable {
    let sessionId: String
    /// Stato scritto dall'hook; il monitor può correggerlo (interruzioni, inattività).
    var state: SessionState
    let event: String?
    let cwd: String
    let projectRoot: String?
    let transcriptPath: String?
    let pid: Int32
    let appPath: String?
    let appPid: Int32?
    let tty: String?
    let updatedAt: TimeInterval

    /// Titolo letto dal transcript (non presente nel file di stato).
    var title: String?

    var id: String { sessionId }

    /// Radice del progetto (cartella con .idea, .vscode o .git), oppure la cartella della sessione.
    var rootPath: String {
        if let root = projectRoot, !root.isEmpty { return root }
        return cwd
    }

    /// Sottocartella rispetto alla radice, se Claude è stato lanciato più in profondità.
    var subPath: String? {
        guard rootPath != cwd, cwd.hasPrefix(rootPath + "/") else { return nil }
        return String(cwd.dropFirst(rootPath.count + 1))
    }

    /// Bundle dell'app che ha lanciato la sessione (Terminal, iTerm, VS Code, IntelliJ...).
    var appURL: URL? {
        guard let path = appPath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var appName: String? {
        appURL?.deletingPathExtension().lastPathComponent
    }

    var projectName: String {
        let name = URL(fileURLWithPath: rootPath).lastPathComponent
        return name.isEmpty ? "Session" : name
    }

    /// Nome mostrato nel menu: "progetto" oppure "progetto/sottocartella".
    var displayName: String {
        if let sub = subPath { return "\(projectName)/\(sub)" }
        return projectName
    }

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt) }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state, event, cwd, pid, tty
        case appPath = "app_path"
        case appPid = "app_pid"
        case projectRoot = "project_root"
        case transcriptPath = "transcript_path"
        case updatedAt = "updated_at"
    }
}
