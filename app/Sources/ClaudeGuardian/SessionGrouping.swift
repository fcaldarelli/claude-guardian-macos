import Foundation

/// Sessioni raggruppate per app di origine e, dentro ogni app, per progetto.
struct AppGroup: Identifiable {
    let id: String              // percorso del bundle, o "" se l'app non è identificata
    let name: String
    let projects: [ProjectGroup]
    /// Stato più urgente tra le sessioni del gruppo (per l'ordinamento).
    let priority: Int
}

struct ProjectGroup: Identifiable {
    let id: String              // radice del progetto
    let name: String
    let sessions: [Session]
    let priority: Int
}

enum SessionGrouping {

    static func group(_ sessions: [Session]) -> [AppGroup] {
        let byApp = Dictionary(grouping: sessions) { $0.appPath ?? "" }

        let apps = byApp.map { appPath, appSessions -> AppGroup in
            let byProject = Dictionary(grouping: appSessions) { $0.rootPath }

            let projects = byProject.map { root, projectSessions -> ProjectGroup in
                let sorted = projectSessions.sorted(by: sessionOrder)
                return ProjectGroup(
                    id: root,
                    name: sorted.first?.projectName ?? root,
                    sessions: sorted,
                    priority: sorted.map(\.state.sortOrder).min() ?? .max
                )
            }
            .sorted { groupOrder($0, $1) }

            return AppGroup(
                id: appPath,
                name: appSessions.first?.appName ?? "Unknown App",
                projects: projects,
                priority: projects.map(\.priority).min() ?? .max
            )
        }

        return apps.sorted { groupOrder($0, $1) }
    }

    /// Prima chi aspetta te, poi chi lavora, poi le inattive; a parità, la più recente.
    private static func sessionOrder(_ a: Session, _ b: Session) -> Bool {
        if a.state.sortOrder != b.state.sortOrder { return a.state.sortOrder < b.state.sortOrder }
        return a.updatedAt > b.updatedAt
    }

    private static func groupOrder<G: NamedGroup>(_ a: G, _ b: G) -> Bool {
        if a.priority != b.priority { return a.priority < b.priority }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

protocol NamedGroup {
    var name: String { get }
    var priority: Int { get }
}

extension AppGroup: NamedGroup {}
extension ProjectGroup: NamedGroup {}
