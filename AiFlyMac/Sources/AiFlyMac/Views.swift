import SwiftUI
import AppKit
import WebKit
import QuickLookUI

struct LauncherView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: model.mode == .files ? "magnifyingglass" : "sparkles")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField(model.mode == .files ? model.searchPlaceholder : "Ask AiFly anything…", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22))
                        .focused($searchFocused)
                        .onSubmit { submit() }
                    if model.isWorking || model.isSearchingFiles { ProgressView().controlSize(.small) }
                    Picker("Mode", selection: $model.mode) {
                        ForEach(LauncherMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding(.horizontal, 20)
                .frame(height: 64)

                if model.mode == .files && !model.availableFormatFilters.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(Array(model.availableFormatFilters.enumerated()), id: \.element) { index, format in
                                Button { model.selectFormatFilter(at: index) } label: {
                                    HStack(spacing: 5) {
                                        Text(format)
                                        Text("⌘\(index + 1)").foregroundStyle(.secondary)
                                    }
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .frame(height: 25)
                                    .background(model.selectedFormatFilter == format ? Color.accentColor.opacity(0.17) : Color.white.opacity(0.50))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 34)
                }
            }

            Divider()

            Group {
                if model.mode == .files { fileResults } else { chat }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color.white.opacity(0.72))
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onChange(of: model.query) { _ in model.updateSearch() }
        .onChange(of: model.mode) { _ in model.updateSearch(); searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .focusLauncher)) { _ in searchFocused = true }
        .onAppear { searchFocused = true }
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
    }

    private var fileResults: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let root = model.searchRoot {
                    HStack(spacing: 7) {
                        Button { model.leaveCurrentFolder() } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        Text(root.lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("Searching here").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    Divider()
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                        if model.query.isEmpty && model.searchRoot == nil {
                            EmptyStateView(
                                title: "Find anything on your Mac",
                                systemImage: "doc.text.magnifyingglass",
                                description: "Type a filename, folder, or Spotlight phrase."
                            )
                            .frame(height: 360)
                        } else if model.visibleResults.isEmpty {
                            EmptyStateView(
                                title: "No results",
                                systemImage: "magnifyingglass",
                                description: "No files matched \u{201c}\(model.query)\u{201d}."
                            )
                            .frame(height: 360)
                        } else {
                            ForEach(Array(model.visibleResults.enumerated()), id: \.element.id) { index, item in
                                FileRow(item: item, selected: index == model.selection)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) {
                                        model.selection = index
                                        item.isDirectory ? model.enterFolder(item.url) : model.activateSelection()
                                    }
                                    .onTapGesture { model.selection = index; model.hideActions() }
                                    .contextMenu {
                                        if item.isDirectory {
                                            Button("Open Folder Here") {
                                                model.selection = index
                                                model.enterFolder(item.url)
                                            }
                                            Divider()
                                        }
                                        Button("Open") { model.selection = index; model.perform(.open) }
                                        Button("Show in Finder") { model.selection = index; model.perform(.reveal) }
                                        Button("Copy Path") { model.selection = index; model.perform(.copyPath) }
                                    }
                            }
                        }
                    }
                    .padding(8)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .fileSelectionChanged)) { _ in
                        proxy.scrollTo(model.selection, anchor: .center)
                    }
                }
            }
            .frame(minWidth: 390, maxWidth: .infinity)

            FilePreviewPanel()
                .environmentObject(model)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
        }
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.messages.isEmpty {
                        EmptyStateView(
                            title: "Ask without switching apps",
                            systemImage: "sparkles",
                            description: "Choose a provider and API key in Settings."
                        )
                            .frame(height: 350)
                    }
                    ForEach(model.messages) { message in
                        Group {
                            if message.role == "assistant" {
                                RichHTMLView(fragment: message.content)
                            } else {
                                Text(message.content)
                                    .textSelection(.enabled)
                            }
                        }
                            .padding(message.role == "user" ? 12 : 14)
                            .background(message.role == "user" ? Color.accentColor.opacity(0.15) : Color.white)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        message.role == "user" ? Color.clear : Color.black.opacity(0.10),
                                        lineWidth: 1
                                    )
                            }
                            .shadow(
                                color: message.role == "user" ? .clear : Color.black.opacity(0.06),
                                radius: 5,
                                y: 2
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                            .id(message.id)
                    }
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                .padding(14)
            }
            .onChange(of: model.messages.count) { _ in if let id = model.messages.last?.id { proxy.scrollTo(id) } }
        }
    }

    private func submit() {
        if model.mode == .files && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.switchToAI()
        } else if model.mode == .files {
            model.performPrimaryFileAction()
        }
        else if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.switchToMacSearch()
        } else {
            Task { await model.sendQuestion() }
        }
    }

}

private struct FilePreviewPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let file = model.selectedFile {
                if file.isGoogleDriveItem {
                    HStack(spacing: 8) {
                        Button {
                            Task { await model.downloadSelectedGoogleDriveFile() }
                        } label: {
                            Label(model.isDownloading ? "Downloading…" : "Download", systemImage: "arrow.down.circle")
                        }
                        .disabled(model.isDownloading || file.isDirectory)
                        Button { model.openSelectedFile() } label: {
                            Label("Open", systemImage: "arrow.up.forward.app")
                        }
                        Spacer()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                }
                QuickLookPreview(url: file.url)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260, alignment: .top)
                    .background(Color.white.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.75), lineWidth: 1)
                    }
                    .padding(12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(file.folder).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)

                if model.showFileActions {
                    VStack(spacing: 2) {
                        ForEach(Array(FileAction.allCases.enumerated()), id: \.element.id) { index, action in
                            HStack {
                                Image(systemName: action.icon).frame(width: 18)
                                Text(action.rawValue)
                                Spacer()
                                if index == model.actionSelection { Image(systemName: "return") }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(index == model.actionSelection ? Color.accentColor.opacity(0.14) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                            .onTapGesture { model.actionSelection = index; model.perform(action) }
                        }
                    }
                    .padding(7)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.16))
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}

private struct RichHTMLView: View {
    let fragment: String
    @State private var contentHeight: CGFloat = 60

    var body: some View {
        HTMLWebView(fragment: fragment, contentHeight: $contentHeight)
            .frame(maxWidth: .infinity)
            .frame(height: contentHeight)
    }
}

private struct HTMLWebView: NSViewRepresentable {
    let fragment: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedFragment != fragment else { return }
        context.coordinator.loadedFragment = fragment
        let cleanFragment = fragment
            .replacingOccurrences(of: "```html", with: "")
            .replacingOccurrences(of: "```", with: "")
        let document = """
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <meta name="color-scheme" content="light">
        <style>
        *{box-sizing:border-box} body{margin:0;color:#1f2937;background:transparent;font:14px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.48;overflow:hidden}
        p{margin:0 0 9px} p:last-child{margin-bottom:0} strong{font-weight:700;color:#111827}
        ul,ol{margin:5px 0 9px;padding-left:21px} li{margin:3px 0}
        table{width:100%;border-collapse:collapse;margin:8px 0;font-size:13px} th{background:#eef2ff;font-weight:700;text-align:left} th,td{border:1px solid #dbe1ea;padding:6px 8px;vertical-align:top}
        h1,h2,h3{font-size:15px;margin:10px 0 5px;color:#111827} a{color:#2563eb}
        </style></head><body>\(cleanFragment)</body></html>
        """
        webView.loadHTMLString(document, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var contentHeight: CGFloat
        var loadedFragment: String?

        init(contentHeight: Binding<CGFloat>) { _contentHeight = contentHeight }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { [weak self] value, _ in
                guard let height = value as? NSNumber else { return }
                DispatchQueue.main.async {
                    // Size the web content to its full document so the enclosing
                    // SwiftUI chat view owns scrolling instead of clipping HTML.
                    self?.contentHeight = max(34, min(CGFloat(truncating: height), 6000))
                }
            }
        }
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

private struct FileRow: View {
    let item: FileResult
    let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: item.icon).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).fontWeight(.medium).lineLimit(1)
                Text(item.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "return").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).frame(height: 52)
        .background(selected ? Color.accentColor.opacity(0.16) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var provider: AIProvider = .openAI
    @State private var shortcut: Shortcut = .optionSpace
    @State private var openAIKey = ""
    @State private var geminiKey = ""
    @State private var includedExtensions = ""
    @State private var excludedExtensions = ""
    @State private var includedKinds: Set<String> = []
    @State private var excludedKinds: Set<String> = []
    @State private var excludedFolders: [String] = []
    @State private var launchAtLogin = false
    @State private var saved = false

    var body: some View {
        Form {
            Section("Launcher") {
                Picker("Global hotkey", selection: $shortcut) {
                    ForEach(Shortcut.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("The shortcut opens AiFly from any app. Some combinations may already be reserved by macOS.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Launch AiFly at login", isOn: $launchAtLogin)
            }
            Section("Search extensions") {
                TextField("Include only (example: pdf, png, docx)", text: $includedExtensions)
                TextField("Always exclude (example: tmp, log, app)", text: $excludedExtensions)
                Text("Leave Include empty to allow every extension. Exclude always takes priority.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("File types to include") {
                ScopeKindGrid(selection: $includedKinds)
                Text("No selection means all file types.").font(.caption).foregroundStyle(.secondary)
            }
            Section("File types to avoid") {
                ScopeKindGrid(selection: $excludedKinds)
            }
            Section("Folders to avoid") {
                ForEach(excludedFolders, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { excludedFolders.removeAll { $0 == path } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add Folder…") { chooseExcludedFolder() }
            }
            Section("AI provider") {
                Picker("Provider", selection: $provider) {
                    ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) }
                }
                SecureField("OpenAI API key", text: $openAIKey)
                SecureField("Gemini API key", text: $geminiKey)
                Text("API keys are stored in your macOS Keychain and sent only to the selected provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if saved { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                Spacer()
                Button("Save Settings") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            provider = model.settings.provider
            shortcut = model.settings.shortcut
            openAIKey = model.settings.openAIKey
            geminiKey = model.settings.geminiKey
            includedExtensions = model.settings.includedExtensions.joined(separator: ", ")
            excludedExtensions = model.settings.excludedExtensions.joined(separator: ", ")
            includedKinds = Set(model.settings.includedKinds)
            excludedKinds = Set(model.settings.excludedKinds)
            excludedFolders = model.settings.excludedFolders
            launchAtLogin = model.settings.launchAtLogin
        }
    }

    private func save() {
        model.settings.provider = provider
        model.settings.shortcut = shortcut
        model.settings.openAIKey = openAIKey
        model.settings.geminiKey = geminiKey
        model.settings.includedExtensions = parseExtensions(includedExtensions)
        model.settings.excludedExtensions = parseExtensions(excludedExtensions)
        model.settings.includedKinds = Array(includedKinds).sorted()
        model.settings.excludedKinds = Array(excludedKinds).sorted()
        model.settings.excludedFolders = excludedFolders
        model.settings.launchAtLogin = launchAtLogin
        NotificationCenter.default.post(name: .hotKeyChanged, object: nil)
        NotificationCenter.default.post(name: .launchAtLoginChanged, object: nil)
        model.updateSearch()
        saved = true
    }

    private func parseExtensions(_ value: String) -> [String] {
        Array(Set(value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t")).lowercased() }
            .filter { !$0.isEmpty }))
            .sorted()
    }

    private func chooseExcludedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let additions = panel.urls.map(\.standardizedFileURL.path)
            excludedFolders = Array(Set(excludedFolders + additions)).sorted()
        }
    }
}

private struct ScopeKindGrid: View {
    @Binding var selection: Set<String>
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
            ForEach(FileScopeKind.allCases) { kind in
                Toggle(kind.rawValue, isOn: Binding(
                    get: { selection.contains(kind.rawValue) },
                    set: { enabled in
                        if enabled { selection.insert(kind.rawValue) }
                        else { selection.remove(kind.rawValue) }
                    }
                ))
                .toggleStyle(.checkbox)
            }
        }
    }
}
