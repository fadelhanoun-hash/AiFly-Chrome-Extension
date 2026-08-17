import Foundation
import AppKit
import Contacts

enum LauncherMode: String, CaseIterable, Identifiable {
    case files = "Search Mac"
    case ask = "Ask AI"
    case notes = "Notes"
    var id: String { rawValue }
}

enum LauncherTheme: String, CaseIterable, Identifiable, Codable {
    case alfredNavy = "Alfred Navy"
    case graphite = "Graphite"
    case midnight = "Midnight"
    case frost = "Frost"
    case plum = "Plum"
    case paperWhite = "Paper White"
    case warmWhite = "Warm White"

    var id: String { rawValue }
}

struct ContactField: Identifiable, Hashable {
    let label: String
    let value: String
    let icon: String
    var id: String { "\(label)|\(value)" }
}

struct ContactResult: Identifiable, Hashable {
    let id: String
    let displayName: String
    let organization: String
    let fields: [ContactField]
    let imageData: Data?
}

struct WebSearchEngine: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var shortcut: String
    var isEnabled: Bool
    var isFallback: Bool
    let searchURL: String
    let icon: String

    static let defaults: [WebSearchEngine] = [
        .init(id: "youtube", name: "YouTube", shortcut: "yt", isEnabled: true, isFallback: true, searchURL: "https://www.youtube.com/results?search_query=", icon: "play.rectangle.fill"),
        .init(id: "google", name: "Google", shortcut: "g", isEnabled: true, isFallback: true, searchURL: "https://www.google.com/search?q=", icon: "globe"),
        .init(id: "images", name: "Google Images", shortcut: "gi", isEnabled: true, isFallback: false, searchURL: "https://www.google.com/search?tbm=isch&q=", icon: "photo.on.rectangle"),
        .init(id: "maps", name: "Apple Maps", shortcut: "m", isEnabled: true, isFallback: false, searchURL: "https://maps.apple.com/?q=", icon: "map.fill")
    ]
}

struct WebSearchResult: Identifiable, Hashable {
    let id: String
    let engineID: String
    let title: String
    let subtitle: String
    let url: URL
    let thumbnailURL: URL?
    let isFallback: Bool
}

enum MacSearchResult: Identifiable, Hashable {
    case file(FileResult)
    case contact(ContactResult)
    case web(WebSearchResult)

    var id: String {
        switch self {
        case .file(let file): return "file|\(file.id)"
        case .contact(let contact): return "contact|\(contact.id)"
        case .web(let result): return "web|\(result.id)"
        }
    }
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
    var content: String

    init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

struct SavedNote: Identifiable, Codable {
    let id: UUID
    var title: String
    var html: String
    var updatedAt: Date

    init(id: UUID = UUID(), title: String, html: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.html = html
        self.updatedAt = updatedAt
    }
}

struct AppSettings {
    var webEngines: [WebSearchEngine] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "webSearchEngines"),
                  let engines = try? JSONDecoder().decode([WebSearchEngine].self, from: data) else { return WebSearchEngine.defaults }
            return engines
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "webSearchEngines") }
        }
    }
    var theme: LauncherTheme {
        get { LauncherTheme(rawValue: UserDefaults.standard.string(forKey: "launcherTheme") ?? "") ?? .alfredNavy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "launcherTheme") }
    }
    var transparency: Double {
        get {
            guard UserDefaults.standard.object(forKey: "launcherTransparency") != nil else { return 0.90 }
            return UserDefaults.standard.double(forKey: "launcherTransparency")
        }
        set { UserDefaults.standard.set(min(max(newValue, 0.55), 1.0), forKey: "launcherTransparency") }
    }
    var aiFontSize: Double {
        get {
            guard UserDefaults.standard.object(forKey: "aiFontSize") != nil else { return 14 }
            return min(max(UserDefaults.standard.double(forKey: "aiFontSize"), 11), 24)
        }
        set { UserDefaults.standard.set(min(max(newValue, 11), 24), forKey: "aiFontSize") }
    }
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
    @Published var recentFiles: [FileResult] = []
    @Published var recentApplications: [FileResult] = []
    @Published var isLoadingRecents = false
    @Published var contactResults: [ContactResult] = []
    @Published var applicationResults: [FileResult] = []
    @Published var folderResults: [FileResult] = []
    @Published var googleDriveResults: [FileResult] = []
    @Published var googleDriveCatalogResults: [WebSearchResult] = []
    @Published var isIndexingGoogleDrive = false
    @Published var isRefreshingPersistentIndex = false
    @Published var webResults: [WebSearchResult] = []
    @Published var activeWebEngine: WebSearchEngine?
    @Published var isSearchingWeb = false
    @Published var contactSelection = 0
    @Published var contactFieldSelection = 0
    @Published var showingContactDetails = false
    @Published var isSearchingContacts = false
    @Published var themeRevision = 0
    @Published var messages: [ChatMessage] = []
    @Published var selectedResponseText: [UUID: String] = [:]
    @Published var aiFontSize: Double = 14
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var savedNotes: [SavedNote] = []
    @Published var noteSearch = ""
    @Published var notePickerMessageID: UUID?
    @Published var lastSavedNoteID: UUID?
    @Published var noteListSelection = 0
    @Published var showingLauncherNote = false
    @Published var launcherNoteID: UUID?
    @Published var showLargePreview = false
    @Published var hasActivatedResultPreview = false
    @Published var webDialogResult: WebSearchResult?
    @Published var querySuggestion: String?
    var settings = AppSettings()
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private var contactSearchTask: Task<Void, Never>?
    private var applicationSearchTask: Task<Void, Never>?
    private var folderSearchTask: Task<Void, Never>?
    private var googleDriveSearchTask: Task<Void, Never>?
    private var webSearchTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var folderHistory: [FileNavigationState] = []
    private var pendingRestoredSelection: Int?
    private var pendingRestoredFilter: String?
    private let savedNotesKey = "AiFly.savedNotes"
    private let lastSavedNoteIDKey = "AiFly.lastSavedNoteID"
    private let lastLauncherModeKey = "AiFly.lastLauncherMode"

    init() {
        aiFontSize = settings.aiFontSize
        if let value = UserDefaults.standard.string(forKey: lastLauncherModeKey),
           let savedMode = LauncherMode(rawValue: value) {
            mode = savedMode
        }
        if let data = UserDefaults.standard.data(forKey: savedNotesKey),
           let decoded = try? JSONDecoder().decode([SavedNote].self, from: data) {
            savedNotes = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let value = UserDefaults.standard.string(forKey: lastSavedNoteIDKey) {
            lastSavedNoteID = UUID(uuidString: value)
        }
        startPersistentIndexUpdates()
    }

    func adjustAIFontSize(by amount: Double) {
        aiFontSize = min(max(aiFontSize + amount, 11), 24)
        settings.aiFontSize = aiFontSize
    }

    func clearAIChat() {
        messages.removeAll()
        selectedResponseText.removeAll()
        errorMessage = nil
        notePickerMessageID = nil
    }

    private func startPersistentIndexUpdates() {
        Task { [weak self] in
            while !Task.isCancelled {
                self?.isRefreshingPersistentIndex = true
                await PersistentSpotlightIndex.refreshIfNeeded()
                self?.isRefreshingPersistentIndex = false
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func loadRecents() {
        guard !isLoadingRecents else { return }
        isLoadingRecents = true
        Task {
            let snapshot = await RecentItemsSearch.load()
            recentFiles = Array(applySearchRules(to: snapshot.files).prefix(12))
            recentApplications = Array(snapshot.applications.prefix(12))
            isLoadingRecents = false
        }
    }

    func updateSearch() {
        if mode == .notes {
            querySuggestion = nil
            noteListSelection = min(noteListSelection, max(0, launcherNotes.count - 1))
            return
        }
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation
        selectedFormatFilter = nil
        let rawTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let term: String
        if searchRoot != nil, let separator = query.lastIndex(of: ">") {
            term = query[query.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            term = rawTerm
        }
        if searchRoot == nil { updateQuerySuggestion(for: term) } else { querySuggestion = nil }
        if mode == .files, let (engine, webTerm) = webCommand(for: term) {
            searchTask?.cancel()
            contactSearchTask?.cancel()
            applicationSearchTask?.cancel()
            folderSearchTask?.cancel()
            googleDriveSearchTask?.cancel()
            results = []
            contactResults = []
            applicationResults = []
            folderResults = []
            googleDriveResults = []
            googleDriveCatalogResults = []
            isIndexingGoogleDrive = false
            activeWebEngine = engine
            hasActivatedResultPreview = false
            updateWebSearch(engine: engine, term: webTerm)
            return
        }
        activeWebEngine = nil
        hasActivatedResultPreview = false
        webResults = []
        isSearchingWeb = false
        guard mode == .files, !term.isEmpty || searchRoot != nil else {
            results = []
            applicationResults = []
            folderResults = []
            googleDriveResults = []
            googleDriveCatalogResults = []
            isIndexingGoogleDrive = false
            contactResults = []
            selection = 0
            showFileActions = false
            isSearchingFiles = false
            return
        }
        updateContactSearch()
        updateApplicationSearch()
        updateFolderSearch()
        updateGoogleDriveSearch()
        isSearchingFiles = true
        searchTask = Task {
            if !term.isEmpty { try? await Task.sleep(for: .milliseconds(140)) }
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
                selection = min(pendingRestoredSelection, max(0, visibleSearchResults.count - 1))
            } else {
                selection = min(selection, max(0, visibleSearchResults.count - 1))
            }
            self.pendingRestoredSelection = nil
            showFileActions = false
            isSearchingFiles = false
        }
    }

    var availableFormatFilters: [String] {
        let candidates = unfilteredFileResults
        var labels = Set(candidates.filter { !$0.isDirectory && $0.url.pathExtension.lowercased() != "app" }.map(\.formatLabel))
        let remoteFiles = googleDriveCatalogResults.filter { $0.engineID == "google_drive_file" }
        labels.formUnion(remoteFiles.compactMap { result in
            let fileExtension = (result.title as NSString).pathExtension.uppercased()
            return fileExtension.isEmpty ? nil : fileExtension
        })
        if candidates.contains(where: { !$0.isDirectory && $0.url.pathExtension.lowercased() != "app" }) { labels.insert("File") }
        if !remoteFiles.isEmpty { labels.insert("File") }
        if !applicationResults.isEmpty || candidates.contains(where: { $0.url.pathExtension.lowercased() == "app" }) { labels.insert("Application") }
        if !folderResults.isEmpty || candidates.contains(where: { $0.isDirectory && $0.url.pathExtension.lowercased() != "app" }) { labels.insert("Folder") }
        if googleDriveCatalogResults.contains(where: { $0.engineID == "google_drive_folder" }) { labels.insert("Folder") }
        if !contactResults.isEmpty { labels.insert("Contact") }
        let priority = ["Application", "Folder", "Contact", "File"]
        return labels.sorted {
            let left = priority.firstIndex(of: $0) ?? Int.max
            let right = priority.firstIndex(of: $1) ?? Int.max
            if left != right { return left < right }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }.prefix(9).map { $0 }
    }

    var visibleResults: [FileResult] {
        guard let selectedFormatFilter else { return unfilteredFileResults }
        return unfilteredFileResults.filter { file in
            switch selectedFormatFilter {
            case "Application": return file.url.pathExtension.lowercased() == "app"
            case "Folder": return file.isDirectory && file.url.pathExtension.lowercased() != "app"
            case "Contact": return false
            case "File": return !file.isDirectory && file.url.pathExtension.lowercased() != "app"
            default: return !file.isDirectory && file.formatLabel == selectedFormatFilter
            }
        }
    }

    private var unfilteredFileResults: [FileResult] {
        var seen = Set<String>()
        return (googleDriveResults + results).filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    var visibleSearchResults: [MacSearchResult] {
        if let activeWebEngine {
            return webResults
                .filter { $0.engineID == activeWebEngine.id }
                .map(MacSearchResult.web)
        }
        let standardFolders = visibleResults.filter { $0.isDirectory && $0.url.pathExtension.lowercased() != "app" }
        let dedicatedFolders = searchRoot == nil && (selectedFormatFilter == nil || selectedFormatFilter == "Folder") ? folderResults : []
        var seenFolderPaths = Set<String>()
        let folders = (dedicatedFolders + standardFolders)
            .filter { seenFolderPaths.insert($0.url.standardizedFileURL.path).inserted }
            .map(MacSearchResult.file)
        let contacts = searchRoot == nil && (selectedFormatFilter == nil || selectedFormatFilter == "Contact") ? contactResults.map(MacSearchResult.contact) : []
        let applications = searchRoot == nil && (selectedFormatFilter == nil || selectedFormatFilter == "Application") ? applicationResults.map(MacSearchResult.file) : []
        let applicationPaths = Set(applicationResults.map { $0.url.standardizedFileURL.path })
        let files = visibleResults.filter {
            !$0.isDirectory && $0.url.pathExtension.lowercased() != "app" && !applicationPaths.contains($0.url.standardizedFileURL.path)
        }.map(MacSearchResult.file)
        let localNames = Set(unfilteredFileResults.map { $0.name.lowercased() })
        let remoteDrive = googleDriveCatalogResults.filter { result in
            guard !localNames.contains(result.title.lowercased()) else { return false }
            switch selectedFormatFilter {
            case nil: return true
            case "Folder": return result.engineID == "google_drive_folder"
            case "File": return result.engineID == "google_drive_file"
            case "Application", "Contact": return false
            default: return result.engineID == "google_drive_file" && (result.title as NSString).pathExtension.uppercased() == selectedFormatFilter
            }
        }.map(MacSearchResult.web)
        var ordered = applications + folders + contacts + remoteDrive + files
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ordered.isEmpty, !term.isEmpty, searchRoot == nil {
            return fallbackWebResults(for: term).map(MacSearchResult.web)
        }
        guard !term.isEmpty, ordered.count > 1 else { return ordered }

        return ordered.enumerated().sorted { left, right in
            let leftScore = matchScore(for: left.element, term: term)
            let rightScore = matchScore(for: right.element, term: term)
            return leftScore == rightScore ? left.offset < right.offset : leftScore < rightScore
        }.map(\.element)
    }

    private func matchScore(for result: MacSearchResult, term: String) -> Int {
        let candidates: [String]
        switch result {
        case .contact(let contact):
            candidates = [contact.displayName.lowercased(), contact.organization.lowercased()]
        case .file(let file):
            candidates = [file.name.lowercased(), file.url.deletingPathExtension().lastPathComponent.lowercased()]
        case .web(let web):
            candidates = [web.title.lowercased(), web.subtitle.lowercased()]
        }
        return candidates.map { value in
            if value == term { return 0 }
            if value.hasPrefix(term) { return 1 }
            if value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(term) }) { return 2 }
            if value.contains(term) { return 3 }
            return 4
        }.min() ?? 4
    }

    func selectFormatFilter(at index: Int) {
        guard availableFormatFilters.indices.contains(index) else { return }
        let format = availableFormatFilters[index]
        selectedFormatFilter = selectedFormatFilter == format ? nil : format
        selection = 0
        hasActivatedResultPreview = false
        showFileActions = false
        NotificationCenter.default.post(name: .fileSelectionChanged, object: nil)
    }

    var selectedFile: FileResult? {
        guard visibleSearchResults.indices.contains(selection),
              case .file(let file) = visibleSearchResults[selection] else { return nil }
        return file
    }

    var selectedWebResult: WebSearchResult? {
        guard visibleSearchResults.indices.contains(selection),
              case .web(let result) = visibleSearchResults[selection] else { return nil }
        return result
    }

    var searchPlaceholder: String {
        if let searchRoot { return "Search inside \(searchRoot.lastPathComponent)…" }
        return "Search files and folders — Return to Ask AI"
    }

    var folderBreadcrumbs: [URL] {
        guard let searchRoot else { return [] }
        var seen = Set<String>()
        return (folderHistory.compactMap(\.searchRoot) + [searchRoot]).filter {
            seen.insert($0.standardizedFileURL.path).inserted
        }
    }

    func resetForHotKeyLaunch() {
        searchTask?.cancel()
        searchGeneration = UUID()
        if let value = UserDefaults.standard.string(forKey: lastLauncherModeKey),
           let savedMode = LauncherMode(rawValue: value) {
            mode = savedMode
        }
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
        showLargePreview = false
        hasActivatedResultPreview = false
        querySuggestion = nil
        showingLauncherNote = false
        webDialogResult = nil
        contactResults = []
        applicationResults = []
        folderResults = []
        googleDriveResults = []
        googleDriveCatalogResults = []
        isIndexingGoogleDrive = false
        webResults = []
        activeWebEngine = nil
        isSearchingWeb = false
        contactSelection = 0
        contactFieldSelection = 0
        showingContactDetails = false
        loadRecents()
    }

    func rememberLauncherMode() {
        UserDefaults.standard.set(mode.rawValue, forKey: lastLauncherModeKey)
    }

    func acceptQuerySuggestion() {
        guard let querySuggestion else { return }
        query = querySuggestion
        self.querySuggestion = nil
    }

    var querySuggestionSuffix: String? {
        guard let suggestion = querySuggestion,
              suggestion.lowercased().hasPrefix(query.lowercased()),
              suggestion.count > query.count else { return nil }
        return String(suggestion.dropFirst(query.count))
    }

    private func updateQuerySuggestion(for term: String) {
        suggestionTask?.cancel()
        guard term.count >= 2 else {
            querySuggestion = nil
            return
        }
        suggestionTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let suggestion = await WebSearchService.completion(for: term)
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == term else { return }
            querySuggestion = suggestion
        }
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
        loadRecents()
    }

    var selectedContact: ContactResult? {
        guard visibleSearchResults.indices.contains(selection),
              case .contact(let contact) = visibleSearchResults[selection] else { return nil }
        return contact
    }

    func updateContactSearch() {
        contactSearchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .files, searchRoot == nil else {
            contactResults = []
            return
        }
        guard !term.isEmpty else {
            contactResults = []
            contactSelection = 0
            showingContactDetails = false
            isSearchingContacts = false
            return
        }
        isSearchingContacts = true
        contactSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            do {
                contactResults = try await ContactsSearch.find(term)
                contactFieldSelection = 0
                showingContactDetails = false
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                contactResults = []
            }
            isSearchingContacts = false
        }
    }

    func updateApplicationSearch() {
        applicationSearchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .files, searchRoot == nil, !term.isEmpty else {
            applicationResults = []
            return
        }
        applicationSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let matches = await InstalledApplicationSearch.find(term)
            guard !Task.isCancelled else { return }
            applicationResults = matches
            selection = min(selection, max(0, visibleSearchResults.count - 1))
        }
    }

    func updateFolderSearch() {
        folderSearchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .files, searchRoot == nil, !term.isEmpty else {
            folderResults = []
            return
        }
        folderSearchTask = Task {
            guard !Task.isCancelled else { return }
            let matches = await FolderNameSearch.find(term)
            guard !Task.isCancelled else { return }
            folderResults = applySearchRules(to: matches)
            selection = min(selection, max(0, visibleSearchResults.count - 1))
        }
    }

    func updateGoogleDriveSearch() {
        googleDriveSearchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .files, searchRoot == nil, !term.isEmpty else {
            googleDriveResults = []
            googleDriveCatalogResults = []
            isIndexingGoogleDrive = false
            return
        }
        isIndexingGoogleDrive = true
        googleDriveSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { isIndexingGoogleDrive = false; return }
            async let directMatches = GoogleDriveDirectSearch.find(term)
            async let catalogMatches = GoogleDriveCatalogSearch.find(term)
            let (matches, catalog) = await (directMatches, catalogMatches)
            guard !Task.isCancelled else { isIndexingGoogleDrive = false; return }
            googleDriveResults = applySearchRules(to: matches)
            googleDriveCatalogResults = catalog
            selection = min(selection, max(0, visibleSearchResults.count - 1))
            isIndexingGoogleDrive = false
        }
    }

    func moveContactSelection(_ offset: Int) {
        if showingContactDetails, let contact = selectedContact, !contact.fields.isEmpty {
            let count = contact.fields.count
            contactFieldSelection = (contactFieldSelection + offset + count) % count
        } else if !contactResults.isEmpty {
            let count = contactResults.count
            contactSelection = (contactSelection + offset + count) % count
            contactFieldSelection = 0
        }
        NotificationCenter.default.post(name: .contactSelectionChanged, object: nil)
    }

    func showContactDetails() {
        guard selectedContact != nil else { return }
        showingContactDetails = true
        contactFieldSelection = 0
    }

    func hideContactDetails() {
        showingContactDetails = false
        contactFieldSelection = 0
    }

    func copySelectedContactField() {
        guard let fields = selectedContact?.fields, fields.indices.contains(contactFieldSelection) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fields[contactFieldSelection].value, forType: .string)
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
        results = []
        folderResults = []
        applicationResults = []
        contactResults = []
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
        selection = min(previous.selection, max(0, visibleSearchResults.count - 1))
        pendingRestoredSelection = queryChanged ? previous.selection : nil
        pendingRestoredFilter = queryChanged ? previous.formatFilter : nil
        query = previous.query
        showFileActions = false
        isSearchingFiles = false
        NotificationCenter.default.post(name: .fileSelectionChanged, object: nil)
    }

    func navigateToFolderBreadcrumb(_ folder: URL) {
        let target = folder.standardizedFileURL.path
        guard folderBreadcrumbs.contains(where: { $0.standardizedFileURL.path == target }) else { return }
        while searchRoot?.standardizedFileURL.path != target, let previous = folderHistory.popLast() {
            searchRoot = previous.searchRoot
        }
        query = ""
        results = []
        selection = 0
        selectedFormatFilter = nil
        hasActivatedResultPreview = false
        showFileActions = false
        updateSearch()
    }

    func moveFileSelection(_ offset: Int) {
        if !visibleSearchResults.isEmpty {
            let count = visibleSearchResults.count
            if !hasActivatedResultPreview {
                selection = offset >= 0 ? 0 : count - 1
                hasActivatedResultPreview = true
            } else {
                selection = (selection + offset + count) % count
            }
            showingContactDetails = false
        }
        showFileActions = false
        NotificationCenter.default.post(name: .fileSelectionChanged, object: nil)
    }

    func selectSearchResult(at index: Int) {
        guard visibleSearchResults.indices.contains(index) else { return }
        selection = index
        hasActivatedResultPreview = true
    }

    func openWebDialog(_ result: WebSearchResult) {
        webDialogResult = result
    }

    func closeWebDialog() {
        webDialogResult = nil
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
        if selectedWebResult != nil {
            return
        } else if selectedContact != nil {
            showContactDetails()
        } else if let selectedFile, selectedFile.isDirectory {
            enterFolder(selectedFile.url)
        } else {
            showActions()
        }
    }

    func handleLeftArrow() {
        if showingContactDetails {
            hideContactDetails()
        } else if showFileActions {
            hideActions()
        } else if searchRoot != nil {
            leaveCurrentFolder()
        }
    }

    func performPrimaryFileAction() {
        if selectedWebResult != nil {
            activateSelection()
        } else if selectedContact != nil {
            showContactDetails()
        } else if let selectedFile, selectedFile.isDirectory {
            enterFolder(selectedFile.url)
        } else if showFileActions, FileAction.allCases.indices.contains(actionSelection) {
            perform(FileAction.allCases[actionSelection])
        } else {
            activateSelection()
        }
    }

    func performAlfredStyleAction() -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let actions: [(String, String)] = [
            ("google ", "https://www.google.com/search?q="),
            ("images ", "https://www.google.com/search?tbm=isch&q="),
            ("maps ", "https://maps.apple.com/?q="),
            ("youtube ", "https://www.youtube.com/results?search_query=")
        ]
        for (prefix, destination) in actions where value.lowercased().hasPrefix(prefix) {
            let term = String(value.dropFirst(prefix.count))
            guard !term.isEmpty,
                  let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: destination + escaped) else { return false }
            NSWorkspace.shared.open(url)
            NSApp.keyWindow?.orderOut(nil)
            return true
        }
        if let url = URL(string: value), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
            NSWorkspace.shared.open(url)
            NSApp.keyWindow?.orderOut(nil)
            return true
        }
        return false
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

    func openSelectedFolderExternally() {
        guard let file = selectedFile, file.isDirectory else { return }
        NSWorkspace.shared.open(file.url)
        NSApp.keyWindow?.orderOut(nil)
    }

    func openRecentItem(_ item: FileResult) {
        NSWorkspace.shared.open(item.url)
        NSApp.keyWindow?.orderOut(nil)
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
        if let web = selectedWebResult {
            NSWorkspace.shared.open(web.url)
            NSApp.keyWindow?.orderOut(nil)
            return
        }
        guard let file = selectedFile else { return }
        NSWorkspace.shared.open(file.url)
        NSApp.keyWindow?.orderOut(nil)
    }

    func revealSelection() {
        guard let file = selectedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func copySelectedFile() {
        guard let file = selectedFile else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file.url as NSURL])
    }

    func trashSelectedFile() {
        guard let file = selectedFile else { return }
        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: file.url, resultingItemURL: &trashedURL)
            results.removeAll { $0.url.standardizedFileURL == file.url.standardizedFileURL }
            applicationResults.removeAll { $0.url.standardizedFileURL == file.url.standardizedFileURL }
            selection = min(selection, max(0, visibleSearchResults.count - 1))
            showLargePreview = false
        } catch {
            errorMessage = "Could not move item to Trash: \(error.localizedDescription)"
        }
    }

    private func webCommand(for value: String) -> (WebSearchEngine, String)? {
        guard let space = value.firstIndex(of: " ") else { return nil }
        let shortcut = value[..<space].lowercased()
        let term = value[value.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty,
              let engine = settings.webEngines.first(where: { $0.isEnabled && $0.shortcut.lowercased() == shortcut }) else { return nil }
        return (engine, term)
    }

    private func updateWebSearch(engine: WebSearchEngine, term: String) {
        webSearchTask?.cancel()
        isSearchingWeb = true
        selection = 0
        webSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let matches = await WebSearchService.search(engine: engine, term: term)
            guard !Task.isCancelled, activeWebEngine?.id == engine.id else { return }
            webResults = matches.filter { $0.engineID == engine.id }
            isSearchingWeb = false
            selection = 0
        }
    }

    private func fallbackWebResults(for term: String) -> [WebSearchResult] {
        settings.webEngines.filter { $0.isEnabled && $0.isFallback }.compactMap { engine in
            guard let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: engine.searchURL + escaped) else { return nil }
            return WebSearchResult(
                id: "fallback|\(engine.id)|\(term)", engineID: engine.id,
                title: "Search \(engine.name) for \u{201c}\(term)\u{201d}",
                subtitle: "No Mac match — open in \(engine.name)", url: url,
                thumbnailURL: nil, isFallback: true
            )
        }
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

    var filteredNotes: [SavedNote] {
        let term = noteSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return savedNotes }
        return savedNotes.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    var launcherNotes: [SavedNote] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return savedNotes }
        return savedNotes.filter {
            $0.title.localizedCaseInsensitiveContains(term) || plainText(from: $0.html).localizedCaseInsensitiveContains(term)
        }
    }

    var selectedLauncherNote: SavedNote? {
        if showingLauncherNote, let launcherNoteID {
            return savedNotes.first { $0.id == launcherNoteID }
        }
        return launcherNotes.indices.contains(noteListSelection) ? launcherNotes[noteListSelection] : nil
    }

    func moveNoteSelection(_ offset: Int) {
        guard !launcherNotes.isEmpty else { return }
        let count = launcherNotes.count
        noteListSelection = (noteListSelection + offset + count) % count
        NotificationCenter.default.post(name: .noteSelectionChanged, object: nil)
    }

    func openLauncherNote(at index: Int) {
        guard launcherNotes.indices.contains(index) else { return }
        noteListSelection = index
        launcherNoteID = launcherNotes[index].id
        showingLauncherNote = true
    }

    func closeLauncherNote() {
        showingLauncherNote = false
    }

    func updateSavedNote(id: UUID, html: String) {
        guard let index = savedNotes.firstIndex(where: { $0.id == id }) else { return }
        savedNotes[index].html = html
        savedNotes[index].updatedAt = Date()
        persistNotes()
    }

    var lastSavedNote: SavedNote? {
        guard let lastSavedNoteID else { return nil }
        return savedNotes.first { $0.id == lastSavedNoteID }
    }

    func updateMessageContent(id: UUID, html: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }), messages[index].role == "assistant" else { return }
        messages[index].content = html
    }

    func redoAsTable(messageID: UUID) async {
        guard !isWorking, let message = messages.first(where: { $0.id == messageID }) else { return }
        isWorking = true
        errorMessage = nil
        do {
            let prompt = "Convert the following response into a concise, clinically useful HTML table. Return only the HTML table and preserve all important facts: \(message.content)"
            let answer = try await AIService.respond(to: prompt, history: [], settings: settings)
            updateMessageContent(id: messageID, html: answer)
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    func beginFollowUp(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        mode = .ask
        let context = plainText(from: message.content)
        query = "Follow up on \(String(context.prefix(100))): "
        NotificationCenter.default.post(name: .focusLauncher, object: nil)
    }

    func sendFollowUp(_ question: String, about messageID: UUID) async {
        guard let responseIndex = messages.firstIndex(where: { $0.id == messageID }), !isWorking else { return }
        let response = messages[responseIndex]
        let contextualQuestion = "Regarding this response:\n\(plainText(from: response.content))\n\nFollow-up question: \(question)"
        messages.append(ChatMessage(role: "user", content: question))
        isWorking = true
        errorMessage = nil
        do {
            let priorHistory = Array(messages.prefix(responseIndex + 1).suffix(10))
            let answer = try await AIService.respond(to: contextualQuestion, history: priorHistory, settings: settings)
            messages.append(ChatMessage(role: "assistant", content: answer))
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    func copyMessage(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText(from: message.content), forType: .string)
    }

    func findImage(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        let selected = selectedResponseText[messageID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let terms = String((selected.isEmpty ? plainText(from: message.content) : selected).prefix(180))
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "udm", value: "2"), URLQueryItem(name: "q", value: terms)]
        if let url = components?.url { NSWorkspace.shared.open(url) }
    }

    func findOnComputer(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        let selected = selectedResponseText[messageID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        query = String((selected.isEmpty ? plainText(from: message.content) : selected).prefix(240))
        mode = .files
        updateSearch()
        NotificationCenter.default.post(name: .focusLauncher, object: nil)
    }

    func openNotePicker(messageID: UUID) {
        noteSearch = ""
        notePickerMessageID = messageID
    }

    func closeNotePicker() {
        notePickerMessageID = nil
        noteSearch = ""
    }

    func createNoteAndSave(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }) else { return }
        let plain = plainText(from: message.content)
        let title = String(plain.prefix(52)).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = SavedNote(title: title.isEmpty ? "AiFly Note" : title, html: message.content)
        savedNotes.insert(note, at: 0)
        rememberSavedNote(note.id)
        closeNotePicker()
        persistNotes()
    }

    func saveMessage(_ messageID: UUID, to noteID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }),
              let index = savedNotes.firstIndex(where: { $0.id == noteID }) else { return }
        savedNotes[index].html += "<hr>\(message.content)"
        savedNotes[index].updatedAt = Date()
        let updated = savedNotes.remove(at: index)
        savedNotes.insert(updated, at: 0)
        rememberSavedNote(noteID)
        closeNotePicker()
        persistNotes()
    }

    func saveToLastNote(messageID: UUID) {
        guard let lastSavedNoteID else { return }
        saveMessage(messageID, to: lastSavedNoteID)
    }

    private func rememberSavedNote(_ id: UUID) {
        lastSavedNoteID = id
        UserDefaults.standard.set(id.uuidString, forKey: lastSavedNoteIDKey)
    }

    private func persistNotes() {
        guard let data = try? JSONEncoder().encode(savedNotes) else { return }
        UserDefaults.standard.set(data, forKey: savedNotesKey)
    }

    private func plainText(from html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else { return html }
        return attributed.string.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Notification.Name {
    static let fileSelectionChanged = Notification.Name("AiFly.fileSelectionChanged")
    static let contactSelectionChanged = Notification.Name("AiFly.contactSelectionChanged")
    static let noteSelectionChanged = Notification.Name("AiFly.noteSelectionChanged")
}
