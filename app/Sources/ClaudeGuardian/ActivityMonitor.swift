import Foundation
import Darwin

/// Legge i file di stato scritti dall'hook in ~/.claude/activity e
/// tiene aggiornato l'elenco delle sessioni.
final class ActivityMonitor: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    var workingCount: Int { sessions.filter { $0.state == .working }.count }
    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    /// Inattive: turno finito, oppure "al lavoro" senza attività da troppo tempo.
    var idleCount: Int { sessions.filter { $0.state == .idle || $0.state == .stalled }.count }

    /// Icona nella barra: mano alzata se almeno una sessione aspetta un tuo permesso.
    var menuBarSymbol: String {
        if waitingCount > 0 { return "hand.raised.fill" }
        return workingCount > 0 ? "sparkles" : "sparkle"
    }

    let directory: URL = {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_ACTIVITY_DIR"] {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/activity", isDirectory: true)
    }()

    /// Oltre questo tempo senza aggiornamenti una sessione senza PID valido viene ignorata.
    private let staleAfter: TimeInterval = 12 * 60 * 60

    /// Dopo quanto tempo senza alcuna attività una sessione "al lavoro" viene considerata ferma.
    /// Un comando molto lungo (es. una build di 15 minuti) può superarlo: in quel caso compare
    /// come "Nessuna attività" finché non termina.
    private let stalledAfter: TimeInterval = 10 * 60

    private let titleReader = TranscriptTitleReader()
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        startWatching()
        // Controllo periodico: serve a scartare le sessioni il cui processo è morto
        // senza che l'hook SessionEnd sia scattato (crash, terminale chiuso).
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.reload()
        }
    }

    deinit {
        timer?.invalidate()
        source?.cancel()
    }

    func reload() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        let now = Date().timeIntervalSince1970

        var result: [Session] = []
        for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
            guard let data = try? Data(contentsOf: file),
                  var session = try? decoder.decode(Session.self, from: data) else { continue }

            if !isAlive(session, now: now) {
                try? fm.removeItem(at: file)
                continue
            }
            var lastActivity = session.updatedAt
            if let path = session.transcriptPath, !path.isEmpty {
                let info = titleReader.info(forTranscriptAt: path)
                session.title = info.title

                // Interruzione (Esc) o errore API: Claude Code non chiama l'hook Stop,
                // quindi lo stato registrato resterebbe "al lavoro".
                if info.interrupted && (session.state == .working || session.state == .waiting) {
                    session.state = .idle
                }
                if let modified = info.lastModified {
                    lastActivity = max(lastActivity, modified.timeIntervalSince1970)
                }
            }
            // Rete di sicurezza: "al lavoro" ma nessun evento e nessuna scrittura nel transcript
            // da troppo tempo. Non viene più contata tra le sessioni al lavoro.
            if session.state == .working && now - lastActivity > stalledAfter {
                session.state = .stalled
            }
            result.append(session)
        }
        titleReader.retain(only: Set(result.compactMap(\.transcriptPath)))

        result.sort {
            if $0.state.sortOrder != $1.state.sortOrder { return $0.state.sortOrder < $1.state.sortOrder }
            return $0.updatedAt > $1.updatedAt
        }

        let apply = { self.sessions = result }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    private func isAlive(_ session: Session, now: TimeInterval) -> Bool {
        if session.pid > 1 {
            // kill(pid, 0) non invia segnali: verifica solo che il processo esista.
            if kill(session.pid, 0) == 0 { return true }
            return errno == EPERM
        }
        return now - session.updatedAt < staleAfter
    }

    /// Osserva la cartella: ogni scrittura dell'hook aggiorna subito il conteggio.
    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.reload() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }
}
