import Foundation

/// Versione dell'app: unica fonte.
///
/// Per rilasciare una nuova versione basta cambiare questi valori.
/// build-app.sh li legge da questo file e li scrive nell'Info.plist,
/// così la versione nel menu e quella mostrata dal Finder coincidono.
enum AppInfo {
    static let version = "1.0.0"
    static let build = "1"

    /// "1.0.0", oppure "1.0.0 (42)" se il numero di build è diverso da "1".
    static var versionString: String {
        build == "1" ? version : "\(version) (\(build))"
    }
}
