import SwiftUI
import AppKit
import WebKit
import QuickLookUI
import QuickLookThumbnailing

struct LauncherView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var showingQuickMenu = false
    @State private var zoomStartFontSize: Double?
    @GestureState private var liveChatMagnification: CGFloat = 1
    @Namespace private var tabSelectionAnimation

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: modeIcon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .leading) {
                        if let suffix = model.querySuggestionSuffix {
                            HStack(spacing: 0) {
                                Text(model.query).hidden()
                                Text(suffix).foregroundStyle(model.settings.theme.secondaryText.opacity(0.72))
                            }
                            .font(.system(size: 22))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                        }
                        TextField(searchPlaceholder, text: $model.query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 22))
                            .focused($searchFocused)
                            .onSubmit { submit() }
                    }
                    if model.isWorking || model.isSearchingFiles || model.isSearchingWeb { ProgressView().controlSize(.small) }
                    Button { showingQuickMenu.toggle() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Options")
                    .popover(isPresented: $showingQuickMenu, arrowEdge: .top) {
                        QuickOptionsMenu(isPresented: $showingQuickMenu)
                            .environmentObject(model)
                    }
                }
                .padding(.horizontal, 28)
                .frame(height: 56)

                HStack {
                    Spacer(minLength: 20)
                    HStack(spacing: 3) {
                        ForEach(LauncherMode.allCases) { mode in
                            Button {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                    model.mode = mode
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: icon(for: mode))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(mode.rawValue)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .foregroundStyle(model.mode == mode ? model.settings.theme.primaryText : model.settings.theme.secondaryText)
                                .padding(.horizontal, 11)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .contentShape(Capsule())
                                .background {
                                    if model.mode == mode {
                                        Capsule(style: .continuous)
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                Capsule(style: .continuous)
                                                    .fill(Color.white.opacity(0.24))
                                            }
                                            .overlay {
                                                Capsule(style: .continuous)
                                                    .stroke(Color.white.opacity(0.48), lineWidth: 0.8)
                                            }
                                            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                                            .matchedGeometryEffect(id: "active-launcher-tab", in: tabSelectionAnimation)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
                        }
                    }
                    .padding(4)
                    .frame(width: 660, height: 40)
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: model.mode)
                    Spacer(minLength: 20)
                }
                .frame(height: 40)
                .padding(.bottom, 14)

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
                                    .background(model.selectedFormatFilter == format ? model.settings.theme.selection : model.settings.theme.cardSurface)
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

            Group {
                switch model.mode {
                case .files: fileResults
                case .browser: browserView
                case .ask: chat
                case .notes: notesList
                case .google: googleSearch
                case .images: imageSearch
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.mode == .files && (model.isIndexingGoogleDrive || model.isSearchingFiles) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(model.isIndexingGoogleDrive ? "Indexing Google Drive…" : "Searching Spotlight…")
                        .font(.caption)
                        .foregroundStyle(model.settings.theme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 30)
                .background(model.settings.theme.cardSurface.opacity(0.55))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .foregroundStyle(model.settings.theme.primaryText)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).opacity(model.settings.transparency)
                model.settings.theme.background.opacity(model.settings.transparency)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .animation(.easeOut(duration: 0.16), value: model.isIndexingGoogleDrive)
        .animation(.easeOut(duration: 0.16), value: model.isSearchingFiles)
        .onChange(of: model.query) { _ in model.updateSearch() }
        .onChange(of: model.mode) { _ in
            model.rememberLauncherMode()
            model.performCurrentModeCommand()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusLauncher)) { _ in focusSearchField() }
        .onAppear { focusSearchField(); model.loadRecents() }
        .onExitCommand { NSApp.keyWindow?.orderOut(nil) }
    }

    private var searchPlaceholder: String {
        switch model.mode {
        case .files: return model.searchPlaceholder
        case .browser: return "Search selected folder…"
        case .ask: return "Ask AiFly anything…"
        case .notes: return "Search notes…"
        case .google: return "Search Google…"
        case .images: return "Search Google Images…"
        }
    }

    private var modeIcon: String {
        icon(for: model.mode)
    }

    private func icon(for mode: LauncherMode) -> String {
        switch mode {
        case .files: return "magnifyingglass"
        case .browser: return "folder"
        case .ask: return "sparkles"
        case .notes: return "note.text"
        case .google: return "globe"
        case .images: return "photo.on.rectangle.angled"
        }
    }

    private var browserView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        Text("Favorites").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        ForEach(Array(model.starredBrowserFolders.enumerated()), id: \.element.path) { index, folder in
                            Button { model.openBrowserFavorite(folder) } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path)).resizable().scaledToFit().frame(width: 20, height: 20)
                                    Text(folder.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                                .padding(.horizontal, 8).frame(height: 34)
                                .background(index == model.browserFavoriteSelection ? model.settings.theme.selection : .clear)
                            }.buttonStyle(.plain)
                        }
                        if model.starredBrowserFolders.isEmpty {
                            Text("Star folders in Settings → Browser").font(.caption).foregroundStyle(.secondary).padding(12)
                        }
                    }.padding(6)
                }
                .frame(width: 230)
                .id("browser-favorites")
                Divider()

                if model.browserColumns.isEmpty {
                    EmptyStateView(title: "Choose a favorite", systemImage: "folder", description: "Select a starred folder to open the next column.")
                        .frame(width: 460)
                        .frame(maxHeight: .infinity)
                } else {
                        ForEach(Array(model.browserColumns.enumerated()), id: \.element.id) { columnIndex, column in
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    Text(column.folder.lastPathComponent).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                    ForEach(Array(column.items.enumerated()), id: \.element.id) { index, item in
                                        Button { model.selectBrowserItem(column: columnIndex, index: index, openFolder: item.isNavigableFolder) } label: {
                                            HStack(spacing: 8) {
                                                Image(nsImage: item.icon).resizable().scaledToFit().frame(width: 20, height: 20)
                                                Text(item.name).lineLimit(1)
                                                Spacer()
                                                if item.isNavigableFolder { Image(systemName: "chevron.right").font(.caption) }
                                            }
                                            .padding(.horizontal, 8).frame(height: 34)
                                            .background(columnIndex == model.browserActiveColumn && index == column.selection ? model.settings.theme.selection : .clear)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(6)
                            }
                            .frame(width: 230)
                            .id("browser-column-\(columnIndex)")
                            Divider()
                        }
                }
            }
            }
            .onChange(of: model.browserActiveColumn) { column in
                withAnimation(.easeOut(duration: 0.16)) {
                    proxy.scrollTo(column < 0 ? "browser-favorites" : "browser-column-\(column)", anchor: column < 0 ? .leading : .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func focusSearchField() {
        searchFocused = false
        DispatchQueue.main.async { searchFocused = true }
    }

    private var fileResults: some View {
        Group {
            if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.searchRoot == nil {
                recentsDashboard
            } else {
                searchedFileResults
            }
        }
    }

    private var recentsDashboard: some View {
        HStack(alignment: .top, spacing: 18) {
            RecentItemsColumn(
                title: "Recent Files",
                systemImage: "clock.arrow.circlepath",
                items: model.recentFiles,
                isLoading: model.isLoadingRecents,
                emptyMessage: "No recent files found",
                gallery: false,
                open: model.openRecentItem
            )
            .frame(minWidth: 390, maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                if model.recentSelection >= 0, model.selectedFile != nil {
                    FilePreviewPanel().environmentObject(model)
                } else {
                    FallbackEngineBar().environmentObject(model)
                    RecentItemsColumn(
                        title: "Recent Apps",
                        systemImage: "square.grid.2x2",
                        items: model.recentApplications,
                        isLoading: model.isLoadingRecents,
                        emptyMessage: "No recent apps found",
                        gallery: true,
                        open: model.openRecentItem
                    )
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
        }
        .padding(12)
    }

    private var searchedFileResults: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let root = model.searchRoot {
                    HStack(spacing: 7) {
                        Button { model.leaveCurrentFolder() } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(model.folderBreadcrumbs.enumerated()), id: \.element.path) { index, folder in
                                    if index > 0 {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2).foregroundStyle(model.settings.theme.secondaryText)
                                    }
                                    Button { model.navigateToFolderBreadcrumb(folder) } label: {
                                        HStack(spacing: 5) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                                                .resizable().frame(width: 18, height: 18)
                                            Text(folder.lastPathComponent)
                                                .font(.subheadline.weight(folder == root ? .semibold : .regular))
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Spacer(minLength: 4)
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
                        } else if model.visibleSearchResults.isEmpty {
                            EmptyStateView(
                                title: "No results",
                                systemImage: "magnifyingglass",
                                description: "No files matched \u{201c}\(model.query)\u{201d}."
                            )
                            .frame(height: 360)
                        } else {
                            ForEach(Array(model.visibleSearchResults.enumerated()), id: \.element.id) { index, result in
                                switch result {
                                case .file(let item):
                                    FileRow(item: item, selected: model.hasActivatedResultPreview && index == model.selection)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            model.selectSearchResult(at: index)
                                            item.isNavigableFolder ? model.enterFolder(item.url) : model.activateSelection()
                                        }
                                        .onTapGesture {
                                            model.selectSearchResult(at: index); model.hideActions(); model.hideContactDetails()
                                            if item.isApplication { model.activateSelection() }
                                            else if item.isNavigableFolder { model.enterFolder(item.url) }
                                        }
                                        .contextMenu {
                                            if item.isNavigableFolder {
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
                                case .contact(let contact):
                                    ContactRow(contact: contact, selected: model.hasActivatedResultPreview && index == model.selection)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { model.selectSearchResult(at: index); model.showContactDetails() }
                                        .onTapGesture { model.selectSearchResult(at: index); model.hideActions() }
                                case .system(let result):
                                    SystemResultRow(result: result, selected: model.hasActivatedResultPreview && index == model.selection)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) { model.selectSearchResult(at: index); model.activateSelection() }
                                        .onTapGesture { model.selectSearchResult(at: index); model.hideActions(); model.hideContactDetails() }
                                case .web(let result):
                                    WebResultRow(result: result, selected: model.hasActivatedResultPreview && index == model.selection)
                                        .environmentObject(model)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture(count: 2) {
                                            model.selectSearchResult(at: index)
                                            result.isFallback ? model.openWebDialog(result) : model.activateSelection()
                                        }
                                        .onTapGesture {
                                            model.selectSearchResult(at: index)
                                            model.hideActions(); model.hideContactDetails()
                                            if result.engineID == "google_drive_folder" { model.focusGoogleDriveFolder(result) }
                                            else if result.isFallback { model.openWebDialog(result) }
                                        }
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

            Group {
                if !model.hasActivatedResultPreview {
                    Color.clear
                } else if let web = model.selectedWebResult {
                    WebPreviewPanel(result: web).environmentObject(model)
                } else if model.showingContactDetails, let contact = model.selectedContact {
                    ContactDetailPanel(contact: contact).environmentObject(model)
                } else {
                    FilePreviewPanel().environmentObject(model)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
        }
        .overlay {
            if let dialogResult = model.webDialogResult {
                WebSearchDialog(result: dialogResult)
                    .environmentObject(model)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if model.showLargePreview {
                if let web = model.selectedWebResult {
                    LargeWebPreview(result: web)
                        .environmentObject(model)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if let file = model.selectedFile {
                    LargeFilePreview(file: file)
                        .environmentObject(model)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.showLargePreview)
    }

    private var notesList: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if model.launcherNotes.isEmpty {
                            EmptyStateView(title: "No notes", systemImage: "note.text", description: "Save an AI response to create your first note.")
                                .frame(height: 340)
                        } else {
                            ForEach(Array(model.launcherNotes.enumerated()), id: \.element.id) { index, note in
                                Button { model.openLauncherNote(at: index) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "note.text").font(.title2).foregroundStyle(model.settings.theme.secondaryText)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(note.title).font(.headline).lineLimit(2)
                                            Text(note.updatedAt, style: .relative).font(.caption).foregroundStyle(model.settings.theme.secondaryText)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14).frame(height: 66)
                                    .background(index == model.noteListSelection ? model.settings.theme.selection : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                    }
                    .padding(10)
                }
                .onReceive(NotificationCenter.default.publisher(for: .noteSelectionChanged)) { _ in
                    proxy.scrollTo(model.noteListSelection, anchor: .center)
                }
            }
            .frame(minWidth: 250, idealWidth: 290, maxWidth: 330)

            Divider()

            if let note = model.selectedLauncherNote {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "note.text")
                        Text(note.title).font(.headline).lineLimit(1)
                        Spacer()
                        Text("⌘B  Bold   ⌘I  Italic   ⌘U  Underline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18).frame(height: 52)

                    Divider()

                    RichHTMLView(fragment: note.html, theme: .paperWhite, findText: model.query, findGeneration: model.noteFindGeneration, scrollable: true) { html in
                        model.updateSavedNote(id: note.id, html: html)
                    }
                    .padding(18)
                }
                .foregroundStyle(Color(red: 0.10, green: 0.13, blue: 0.18))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.white)
                .id(note.id)
            } else {
                EmptyStateView(title: "Select a note", systemImage: "note.text", description: "Choose a note from the list to view and edit it.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { model.saveNotesOnExit() }
        .clipped()
    }

    private var chat: some View {
        ZStack(alignment: .trailing) {
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
                            if message.role == "assistant" {
                                VStack(alignment: .leading, spacing: 9) {
                                    RichHTMLView(
                                        fragment: message.content,
                                        theme: model.settings.theme,
                                        fontSize: model.aiFontSize,
                                        onSelectionChange: { model.selectedResponseText[message.id] = $0 },
                                        onChange: { model.updateMessageContent(id: message.id, html: $0) }
                                    )

                                    ResponseActions(messageID: message.id)
                                        .environmentObject(model)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(message.id)
                            } else {
                                Text(message.content)
                                    .font(.system(size: model.aiFontSize))
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .background(model.settings.theme.cardSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .id(message.id)
                            }
                        }
                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: model.messages.count) { _ in if let id = model.messages.last?.id { proxy.scrollTo(id) } }
            }

            if let messageID = model.notePickerMessageID {
                NotePickerPanel(messageID: messageID)
                    .environmentObject(model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.notePickerMessageID)
        .scaleEffect(liveChatMagnification, anchor: .top)
        .clipped()
        .simultaneousGesture(
            MagnificationGesture()
                .updating($liveChatMagnification) { scale, state, _ in
                    state = min(max(scale, 0.78), 1.45)
                }
                .onChanged { _ in
                    if zoomStartFontSize == nil { zoomStartFontSize = model.aiFontSize }
                }
                .onEnded { scale in
                    model.setAIFontSize((zoomStartFontSize ?? model.aiFontSize) * scale)
                    zoomStartFontSize = nil
                }
        )
    }

    private var googleSearch: some View {
        Group {
            if model.isSearchingWeb {
                EmptyStateView(title: "Searching Google API…", systemImage: "globe", description: "Retrieving results without opening Google Search.")
            } else if !model.webResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(model.webResults) { result in
                            Button { NSWorkspace.shared.open(result.url) } label: {
                                GoogleNativeResultRow(result: result).environmentObject(model)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            } else {
                EmptyStateView(
                    title: "Search Google API",
                    systemImage: "globe",
                    description: model.errorMessage ?? "Enter a search above and press Return. AiFly can use its no-key web fallback."
                )
            }
        }
    }

    private var imageSearch: some View {
        ZStack {
            if model.imageSearchFailed, model.imageSearchURL == nil {
                EmptyStateView(
                    title: "Google Image API unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: model.errorMessage ?? "Check the API key and Search Engine ID in Settings → Web Search."
                )
            } else if model.imageSearchFailed, let url = model.imageSearchURL {
                VStack(spacing: 14) {
                    EmptyStateView(
                        title: "Images could not load",
                        systemImage: "photo.badge.exclamationmark",
                        description: "Google did not return a gallery. Try again or open Google Images."
                    )
                    HStack {
                        Button("Try Again") { model.submitImageSearch() }
                        Button("Open Google Images") { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.bordered)
                }
            } else if model.imageResults.isEmpty, let url = model.imageSearchURL {
                GoogleImageGalleryLoader(
                    url: url,
                    onResults: { model.acceptGoogleImageURLs($0, sourceURL: url) },
                    onFailure: { model.markGoogleImageSearchFailed(sourceURL: url) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(12)
            } else if model.isSearchingWeb {
                EmptyStateView(
                    title: "Finding images…",
                    systemImage: "photo.on.rectangle.angled",
                    description: "Type above and press Return for a gallery."
                )
            } else if model.imageResults.isEmpty {
                EmptyStateView(
                    title: "Search Google Images",
                    systemImage: "photo.on.rectangle.angled",
                    description: "Type above and press Return for a gallery."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(model.imageResults) { result in
                            ImageGalleryTile(result: result) { model.selectedImageResult = result }
                                .environmentObject(model)
                                .onAppear {
                                    if result.id == model.imageResults.last?.id {
                                        model.loadMoreImagesIfNeeded()
                                    }
                                }
                        }
                    }
                    .padding(14)
                    if model.isLoadingMoreImages {
                        ProgressView("Loading more images…")
                            .padding(.bottom, 16)
                    }
                }
            }
            if let result = model.selectedImageResult { imageActions(result) }
        }
    }

    private func imageActions(_ result: WebSearchResult) -> some View {
        VStack(spacing: 12) {
            AsyncImage(url: result.thumbnailURL) { phase in
                if let image = phase.image { image.resizable().scaledToFit() }
                else { ProgressView() }
            }
            .frame(maxWidth: 560, maxHeight: 330)
            HStack {
                Button("Open Image") { if let url = result.thumbnailURL { NSWorkspace.shared.open(url) } }
                Button("Copy Image Link") {
                    guard let url = result.thumbnailURL else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                Button("Open Google Images") { NSWorkspace.shared.open(result.url) }
                Button("Close") { model.selectedImageResult = nil }
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .background(model.settings.theme.background.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 28, y: 10)
        .padding(24)
    }

    private func submit() {
        model.rememberCurrentSearch()
        model.handleLauncherReturn(cycleDirection: 1)
    }

}

private struct GoogleNativeResultRow: View {
    @EnvironmentObject private var model: AppModel
    let result: WebSearchResult

    var body: some View {
        if result.engineID == "google_ai" || result.engineID == "google_featured" {
            aiOverviewCard
        } else if result.engineID == "google_ai_source" {
            aiSourceRow
        } else if result.engineID == "google_knowledge" {
            knowledgeCard
        } else if result.engineID == "google_answer" {
            answerCard
        } else {
            organicResult
        }
    }

    private var aiOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color(red: 0.32, green: 0.43, blue: 0.94))
                Text(result.engineID == "google_ai" ? "Google AI Overview" : "Google featured answer")
                    .font(.headline)
                Spacer()
            }
            Text(result.subtitle)
                .font(.system(size: 14.5)).lineSpacing(3)
                .multilineTextAlignment(.leading).lineLimit(14)
            Text("Open source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(red: 0.20, green: 0.43, blue: 0.88))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(17)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.08)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.18)) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    private var aiSourceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill").foregroundStyle(Color.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(result.subtitle).font(.caption).foregroundStyle(model.settings.theme.secondaryText).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(model.settings.theme.secondaryText)
        }
        .padding(.horizontal, 17).padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var organicResult: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AsyncImage(url: faviconURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else { Image(systemName: "globe").foregroundStyle(.secondary) }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayHost).font(.subheadline.weight(.medium)).foregroundStyle(model.settings.theme.primaryText)
                    Text(result.url.absoluteString).font(.caption2).foregroundStyle(model.settings.theme.secondaryText).lineLimit(1)
                }
            }
            Text(result.title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(red: 0.20, green: 0.43, blue: 0.88))
                .multilineTextAlignment(.leading).lineLimit(2)
            Text(result.subtitle)
                .font(.subheadline).foregroundStyle(model.settings.theme.primaryText.opacity(0.82))
                .multilineTextAlignment(.leading).lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private var knowledgeCard: some View {
        HStack(alignment: .top, spacing: 14) {
            if let imageURL = result.thumbnailURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Color.clear }
                }
                .frame(width: 92, height: 92).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Knowledge panel").font(.caption.weight(.semibold)).foregroundStyle(model.settings.theme.secondaryText)
                Text(result.title).font(.title2.weight(.semibold)).multilineTextAlignment(.leading)
                Text(result.subtitle).font(.subheadline).lineLimit(5).multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(model.settings.theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(Rectangle())
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("People also ask").font(.caption.weight(.semibold)).foregroundStyle(model.settings.theme.secondaryText)
            HStack(alignment: .top) {
                Text(result.title).font(.headline).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(model.settings.theme.secondaryText)
            }
            Text(result.subtitle).font(.subheadline).foregroundStyle(model.settings.theme.secondaryText).lineLimit(3).multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(model.settings.theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contentShape(Rectangle())
    }

    private var displayHost: String {
        (result.url.host ?? "Google result").replacingOccurrences(of: "www.", with: "")
    }

    private var faviconURL: URL? {
        guard let host = result.url.host else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [URLQueryItem(name: "domain", value: host), URLQueryItem(name: "sz", value: "64")]
        return components?.url
    }
}

private struct ImageGalleryTile: View {
    @EnvironmentObject private var model: AppModel
    let result: WebSearchResult
    let onSelect: () -> Void
    @State private var hovered = false
    @State private var loadedImage: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                AsyncImage(url: result.thumbnailURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill().onAppear { loadNativeImage() }
                    } else {
                        Rectangle().fill(model.settings.theme.cardSurface).overlay { ProgressView() }
                    }
                }
                .frame(height: 128).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if hovered {
                Button(action: copyImage) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(7)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func loadNativeImage() {
        guard loadedImage == nil, let url = result.thumbnailURL else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            loadedImage = image
        }
    }

    private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let loadedImage {
            pasteboard.writeObjects([loadedImage])
        } else if let url = result.thumbnailURL {
            pasteboard.setString(url.absoluteString, forType: .string)
        }
    }
}

private struct RecentItemsColumn: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let systemImage: String
    let items: [FileResult]
    let isLoading: Bool
    let emptyMessage: String
    let gallery: Bool
    let open: (FileResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 5)

            if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if gallery {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                            spacing: 12
                        ) {
                            ForEach(items) { item in
                                Button { open(item) } label: {
                                    VStack(spacing: 7) {
                                        Image(nsImage: item.icon)
                                            .resizable()
                                            .frame(width: 62, height: 62)
                                        Text(item.name.hasSuffix(".app") ? String(item.name.dropLast(4)) : item.name)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(items) { item in
                                Button { model.selectRecentItem(item); open(item) } label: {
                                    HStack(spacing: 10) {
                                        Image(nsImage: item.icon)
                                            .resizable()
                                            .frame(width: 30, height: 30)
                                        Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 50)
                                    .background(model.recentSelection >= 0 && model.recentFiles.indices.contains(model.recentSelection) && model.recentFiles[model.recentSelection].id == item.id ? model.settings.theme.selection : model.settings.theme.cardSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct FallbackEngineBar: View {
    @EnvironmentObject private var model: AppModel
    private var engines: [WebSearchEngine] { model.settings.webEngines.filter { $0.isEnabled && $0.isFallback } }

    var body: some View {
        if !engines.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label("Web Fallback", systemImage: "globe")
                    .font(.subheadline.weight(.semibold)).padding(.horizontal, 5)
                HStack(spacing: 7) {
                    ForEach(engines) { engine in
                        Button {
                            let home: String
                            switch engine.id {
                            case "youtube": home = "https://www.youtube.com"
                            case "maps": home = "https://maps.apple.com"
                            default: home = "https://www.google.com"
                            }
                            if let url = URL(string: home) { NSWorkspace.shared.open(url) }
                        } label: {
                            Label(engine.name, systemImage: engine.icon)
                                .font(.caption.weight(.medium)).lineLimit(1)
                                .padding(.horizontal, 9).frame(height: 28)
                                .background(model.settings.theme.cardSurface).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(model.settings.theme.primaryText.opacity(0.08), lineWidth: 1)
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
        .background(Color.clear)
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}

private struct LargeFilePreview: View {
    @EnvironmentObject private var model: AppModel
    let file: FileResult

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(file.url.pathExtension.lowercased() == "app" ? file.url.deletingPathExtension().lastPathComponent : file.name)
                    .font(.title2.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(file.formatLabel)
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(model.settings.theme.selection).clipShape(Capsule())
            }
            if file.isDirectory || file.url.pathExtension.lowercased() == "app" {
                Image(nsImage: file.icon)
                    .resizable().scaledToFit()
                    .frame(maxWidth: 230, maxHeight: 230)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                QuickLookPreview(url: file.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text(file.folder).font(.caption).foregroundStyle(model.settings.theme.secondaryText).lineLimit(1)
            HStack(spacing: 12) {
                PreviewKey(key: "C", title: "Copy")
                PreviewKey(key: "R", title: "Reveal")
                PreviewKey(key: "O", title: "Open")
                PreviewKey(key: "⌫", title: "Trash")
                Spacer()
                Text("Shift or Esc to close").font(.caption).foregroundStyle(model.settings.theme.secondaryText)
            }
        }
        .padding(20)
        .frame(maxWidth: 680, maxHeight: 460)
        .background(.ultraThinMaterial)
        .background(model.settings.theme.background.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(model.settings.theme.primaryText.opacity(0.12)) }
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        .padding(24)
    }
}

private struct LargeWebPreview: View {
    @EnvironmentObject private var model: AppModel
    let result: WebSearchResult

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: result.engineID == "youtube" ? "play.rectangle.fill" : "globe")
                    .foregroundStyle(result.engineID == "youtube" ? Color.red : model.settings.theme.secondaryText)
                Text(result.title).font(.headline).lineLimit(1)
                Spacer()
                Button { NSWorkspace.shared.open(result.url) } label: {
                    Label("Open in Web", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            }
            if let embeddedURL {
                EmbeddedWebView(url: embeddedURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if result.engineID == "youtube" {
                VStack(spacing: 14) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 84)).foregroundStyle(.red)
                    Text(result.title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    Text("This is a YouTube search suggestion, not an individual video.")
                        .font(.subheadline).foregroundStyle(model.settings.theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmbeddedWebView(url: result.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack {
                Text(result.subtitle).font(.caption).foregroundStyle(model.settings.theme.secondaryText)
                Spacer()
                Text("Shift or Esc to close").font(.caption).foregroundStyle(model.settings.theme.secondaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: 720, maxHeight: 480)
        .background(.ultraThinMaterial)
        .background(model.settings.theme.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(model.settings.theme.primaryText.opacity(0.12)) }
        .shadow(color: .black.opacity(0.30), radius: 30, y: 12)
        .padding(22)
    }

    private var embeddedURL: URL? {
        guard result.engineID == "youtube",
              let components = URLComponents(url: result.url, resolvingAgainstBaseURL: false),
              let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
              let url = URL(string: "https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0") else { return nil }
        return url
    }
}

private struct WebSearchDialog: View {
    @EnvironmentObject private var model: AppModel
    let result: WebSearchResult

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                Text(result.title).font(.headline).lineLimit(1)
                Spacer()
                Button { NSWorkspace.shared.open(result.url) } label: {
                    Label("Open in Web", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                Button { model.closeWebDialog() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).frame(height: 52)

            EmbeddedWebView(url: result.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 720, maxHeight: 470)
        .background(Color.white)
        .foregroundStyle(Color(red: 0.10, green: 0.13, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.12)) }
        .shadow(color: .black.opacity(0.30), radius: 30, y: 12)
        .padding(22)
    }
}

private struct EmbeddedWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.mediaTypesRequiringUserActionForPlayback = [.audio, .video]
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

private struct GoogleImageGalleryLoader: NSViewRepresentable {
    let url: URL
    let onResults: ([URL]) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResults: onResults, onFailure: onFailure) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let thumbnailGridScript = """
        (() => {
          const install = () => {
            window.scrollBy(0, Math.max(700, window.innerHeight));
            const sources = Array.from(document.images)
              .filter(img => img.naturalWidth >= 80 && img.naturalHeight >= 60)
              .map(img => img.currentSrc || img.src)
              .filter(src => typeof src === 'string' && (src.startsWith('https://') || src.startsWith('data:image/')));
            if (sources.length < 2) return;
            let grid = document.getElementById('aifly-image-grid');
            if (!grid) {
              grid = document.createElement('main');
              grid.id = 'aifly-image-grid';
              document.documentElement.appendChild(grid);
            }
            const unique = Array.from(new Set(sources)).slice(0, 80);
            if (grid.dataset.count === String(unique.length)) return;
            grid.dataset.count = String(unique.length);
            grid.replaceChildren(...unique.map(src => {
              const image = document.createElement('img');
              image.src = src;
              image.loading = 'eager';
              return image;
            }));
          };
          const style = document.createElement('style');
          style.textContent = [
            'html, body { margin: 0 !important; min-height: 100% !important; background: transparent !important; }',
            'body > * { visibility: hidden !important; }',
            '#aifly-image-grid { visibility: visible !important; position: fixed !important; inset: 0 !important;',
            'z-index: 2147483647 !important; overflow-y: auto !important; padding: 10px !important;',
            'box-sizing: border-box !important; display: grid !important;',
            'grid-template-columns: repeat(4, minmax(0, 1fr)) !important;',
            'grid-auto-rows: 150px !important; gap: 10px !important; background: transparent !important; }',
            '#aifly-image-grid img { visibility: visible !important; width: 100% !important; height: 100% !important;',
            'object-fit: cover !important; border-radius: 12px !important; }'
          ].join(' ');
          document.documentElement.appendChild(style);
          install();
          window.setInterval(install, 600);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: thumbnailGridScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        context.coordinator.reset()
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onResults: ([URL]) -> Void
        private let onFailure: () -> Void
        private var attempts = 0

        init(onResults: @escaping ([URL]) -> Void, onFailure: @escaping () -> Void) {
            self.onResults = onResults
            self.onFailure = onFailure
        }

        func reset() { attempts = 0 }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            inspect(webView)
        }

        private func inspect(_ webView: WKWebView) {
            attempts += 1
            let script = """
            (() => {
              const seen = new Set();
              const candidates = [];
              const add = (raw) => {
                if (typeof raw !== 'string') return;
                const value = raw.replace(/&amp;/g, '&').replace(/\\\\u003d/g, '=')
                  .replace(/\\\\u0026/g, '&').replace(/\\\\u002f/g, '/').replace(/\\\\\\\\\\//g, '/');
                if (value.startsWith('https://')) candidates.push(value);
              };
              window.scrollBy(0, Math.max(500, window.innerHeight));
              Array.from(document.images).forEach((img) => {
                const link = img.closest('a')?.href || '';
                try {
                  const parsed = new URL(link, location.href);
                  add(parsed.searchParams.get('imgurl') || parsed.searchParams.get('mediaurl') || '');
                } catch {}
                [img.dataset.src, img.dataset.iurl, img.dataset.ou,
                 img.getAttribute('data-src'), img.getAttribute('data-iurl'),
                 img.getAttribute('data-ou'), img.currentSrc, img.src].forEach(add);
              });
              performance.getEntriesByType('resource').forEach((entry) => add(entry.name));
              return candidates.filter((value) => {
                if (seen.has(value)) return false;
                const lower = value.toLowerCase();
                if (lower.includes('images/branding') || lower.includes('favicon') || lower.includes('logo')) return false;
                const isImage = lower.includes('encrypted-tbn') || lower.includes('gstatic')
                  || lower.includes('googleusercontent') || lower.includes('ggpht')
                  || lower.includes('.jpg') || lower.includes('.jpeg')
                  || lower.includes('.png') || lower.includes('.webp');
                if (!isImage) return false;
                seen.add(value);
                return true;
              }).slice(0, 40);
            })()
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] value, _ in
                guard let self else { return }
                let urls = (value as? [String] ?? []).compactMap(URL.init(string:))
                if urls.count >= 4 {
                    self.onResults(urls)
                } else if self.attempts < 16, let webView {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.inspect(webView)
                    }
                } else {
                    self.onFailure()
                }
            }
        }
    }
}

private struct PreviewKey: View {
    let key: String
    let title: String
    var body: some View {
        HStack(spacing: 4) {
            Text(key).font(.caption2.weight(.bold)).padding(.horizontal, 5).frame(height: 20)
                .background(Color.white.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(title).font(.caption)
        }
    }
}

private struct ResponseActions: View {
    @EnvironmentObject private var model: AppModel
    let messageID: UUID
    @State private var showingFollowUp = false
    @State private var followUpText = ""
    @FocusState private var followUpFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ActionChip(title: "Table", icon: "tablecells") { Task { await model.redoAsTable(messageID: messageID) } }
                    ActionChip(title: "Follow Up", icon: "arrowshape.turn.up.left") {
                        showingFollowUp.toggle()
                        if showingFollowUp {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { followUpFocused = true }
                        }
                    }
                    ActionChip(title: "Copy", icon: "doc.on.doc") { model.copyMessage(messageID: messageID) }
                    ActionChip(title: "Find Image", icon: "photo.on.rectangle.angled") { model.findImage(messageID: messageID) }
                    ActionChip(title: "Computer", icon: "desktopcomputer") { model.findOnComputer(messageID: messageID) }
                    ActionChip(title: "Save to Note", icon: "note.text.badge.plus") { model.openNotePicker(messageID: messageID) }
                    if let note = model.lastSavedNote {
                        ActionChip(title: "Save · \(shortNoteTitle(note.title))", icon: "tray.and.arrow.down") {
                            model.saveToLastNote(messageID: messageID)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            if showingFollowUp {
                HStack(spacing: 8) {
                    TextField("Ask a follow-up about this response…", text: $followUpText)
                        .textFieldStyle(.plain)
                        .font(.system(size: model.aiFontSize))
                        .focused($followUpFocused)
                        .onSubmit { sendFollowUp() }
                    Button(action: sendFollowUp) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 25, height: 25)
                            .background(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.18) : Color.accentColor)
                            .foregroundStyle(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                }
                .padding(.leading, 12).padding(.trailing, 7)
                .frame(height: 38)
                .background(model.settings.theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black.opacity(0.10)) }
            }
        }
        .animation(.easeOut(duration: 0.16), value: showingFollowUp)
    }

    private func shortNoteTitle(_ title: String) -> String {
        title.count > 15 ? String(title.prefix(15)) + "…" : title
    }

    private func sendFollowUp() {
        let question = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !model.isWorking else { return }
        followUpText = ""
        showingFollowUp = false
        Task { await model.sendFollowUp(question, about: messageID) }
    }
}

private struct ActionChip: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovering = false
    @State private var clicked = false

    var body: some View {
        Button {
            clicked = true
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { clicked = false }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: min(max(model.aiFontSize * 0.78, 10.5), 15), weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: max(26, model.aiFontSize + 13))
                .foregroundStyle((hovering || clicked) ? Color.accentColor : model.settings.theme.primaryText.opacity(0.72))
                .background((hovering || clicked) ? Color.accentColor.opacity(clicked ? 0.22 : 0.12) : model.settings.theme.cardSurface)
                .clipShape(Capsule())
                .overlay { Capsule().stroke((hovering || clicked) ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.09), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .scaleEffect(clicked ? 0.97 : 1)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.10), value: clicked)
    }
}

private struct QuickOptionsMenu: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Font size", systemImage: "textformat.size")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button { model.adjustAIFontSize(by: -1) } label: {
                    Image(systemName: "minus").frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                Text("\(Int(model.aiFontSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 24)
                Button { model.adjustAIFontSize(by: 1) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
            }

            Button {
                model.clearAIChat()
                isPresented = false
            } label: {
                Label("Clear AI Chat", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7)

            Button {
                isPresented = false
                NotificationCenter.default.post(name: .openSettings, object: nil)
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7)
        }
        .padding(12)
        .frame(width: 235)
    }
}

private struct NotePickerPanel: View {
    @EnvironmentObject private var model: AppModel
    let messageID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Save to Note").font(.headline)
                Spacer()
                Button { model.closeNotePicker() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            TextField("Search notes", text: $model.noteSearch)
                .textFieldStyle(.roundedBorder)
            Button { model.createNoteAndSave(messageID: messageID) } label: {
                Label("Create New Note", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.filteredNotes) { note in
                        Button { model.saveMessage(messageID, to: note.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "note.text").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text(note.updatedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(9)
                            .background(Color.white.opacity(0.68))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.10)) }
        .shadow(color: .black.opacity(0.16), radius: 18, x: -4)
        .padding(10)
    }
}

private struct RichHTMLView: View {
    let fragment: String
    let theme: LauncherTheme
    var fontSize: Double = 14
    var findText: String = ""
    var findGeneration = 0
    var scrollable = false
    var onSelectionChange: (String) -> Void = { _ in }
    let onChange: (String) -> Void
    @State private var contentHeight: CGFloat = 60

    var body: some View {
        HTMLWebView(fragment: fragment, theme: theme, fontSize: fontSize, findText: findText, findGeneration: findGeneration, scrollable: scrollable, contentHeight: $contentHeight, onSelectionChange: onSelectionChange, onChange: onChange)
            .frame(maxWidth: .infinity, maxHeight: scrollable ? .infinity : nil)
            .frame(height: scrollable ? nil : contentHeight)
    }
}

private struct HTMLWebView: NSViewRepresentable {
    let fragment: String
    let theme: LauncherTheme
    let fontSize: Double
    let findText: String
    let findGeneration: Int
    let scrollable: Bool
    @Binding var contentHeight: CGFloat
    let onSelectionChange: (String) -> Void
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(contentHeight: $contentHeight, onSelectionChange: onSelectionChange, onChange: onChange) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "contentChanged")
        configuration.userContentController.add(context.coordinator, name: "selectionChanged")
        configuration.userContentController.addUserScript(WKUserScript(source: """
        document.addEventListener('input', function() {
          window.webkit.messageHandlers.contentChanged.postMessage(document.body.innerHTML);
        });
        document.addEventListener('selectionchange', function() {
          window.webkit.messageHandlers.selectionChanged.postMessage(window.getSelection().toString());
        });
        document.addEventListener('paste', function() {
          requestAnimationFrame(function() {
            window.webkit.messageHandlers.contentChanged.postMessage(document.body.innerHTML);
          });
        });
        document.addEventListener('keydown', function(event) {
          if (!(event.metaKey || event.ctrlKey)) return;
          const key = event.key.toLowerCase();
          if (key === 'b' || key === 'i' || key === 'u') {
            event.preventDefault();
            document.execCommand(key === 'b' ? 'bold' : (key === 'i' ? 'italic' : 'underline'), false, null);
            window.webkit.messageHandlers.contentChanged.postMessage(document.body.innerHTML);
          } else if (event.shiftKey && (key === '7' || key === '8')) {
            event.preventDefault();
            document.execCommand(key === '7' ? 'insertOrderedList' : 'insertUnorderedList', false, null);
            window.webkit.messageHandlers.contentChanged.postMessage(document.body.innerHTML);
          } else if (event.altKey && (key === '1' || key === '2' || key === '3')) {
            event.preventDefault();
            document.execCommand('formatBlock', false, 'h' + key);
            window.webkit.messageHandlers.contentChanged.postMessage(document.body.innerHTML);
          }
        });
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView: WKWebView = scrollable
            ? WKWebView(frame: .zero, configuration: configuration)
            : PassthroughScrollWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedFragment != fragment {
            context.coordinator.loadedFragment = fragment
            context.coordinator.loadedFontSize = fontSize
            let cleanFragment = fragment
                .replacingOccurrences(of: "```html", with: "")
                .replacingOccurrences(of: "```", with: "")
            let document = """
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <meta name="color-scheme" content="light">
        <style>
        *{box-sizing:border-box;max-width:100%} html,body{width:100%;max-width:100%;min-height:100%} body{margin:0;padding:2px 2px \(scrollable ? "180px" : "2px");color:\(theme.htmlText);background:transparent;font:\(fontSize)px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.48;overflow-x:hidden;overflow-y:\(scrollable ? "auto" : "hidden");overflow-wrap:anywhere;word-break:normal;cursor:text;outline:none;min-height:100%}
        p{margin:0 0 9px} p:last-child{margin-bottom:0} strong{font-weight:700;color:\(theme.htmlHeading)}
        ul,ol{margin:5px 0 9px;padding-left:21px} li{margin:3px 0}
        table{width:100%;table-layout:fixed;border-collapse:collapse;margin:8px 0;font-size:.93em} th{background:#eef2ff;font-weight:700;text-align:left} th,td{border:1px solid #dbe1ea;padding:6px 8px;vertical-align:top;overflow-wrap:anywhere} img,video{display:block;max-width:100%;height:auto}
        h1,h2,h3{font-size:15px;margin:10px 0 5px;color:\(theme.htmlHeading)} a{color:#2563eb}
        ::highlight(note-find){background:#dbeafe;color:inherit} ::highlight(note-find-active){background:#93c5fd;color:inherit}
        </style></head><body contenteditable="true" spellcheck="true">\(cleanFragment)</body></html>
        """
            webView.loadHTMLString(document, baseURL: nil)
        } else if context.coordinator.loadedFontSize != fontSize {
            context.coordinator.loadedFontSize = fontSize
            webView.evaluateJavaScript("document.body.style.fontSize='\(fontSize)px'; Math.ceil(document.documentElement.scrollHeight)") { value, _ in
                guard let height = value as? NSNumber else { return }
                DispatchQueue.main.async { contentHeight = max(34, min(CGFloat(truncating: height), 6000)) }
            }
        }
        if context.coordinator.findText != findText {
            context.coordinator.findText = findText
            context.coordinator.find(findText, in: webView)
        }
        if context.coordinator.findGeneration != findGeneration {
            context.coordinator.findGeneration = findGeneration
            context.coordinator.advanceFind(in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "contentChanged")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "selectionChanged")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var contentHeight: CGFloat
        var loadedFragment: String?
        var loadedFontSize: Double?
        var findText = ""
        var findGeneration = 0
        let onChange: (String) -> Void
        let onSelectionChange: (String) -> Void

        init(contentHeight: Binding<CGFloat>, onSelectionChange: @escaping (String) -> Void, onChange: @escaping (String) -> Void) {
            _contentHeight = contentHeight
            self.onSelectionChange = onSelectionChange
            self.onChange = onChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { [weak self] value, _ in
                guard let height = value as? NSNumber else { return }
                DispatchQueue.main.async {
                    // Size the web content to its full document so the enclosing
                    // SwiftUI chat view owns scrolling instead of clipping HTML.
                    self?.contentHeight = max(34, min(CGFloat(truncating: height), 6000))
                }
            }
            find(findText, in: webView)
        }

        func find(_ text: String, in webView: WKWebView) {
            guard let data = try? JSONSerialization.data(withJSONObject: [text]),
                  let json = String(data: data, encoding: .utf8) else { return }
            let argument = String(json.dropFirst().dropLast())
            webView.evaluateJavaScript("""
            (function(term) {
              if (!window.CSS || !CSS.highlights || typeof Highlight === 'undefined') {
                if (term.trim()) window.find(term, false, false, true, false, true, false);
                return;
              }
              CSS.highlights.delete('note-find');
              CSS.highlights.delete('note-find-active');
              window.__noteFindRanges = [];
              window.__noteFindIndex = -1;
              if (!term.trim()) return;
              const needle = term.toLocaleLowerCase();
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              let node;
              while ((node = walker.nextNode())) {
                const value = node.nodeValue.toLocaleLowerCase();
                let start = 0;
                while ((start = value.indexOf(needle, start)) !== -1) {
                  const range = new Range();
                  range.setStart(node, start);
                  range.setEnd(node, start + term.length);
                  window.__noteFindRanges.push(range);
                  start += Math.max(1, term.length);
                }
              }
              CSS.highlights.set('note-find', new Highlight(...window.__noteFindRanges));
              if (window.__noteFindRanges.length) {
                window.__noteFindIndex = 0;
                CSS.highlights.set('note-find-active', new Highlight(window.__noteFindRanges[0]));
                const rect = window.__noteFindRanges[0].getBoundingClientRect();
                window.scrollTo({top: Math.max(0, window.scrollY + rect.top - 80), behavior:'smooth'});
              }
            })(\(argument));
            """)
        }

        func advanceFind(in webView: WKWebView) {
            webView.evaluateJavaScript("""
            (function() {
              const ranges = window.__noteFindRanges || [];
              if (!ranges.length || !window.CSS || !CSS.highlights) return;
              window.__noteFindIndex = (window.__noteFindIndex + 1) % ranges.length;
              const active = ranges[window.__noteFindIndex];
              CSS.highlights.set('note-find-active', new Highlight(active));
              const rect = active.getBoundingClientRect();
              window.scrollTo({top: Math.max(0, window.scrollY + rect.top - 80), behavior:'smooth'});
            })();
            """)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "selectionChanged", let text = message.body as? String {
                onSelectionChange(text)
                return
            }
            guard message.name == "contentChanged", let html = message.body as? String else { return }
            loadedFragment = html
            onChange(html)
            guard let webView = message.webView else { return }
            webView.evaluateJavaScript("Math.ceil(document.documentElement.scrollHeight)") { [weak self] value, _ in
                guard let height = value as? NSNumber else { return }
                DispatchQueue.main.async {
                    self?.contentHeight = max(34, min(CGFloat(truncating: height), 6000))
                }
            }
        }
    }
}

private final class PassthroughScrollWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // The HTML response is sized to its full content height, so its own
        // WebKit scroll view must never trap trackpad or mouse-wheel gestures.
        // Forward them to the enclosing SwiftUI conversation scroller.
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return
            }
            ancestor = view.superview
        }
        nextResponder?.scrollWheel(with: event)
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

private struct ContactRow: View {
    @EnvironmentObject private var model: AppModel
    let contact: ContactResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 15) {
            Group {
                if let data = contact.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable().foregroundStyle(model.settings.theme.secondaryText)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName).font(.title3.weight(.medium)).lineLimit(1)
                Text(contact.organization.isEmpty ? contact.fields.first?.value ?? "Contact" : contact.organization)
                    .font(.subheadline).foregroundStyle(model.settings.theme.secondaryText).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "chevron.right").foregroundStyle(model.settings.theme.secondaryText) }
        }
        .padding(.horizontal, 18)
        .frame(height: 72)
        .background(selected ? model.settings.theme.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct WebResultRow: View {
    @EnvironmentObject private var model: AppModel
    let result: WebSearchResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 13) {
            if let thumbnailURL = result.thumbnailURL {
                AsyncImage(url: thumbnailURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Image(systemName: resultIcon).font(.system(size: 24)).foregroundStyle(Color.blue) }
                }
                .frame(width: 42, height: 42).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else if result.engineID == "google_drive_folder" {
                Image(nsImage: NSWorkspace.shared.icon(forFileType: "public.folder"))
                    .resizable().scaledToFit().frame(width: 38, height: 38)
            } else {
                Image(systemName: resultIcon)
                    .font(.system(size: 25)).frame(width: 38)
                    .foregroundStyle(result.engineID == "youtube" ? Color.red : driveResult ? Color.blue : model.settings.theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title).font(.headline).lineLimit(2)
                Text(result.subtitle).font(.subheadline).foregroundStyle(model.settings.theme.secondaryText).lineLimit(1)
            }
            Spacer()
            Image(systemName: "arrow.up.right.square").foregroundStyle(model.settings.theme.secondaryText)
        }
        .padding(.horizontal, 16).frame(height: 68)
        .background(selected ? model.settings.theme.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var engine: WebSearchEngine? { model.settings.webEngines.first { $0.id == result.engineID } }
    private var driveResult: Bool { result.engineID.hasPrefix("google_drive_") }
    private var resultIcon: String {
        switch result.engineID {
        case "google_drive_folder": return "folder.fill"
        case "google_drive_file": return "externaldrive.badge.icloud"
        default: return engine?.icon ?? "globe"
        }
    }
}

private struct WebPreviewPanel: View {
    @EnvironmentObject private var model: AppModel
    let result: WebSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let thumbnail = result.thumbnailURL {
                AsyncImage(url: thumbnail) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Rectangle().fill(model.settings.theme.cardSurface).overlay { ProgressView() } }
                }
                .frame(maxWidth: .infinity).frame(height: 190).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Image(systemName: result.engineID == "google_drive_folder" ? "folder.fill" : (result.engineID == "google_drive_file" ? "externaldrive.badge.icloud" : model.settings.webEngines.first(where: { $0.id == result.engineID })?.icon ?? "globe"))
                    .font(.system(size: 64)).foregroundStyle(model.settings.theme.secondaryText)
                    .frame(maxWidth: .infinity).frame(height: 150)
            }
            Text(result.title).font(.title3.weight(.semibold)).lineLimit(4)
            Text(result.subtitle).font(.subheadline).foregroundStyle(model.settings.theme.secondaryText)
            Button {
                if result.engineID.hasPrefix("google_drive_") { model.openGoogleDriveResult(result) }
                else { NSWorkspace.shared.open(result.url) }
            } label: {
                Label(
                    result.engineID == "google_drive_file" ? "Download & Open" : (result.engineID == "google_drive_folder" ? "Open Folder" : "Open in Web"),
                    systemImage: result.engineID.hasPrefix("google_drive_") ? "arrow.down.circle.fill" : "arrow.up.right.square"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding(14)
    }
}

private struct ContactDetailPanel: View {
    @EnvironmentObject private var model: AppModel
    let contact: ContactResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 42))
                    .foregroundStyle(model.settings.theme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName).font(.title3.weight(.semibold))
                    if !contact.organization.isEmpty { Text(contact.organization).foregroundStyle(model.settings.theme.secondaryText) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(contact.fields.enumerated()), id: \.element.id) { index, field in
                        Button { model.contactFieldSelection = index; model.copySelectedContactField() } label: {
                            HStack(spacing: 11) {
                                Image(systemName: field.icon).frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(field.label).font(.caption).foregroundStyle(model.settings.theme.secondaryText)
                                    Text(field.value).font(.subheadline).lineLimit(3)
                                }
                                Spacer()
                                Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(model.settings.theme.secondaryText)
                            }
                            .padding(10)
                            .background(index == model.contactFieldSelection ? model.settings.theme.selection : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }
        }
        .background(Color.white.opacity(0.04))
    }
}

private struct FileRow: View {
    @EnvironmentObject private var model: AppModel
    let item: FileResult
    let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            FileListThumbnail(item: item)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.pathExtension.lowercased() == "app" ? item.url.deletingPathExtension().lastPathComponent : item.name)
                    .fontWeight(.medium).lineLimit(1)
                Text(item.url.pathExtension.lowercased() == "app" ? "Application · \(item.folder)" : item.folder)
                    .font(.subheadline).foregroundStyle(model.settings.theme.secondaryText).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "return").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 18).frame(height: 66)
        .background(selected ? model.settings.theme.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FileListThumbnail: View {
    let item: FileResult
    @State private var thumbnail: NSImage?

    private var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp"].contains(item.url.pathExtension.lowercased())
    }
    private var isVideo: Bool {
        ["mov", "mp4", "m4v", "avi", "mkv", "webm"].contains(item.url.pathExtension.lowercased())
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                Image(nsImage: item.icon).resizable().scaledToFit()
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: (isImage || isVideo) ? 7 : 3, style: .continuous))
        .task(id: item.id) {
            guard isImage || isVideo else { thumbnail = nil; return }
            let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 120, height: 120), scale: 2, representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

private struct SystemResultRow: View {
    @EnvironmentObject private var model: AppModel
    let result: SystemSearchResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(model.settings.theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).fontWeight(.medium).lineLimit(1)
                Text("\(result.category) | \(result.subtitle)")
                    .font(.subheadline).foregroundStyle(model.settings.theme.secondaryText).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "return").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 18).frame(height: 66)
        .background(selected ? model.settings.theme.selection : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var icon: String {
        switch result.category {
        case "Message": return "message.fill"
        case "Contact": return "person.crop.circle.fill"
        case "Event": return "calendar"
        case "Reminder": return "checklist"
        case "Bookmark": return "bookmark.fill"
        case "System Setting": return "gearshape.fill"
        default: return "magnifyingglass"
        }
    }
}

extension LauncherTheme {
    var background: Color {
        switch self {
        case .alfredNavy: return Color(red: 0.10, green: 0.13, blue: 0.25)
        case .graphite: return Color(red: 0.12, green: 0.13, blue: 0.15)
        case .midnight: return Color(red: 0.025, green: 0.06, blue: 0.12)
        case .frost: return Color(red: 0.88, green: 0.92, blue: 0.96)
        case .plum: return Color(red: 0.20, green: 0.09, blue: 0.24)
        case .paperWhite: return Color(nsColor: .windowBackgroundColor)
        case .warmWhite: return Color(red: 0.98, green: 0.96, blue: 0.92)
        }
    }
    var isLight: Bool { self == .frost || self == .paperWhite || self == .warmWhite }
    var primaryText: Color { isLight ? Color(red: 0.10, green: 0.13, blue: 0.18) : .white }
    var secondaryText: Color { isLight ? Color.black.opacity(0.48) : Color.white.opacity(0.46) }
    var cardSurface: Color { isLight ? Color.black.opacity(0.035) : Color.white.opacity(0.075) }
    var htmlText: String { isLight ? "#27303f" : "#eef1f7" }
    var htmlHeading: String { isLight ? "#111827" : "#ffffff" }
    var selection: Color {
        switch self {
        case .alfredNavy: return Color(red: 0.30, green: 0.36, blue: 0.52).opacity(0.38)
        case .graphite: return Color.white.opacity(0.085)
        case .midnight: return Color.blue.opacity(0.14)
        case .frost: return Color.blue.opacity(0.09)
        case .plum: return Color.purple.opacity(0.17)
        case .paperWhite: return Color.blue.opacity(0.075)
        case .warmWhite: return Color.orange.opacity(0.075)
        }
    }
}

private struct SettingsFolderBrowser: View {
    @Binding var starredFolders: [String]
    @State private var columns: [URL] = [FileManager.default.homeDirectoryForCurrentUser]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Locations").font(.headline).padding(.horizontal, 10).padding(.bottom, 4)
                ForEach(BrowserLocation.available) { location in
                    Button { columns = [location.url] } label: {
                        HStack(spacing: 8) {
                            Image(nsImage: location.icon).resizable().scaledToFit().frame(width: 20, height: 20)
                            Text(location.name).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 34)
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, 10).frame(width: 170)
            Divider()

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(columns.enumerated()), id: \.element.path) { columnIndex, folder in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                Text(folder.lastPathComponent).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                ForEach(folderChildren(folder), id: \.path) { child in
                                    HStack(spacing: 8) {
                                        Button {
                                            columns = Array(columns.prefix(columnIndex + 1)) + [child]
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(nsImage: NSWorkspace.shared.icon(forFile: child.path)).resizable().scaledToFit().frame(width: 20, height: 20)
                                                Text(child.lastPathComponent).lineLimit(1)
                                                Spacer()
                                                Image(systemName: "chevron.right").font(.caption)
                                            }.contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                        Button { toggleStar(child) } label: {
                                            Image(systemName: starredFolders.contains(child.standardizedFileURL.path) ? "star.fill" : "star")
                                                .foregroundStyle(starredFolders.contains(child.standardizedFileURL.path) ? .yellow : .secondary)
                                        }.buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8).frame(height: 34)
                                }
                            }.padding(6)
                        }
                        .frame(width: 230)
                        .id("settings-browser-column-\(columnIndex)")
                        Divider()
                    }
                }
            }
                .onChange(of: columns.count) { count in
                    guard count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo("settings-browser-column-\(count - 1)", anchor: .trailing)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Starred Folders").font(.headline).padding(.bottom, 4)
                if starredFolders.isEmpty {
                    Text("Click a star beside any folder.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(starredFolders.enumerated()), id: \.element) { index, path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit().frame(width: 20, height: 20)
                        Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1)
                        Spacer()
                        Button { moveStarredFolder(from: index, by: -1) } label: {
                            Image(systemName: "chevron.up").foregroundStyle(index == 0 ? .tertiary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        .help("Move up")
                        Button { moveStarredFolder(from: index, by: 1) } label: {
                            Image(systemName: "chevron.down").foregroundStyle(index == starredFolders.count - 1 ? .tertiary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(index == starredFolders.count - 1)
                        .help("Move down")
                        Button { starredFolders.removeAll { $0 == path } } label: {
                            Image(systemName: "star.slash").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }.padding(.vertical, 5)
                }
                Spacer()
            }
            .padding(14).frame(width: 240, alignment: .topLeading)
            .background(Color(nsColor: NSColor(calibratedWhite: 0.94, alpha: 1)))
        }
    }

    private func folderChildren(_ folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey], options: [.skipsHiddenFiles])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.pathExtension.lowercased() != "app" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func toggleStar(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        if starredFolders.contains(path) { starredFolders.removeAll { $0 == path } }
        else { starredFolders.append(path) }
    }

    private func moveStarredFolder(from index: Int, by offset: Int) {
        let destination = index + offset
        guard starredFolders.indices.contains(index), starredFolders.indices.contains(destination) else { return }
        starredFolders.swapAt(index, destination)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var provider: AIProvider = .openAI
    @State private var shortcut: Shortcut = .optionSpace
    @State private var openAIKey = ""
    @State private var geminiKey = ""
    @State private var googleSearchAPIKey = ""
    @State private var googleSearchEngineID = ""
    @State private var serperAPIKey = ""
    @State private var includedExtensions = ""
    @State private var excludedExtensions = ""
    @State private var includedKinds: Set<String> = []
    @State private var excludedKinds: Set<String> = []
    @State private var excludedFolders: [String] = []
    @State private var launchAtLogin = false
    @State private var settingsLoaded = false
    @State private var theme: LauncherTheme = .alfredNavy
    @State private var transparency = 0.90
    @State private var keySaveTask: Task<Void, Never>?
    @State private var webEngines: [WebSearchEngine] = WebSearchEngine.defaults
    @State private var starredFolders: [String] = []

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gearshape") }
            themeSettings
                .tabItem { Label("Themes", systemImage: "paintpalette") }
            webSearchSettings
                .tabItem { Label("Web Search", systemImage: "globe") }
            browserSettings
                .tabItem { Label("Browser", systemImage: "folder") }
        }
        .padding(.top, 8)
        .onAppear {
            loadSettings()
            DispatchQueue.main.async { settingsLoaded = true }
        }
        .onDisappear { save(includeKeys: true) }
        .onChange(of: provider) { _ in save(includeKeys: false) }
        .onChange(of: shortcut) { _ in save(includeKeys: false) }
        .onChange(of: includedExtensions) { _ in save(includeKeys: false) }
        .onChange(of: excludedExtensions) { _ in save(includeKeys: false) }
        .onChange(of: includedKinds) { _ in save(includeKeys: false) }
        .onChange(of: excludedKinds) { _ in save(includeKeys: false) }
        .onChange(of: excludedFolders) { _ in save(includeKeys: false) }
        .onChange(of: launchAtLogin) { _ in save(includeKeys: false) }
        .onChange(of: theme) { _ in save(includeKeys: false) }
        .onChange(of: transparency) { _ in save(includeKeys: false) }
        .onChange(of: openAIKey) { _ in scheduleKeySave() }
        .onChange(of: geminiKey) { _ in scheduleKeySave() }
        .onChange(of: googleSearchAPIKey) { _ in scheduleKeySave() }
        .onChange(of: serperAPIKey) { _ in scheduleKeySave() }
        .onChange(of: googleSearchEngineID) { _ in save(includeKeys: false) }
        .onChange(of: webEngines) { _ in save(includeKeys: false) }
        .onChange(of: starredFolders) { _ in save(includeKeys: false) }
    }

    private var generalSettings: some View {
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
        }
        .formStyle(.grouped)
    }

    private var themeSettings: some View {
        Form {
            Section("Launcher theme") {
                ForEach(LauncherTheme.allCases) { option in
                    Button { theme = option } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(option.background)
                                .frame(width: 52, height: 34)
                                .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.18)) }
                            Text(option.rawValue)
                            Spacer()
                            if theme == option { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("Transparency") {
                Slider(value: $transparency, in: 0.55...1.0, step: 0.05) {
                    Text("Transparency")
                } minimumValueLabel: {
                    Image(systemName: "circle.lefthalf.filled")
                } maximumValueLabel: {
                    Image(systemName: "circle.fill")
                }
                Text("\(Int(transparency * 100))% entire app opacity")
                    .font(.caption).foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.background)
                    .opacity(transparency)
                    .frame(height: 130)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Search files, contacts, and actions").font(.title2)
                            HStack {
                                Image(systemName: "doc.text")
                                VStack(alignment: .leading) {
                                    Text("Selected result").font(.headline)
                                    Text("A clean Alfred-style preview").foregroundStyle(theme.secondaryText)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.selection).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .foregroundStyle(theme.primaryText).padding(16)
                    }
            }
        }
        .formStyle(.grouped)
    }

    private var webSearchSettings: some View {
        Form {
            Section("Serper — Recommended") {
                SecureField("Serper API key", text: $serperAPIKey)
                Link("Create or view your Serper key", destination: URL(string: "https://serper.dev/")!)
                Text("Provides native Google web and image results. AiFly uses no-key fallbacks when this is blank. Stored in macOS Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Google Custom Search API") {
                SecureField("API key", text: $googleSearchAPIKey)
                TextField("Programmable Search Engine ID (cx)", text: $googleSearchEngineID)
                Text("Used for native web and image results without loading google.com or triggering CAPTCHA. Google has closed this API to new customers; these fields require an existing enabled project.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Search engines") {
                Text("Type a shortcut, a space, then your search. Example: yt chest tube procedure")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($webEngines) { $engine in
                    HStack(spacing: 12) {
                        Toggle("", isOn: $engine.isEnabled).labelsHidden()
                        Image(systemName: engine.icon).frame(width: 22)
                        Text(engine.name).frame(width: 110, alignment: .leading)
                        TextField("Shortcut", text: $engine.shortcut)
                            .textFieldStyle(.roundedBorder).frame(width: 72)
                        Spacer()
                        Toggle("Fallback", isOn: $engine.isFallback)
                            .toggleStyle(.checkbox)
                            .disabled(!engine.isEnabled)
                    }
                }
            }
            Section("Fallback") {
                Text("Checked fallback engines appear as actions only when Search Mac finds no local match. Selecting one opens the query on that website.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var browserSettings: some View {
        SettingsFolderBrowser(starredFolders: $starredFolders)
            .padding(12)
    }

    private func loadSettings() {
        provider = model.settings.provider
        shortcut = model.settings.shortcut
        openAIKey = model.settings.openAIKey
        geminiKey = model.settings.geminiKey
        googleSearchAPIKey = model.settings.googleSearchAPIKey
        googleSearchEngineID = model.settings.googleSearchEngineID
        serperAPIKey = model.settings.serperAPIKey
        includedExtensions = model.settings.includedExtensions.joined(separator: ", ")
        excludedExtensions = model.settings.excludedExtensions.joined(separator: ", ")
        includedKinds = Set(model.settings.includedKinds)
        excludedKinds = Set(model.settings.excludedKinds)
        excludedFolders = model.settings.excludedFolders
        launchAtLogin = model.settings.launchAtLogin
        theme = model.settings.theme
        transparency = model.settings.transparency
        webEngines = model.settings.webEngines
        starredFolders = model.settings.starredFolders
    }

    private func save(includeKeys: Bool) {
        guard settingsLoaded else { return }
        let shortcutChanged = model.settings.shortcut != shortcut
        let launchAtLoginChanged = model.settings.launchAtLogin != launchAtLogin
        model.settings.provider = provider
        model.settings.starredFolders = starredFolders
        model.settings.googleSearchEngineID = googleSearchEngineID
        model.settings.shortcut = shortcut
        if includeKeys {
            model.settings.openAIKey = openAIKey
            model.settings.geminiKey = geminiKey
            model.settings.googleSearchAPIKey = googleSearchAPIKey
            model.settings.serperAPIKey = serperAPIKey
        }
        model.settings.includedExtensions = parseExtensions(includedExtensions)
        model.settings.excludedExtensions = parseExtensions(excludedExtensions)
        model.settings.includedKinds = Array(includedKinds).sorted()
        model.settings.excludedKinds = Array(excludedKinds).sorted()
        model.settings.excludedFolders = excludedFolders
        model.settings.launchAtLogin = launchAtLogin
        model.settings.theme = theme
        model.settings.transparency = transparency
        model.settings.webEngines = webEngines.map { engine in
            var cleaned = engine
            cleaned.shortcut = engine.shortcut.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }
        model.themeRevision += 1
        if shortcutChanged { NotificationCenter.default.post(name: .hotKeyChanged, object: nil) }
        if launchAtLoginChanged { NotificationCenter.default.post(name: .launchAtLoginChanged, object: nil) }
        model.updateSearch()
    }

    private func scheduleKeySave() {
        guard settingsLoaded else { return }
        keySaveTask?.cancel()
        keySaveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await MainActor.run { save(includeKeys: true) }
        }
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
