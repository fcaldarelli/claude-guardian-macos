import AppKit
import ApplicationServices

/// Riporta in primo piano l'app, la finestra e quando possibile la scheda
/// da cui è stata lanciata una sessione Claude Code.
///
/// Strategia, dalla più precisa alla più generica:
///  1. Terminal / iTerm2: scheda esatta tramite il tty (AppleScript).
///  2. Qualsiasi app: finestra il cui titolo contiene il nome del progetto (Accessibilità).
///  3. Editor: apertura della radice del progetto, che porta avanti la finestra già aperta.
///  4. Altrimenti: attivazione dell'app.
enum SessionFocuser {

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
    ]

    private static func isEditor(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.microsoft.VSCode")      // VS Code e Insiders
            || bundleID.hasPrefix("com.jetbrains.")      // IntelliJ, PyCharm, WebStorm...
            || bundleID.hasPrefix("com.google.android.studio")
            || bundleID == "com.vscodium"
            || bundleID == "com.todesktop.230313mzl4w4u92" // Cursor
            || bundleID == "com.exafunction.windsurf"
            || bundleID == "dev.zed.Zed"
    }

    static func focus(_ session: Session) {
        guard let appURL = session.appURL,
              let bundle = Bundle(url: appURL),
              let bundleID = bundle.bundleIdentifier else {
            // App non identificata (es. sessione dentro tmux): mostra la cartella nel Finder.
            revealInFinder(session)
            return
        }

        let running = runningApp(for: session, bundleID: bundleID)

        if terminalBundleIDs.contains(bundleID) {
            if let tty = session.tty, !tty.isEmpty, selectTerminalTab(bundleID: bundleID, tty: tty) {
                return
            }
            if let running, raiseWindow(of: running, for: session) { return }
            activate(running, appURL: appURL)
            return
        }

        if isEditor(bundleID) {
            // Prima si cerca la finestra già aperta (nessun effetto collaterale);
            // se non si trova, si chiede all'editor di aprire la radice del progetto.
            if let running, raiseWindow(of: running, for: session) { return }

            if bundleID.hasPrefix("com.jetbrains.") || bundleID.hasPrefix("com.google.android.studio") {
                // Come il launcher da riga di comando di JetBrains ("idea /percorso"):
                // il percorso viene passato all'istanza già aperta, che porta in primo
                // piano la finestra di quel progetto (anche a schermo intero in un altro Spazio).
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-na", appURL.path, "--args", session.rootPath]
                if (try? process.run()) != nil { return }
            }

            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: session.rootPath)],
                withApplicationAt: appURL,
                configuration: config
            )
            return
        }

        if let running, raiseWindow(of: running, for: session) { return }
        activate(running, appURL: appURL)
    }

    static func revealInFinder(_ session: Session) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
    }

    // MARK: - App

    /// Se l'hook ha registrato il PID dell'app si usa quello (utile con più copie della
    /// stessa app, es. IntelliJ Ultimate e Community); altrimenti si cerca per bundle id.
    private static func runningApp(for session: Session, bundleID: String) -> NSRunningApplication? {
        if let pid = session.appPid, pid > 1,
           let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier == bundleID {
            return app
        }
        let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let appURL = session.appURL,
           let exact = candidates.first(where: { $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL }) {
            return exact
        }
        return candidates.first
    }

    private static func activate(_ running: NSRunningApplication?, appURL: URL) {
        if let running {
            running.unhide()
            running.activate(options: [.activateAllWindows])
        } else {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }

    // MARK: - Finestra per titolo (Accessibilità)

    static var accessibilityEnabled: Bool { AXIsProcessTrusted() }

    /// Mostra la richiesta di sistema per il permesso di Accessibilità.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Finestre dell'app con il loro titolo (solo quelle visibili all'Accessibilità:
    /// le finestre a schermo intero in altri Spazi di solito non compaiono).
    private static func titledWindows(of app: NSRunningApplication) -> [(AXUIElement, String)] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }

        return windows.compactMap { window in
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                  let text = title as? String, !text.isEmpty else { return nil }
            return (window, text)
        }
    }

    /// Cerca tra le finestre dell'app quella del progetto e la porta in primo piano.
    private static func raiseWindow(of app: NSRunningApplication, for session: Session) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let window = bestMatch(in: titledWindows(of: app), for: session) else { return false }

        // Prima si attiva l'app, poi si alza la finestra: nell'ordine inverso l'attivazione
        // riporterebbe davanti l'ultima finestra usata (es. l'altro progetto IntelliJ).
        app.unhide()
        app.activate(options: [])
        bringToFront(window, of: app)

        // L'attivazione è asincrona: si ripete il raise appena l'app è davvero attiva.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { bringToFront(window, of: app) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { bringToFront(window, of: app) }
        return true
    }

    private static func bringToFront(_ window: AXUIElement, of app: NSRunningApplication) {
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Nomi con cui il progetto può comparire nel titolo della finestra.
    private static func candidateNames(for session: Session) -> [String] {
        var names = [session.projectName, URL(fileURLWithPath: session.cwd).lastPathComponent]
        // IntelliJ usa il nome del progetto salvato in .idea/.name, che può differire dalla cartella.
        let ideaName = URL(fileURLWithPath: session.rootPath).appendingPathComponent(".idea/.name")
        if let name = try? String(contentsOf: ideaName, encoding: .utf8) {
            names.append(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var seen = Set<String>()
        return names.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Divide un titolo nei suoi pezzi. Si divide sui trattini solo se circondati da spazi,
    /// così un progetto come "shop-backend" resta intero.
    private static func titleParts(_ title: String) -> [String] {
        var text = title
        for separator in [" — ", " – ", " - ", " | ", "[", "]", "(", ")"] {
            text = text.replacingOccurrences(of: separator, with: "\u{1F}")
        }
        return text.split(separator: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Sceglie la finestra più probabile. Prima corrispondenze esatte su un "pezzo" del titolo
    /// (gli editor usano titoli come "progetto – File.java" o "file.ts — progetto"),
    /// poi il percorso completo, poi il nome contenuto nel titolo, solo se univoco.
    private static func bestMatch(in windows: [(AXUIElement, String)], for session: Session) -> AXUIElement? {
        let names = candidateNames(for: session)
        let parts = titleParts

        // 1. Un pezzo del titolo coincide con il nome del progetto.
        let exact = windows.filter { _, title in
            parts(title).contains { part in names.contains { $0.caseInsensitiveCompare(part) == .orderedSame } }
        }
        if exact.count == 1 { return exact[0].0 }

        // 2. Il titolo contiene il percorso della sessione (alcuni terminali mostrano la cartella).
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [session.cwd, session.cwd.replacingOccurrences(of: home, with: "~")]
        let byPath = windows.filter { _, title in paths.contains { title.contains($0) } }
        if byPath.count == 1 { return byPath[0].0 }
        if !exact.isEmpty { return exact[0].0 }

        // 3. Il nome compare nel titolo: accettato solo se una sola finestra corrisponde,
        //    per evitare di aprire quella sbagliata (es. "app" dentro "my-app").
        let loose = windows.filter { _, title in
            names.contains { title.localizedCaseInsensitiveContains($0) }
        }
        return loose.count == 1 ? loose[0].0 : nil
    }

    // MARK: - Diagnostica

    /// Testo con ciò che l'app vede per questa sessione, da incollare in caso di problemi.
    static func diagnostics(for session: Session) -> String {
        var lines = [
            "Claude Guardian \(AppInfo.versionString) – diagnostics",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Session: \(session.sessionId)",
            "Displayed state: \(session.state.rawValue) · last hook event: \(session.event ?? "-") \(Date(timeIntervalSince1970: session.updatedAt))",
            "Transcript: \(session.transcriptPath ?? "- (not yet recorded by the hook)")",
            "Folder: \(session.cwd)",
            "Project root: \(session.rootPath)",
            "Names searched: \(candidateNames(for: session).joined(separator: " | "))",
            "App: \(session.appPath ?? "-") (recorded pid: \(session.appPid ?? 0))",
            "TTY: \(session.tty ?? "-")",
            "Accessibility granted: \(AXIsProcessTrusted() ? "yes" : "NO")",
        ]

        guard let appURL = session.appURL,
              let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
            lines.append("Bundle not identified")
            return lines.joined(separator: "\n")
        }
        lines.append("Bundle id: \(bundleID)")

        guard let running = runningApp(for: session, bundleID: bundleID) else {
            lines.append("App not running")
            return lines.joined(separator: "\n")
        }
        lines.append("Instance: pid \(running.processIdentifier)")

        let windows = titledWindows(of: running)
        let chosen = bestMatch(in: windows, for: session)
        lines.append("Windows visible to Accessibility: \(windows.count)")
        for (window, title) in windows {
            let mark = (chosen.map { CFEqual($0, window) } ?? false) ? "→" : " "
            lines.append("\(mark) \(title)   [parts: \(titleParts(title).joined(separator: " | "))]")
        }
        if chosen == nil {
            lines.append("No window selected: using the fallback (opening the project).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Terminal / iTerm2 (AppleScript)

    /// Seleziona la scheda del terminale con quel tty.
    /// La prima volta macOS chiede il permesso di "Automazione" per controllare il terminale.
    private static func selectTerminalTab(bundleID: String, tty: String) -> Bool {
        let safeTTY = tty.replacingOccurrences(of: "\"", with: "")
        let source: String
        switch bundleID {
        case "com.apple.Terminal":
            source = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(safeTTY)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        case "com.googlecode.iterm2":
            source = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(safeTTY)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return false
        }

        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("ClaudeGuardian: AppleScript failed: \(error)")
            return false
        }
        return result?.booleanValue ?? false
    }
}
