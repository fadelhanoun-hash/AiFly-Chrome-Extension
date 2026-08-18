import SwiftUI
import AppKit
import ServiceManagement

@main
struct AiFlyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AiFly", systemImage: "sparkles") {
            Button("Open AiFly") { appDelegate.showLauncher() }
            Divider()
            Button("Settings…") { appDelegate.showSettings() }
            Button("Quit AiFly") { NSApplication.shared.terminate(nil) }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private var hotKey: GlobalHotKey?
    private var launcherWindow: LauncherPanel?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var modifierMonitor: Any?
    private var shiftWasDown = false
    private var isResizingLauncher = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerHotKey()
        configureLaunchAtLogin()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let launcher = self.launcherWindow,
                  launcher.isKeyWindow else { return event }

            if event.keyCode == 53 {
                if self.model.webDialogResult != nil {
                    self.model.closeWebDialog()
                    return nil
                }
                if self.model.showLargePreview {
                    self.model.showLargePreview = false
                    return nil
                }
                launcher.orderOut(nil)
                return nil
            }
            if self.model.showLargePreview {
                switch event.keyCode {
                case 8: self.model.copySelectedFile()          // C
                case 15: self.model.revealSelection()          // R
                case 31, 36, 76: self.model.activateSelection() // O / Return
                case 51: self.model.trashSelectedFile()        // Delete -> Trash
                default: break
                }
                if [8, 15, 31, 36, 76, 51].contains(event.keyCode) { return nil }
            }
            if event.keyCode == 48, self.model.querySuggestion != nil {
                self.model.acceptQuerySuggestion()
                NotificationCenter.default.post(name: .focusLauncher, object: nil)
                return nil
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let editingSearchField = launcher.firstResponder is NSTextView
            let isHorizontalArrow = event.keyCode == 123 || event.keyCode == 124
            let isModifiedArrow = [123, 124, 125, 126].contains(event.keyCode)
                && !modifiers.intersection([.command, .option]).isEmpty
            let selectedFolderCanOpen = self.model.selectedFile?.isDirectory == true
                || self.model.selectedWebResult?.engineID == "google_drive_folder"
            let folderArrowNavigation = self.model.mode == .files
                && self.model.hasActivatedResultPreview
                && ((event.keyCode == 124 && selectedFolderCanOpen)
                    || (event.keyCode == 123 && self.model.searchRoot != nil))
            if editingSearchField && (isHorizontalArrow || isModifiedArrow) && !folderArrowNavigation {
                return event
            }
            if self.model.mode == .files,
               modifiers.contains(.option),
               (event.keyCode == 36 || event.keyCode == 76),
               self.model.selectedFile?.isDirectory == true {
                self.model.openSelectedFolderExternally()
                return nil
            }
            if self.model.mode == .notes {
                switch event.keyCode {
                case 126: self.model.moveNoteSelection(-1)
                case 125: self.model.moveNoteSelection(1)
                default: return event
                }
                return nil
            }
            if self.model.mode == .ask && (event.keyCode == 126 || event.keyCode == 125) {
                self.model.cycleQuestionHistory(event.keyCode == 126 ? -1 : 1)
                NotificationCenter.default.post(name: .focusLauncher, object: nil)
                return nil
            }
            guard self.model.mode == .files else { return event }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
               let filterIndex = self.filterIndex(for: event.keyCode) {
                self.model.selectFormatFilter(at: filterIndex)
                return nil
            }
            switch event.keyCode {
            case 126: self.model.moveFileSelection(-1) // Up
            case 125: self.model.moveFileSelection(1)  // Down
            case 124: self.model.handleRightArrow()     // Enter folder / actions
            case 123: self.model.handleLeftArrow()      // Parent folder / close actions
            default: return event
            }
            return nil
        }
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self,
                  let launcher = self.launcherWindow,
                  launcher.isKeyWindow,
                  self.model.mode == .files else { return event }
            let shiftDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
            if shiftDown && !self.shiftWasDown
                && self.model.hasActivatedResultPreview
                && (self.model.selectedFile != nil || self.model.selectedWebResult != nil) {
                self.model.showLargePreview.toggle()
            }
            self.shiftWasDown = shiftDown
            return event
        }
        NotificationCenter.default.addObserver(
            forName: .hotKeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.registerHotKey() }
        }
        NotificationCenter.default.addObserver(
            forName: .launchAtLoginChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.configureLaunchAtLogin() }
        }
        NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showSettings() }
        }
    }

    private func registerHotKey() {
        hotKey = GlobalHotKey(shortcut: model.settings.shortcut) { [weak self] in
            guard let self else { return }
            self.model.resetForHotKeyLaunch()
            self.showLauncher()
        }
        if hotKey == nil {
            model.errorMessage = "The selected global shortcut is already used by macOS or another app. Choose another shortcut in Settings."
        }
    }

    private func configureLaunchAtLogin() {
        do {
            if model.settings.launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            model.errorMessage = "Launch at login could not be updated: \(error.localizedDescription)"
        }
    }

    func toggleLauncher() {
        guard let window = launcherWindow else {
            showLauncher()
            return
        }
        window.isVisible ? window.orderOut(nil) : showLauncher()
    }

    func showLauncher() {
        settingsWindow?.orderOut(nil)
        if launcherWindow == nil {
            let defaults = UserDefaults.standard
            let savedWidth = defaults.double(forKey: "launcherWidth")
            let savedHeight = defaults.double(forKey: "launcherHeight")
            let initialSize = NSSize(
                width: savedWidth >= 720 ? savedWidth : 820,
                height: savedHeight >= 500 ? savedHeight : 560
            )
            let savedX = defaults.object(forKey: "launcherX") as? Double
            let savedY = defaults.object(forKey: "launcherY") as? Double
            let savedOrigin = savedX.flatMap { x in savedY.map { NSPoint(x: x, y: $0) } }
            let proposedFrame = NSRect(origin: savedOrigin ?? .zero, size: initialSize)
            let hasVisibleSavedFrame = savedOrigin != nil && NSScreen.screens.contains {
                $0.visibleFrame.intersection(proposedFrame).width >= 120
                    && $0.visibleFrame.intersection(proposedFrame).height >= 80
            }
            let launcherView = LauncherView()
                .environmentObject(model)
            let window = LauncherPanel(
                contentRect: hasVisibleSavedFrame ? proposedFrame : NSRect(origin: .zero, size: initialSize),
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("launcher")
            window.delegate = self
            window.minSize = NSSize(width: 720, height: 500)
            window.contentView = NSHostingView(rootView: launcherView)
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.animationBehavior = .utilityWindow
            launcherWindow = window
            if !hasVisibleSavedFrame { window.center() }
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let window = launcherWindow else { return }
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusLauncher, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .focusLauncher, object: nil)
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(model)
                .frame(width: 620, height: 700)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "AiFly Settings"
            window.contentView = NSHostingView(rootView: settingsView)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "launcher" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak window] in
            guard let self, let window,
                  !self.isResizingLauncher,
                  !window.isKeyWindow else { return }
            window.orderOut(nil)
        }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "launcher" else { return }
        isResizingLauncher = true
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "launcher" else { return }
        isResizingLauncher = false
        window.makeKey()
        NotificationCenter.default.post(name: .focusLauncher, object: nil)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "launcher" else { return }
        UserDefaults.standard.set(window.frame.width, forKey: "launcherWidth")
        UserDefaults.standard.set(window.frame.height, forKey: "launcherHeight")
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "launcher" else { return }
        UserDefaults.standard.set(window.frame.origin.x, forKey: "launcherX")
        UserDefaults.standard.set(window.frame.origin.y, forKey: "launcherY")
    }

    private func filterIndex(for keyCode: UInt16) -> Int? {
        [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8][keyCode]
    }

}

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension Notification.Name {
    static let focusLauncher = Notification.Name("AiFly.focusLauncher")
    static let hotKeyChanged = Notification.Name("AiFly.hotKeyChanged")
    static let launchAtLoginChanged = Notification.Name("AiFly.launchAtLoginChanged")
    static let openSettings = Notification.Name("AiFly.openSettings")
}
