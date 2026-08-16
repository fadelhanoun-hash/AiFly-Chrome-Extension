import Foundation
import Security
import Carbon.HIToolbox

@MainActor
enum SpotlightSearch {
    private static var activeQueries: [UUID: SpotlightQuerySession] = [:]

    static func find(_ term: String, inside folder: URL? = nil) async -> [FileResult] {
        if let folder { return await FolderSearch.find(term, inside: folder) }
        let commandResults = await SpotlightCommandFallback.find(term)
        if !commandResults.isEmpty { return commandResults }
        let nativeResults: [FileResult] = await withCheckedContinuation { continuation in
            let id = UUID()
            let session = SpotlightQuerySession(term: term) { results in
                activeQueries[id] = nil
                continuation.resume(returning: results)
            }
            activeQueries[id] = session
            session.start()
        }
        return nativeResults
    }
}

private enum FolderSearch {
    static func find(_ term: String, inside folder: URL) async -> [FileResult] {
        await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .nameKey]
            let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
            var urls: [URL] = []

            if normalizedTerm.isEmpty {
                urls = (try? manager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles]
                )) ?? []
            } else if let enumerator = manager.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                while let url = enumerator.nextObject() as? URL {
                    if url.lastPathComponent.localizedCaseInsensitiveContains(normalizedTerm) {
                        urls.append(url)
                        if urls.count >= 80 { break }
                    }
                }
            }

            return urls
                .map(FileResult.init(url:))
                .sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .prefix(40)
                .map { $0 }
        }.value
    }
}

private enum SpotlightCommandFallback {
    static func find(_ term: String) async -> [FileResult] {
        await Task.detached(priority: .userInitiated) {
            let escaped = term
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let expression = "(kMDItemFSName == \"*\(escaped)*\"cd) || (kMDItemDisplayName == \"*\(escaped)*\"cd)"
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-onlyin", FileManager.default.homeDirectoryForCurrentUser.path, expression]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let results = String(decoding: data, as: UTF8.self)
                    .split(separator: "\n")
                    .map { FileResult(url: URL(fileURLWithPath: String($0))) }
                return Array(results.sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }.prefix(40))
            } catch {
                return []
            }
        }.value
    }
}

@MainActor
private final class SpotlightQuerySession {
    private let query = NSMetadataQuery()
    private let term: String
    private let completion: ([FileResult]) -> Void
    private var observer: NSObjectProtocol?
    private var hasFinished = false

    init(term: String, completion: @escaping ([FileResult]) -> Void) {
        self.term = term
        self.completion = completion
    }

    func start() {
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(
            format: "(%K CONTAINS[cd] %@) OR (%K CONTAINS[cd] %@)",
            NSMetadataItemFSNameKey, term,
            NSMetadataItemDisplayNameKey, term
        )
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
        query.start()

        // Initial Spotlight gathering can take several seconds on large home
        // folders. Only time out after giving the metadata index time to reply.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        query.disableUpdates()

        let loweredTerm = term.lowercased()
        let matches = query.results
            .compactMap { $0 as? NSMetadataItem }
            .compactMap { item -> FileResult? in
                guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                      FileManager.default.fileExists(atPath: path) else { return nil }
                return FileResult(url: URL(fileURLWithPath: path))
            }
            .sorted { left, right in
                let leftPrefix = left.name.lowercased().hasPrefix(loweredTerm)
                let rightPrefix = right.name.lowercased().hasPrefix(loweredTerm)
                if leftPrefix != rightPrefix { return leftPrefix }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }

        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        completion(Array(matches.prefix(40)))
    }
}

enum AIService {
    private static let medicalHTMLPrompt = """
    You are AiFly Medical, a concise residency-level clinical assistant. Default to clinically useful medical, residency, diagnostic, and treatment guidance. When relevant, include differential diagnosis, workup, initial management, medication names and doses, contraindications, disposition, and urgent red flags. Clearly distinguish established guidance from uncertainty and do not invent patient details.

    Return ONLY an HTML fragment, never Markdown and never a full HTML document. Use semantic <p>, <strong>, <ul>, <ol>, <li>, and compact <table> elements as helpful. Bold important clinical keywords. Add restrained inline colors to bold keywords: diagnoses and key findings #2563eb, treatments and medications #059669, warnings/contraindications #dc2626, and doses/lab thresholds #7c3aed. Use <span style="color:...;font-weight:700"> for colored emphasis. Keep answers concise unless the user requests depth. Do not include scripts, images, external resources, or code fences.
    """

    static func respond(to question: String, history: [ChatMessage], settings: AppSettings) async throws -> String {
        switch settings.provider {
        case .openAI: return try await openAI(question, history: history, key: settings.openAIKey)
        case .gemini: return try await gemini(question, history: history, key: settings.geminiKey)
        }
    }

    private static func openAI(_ question: String, history: [ChatMessage], key: String) async throws -> String {
        guard !key.isEmpty else { throw ServiceError.missingKey("OpenAI") }
        var messages = [["role": "system", "content": medicalHTMLPrompt]]
        messages += history.map { ["role": $0.role, "content": $0.content] }
        messages.append(["role": "user", "content": question])
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "gpt-4o-mini", "messages": messages, "max_tokens": 1200])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content else { throw ServiceError.invalidResponse }
        return text
    }

    private static func gemini(_ question: String, history: [ChatMessage], key: String) async throws -> String {
        guard !key.isEmpty else { throw ServiceError.missingKey("Gemini") }
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let context = history.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["contents": [["parts": [["text": "\(medicalHTMLPrompt)\n\nConversation:\n\(context)\nUser: \(question)"]]]]])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text else { throw ServiceError.invalidResponse }
        return text
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data))
                .map { String(describing: $0) } ?? "Request failed"
            throw ServiceError.remote(detail)
        }
    }
}

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
    let choices: [Choice]
}
private struct GeminiResponse: Decodable {
    struct Candidate: Decodable { struct Content: Decodable { struct Part: Decodable { let text: String }; let parts: [Part] }; let content: Content }
    let candidates: [Candidate]
}

enum ServiceError: LocalizedError {
    case missingKey(String), invalidResponse, remote(String)
    var errorDescription: String? {
        switch self {
        case .missingKey(let provider): return "Add your \(provider) API key in Settings."
        case .invalidResponse: return "The AI provider returned an unreadable response."
        case .remote(let message): return message
        }
    }
}

enum KeychainStore {
    private static let service = "com.aifly.mac"
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func write(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init?(shortcut: Shortcut, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &eventType, pointer, &handler)
        let signature = OSType(0x41494659) // AIFY
        let id = EventHotKeyID(signature: signature, id: 1)
        let modifiers: UInt32
        switch shortcut {
        case .commandSpace: modifiers = UInt32(cmdKey)
        case .optionSpace: modifiers = UInt32(optionKey)
        case .controlSpace: modifiers = UInt32(controlKey)
        case .commandShiftSpace: modifiers = UInt32(cmdKey | shiftKey)
        }
        guard RegisterEventHotKey(UInt32(kVK_Space), modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
