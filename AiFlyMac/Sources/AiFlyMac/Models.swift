import Foundation
import AppKit

enum LauncherMode: String, CaseIterable, Identifiable {
    case files = "Files"
    case ask = "Ask AI"
    var id: String { rawValue }
}

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "OpenAI"
    case gemini = "Gemini"
    var id: String { rawValue }
}

enum Shortcut: String, CaseIterable, Identifiable, Codable {
    case commandSpace = "⌘ Space"
    case optionSpace = "⌥ Space"
    case controlSpace = "⌃ Space"
    case commandShiftSpace = "⌘ ⇧ Space"
    var id: String { rawValue }
}

enum FileScopeKind: String, CaseIterable, Identifiable {
    case folders = "Folders"
    case documents = "Documents"
    case images = "Images"
    case video = "Video"
    case audio = "Audio"
    case archives = "Archives"
    case other = "Other"

    var id: String { rawValue }
}

struct FileResult: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var folder: String { url.deletingLastPathComponent().path }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
    var isGoogleDriveItem: Bool {
        let path = url.path.lowercased()
        return path.contains("/library/cloudstorage/googledrive-") || path.contains("/google drive/")
    }
    var formatLabel: String {
        if isDirectory { return "Folder" }
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "File" : ext
    }
    var scopeKind: FileScopeKind {
        if isDirectory { return .folders }
        let ext = url.pathExtension.lowercased()
        if ["pdf", "doc", "docx", "txt", "rtf", "pages", "xls", "xlsx", "csv", "ppt", "pptx", "key"].contains(ext) { return .documents }
        if ["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "svg", "webp"].contains(ext) { return .images }
        if ["mov", "mp4", "m4v", "avi", "mkv", "webm"].contains(ext) { return .video }
        if ["mp3", "m4a", "wav", "aac", "flac", "aiff"].contains(ext) { return .audio }
        if ["zip", "rar", "7z", "tar", "gz", "dmg", "pkg"].contains(ext) { return .archives }
        return .other
    }
}

enum FileAction: String, CaseIterable, Identifiable {
    case open = "Open"
    case reveal = "Show in Finder"
    case copyPath = "Copy Path"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .open: return "arrow.up.forward.app"
        case .reveal: return "folder"
        case .copyPath: return "doc.on.doc"
        }
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: String
    let content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct AppSettings {
    var provider: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .openAI }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "provider") }
    }
    var shortcut: Shortcut {
        get { Shortcut(rawValue: UserDefaults.standard.string(forKey: "shortcut") ?? "") ?? .optionSpace }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "shortcut") }
    }
    var openAIKey: String {
        get { KeychainStore.read("openai-key") ?? "" }
        set { KeychainStore.write(newValue, account: "openai-key") }
    }
    var geminiKey: String {
        get { KeychainStore.read("gemini-key") ?? "" }
        set { KeychainStore.write(newValue, account: "gemini-key") }
    }
    var includedExtensions: [String] {
        get { UserDefaults.standard.stringArray(forKey: "includedExtensions") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "includedExtensions") }
    }
    var excludedExtensions: [String] {
        get { UserDefaults.standard.stringArray(forKey: "excludedExtensions") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "excludedExtensions") }
    }
    var includedKinds: [String] {
        get { UserDefaults.standard.stringArray(forKey: "includedKinds") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "includedKinds") }
    }
    var excludedKinds: [String] {
        get { UserDefaults.standard.stringArray(forKey: "excludedKinds") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "excludedKinds") }
    }
    var excludedFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: "excludedFolders") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "excludedFolders") }
    }
    var launchAtLogin: Bool {
        get {
            guard UserDefaults.standard.object(forKey: "launchAtLogin") != nil else { return true }
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private struct FileNavigationState {
        let query: String
        let results: [FileResult]
        let selection: Int
        let formatFilter: String?
        let searchRoot: URL?
    }

    @Published var mode: LauncherMode = .files
    @Published var query = ""
    @Published var results: [FileResult] = []
    @Published var selection = 0
    @Published var showFileActions = false
    @Published var actionSelection = 0
    @Published var selectedFormatFilter: String?
    @Published var searchRoot: URL?
    @Published var isDownloading = false
    @Published var isSearchingFiles = false
    @Published var messages: [ChatMessage] = []
    @Published var isWorking = false
    @Published var errorMessage: String?
    var settings = AppSettings()
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private var folderHistory: [FileNavigationState] = []
    private var pendingRestoredSelection: Int?
    private var pendingRestoredFilter: String?

    func updateSearch() {
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation
        selectedFormatFilter = nil
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .files, !term.isEmpty || searchRoot != nil else {
            results = []
            selection = 0
            showFileActions = false
            isSearchingFiles = false
            return
        }
        isSearchingFiles = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            let matches = await SpotlightSearch.find(term, inside: searchRoot)
            guard !Task.isCancelled, searchGeneration == generation else { return }
            results = applySearchRules(to: matches).sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            if let pendingRestoredFilter, availableFormatFilters.contains(pendingRestoredFilter) {
                selectedFormatFilter = pendingRestoredFilter
            }
            self.pendingRestoredFilter = nil
            if let pendingRestoredSelection {
                selection = min(pendingRestoredSelection, max(0, visibleResults.count - 1))
            } else {
                selection = min(selection, max(0, visibleResults.count - 1))
            }
            self.pendingRestoredSelection = nil
            showFileActions = false
            isSearchingFiles = false
        }
    }

    var availableFormatFilters: [String] {
        let labels = Set(results.map(\.formatLabel))
        return labels.sorted {
            if $0 == "Folder" { return true }
            if $1 == "Folder" { return false }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
        .prefix(9)
        .map { $0 }
    }

    var visibleResults: [FileResult] {
        guard let selectedFormatFilter else { return results }
        return results.filter { $0.formatLabel == selectedFormatFilter }
    }

    func selectFormatFilter(at index: Int) {
        guard availableFormatFilters.indices.contains(index) else { return }
        let format = availableFormatFilters[index]
        selectedFormatFilter = selectedFormatFilter == format ? nil : format
        selection = 0
        showFileActions = false
        NotificationCenter.default.post(name: .fileSelectionChanged, object: nil)
    }

    var selectedFile: FileResult? {
        visibleResults.indices.contains(selection) ? visibleResults[selection] : nil
    }

    var searchPlaceholder: String {
        if let searchRoot { return "Search inside \(searchRoot.lastPathComponent)…" }
        return "Search files and folders — Return to Ask AI"
    }

    func resetForHotKeyLaunch() {
        searchTask?.cancel()
        searchGeneration = UUID()
        mode = .files
        query = ""
        results = []
        selection = 0
        selectedFormatFilter = nil
        searchRoot = nil
        folderHistory = []
        pendingRestoredSelection = nil
        pendingRestoredFilter = nil
        showFileActions = false
        isSearchingFiles = false
        errorMessage = nil
    }

    func switchToAI() {
        mode = .ask
        query = ""
        errorMessage = nil
    }

    func switchToMacSearch() {
        mode = .files
        query = ""
        results = []
        selection = 0
        selectedFormatFilter = nil
        searchRoot = nil
        folderHistory = []
        pendingRestoredSelection = nil
        pendingRestoredFilter = nil
        showFileActions = false
        errorMessage = nil
    }

    private func applySearchRules(to matches: [FileResult]) -> [FileResult] {
        let includedExtensions = Set(settings.includedExtensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) })
        let excludedExtensions = Set(settings.excludedExtensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) })
        let includedKinds = Set(settings.includedKinds)
        let excludedKinds = Set(settings.excludedKinds)
        let excludedFolders = settings.excludedFolders.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        return matches.filter { item in
            let path = item.url.standardizedFileURL.path
            if excludedFolders.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return false }
            if !item.isDirectory && !includedKinds.isEmpty && !includedKinds.contains(item.scopeKind.rawValue) { return false }
            if excludedKinds.contains(item.scopeKind.rawValue) { return false }
            if !item.isDirectory {
                let ext = item.url.pathExtension.lowercased()
                if !includedExtensions.isEmpty && !includedExtensions.contains(ext) { return false }
                if excludedExtensions.contains(ext) { return false }
            }
            return true
        }
    }

    func enterFolder(_ folder: URL) {
        guard FileResult(url: folder).isDirectory else { return }
        folderHistory.append(FileNavigationState(
            query: query,
            results: results,
            selection: selection,
            formatFilter: selectedFormatFilter,
            searchRoot: searchRoot
        ))
        pendingRestoredSelection = nil
        pendingRestoredFilter = nil
        searchRoot = folder
        query = ""
        selection = 0
        showFileActions = false
        updateSearch()
    }

    func leaveCurrentFolder() {
        guard let previous = folderHistory.popLast() else { return }
        let queryChanged = previous.query != query
        searchTask?.cancel()
        searchGeneration = UUID()
        searchRoot = previous.searchRoot
        results = previous.results
        selectedFormatFilter = previous.formatFilter
        selection = min(previous.selection, max(0, visibleResults.count - 1))
        pendingRestoredSelection = queryChanged ? previous.selection : nil
        pendingRestoredFilter = queryChanged ? previous.formatFilter : nil
        query = previous.query
        showFileActions = false
        isSearchingFiles = false
        NotificationCenter.default.post(name: .fileSelectionChanged, object: nil)
    }

    func moveFileSelection(_ offset: Int) {
        if showFileActions {
            let count = FileAction.allCases.count
            actionSelection = (actionSelection + offset + count) % count
        } else if !visibleResults.isEmpty {
            let count = visibleResults.count
            selection = (selection + offset + count) % count
        }
        NotificationCenter.default.post(name: .fileSelectionChanged, object: nil)
    }

    func showActions() {
        guard selectedFile != nil else { return }
        showFileActions = true
        actionSelection = 0
    }

    func hideActions() {
        showFileActions = false
    }

    func handleRightArrow() {
        if let selectedFile, selectedFile.isDirectory {
            enterFolder(selectedFile.url)
        } else {
            showActions()
        }
    }

    func handleLeftArrow() {
        if showFileActions {
            hideActions()
        } else if searchRoot != nil {
            leaveCurrentFolder()
        }
    }

    func performPrimaryFileAction() {
        if showFileActions, FileAction.allCases.indices.contains(actionSelection) {
            perform(FileAction.allCases[actionSelection])
        } else {
            activateSelection()
        }
    }

    func perform(_ action: FileAction) {
        guard let file = selectedFile else { return }
        switch action {
        case .open:
            NSWorkspace.shared.open(file.url)
            NSApp.keyWindow?.orderOut(nil)
        case .reveal:
            NSWorkspace.shared.activateFileViewerSelecting([file.url])
            NSApp.keyWindow?.orderOut(nil)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.url.path, forType: .string)
            showFileActions = false
        }
    }

    func openSelectedFile() {
        guard let file = selectedFile else { return }
        NSWorkspace.shared.open(file.url)
    }

    func downloadSelectedGoogleDriveFile() async {
        guard let file = selectedFile, file.isGoogleDriveItem, !isDownloading else { return }
        isDownloading = true
        let source = file.url
        do {
            let destination = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                let manager = FileManager.default
                let downloads = manager.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                var destination = downloads.appendingPathComponent(source.lastPathComponent)
                if manager.fileExists(atPath: destination.path) {
                    let stem = source.deletingPathExtension().lastPathComponent
                    let ext = source.pathExtension
                    let suffix = "-\(Int(Date().timeIntervalSince1970))"
                    destination = downloads.appendingPathComponent(stem + suffix)
                    if !ext.isEmpty { destination.appendPathExtension(ext) }
                }
                try manager.copyItem(at: source, to: destination)
                return destination
            }.value
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
        isDownloading = false
    }

    func activateSelection() {
        guard let file = selectedFile else { return }
        NSWorkspace.shared.open(file.url)
        NSApp.keyWindow?.orderOut(nil)
    }

    func revealSelection() {
        guard let file = selectedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func sendQuestion() async {
        let question = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isWorking else { return }
        query = ""
        messages.append(ChatMessage(role: "user", content: question))
        isWorking = true
        errorMessage = nil
        do {
            let answer = try await AIService.respond(to: question, history: Array(messages.dropLast().suffix(10)), settings: settings)
            messages.append(ChatMessage(role: "assistant", content: answer))
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

extension Notification.Name {
    static let fileSelectionChanged = Notification.Name("AiFly.fileSelectionChanged")
}
