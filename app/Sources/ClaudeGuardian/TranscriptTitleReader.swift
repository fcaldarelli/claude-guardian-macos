import Foundation

/// Ricava il titolo di una sessione dal suo transcript JSONL.
///
/// Priorità:
///  1. nome dato con /rename (o --name)
///  2. titolo generato automaticamente da Claude Code
///  3. primo messaggio scritto dall'utente
///
/// Il formato del transcript non è un'API documentata e può cambiare tra versioni:
/// per questo il parser è tollerante (accetta più nomi di campo) e, se non trova
/// un titolo, ripiega sul primo prompt.
///
/// Il file viene letto in modo incrementale: a ogni chiamata si leggono solo
/// i byte aggiunti dall'ultima volta.
final class TranscriptTitleReader {

    private struct State {
        var offset: UInt64 = 0
        var remainder = Data()
        var customTitle: String?
        var autoTitle: String?
        var firstPrompt: String?
        /// L'ultimo evento del transcript è un'interruzione dell'utente o un errore API:
        /// in questi casi Claude Code non invoca l'hook Stop.
        var interrupted = false
        var lastModified: Date?

        var title: String? { customTitle ?? autoTitle ?? firstPrompt }
    }

    private var states: [String: State] = [:]
    private let maxLength = 60

    struct Info {
        let title: String?
        let interrupted: Bool
        let lastModified: Date?
    }

    func info(forTranscriptAt path: String) -> Info {
        _ = title(forTranscriptAt: path)
        let state = states[path] ?? State()
        return Info(title: state.title, interrupted: state.interrupted, lastModified: state.lastModified)
    }

    func title(forTranscriptAt path: String) -> String? {
        var state = states[path] ?? State()
        defer { states[path] = state }

        state.lastModified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date

        guard let handle = FileHandle(forReadingAtPath: path) else { return state.title }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd() else { return state.title }
        if end < state.offset {                            // file ricreato o troncato
            let modified = state.lastModified
            state = State()
            state.lastModified = modified
        }
        guard end > state.offset else { return state.title }

        do {
            try handle.seek(toOffset: state.offset)
            var data = state.remainder
            if let chunk = try handle.read(upToCount: Int(end - state.offset)) {
                data.append(chunk)
            }
            state.offset = end

            var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            // L'ultima riga può essere incompleta (Claude Code sta ancora scrivendo): la teniamo da parte.
            state.remainder = Data(lines.removeLast())
            for line in lines where !line.isEmpty {
                process(Data(line), into: &state)
            }
        } catch {
            return state.title
        }
        return state.title
    }

    /// Libera la memoria dei transcript di sessioni non più presenti.
    func retain(only paths: Set<String>) {
        states = states.filter { paths.contains($0.key) }
    }

    // MARK: - Parsing

    private func process(_ line: Data, into state: inout State) {
        guard let text = String(data: line, encoding: .utf8) else { return }

        // Stato del turno: interruzione o errore API chiudono il turno senza hook Stop;
        // qualsiasi messaggio successivo (nuovo prompt, risposta, strumento) lo riapre.
        if text.contains("\"isApiErrorMessage\":true") {
            state.interrupted = true
            return
        }
        if text.contains("[Request interrupted by user"), isInterruptMarker(line) {
            state.interrupted = true
            return
        }
        if text.contains("\"type\":\"assistant\"") || text.contains("\"type\":\"user\"") {
            state.interrupted = false
        }

        // Filtro veloce prima del parsing JSON: la gran parte delle righe non ci interessa.
        let maybeTitle = text.contains("itle\"") || text.contains("\"summary\"")
        let maybePrompt = state.firstPrompt == nil && text.contains("\"type\":\"user\"")
        guard maybeTitle || maybePrompt else { return }

        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else { return }

        if type == "user" {
            if state.firstPrompt == nil, let prompt = userPrompt(from: object) {
                state.firstPrompt = prompt
            }
            return
        }

        let lowered = type.lowercased()
        guard lowered == "summary" || lowered.contains("title") else { return }

        let keys = ["customTitle", "custom_title", "title", "aiTitle", "ai_title", "summary"]
        guard let raw = keys.lazy.compactMap({ object[$0] as? String }).first,
              let value = clean(raw) else { return }

        if lowered.contains("custom") || object["customTitle"] != nil {
            state.customTitle = value       // l'ultimo /rename vince
        } else {
            state.autoTitle = value
        }
    }

    /// Verifica che la riga sia davvero il messaggio di interruzione scritto da Claude Code
    /// e non, per esempio, un prompt che cita quel testo.
    private func isInterruptMarker(_ line: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (object["type"] as? String) == "user",
              let message = object["message"] as? [String: Any] else { return false }

        var texts: [String] = []
        if let content = message["content"] as? String {
            texts = [content]
        } else if let blocks = message["content"] as? [[String: Any]] {
            texts = blocks.compactMap { $0["text"] as? String }
        }
        return texts.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[Request interrupted by user") }
    }

    private func userPrompt(from object: [String: Any]) -> String? {
        if (object["isMeta"] as? Bool) == true { return nil }
        if let userType = object["userType"] as? String, userType != "external" { return nil }
        guard let message = object["message"] as? [String: Any] else { return nil }

        var text: String?
        if let content = message["content"] as? String {
            text = content
        } else if let blocks = message["content"] as? [[String: Any]] {
            // Le risposte degli strumenti (tool_result) non sono prompt dell'utente.
            text = blocks.first { ($0["type"] as? String) == "text" }?["text"] as? String
        }

        guard let text, let cleaned = clean(text) else { return nil }
        // Messaggi generati da comandi o dal sistema, es. "<command-name>/clear</command-name>".
        if cleaned.hasPrefix("<") || cleaned.hasPrefix("Caveat:") { return nil }
        return cleaned
    }

    /// Prima riga, spazi compattati, troncata a una lunghezza leggibile in un menu.
    private func clean(_ raw: String) -> String? {
        let firstLine = raw
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        let compact = firstLine
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !compact.isEmpty else { return nil }
        if compact.count <= maxLength { return compact }
        return String(compact.prefix(maxLength - 1)) + "…"
    }
}
