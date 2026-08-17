import Foundation
import Security
import Carbon.HIToolbox
import Contacts

enum WebSearchService {
    static func completion(for term: String) async -> String? {
        let values = await suggestions(term, youtube: false)
        return values.first { $0.localizedCaseInsensitiveCompare(term) != .orderedSame }
    }

    static func search(engine: WebSearchEngine, term: String) async -> [WebSearchResult] {
        if engine.id == "youtube", let videos = await youtubeVideos(term), !videos.isEmpty { return videos }
        if engine.id == "google" || engine.id == "youtube" {
            let suggestions = await suggestions(term, youtube: engine.id == "youtube")
            if !suggestions.isEmpty {
                return suggestions.compactMap { suggestion in
                    makeDirectResult(engine: engine, term: suggestion, subtitle: "Suggested search")
                }
            }
        }
        return [makeDirectResult(engine: engine, term: term, subtitle: "Open in \(engine.name)")].compactMap { $0 }
    }

    private static func makeDirectResult(engine: WebSearchEngine, term: String, subtitle: String) -> WebSearchResult? {
        guard let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: engine.searchURL + escaped) else { return nil }
        return WebSearchResult(id: "\(engine.id)|\(term)", engineID: engine.id, title: term, subtitle: subtitle, url: url, thumbnailURL: nil, isFallback: false)
    }

    static func suggestions(_ term: String, youtube: Bool) async -> [String] {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "firefox"),
            URLQueryItem(name: "q", value: term)
        ] + (youtube ? [URLQueryItem(name: "ds", value: "yt")] : [])
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [Any],
              payload.count > 1, let values = payload[1] as? [String] else { return [] }
        return Array(values.prefix(12))
    }

    private static func youtubeVideos(_ term: String) async -> [WebSearchResult]? {
        guard let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.youtube.com/results?search_query=\(escaped)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: "\\\"videoId\\\":\\\"([^\\\"]+)\\\".{0,900}?\\\"title\\\":\\{\\\"runs\\\":\\[\\{\\\"text\\\":\\\"([^\\\"]+)", options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        var results: [WebSearchResult] = []
        for match in regex.matches(in: html, range: range) {
            guard let idRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }
            let id = String(html[idRange])
            guard seen.insert(id).inserted,
                  let videoURL = URL(string: "https://www.youtube.com/watch?v=\(id)") else { continue }
            let rawTitle = String(html[titleRange])
            let title = rawTitle.replacingOccurrences(of: "\\u0026", with: "&").replacingOccurrences(of: "\\\"", with: "\"")
            results.append(WebSearchResult(
                id: "youtube|\(id)", engineID: "youtube", title: title,
                subtitle: "YouTube video", url: videoURL,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"), isFallback: false
            ))
            if results.count == 12 { break }
        }
        return results
    }
}

enum ContactsSearch {
    static func find(_ term: String) async throws -> [ContactResult] {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else { throw ContactsSearchError.accessDenied }

        return try await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactUrlAddressesKey as CNKeyDescriptor,
                CNContactImageDataAvailableKey as CNKeyDescriptor,
                CNContactThumbnailImageDataKey as CNKeyDescriptor
            ]
            let predicate = CNContact.predicateForContacts(matchingName: term)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            return contacts.prefix(50).map { contact in
                var fields: [ContactField] = []
                fields += contact.phoneNumbers.map {
                    ContactField(label: CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0.label ?? "Phone"), value: $0.value.stringValue, icon: "phone.fill")
                }
                fields += contact.emailAddresses.map {
                    ContactField(label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? "Email"), value: $0.value as String, icon: "envelope.fill")
                }
                fields += contact.postalAddresses.map {
                    let value = CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress)
                        .replacingOccurrences(of: "\n", with: ", ")
                    return ContactField(label: CNLabeledValue<CNPostalAddress>.localizedString(forLabel: $0.label ?? "Address"), value: value, icon: "mappin.and.ellipse")
                }
                fields += contact.urlAddresses.map {
                    ContactField(label: CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? "Website"), value: $0.value as String, icon: "link")
                }
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                return ContactResult(
                    id: contact.identifier,
                    displayName: name.isEmpty ? contact.organizationName : name,
                    organization: contact.organizationName,
                    fields: fields,
                    imageData: contact.thumbnailImageData
                )
            }
        }.value
    }
}

enum ContactsSearchError: LocalizedError {
    case accessDenied
    var errorDescription: String? { "Allow Contacts access in System Settings to search contacts." }
}

enum InstalledApplicationSearch {
    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func isSubsequence(_ query: String, of candidate: String) -> Bool {
        var queryIndex = query.startIndex
        for character in candidate where queryIndex < query.endIndex {
            if character == query[queryIndex] {
                query.formIndex(after: &queryIndex)
            }
        }
        return queryIndex == query.endIndex
    }

    /// Lower values are better. `nil` means the application is not a useful match.
    private static func matchScore(applicationName: String, term: String) -> Int? {
        let foldedName = applicationName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let foldedTerm = term
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let name = normalized(foldedName)
        let query = normalized(foldedTerm)
        guard !query.isEmpty else { return nil }

        if name == query { return 0 }
        if name.hasPrefix(query) { return 10 + name.count - query.count }

        let words = foldedName.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { normalized($0).hasPrefix(query) }) { return 30 }
        if name.contains(query) { return 40 + (name.range(of: query)?.lowerBound.utf16Offset(in: name) ?? 0) }

        let initials = words.compactMap(\.first).map(String.init).joined()
        if initials.hasPrefix(query) { return 55 + initials.count - query.count }

        // Alfred-style forgiving matching: accept a compact subsequence or a
        // small spelling error, but keep these below literal matches.
        if query.count >= 3, isSubsequence(query, of: name) {
            return 70 + name.count - query.count
        }
        if query.count >= 4 {
            let allowedEdits = max(1, min(2, query.count / 4))
            let distance = editDistance(query, name)
            if distance <= allowedEdits { return 90 + distance * 10 + abs(name.count - query.count) }
        }
        return nil
    }

    static func find(_ term: String) async -> [FileResult] {
        await Task.detached(priority: .userInitiated) {
            let escaped = term
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let expression = "(kMDItemContentType == \"com.apple.application-bundle\") && (kMDItemFSName == \"*\(escaped)*.app\"cd)"
            let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
            let scopes = ["/Applications", "/System/Applications", homeApplications]
            var seen = Set<String>()
            var matches: [FileResult] = []

            for scope in scopes where FileManager.default.fileExists(atPath: scope) {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
                process.arguments = ["-onlyin", scope, expression]
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                        let url = URL(fileURLWithPath: String(line)).standardizedFileURL
                        if seen.insert(url.path).inserted { matches.append(FileResult(url: url)) }
                    }
                } catch { continue }
            }

            // Spotlight can omit newly installed, excluded, or not-yet-indexed
            // application bundles. Scan the application folders directly as a
            // fallback and merge the results by their permanent file path.
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .nameKey]
            for scope in scopes where FileManager.default.fileExists(atPath: scope) {
                let root = URL(fileURLWithPath: scope, isDirectory: true)
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                ) else { continue }

                for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                    let name = url.deletingPathExtension().lastPathComponent
                    guard matchScore(applicationName: name, term: term) != nil else { continue }
                    let standardizedURL = url.standardizedFileURL
                    if seen.insert(standardizedURL.path).inserted {
                        matches.append(FileResult(url: standardizedURL))
                    }
                }
            }

            return Array(matches.filter {
                matchScore(
                    applicationName: $0.url.deletingPathExtension().lastPathComponent,
                    term: term
                ) != nil
            }.sorted {
                let left = $0.url.deletingPathExtension().lastPathComponent
                let right = $1.url.deletingPathExtension().lastPathComponent
                let leftScore = matchScore(applicationName: left, term: term) ?? Int.max
                let rightScore = matchScore(applicationName: right, term: term) ?? Int.max
                if leftScore != rightScore { return leftScore < rightScore }
                return left.localizedStandardCompare(right) == .orderedAscending
            }.prefix(20))
        }.value
    }
}

enum FolderNameSearch {
    static func find(_ term: String) async -> [FileResult] {
        await Task.detached(priority: .userInitiated) {
            let escaped = term
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let expression = "(kMDItemContentType == \"public.folder\") && (kMDItemFSName == \"*\(escaped)*\"cd)"
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
                return Array(String(decoding: data, as: UTF8.self)
                    .split(separator: "\n")
                    .map { FileResult(url: URL(fileURLWithPath: String($0))) }
                    .filter { $0.isDirectory && $0.url.pathExtension.lowercased() != "app" }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    .prefix(200))
            } catch {
                return []
            }
        }.value
    }
}

enum GoogleDriveDirectSearch {
    static func find(_ term: String) async -> [FileResult] {
        await Task.detached(priority: .utility) { scan(term) }.value
    }

    private static func scan(_ term: String) -> [FileResult] {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let cloudStorage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        var roots: [URL] = []
        if let cloudRoots = try? manager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            roots += cloudRoots.filter { $0.lastPathComponent.lowercased().hasPrefix("googledrive-") }
        }
        let legacy = home.appendingPathComponent("Google Drive", isDirectory: true)
        if manager.fileExists(atPath: legacy.path) { roots.append(legacy) }

        let lowered = term.lowercased()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .nameKey]
        var seen = Set<String>()
        var matches: [FileResult] = []
        let escaped = term.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let expression = "kMDItemFSName == \"*\(escaped)*\"cd"

        // Query every Drive mount explicitly first. A scoped metadata query can
        // see File Provider items omitted by the broader home-directory query.
        for root in roots {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-onlyin", root.path, expression]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let url = URL(fileURLWithPath: String(line)).standardizedFileURL
                    if seen.insert(url.path).inserted { matches.append(FileResult(url: url)) }
                }
            } catch { continue }
        }

        // Only recursively scan mounts that currently expose a real Drive root;
        // stale timestamped mounts can block enumeration indefinitely.
        let activeRoots = roots.filter { root in
            manager.fileExists(atPath: root.appendingPathComponent("My Drive").path)
                || manager.fileExists(atPath: root.appendingPathComponent("Shared drives").path)
        }
        for root in activeRoots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                if url.lastPathComponent.lowercased().contains(lowered),
                   seen.insert(url.standardizedFileURL.path).inserted {
                    matches.append(FileResult(url: url))
                    if matches.count >= 500 { break }
                }
            }
            if matches.count >= 500 { break }
        }
        return matches.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

enum GoogleDriveCatalogSearch {
    static func find(_ term: String) async -> [WebSearchResult] {
        await Task.detached(priority: .utility) { scan(term) }.value
    }

    private static func scan(_ term: String) -> [WebSearchResult] {
        let manager = FileManager.default
        let driveFS = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/DriveFS", isDirectory: true)
        guard let accountFolders = try? manager.contentsOfDirectory(
            at: driveFS, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let escaped = term.replacingOccurrences(of: "'", with: "''")
        let query = "SELECT i.id, replace(replace(i.local_title, char(9), ' '), char(10), ' '), i.mime_type, i.is_folder, COALESCE((SELECT replace(replace(p.local_title, char(9), ' '), char(10), ' ') FROM stable_parents sp JOIN items p ON p.stable_id=sp.parent_stable_id WHERE sp.item_stable_id=i.stable_id LIMIT 1), 'Google Drive') FROM items i WHERE i.trashed=0 AND i.is_tombstone=0 AND i.local_title IS NOT NULL AND lower(i.local_title) LIKE lower('%\(escaped)%') LIMIT 400;"
        var seen = Set<String>()
        var results: [WebSearchResult] = []
        for account in accountFolders {
            let database = account.appendingPathComponent("metadata_sqlite_db")
            guard manager.fileExists(atPath: database.path) else { continue }
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = ["-readonly", "-separator", "\t", database.path, query]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard fields.count >= 5, seen.insert(fields[0]).inserted,
                          let url = URL(string: "https://drive.google.com/open?id=\(fields[0])") else { continue }
                    let isFolder = fields[3] == "1"
                    let isMedia = fields[2].hasPrefix("image/") || fields[2].hasPrefix("video/")
                    let thumbnail = isMedia ? URL(string: "https://drive.google.com/thumbnail?id=\(fields[0])&sz=w240-h180") : nil
                    results.append(WebSearchResult(
                        id: "google-drive|\(fields[0])",
                        engineID: isFolder ? "google_drive_folder" : "google_drive_file",
                        title: fields[1],
                        subtitle: "Google Drive · \(fields[4])",
                        url: url, thumbnailURL: thumbnail, isFallback: false
                    ))
                }
            } catch { continue }
        }
        return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

enum PersistentSpotlightIndex {
    private static let refreshInterval: TimeInterval = 15 * 60
    private static var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AiFly", isDirectory: true)
            .appendingPathComponent("spotlight-index.sqlite")
    }

    static func refreshIfNeeded(force: Bool = false) async {
        await Task.detached(priority: .utility) {
            let manager = FileManager.default
            let database = indexURL
            if !force,
               let values = try? database.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate,
               Date().timeIntervalSince(modified) < refreshInterval { return }
            try? manager.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = database.deletingLastPathComponent().appendingPathComponent("spotlight-index-new.sqlite")
            try? manager.removeItem(at: temporary)

            let spotlight = Process()
            let spotlightOutput = Pipe()
            spotlight.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            spotlight.arguments = ["-onlyin", manager.homeDirectoryForCurrentUser.path, "kMDItemFSName != \"\""]
            spotlight.standardOutput = spotlightOutput
            spotlight.standardError = FileHandle.nullDevice
            let sqlite = Process()
            let sqliteInput = Pipe()
            sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            sqlite.arguments = [temporary.path]
            sqlite.standardInput = sqliteInput
            sqlite.standardOutput = FileHandle.nullDevice
            sqlite.standardError = FileHandle.nullDevice
            do {
                try sqlite.run()
                let writer = sqliteInput.fileHandleForWriting
                writer.write(Data("PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF; CREATE TABLE entries(path TEXT PRIMARY KEY, name TEXT NOT NULL COLLATE NOCASE); CREATE INDEX entries_name ON entries(name); BEGIN;\n".utf8))
                try spotlight.run()
                let data = spotlightOutput.fileHandleForReading.readDataToEndOfFile()
                spotlight.waitUntilExit()
                for rawPath in data.split(separator: 10) {
                    let path = String(decoding: rawPath, as: UTF8.self)
                    guard !path.isEmpty else { continue }
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    let escapedPath = path.replacingOccurrences(of: "'", with: "''")
                    let escapedName = name.replacingOccurrences(of: "'", with: "''")
                    writer.write(Data("INSERT OR IGNORE INTO entries VALUES('\(escapedPath)','\(escapedName)');\n".utf8))
                }
                writer.write(Data("COMMIT;\n".utf8))
                try writer.close()
                sqlite.waitUntilExit()
                guard sqlite.terminationStatus == 0 else { try? manager.removeItem(at: temporary); return }
                if manager.fileExists(atPath: database.path) { try? manager.removeItem(at: database) }
                try? manager.moveItem(at: temporary, to: database)
            } catch { try? manager.removeItem(at: temporary) }
        }.value
    }

    static func find(_ term: String) async -> [FileResult] {
        await Task.detached(priority: .userInitiated) {
            let database = indexURL
            guard FileManager.default.fileExists(atPath: database.path) else { return [] }
            let escaped = term.replacingOccurrences(of: "'", with: "''")
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = ["-readonly", database.path, "SELECT path FROM entries WHERE name LIKE '%\(escaped)%' COLLATE NOCASE ORDER BY CASE WHEN name LIKE '\(escaped)%' COLLATE NOCASE THEN 0 ELSE 1 END, name LIMIT 300;"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap {
                    let path = String($0)
                    return FileManager.default.fileExists(atPath: path) ? FileResult(url: URL(fileURLWithPath: path)) : nil
                }
            } catch { return [] }
        }.value
    }
}

struct RecentItemsSnapshot {
    let files: [FileResult]
    let applications: [FileResult]
}

enum RecentItemsSearch {
    static func load() async -> RecentItemsSnapshot {
        await Task.detached(priority: .utility) {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let recentExpression = "kMDItemLastUsedDate >= $time.today(-30)"
            let fileURLs = runMDFind(scope: home, expression: recentExpression)
                .filter { url in
                    let item = FileResult(url: url)
                    return !item.isDirectory && url.pathExtension.lowercased() != "app"
                }

            let appExpression = "(kMDItemContentType == \"com.apple.application-bundle\") && (kMDItemLastUsedDate >= $time.today(-90))"
            let appScopes = ["/Applications", "/System/Applications", home + "/Applications"]
            var seenApps = Set<String>()
            let applicationURLs = appScopes
                .flatMap { runMDFind(scope: $0, expression: appExpression) }
                .filter { seenApps.insert($0.standardizedFileURL.path).inserted }

            return RecentItemsSnapshot(
                files: Array(fileURLs.prefix(14).map(FileResult.init(url:))),
                applications: Array(applicationURLs.prefix(14).map(FileResult.init(url:)))
            )
        }.value
    }

    private static func runMDFind(scope: String, expression: String) -> [URL] {
        guard FileManager.default.fileExists(atPath: scope) else { return [] }
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", scope, expression]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
        } catch {
            return []
        }
    }
}

@MainActor
enum SpotlightSearch {
    private static var activeQueries: [UUID: SpotlightQuerySession] = [:]

    static func find(_ term: String, inside folder: URL? = nil) async -> [FileResult] {
        if let folder { return await FolderSearch.find(term, inside: folder) }
        async let commandLookup = SpotlightCommandFallback.find(term)
        async let savedLookup = PersistentSpotlightIndex.find(term)
        let (commandResults, savedResults) = await (commandLookup, savedLookup)
        var seen = Set<String>()
        let combined = (commandResults + savedResults).filter { seen.insert($0.url.standardizedFileURL.path).inserted }
        if !combined.isEmpty { return combined }
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
            let contents = (try? manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
            let urls = normalizedTerm.isEmpty
                ? contents
                : contents.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(normalizedTerm) }

            return urls
                .map(FileResult.init(url:))
                .sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .prefix(200)
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
                }.prefix(200))
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
        completion(Array(matches.prefix(200)))
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
