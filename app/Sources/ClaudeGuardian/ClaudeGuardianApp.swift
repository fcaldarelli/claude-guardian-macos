import SwiftUI
import AppKit
import ServiceManagement

@main
struct ClaudeGuardianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = ActivityMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor)
        } label: {
            // "⚙ 3  ✋ 1  ☾ 2": al lavoro, in attesa, inattive. Senza sessioni aperte solo l'icona.
            Image(nsImage: MenuBarIcon.image(
                working: monitor.workingCount,
                waiting: monitor.waitingCount,
                idle: monitor.idleCount,
                hasSessions: !monitor.sessions.isEmpty
            ))
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Niente icona nel Dock anche quando l'app è lanciata fuori dal bundle (swift run).
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuContent: View {
    @ObservedObject var monitor: ActivityMonitor

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .short
        return f
    }()

    /// Rientri: i menu di macOS non hanno livelli di indentazione in SwiftUI,
    /// quindi si usano spazi em (U+2003), che a differenza degli spazi normali non vengono rimossi.
    private static let projectIndent = "\u{2003}"
    private static let sessionIndent = "\u{2003}\u{2003}\u{2003}"

    /// "⚙️  Titolo sessione · Working · 2 min. ago"
    /// Se la sessione è in una sottocartella: "⚙️  Titolo · backend/ · Working · 2 min. ago"
    private func sessionLine(_ session: Session) -> String {
        let when = Self.relative.localizedString(for: session.updatedDate, relativeTo: Date())
        var parts = [session.title ?? "Untitled session"]
        if let sub = session.subPath { parts.append("\(sub)/") }
        parts.append(session.state.label)
        parts.append(when)
        return "\(Self.sessionIndent)\(session.state.emoji)  \(parts.joined(separator: " · "))"
    }

    /// Clic: torna all'app della sessione. Opzione+clic: cartella nel Finder.
    /// Maiuscole+clic: copia negli appunti la diagnostica.
    private func open(_ session: Session) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(SessionFocuser.diagnostics(for: session), forType: .string)
        } else if flags.contains(.option) {
            SessionFocuser.revealInFinder(session)
        } else {
            SessionFocuser.focus(session)
        }
    }

    var body: some View {
        Text("Working: \(monitor.workingCount) · Waiting for you: \(monitor.waitingCount) · Idle: \(monitor.idleCount)")

        if monitor.sessions.isEmpty {
            Divider()
            Text("No active Claude Code sessions")
        } else {
            // App → progetto → sessioni. Le intestazioni delle app sono testo non cliccabile;
            // progetti e sessioni sono cliccabili.
            ForEach(SessionGrouping.group(monitor.sessions)) { app in
                Divider()
                Text(app.name)

                ForEach(app.projects) { project in
                    Button {
                        // Le sessioni di uno stesso progetto e app condividono la finestra:
                        // si usa la più urgente.
                        if let first = project.sessions.first { open(first) }
                    } label: {
                        Text("\(Self.projectIndent)📁 \(project.name)")
                    }
                    .help(project.id)

                    ForEach(project.sessions) { session in
                        Button {
                            open(session)
                        } label: {
                            // Emoji nel testo: nei menu di MenuBarExtra le icone di Label
                            // non compaiono su tutte le versioni di macOS.
                            Text(sessionLine(session))
                        }
                        .help(session.cwd)
                    }
                }
            }
        }

        Divider()

        // Il menu viene ricostruito a ogni apertura, quindi la voce sparisce
        // appena il permesso è concesso.
        if !SessionFocuser.accessibilityEnabled {
            Button("Enable Accessibility to Open the Right Window…") {
                SessionFocuser.requestAccessibility()
            }
        }

        LoginItemToggle()

        Button("Open State Folder") {
            NSWorkspace.shared.open(monitor.directory)
        }

        Button("Refresh") { monitor.reload() }
            .keyboardShortcut("r")

        Divider()

        Text("Claude Guardian \(AppInfo.versionString)")

        Button("Quit Claude Guardian") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Toggle "Apri al login". Funziona solo con l'app impacchettata (build-app.sh), non con `swift run`.
struct LoginItemToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at Login", isOn: $enabled)
            .onChange(of: enabled) { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("ClaudeGuardian: could not update login item: \(error.localizedDescription)")
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
