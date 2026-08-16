import SwiftUI
import AppKit
import ServiceManagement

@main
struct AiFlyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.model)
                .frame(width: 620, height: 700)
        }

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerHotKey()
        configureLaunchAtLogin()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let launcher = self.launcherWindow,
                  launcher.isKeyWindow else { return event }

            if event.keyCode == 53 {
                launcher.orderOut(nil)
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
        if launcherWindow == nil {
            let defaults = UserDefaults.standard
            let savedWidth = defaults.double(forKey: "launcherWidth")
            let savedHeight = defaults.double(forKey: "launcherHeight")
            let initialSize = NSSize(
                width: savedWidth >= 720 ? savedWidth : 820,
                height: savedHeight >= 500 ? savedHeight : 560
            )
            let launcherView = LauncherView()
                .environmentObject(model)
                .preferredColorScheme(.light)
            let window = LauncherPanel(
                contentRect: NSRect(origin: .zero, size: initialSize),
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
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let window = launcherWindow else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusLauncher, object: nil)
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
        window.orderOut(nil)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "launcher" else { return }
        UserDefaults.standard.set(window.frame.width, forKey: "launcherWidth")
        UserDefaults.standard.set(window.frame.height, forKey: "launcherHeight")
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
}
