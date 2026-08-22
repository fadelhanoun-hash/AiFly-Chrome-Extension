import Foundation
import Security
import Carbon.HIToolbox
import Contacts
import CoreSpotlight

enum WebSearchService {
    enum GoogleSearchError: LocalizedError {
        case missingCredentials
        case api(String)
        var errorDescription: String? {
            switch self {
            case .missingCredentials: return "Add a Serper API key in Settings → Web Search."
            case .api(let message): return "Search API: \(message)"
            }
        }
    }

    static func googleCustomSearch(_ term: String, image: Bool, settings: AppSettings, page: Int = 1) async throws -> [WebSearchResult] {
        let serperKey = settings.serperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !serperKey.isEmpty { return try await serperSearch(term, image: image, key: serperKey, page: page) }
        let key = settings.googleSearchAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let engineID = settings.googleSearchEngineID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !engineID.isEmpty else { throw GoogleSearchError.missingCredentials }
        var components = URLComponents(string: "https://customsearch.googleapis.com/customsearch/v1")
        components?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "cx", value: engineID),
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "safe", value: "active"),
            URLQueryItem(name: "num", value: "10"),
            URLQueryItem(name: "start", value: String(min(91, ((max(1, page) - 1) * 10) + 1)))
        ] + (image ? [URLQueryItem(name: "searchType", value: "image")] : [])
        guard let url = components?.url else { throw GoogleSearchError.api("Invalid request.") }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = payload["error"] as? [String: Any],
           let message = error["message"] as? String { throw GoogleSearchError.api(message) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = payload["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let title = item["title"] as? String,
                  let link = item["link"] as? String,
                  let resultURL = URL(string: link) else { return nil }
            let snippet = item["snippet"] as? String ?? (item["displayLink"] as? String ?? "Google result")
            let imageInfo = item["image"] as? [String: Any]
            let thumbnail = (imageInfo?["thumbnailLink"] as? String).flatMap(URL.init(string:))
            let contextURL = (imageInfo?["contextLink"] as? String).flatMap(URL.init(string:)) ?? resultURL
            return WebSearchResult(
                id: "google-api|\(link)", engineID: image ? "images" : "google",
                title: title, subtitle: snippet, url: contextURL,
                thumbnailURL: image ? (thumbnail ?? resultURL) : nil, isFallback: false
            )
        }
    }

    private static func serperSearch(_ term: String, image: Bool, key: String, page: Int) async throws -> [WebSearchResult] {
        guard let url = URL(string: "https://google.serper.dev/\(image ? "images" : "search")") else {
            throw GoogleSearchError.api("Invalid Serper request.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-API-KEY")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "q": term, "gl": "us", "hl": "en", "autocorrect": true, "page": max(1, page)
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleSearchError.api("Serper returned an unreadable response.")
        }
        if let message = payload["message"] as? String { throw GoogleSearchError.api("Serper: \(message)") }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GoogleSearchError.api("Serper request failed.")
        }

        if image {
            let items = payload["images"] as? [[String: Any]] ?? []
            return items.prefix(60).compactMap { item in
                guard let title = item["title"] as? String,
                      let imageString = (item["imageUrl"] as? String) ?? (item["thumbnailUrl"] as? String),
                      let imageURL = URL(string: imageString) else { return nil }
                let pageURL = ((item["link"] as? String).flatMap(URL.init(string:))) ?? imageURL
                let thumbnailURL = ((item["thumbnailUrl"] as? String).flatMap(URL.init(string:))) ?? imageURL
                let source = item["source"] as? String ?? (item["domain"] as? String ?? "Google Images via Serper")
                return WebSearchResult(
                    id: "serper-image|\(imageString)", engineID: "images", title: title,
                    subtitle: source, url: pageURL, thumbnailURL: thumbnailURL, isFallback: false
                )
            }
        }

        var results: [WebSearchResult] = []
        if let overview = payload["aiOverview"],
           let overviewText = aiText(from: overview), !overviewText.isEmpty {
            let sourceItems = aiSources(from: overview)
            let overviewURL = sourceItems.first?.url ?? googleSearchURL(for: term)
            if let overviewURL {
                results.append(WebSearchResult(
                    id: "serper-ai-overview|\(term)", engineID: "google_ai", title: "AI Overview",
                    subtitle: overviewText, url: overviewURL, thumbnailURL: nil, isFallback: false
                ))
            }
            results += sourceItems.prefix(5).map { source in
                WebSearchResult(
                    id: "serper-ai-source|\(source.url.absoluteString)", engineID: "google_ai_source",
                    title: source.title, subtitle: source.url.host ?? "AI Overview source",
                    url: source.url, thumbnailURL: nil, isFallback: false
                )
            }
        }
        if let answerBox = payload["answerBox"] as? [String: Any],
           let answer = aiText(from: answerBox), !answer.isEmpty,
           let linkString = (answerBox["link"] as? String) ?? (answerBox["source"] as? String),
           let link = URL(string: linkString) {
            results.append(WebSearchResult(
                id: "serper-featured|\(link.absoluteString)", engineID: "google_featured",
                title: answerBox["title"] as? String ?? "Featured answer", subtitle: answer,
                url: link, thumbnailURL: nil, isFallback: false
            ))
        }
        if let graph = payload["knowledgeGraph"] as? [String: Any],
           let title = graph["title"] as? String,
           let link = (graph["website"] as? String) ?? (graph["descriptionLink"] as? String),
           let resultURL = URL(string: link) {
            results.append(WebSearchResult(
                id: "serper-knowledge|\(link)", engineID: "google_knowledge", title: title,
                subtitle: graph["description"] as? String ?? (graph["type"] as? String ?? "Google Knowledge Graph"),
                url: resultURL, thumbnailURL: (graph["imageUrl"] as? String).flatMap(URL.init(string:)), isFallback: false
            ))
        }

        let items = payload["organic"] as? [[String: Any]] ?? []
        results += items.prefix(20).compactMap { item in
            guard let title = item["title"] as? String,
                  let link = item["link"] as? String,
                  let resultURL = URL(string: link) else { return nil }
            let subtitle = item["snippet"] as? String ?? (resultURL.host ?? "Google result")
            return WebSearchResult(
                id: "serper-web|\(link)", engineID: "google", title: title,
                subtitle: subtitle, url: resultURL, thumbnailURL: nil, isFallback: false
            )
        }
        if let questions = payload["peopleAlsoAsk"] as? [[String: Any]] {
            results += questions.prefix(5).compactMap { item in
                guard let question = item["question"] as? String,
                      let link = item["link"] as? String,
                      let resultURL = URL(string: link) else { return nil }
                return WebSearchResult(
                    id: "serper-answer|\(question)|\(link)", engineID: "google_answer", title: question,
                    subtitle: item["snippet"] as? String ?? (item["title"] as? String ?? "People also ask"),
                    url: resultURL, thumbnailURL: nil, isFallback: false
                )
            }
        }
        return results
    }

    private static func aiText(from value: Any) -> String? {
        if let text = value as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let object = value as? [String: Any] else { return nil }
        for key in ["text", "answer", "snippet", "content", "overview"] {
            if let text = object[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for key in ["blocks", "paragraphs", "items"] {
            guard let values = object[key] as? [Any] else { continue }
            let text = values.compactMap { aiText(from: $0) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func aiSources(from value: Any) -> [(title: String, url: URL)] {
        guard let object = value as? [String: Any] else { return [] }
        for key in ["sources", "references", "citations"] {
            guard let values = object[key] as? [[String: Any]] else { continue }
            let sources = values.compactMap { item -> (String, URL)? in
                guard let link = (item["link"] as? String) ?? (item["url"] as? String),
                      let url = URL(string: link) else { return nil }
                return (item["title"] as? String ?? item["source"] as? String ?? url.host ?? "Source", url)
            }
            if !sources.isEmpty { return sources }
        }
        return []
    }

    private static func googleSearchURL(for term: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: term)]
        return components?.url
    }

    static func completion(for term: String) async -> String? {
        let values = await suggestions(term, youtube: false)
        return values.first { $0.localizedCaseInsensitiveCompare(term) != .orderedSame }
    }

    static func webFallback(_ term: String) async -> [WebSearchResult] {
        guard var components = URLComponents(string: "https://www.bing.com/search") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "safeSearch", value: "Strict")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(
                pattern: #"<li class="b_algo"[\s\S]*?<h2[^>]*><a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)</a></h2>[\s\S]*?(?:<p[^>]*>([\s\S]*?)</p>)?"#,
                options: [.caseInsensitive]
              ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        return regex.matches(in: html, range: range).prefix(20).compactMap { match in
            guard let linkRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { return nil }
            let link = decodeHTML(String(html[linkRange]))
            guard seen.insert(link).inserted, let resultURL = URL(string: link) else { return nil }
            let title = plainHTML(String(html[titleRange]))
            let snippet: String
            if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound,
               let snippetRange = Range(match.range(at: 3), in: html) {
                snippet = plainHTML(String(html[snippetRange]))
            } else {
                snippet = resultURL.host ?? "Web result"
            }
            return WebSearchResult(
                id: "no-key-web|\(link)", engineID: "google", title: title,
                subtitle: snippet, url: resultURL, thumbnailURL: nil, isFallback: true
            )
        }
    }

    private static func plainHTML(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeHTML(withoutTags).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
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

    static func googleImages(_ term: String) async -> [WebSearchResult] {
        guard let escaped = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.google.com/search?tbm=isch&q=\(escaped)") else { return [] }
        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let html = String(data: data, encoding: .utf8),
           let regex = try? NSRegularExpression(pattern: #"https://encrypted-tbn[0-9]\.gstatic\.com/images\?[^\" ]+"#) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            var seen = Set<String>()
            let googleResults = regex.matches(in: html, range: range).compactMap { match -> WebSearchResult? in
                guard let swiftRange = Range(match.range, in: html) else { return nil }
                let raw = String(html[swiftRange]).replacingOccurrences(of: "&amp;", with: "&")
                guard seen.insert(raw).inserted, let thumbnail = URL(string: raw) else { return nil }
                return WebSearchResult(id: "image|\(raw)", engineID: "images", title: term, subtitle: "Google Images", url: searchURL, thumbnailURL: thumbnail, isFallback: false)
            }
            if !googleResults.isEmpty { return Array(googleResults.prefix(40)) }
        }

        // Google frequently serves an SG_REL anti-automation page to embedded WebKit.
        // Use a server-rendered image feed so the native gallery does not remain blank.
        guard let fallbackURL = URL(string: "https://www.bing.com/images/search?q=\(escaped)&safeSearch=strict") else { return [] }
        var fallbackRequest = URLRequest(url: fallbackURL)
        fallbackRequest.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let (fallbackData, _) = try? await URLSession.shared.data(for: fallbackRequest),
              let fallbackHTML = String(data: fallbackData, encoding: .utf8),
              let attributeRegex = try? NSRegularExpression(pattern: #"\sm=\"([^\"]+)\""#) else { return [] }
        let fallbackRange = NSRange(fallbackHTML.startIndex..<fallbackHTML.endIndex, in: fallbackHTML)
        var seen = Set<String>()
        return attributeRegex.matches(in: fallbackHTML, range: fallbackRange).compactMap { match -> WebSearchResult? in
            guard let valueRange = Range(match.range(at: 1), in: fallbackHTML) else { return nil }
            let json = String(fallbackHTML[valueRange])
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#39;", with: "'")
            guard let data = json.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = (payload["turl"] as? String) ?? (payload["murl"] as? String),
                  seen.insert(raw).inserted,
                  let thumbnail = URL(string: raw) else { return nil }
            return WebSearchResult(id: "image-fallback|\(raw)", engineID: "images", title: term, subtitle: "Image result", url: searchURL, thumbnailURL: thumbnail, isFallback: true)
        }.prefix(40).map { $0 }
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

@MainActor
enum CoreSpotlightSearch {
    private static var activeQueries: [UUID: CSUserQuery] = [:]

    static func find(_ term: String) async -> [SystemSearchResult] {
        let value = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        return await withCheckedContinuation { continuation in
            let queryID = UUID()
            let context = CSUserQueryContext()
            context.enableRankedResults = true
            context.maxResultCount = 80
            let query = CSUserQuery(userQueryString: value, userQueryContext: context)
            var collected: [CSSearchableItem] = []
            query.foundItemsHandler = { items in collected.append(contentsOf: items) }
            query.completionHandler = { _ in
                Task { @MainActor in
                    activeQueries[queryID] = nil
                    var seen = Set<String>()
                    let results = collected.compactMap { item -> SystemSearchResult? in
                        let attributes = item.attributeSet
                        let title = attributes.displayName ?? attributes.title ?? "Spotlight Result"
                        let subtitle = attributes.contentDescription ?? attributes.kind ?? attributes.domainIdentifier ?? "System result"
                        let type = attributes.contentType ?? attributes.contentTypeTree?.first ?? "public.item"
                        let url = attributes.contentURL ?? attributes.path.map { URL(fileURLWithPath: $0) }
                        guard seen.insert(item.uniqueIdentifier).inserted else { return nil }
                        return SystemSearchResult(id: item.uniqueIdentifier, title: title, subtitle: subtitle, contentType: type, url: url)
                    }
                    continuation.resume(returning: Array(results.prefix(40)))
                }
            }
            activeQueries[queryID] = query
            query.start()
        }
    }
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
            let homeApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
            let scopes = ["/Applications", "/System/Applications", homeApplications]
            var seen = Set<String>()
            var matches: [FileResult] = []
            // Application folders are small enough to enumerate directly. This
            // avoids waiting for sequential Spotlight processes on every key.
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

        return matches.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

enum GoogleDriveIndexRefresh {
    static func catalogSignature() -> String {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let driveFS = home.appendingPathComponent("Library/Application Support/Google/DriveFS", isDirectory: true)
        let cloudStorage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let databases = ((try? manager.contentsOfDirectory(at: driveFS, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("metadata_sqlite_db") }
            .filter { manager.fileExists(atPath: $0.path) }
        let databaseState = databases.map { url -> String in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(url.path):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
        }.sorted()
        let mounts = ((try? manager.contentsOfDirectory(at: cloudStorage, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.lowercased().hasPrefix("googledrive-") }
            .map(\.path).sorted()
        return (databaseState + mounts).joined(separator: "|")
    }

    static func force() async {
        await Task.detached(priority: .utility) {
            let manager = FileManager.default
            let cloudStorage = manager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/CloudStorage", isDirectory: true)
            let roots = (try? manager.contentsOfDirectory(
                at: cloudStorage,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ))?.filter { $0.lastPathComponent.lowercased().hasPrefix("googledrive-") } ?? []
            for root in roots {
                // Ask Metadata Server to revisit File Provider placeholders.
                let importer = Process()
                importer.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
                importer.arguments = ["-i", root.path]
                importer.standardOutput = FileHandle.nullDevice
                importer.standardError = FileHandle.nullDevice
                try? importer.run()
                importer.waitUntilExit()

                // Enumerating the Drive roots prompts File Provider to refresh
                // directory metadata without downloading file contents.
                for child in ["My Drive", "Shared drives"] {
                    let url = root.appendingPathComponent(child, isDirectory: true)
                    _ = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.nameKey], options: [.skipsHiddenFiles])
                }
            }
        }.value
    }
}

enum GoogleDriveCatalogBrowser {
    static func isGoogleDriveURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path.lowercased().contains("/library/cloudstorage/googledrive-")
    }

    static func children(of folder: URL) async -> [FileResult] {
        await Task.detached(priority: .utility) { scanChildren(of: folder) }.value
    }

    private static func scanChildren(of folder: URL) -> [FileResult] {
        let standardizedPath = folder.standardizedFileURL.path
        guard let markerRange = standardizedPath.range(of: "/Library/CloudStorage/GoogleDrive-", options: [.caseInsensitive]) else { return [] }
        let afterMarker = standardizedPath[markerRange.upperBound...]
        guard let slash = afterMarker.firstIndex(of: "/") else { return [] }
        let relativePath = String(afterMarker[afterMarker.index(after: slash)...])
        let components = relativePath.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !components.isEmpty else { return [] }

        let manager = FileManager.default
        let driveFS = manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/DriveFS", isDirectory: true)
        let accounts = (try? manager.contentsOfDirectory(at: driveFS, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var found: [String: FileResult] = [:]

        for account in accounts {
            let database = account.appendingPathComponent("metadata_sqlite_db")
            guard manager.fileExists(atPath: database.path) else { continue }
            var parentID: String?
            for component in components {
                let title = sqlQuote(component)
                let query: String
                if let parentID {
                    query = "SELECT c.stable_id FROM items c JOIN stable_parents sp ON sp.item_stable_id=c.stable_id WHERE sp.parent_stable_id=\(parentID) AND c.trashed=0 AND c.is_tombstone=0 AND c.local_title='\(title)' COLLATE NOCASE LIMIT 1;"
                } else {
                    query = "SELECT stable_id FROM items WHERE trashed=0 AND is_tombstone=0 AND is_folder=1 AND local_title='\(title)' COLLATE NOCASE LIMIT 1;"
                }
                parentID = sqlite(database: database, query: query).first?.first
                if parentID == nil { break }
            }
            guard let parentID else { continue }
            let query = "SELECT c.id,replace(replace(c.local_title,char(9),' '),char(10),' '),c.is_folder FROM items c JOIN stable_parents sp ON sp.item_stable_id=c.stable_id WHERE sp.parent_stable_id=\(parentID) AND c.trashed=0 AND c.is_tombstone=0 AND c.local_title IS NOT NULL ORDER BY c.is_folder DESC,c.local_title COLLATE NOCASE;"
            for fields in sqlite(database: database, query: query) where fields.count >= 3 {
                let title = fields[1]
                let isFolder = fields[2] == "1"
                let localURL = folder.appendingPathComponent(title, isDirectory: isFolder)
                let remoteURL = URL(string: "https://drive.google.com/open?id=\(fields[0])")
                found[title.lowercased()] = FileResult(url: localURL, directoryHint: isFolder, remoteURL: remoteURL)
            }
        }
        return Array(found.values)
    }

    private static func sqlite(database: URL, query: String) -> [[String]] {
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
            guard process.terminationStatus == 0 else { return [] }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map {
                $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            }
        } catch { return [] }
    }

    private static func sqlQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
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
        let query = "WITH RECURSIVE matched AS (SELECT stable_id,id,local_title,mime_type,is_folder FROM items WHERE trashed=0 AND is_tombstone=0 AND local_title IS NOT NULL AND lower(local_title) LIKE lower('%\(escaped)%') LIMIT 2000), ancestors(origin,current_id,path,depth) AS (SELECT stable_id,stable_id,'',0 FROM matched UNION ALL SELECT a.origin,sp.parent_stable_id,CASE WHEN p.local_title IS NULL OR p.local_title='' THEN a.path ELSE replace(replace(p.local_title,char(9),' '),char(10),' ') || CASE WHEN a.path='' THEN '' ELSE '/' || a.path END END,a.depth+1 FROM ancestors a JOIN stable_parents sp ON sp.item_stable_id=a.current_id JOIN items p ON p.stable_id=sp.parent_stable_id WHERE a.depth<20), deepest AS (SELECT a.origin,a.path FROM ancestors a WHERE a.depth=(SELECT MAX(b.depth) FROM ancestors b WHERE b.origin=a.origin)) SELECT m.id,replace(replace(m.local_title,char(9),' '),char(10),' '),m.mime_type,m.is_folder,COALESCE(NULLIF(d.path,''),'My Drive') FROM matched m LEFT JOIN deepest d ON d.origin=m.stable_id;"
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
                    let displayPath = cleanDrivePath(parentPath: fields[4], title: fields[1])
                    results.append(WebSearchResult(
                        id: "google-drive|\(fields[0])",
                        engineID: isFolder ? "google_drive_folder" : "google_drive_file",
                        title: fields[1],
                        subtitle: displayPath,
                        url: url, thumbnailURL: thumbnail, isFallback: false
                    ))
                }
            } catch { continue }
        }
        return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func cleanDrivePath(parentPath: String, title: String) -> String {
        let components = parentPath.split(separator: "/").map(String.init)
        let rootIndex = components.lastIndex {
            $0.caseInsensitiveCompare("My Drive") == .orderedSame
                || $0.caseInsensitiveCompare("Shared drives") == .orderedSame
        }
        let visibleParents = rootIndex.map { Array(components.dropFirst($0 + 1)) } ?? components.filter {
            !$0.allSatisfy(\.isNumber) && !$0.lowercased().hasPrefix("google-drive-")
        }
        return (visibleParents + [title]).filter { !$0.isEmpty }.joined(separator: "/")
    }
}

enum SearchLearningStore {
    private static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AiFly", isDirectory: true)
            .appendingPathComponent("search-learning.sqlite")
    }

    private static var spotlightDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AiFly/Indexes", isDirectory: true)
            .appendingPathComponent("spotlight-cache.sqlite")
    }

    static func record(query: String, targetKey: String, kind: String) async {
        await Task.detached(priority: .utility) {
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return }
            let manager = FileManager.default
            try? manager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let escapedQuery = normalized.replacingOccurrences(of: "'", with: "''")
            let escapedTarget = targetKey.replacingOccurrences(of: "'", with: "''")
            let escapedKind = kind.replacingOccurrences(of: "'", with: "''")
            run("CREATE TABLE IF NOT EXISTS choices(query TEXT NOT NULL,target_key TEXT NOT NULL,kind TEXT NOT NULL,use_count INTEGER NOT NULL DEFAULT 1,last_used REAL NOT NULL,PRIMARY KEY(query,target_key)); INSERT INTO choices(query,target_key,kind,use_count,last_used) VALUES('\(escapedQuery)','\(escapedTarget)','\(escapedKind)',1,strftime('%s','now')) ON CONFLICT(query,target_key) DO UPDATE SET use_count=use_count+1,last_used=strftime('%s','now'),kind=excluded.kind;")
        }.value
    }

    static func bonuses(for query: String) async -> [String: Int] {
        await Task.detached(priority: .userInitiated) {
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, FileManager.default.fileExists(atPath: databaseURL.path) else { return [:] }
            let escaped = normalized.replacingOccurrences(of: "'", with: "''")
            let output = run("SELECT target_key,MIN(180,use_count*35 + CASE WHEN last_used > strftime('%s','now')-604800 THEN 35 ELSE 0 END) FROM choices WHERE query='\(escaped)' ORDER BY use_count DESC,last_used DESC LIMIT 50;", capture: true)
            var values: [String: Int] = [:]
            for line in output.split(separator: "\n") {
                let fields = line.split(separator: "|", maxSplits: 1).map(String.init)
                if fields.count == 2, let score = Int(fields[1]) { values[fields[0]] = score }
            }
            return values
        }.value
    }

    static func cachedSpotlightResults(for term: String) async -> [FileResult] {
        await Task.detached(priority: .userInitiated) {
            let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { return [] }
            prepareSpotlightCache()
            let escaped = normalized.replacingOccurrences(of: "'", with: "''")
            let output = runSpotlightCache("SELECT path FROM spotlight_cache WHERE name LIKE '%\(escaped)%' ORDER BY CASE WHEN lower(name) LIKE '\(escaped)%' THEN 0 ELSE 1 END,last_seen DESC LIMIT 200;", capture: true)
            return output.split(separator: "\n").compactMap { value in
                let path = String(value)
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return FileResult(url: URL(fileURLWithPath: path))
            }
        }.value
    }

    static func cacheSpotlightResults(_ results: [FileResult]) async {
        guard !results.isEmpty else { return }
        await Task.detached(priority: .utility) {
            prepareSpotlightCache()
            let rows = results.map { result -> String in
                let path = result.url.standardizedFileURL.path.replacingOccurrences(of: "'", with: "''")
                let name = result.name.replacingOccurrences(of: "'", with: "''")
                return "INSERT INTO spotlight_cache(path,name,last_seen) VALUES('\(path)','\(name)',strftime('%s','now')) ON CONFLICT(path) DO UPDATE SET name=excluded.name,last_seen=excluded.last_seen;"
            }.joined()
            runSpotlightCache("BEGIN;\(rows)COMMIT;")
        }.value
    }

    private static func prepareSpotlightCache() {
        let manager = FileManager.default
        let target = spotlightDatabaseURL
        try? manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let isNew = !manager.fileExists(atPath: target.path)
        runSpotlightCache("CREATE TABLE IF NOT EXISTS spotlight_cache(path TEXT PRIMARY KEY,name TEXT NOT NULL COLLATE NOCASE,last_seen REAL NOT NULL);")
        guard isNew, manager.fileExists(atPath: databaseURL.path) else { return }
        let legacyTable = run("SELECT name FROM sqlite_master WHERE type='table' AND name='spotlight_cache';", capture: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard legacyTable == "spotlight_cache" else { return }
        let legacyPath = databaseURL.path.replacingOccurrences(of: "'", with: "''")
        runSpotlightCache("ATTACH DATABASE '\(legacyPath)' AS legacy; INSERT OR IGNORE INTO spotlight_cache(path,name,last_seen) SELECT path,name,last_seen FROM legacy.spotlight_cache; DETACH DATABASE legacy;")
    }

    @discardableResult
    private static func runSpotlightCache(_ sql: String, capture: Bool = false) -> String {
        run(sql, capture: capture, database: spotlightDatabaseURL)
    }

    @discardableResult
    private static func run(_ sql: String, capture: Bool = false, database: URL? = nil) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [(database ?? databaseURL).path, sql]
        process.standardOutput = capture ? output : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = capture ? output.fileHandleForReading.readDataToEndOfFile() : Data()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        } catch { return "" }
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
        let nativeResults: [FileResult] = await withCheckedContinuation { continuation in
            let id = UUID()
            let session = SpotlightQuerySession(term: term) { results in
                activeQueries[id] = nil
                continuation.resume(returning: results)
            }
            activeQueries[id] = session
            session.start()
        }
        if !nativeResults.isEmpty { return nativeResults }
        return await SpotlightCommandFallback.find(term)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
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

    static func completion(for term: String, settings: AppSettings) async -> String? {
        let prompt = "Autocomplete this medical or general question. Return only one short completed question beginning exactly with these characters, with no explanation: \(term)"
        guard let raw = try? await respond(to: prompt, history: [], settings: settings) else { return nil }
        let withoutTags = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard withoutTags.lowercased().hasPrefix(term.lowercased()), withoutTags.count > term.count else { return nil }
        return String(withoutTags.prefix(180))
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
