import AppKit
import Carbon
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences()
    private lazy var model = ClipboardModel(preferences: preferences)
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private let overlayPresenter = FloatingOverlayPresenter()
    private let historyHotKey = GlobalHotKeyController()
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var appBeforeHistoryBundleIdentifier: String?
    private var appBeforeHistoryProcessIdentifier: pid_t?
    private var lastExternalAppBundleIdentifier: String?
    private var lastExternalAppProcessIdentifier: pid_t?
    private var didRequestAccessibilityPermission = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = updaterController
        setupStatusItem()
        preferences.onHistoryShortcutChanged = { [weak self] enabled, shortcut in
            self?.configureHistoryShortcut(enabled: enabled, shortcut: shortcut)
        }
        preferences.onHistoryRetentionChanged = { [weak self] in
            self?.model.refreshHistory()
        }
        configureHistoryShortcut(enabled: preferences.historyShortcutEnabled, shortcut: preferences.historyShortcut)
        setupWorkspaceActivationTracking()
        model.onNewResults = { [weak self] content, results in
            guard let self else { return }
            self.overlayPresenter.show(
                content: content,
                results: results,
                category: { [weak self] name in self?.model.category(forParser: name) ?? .text },
                preferences: self.preferences,
                copy: { [weak self] value in self?.model.copy(value) },
                showHistory: { [weak self] in self?.openHistoryWindow() }
            )
        }
        model.start()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = AppSymbols.primary
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageOnly
        item.button?.action = #selector(statusItemActivated)
        item.button?.target = self
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    @objc private func statusItemActivated() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusItemMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusItemMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "\(preferences.text(.settings))…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        let updateItem = NSMenuItem(
            title: model.availableUpdateVersion.map { String(format: preferences.text(.updateAvailable), $0) + "…" }
                ?? preferences.text(.checkForUpdates),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: preferences.text(.quit),
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openSettingsFromMenu() {
        openSettingsWindow()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func togglePopover() {
        if let historyWindow, historyWindow.isVisible {
            historyWindow.close()
        } else {
            openHistoryWindow()
        }
    }

    private func configureHistoryShortcut(enabled: Bool, shortcut: KeyboardShortcut) {
        historyHotKey.update(shortcut: enabled ? shortcut : nil) { [weak self] in
            self?.openHistoryWindow()
        }
    }

    private func openHistoryWindow() {
        rememberFrontmostAppBeforeHistory()
        if let historyWindow {
            historyWindow.center()
            showNonActivatingHistoryWindow(historyWindow)
            return
        }

        model.refreshHistory()
        let window = makeHistoryPanel(
            title: preferences.text(.history),
            size: NSSize(width: 720, height: 680)
        )
        window.contentView = NSHostingView(rootView: ClipboardPopoverView(
            model: model,
            preferences: preferences,
            openSettings: { [weak self] in self?.openSettingsWindow() },
            checkForUpdates: { [weak self] in self?.checkForUpdates(closing: self?.historyWindow) },
            close: { [weak self] in self?.historyWindow?.close() },
            paste: { [weak self] payload in self?.pasteToPreviousApp(payload) }
        ))
        historyWindow = window
        showNonActivatingHistoryWindow(window)
    }

    /// Sparkle's windows sit at the normal level, so a floating panel in front would hide them.
    private func checkForUpdates(closing window: NSWindow?) {
        window?.close()
        updaterController.checkForUpdates(nil)
    }

    private func pasteToPreviousApp(_ payload: ClipboardPayload) {
        model.copy(payload)
        let targetApp = appBeforeHistoryTarget()
        historyWindow?.orderOut(nil)
        historyWindow?.close()
        Task { @MainActor in
            if let targetApp {
                targetApp.unhide()
                targetApp.activate()
                await waitUntilFrontmost(targetApp)
            }
            try? await Task.sleep(for: .milliseconds(180))
            sendPasteKeystroke()
        }
    }

    private func setupWorkspaceActivationTracking() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            let bundleIdentifier = app.bundleIdentifier
            let processIdentifier = app.processIdentifier
            let isTerminated = app.isTerminated
            Task { @MainActor in
                self?.rememberExternalApp(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: processIdentifier,
                    isTerminated: isTerminated
                )
            }
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            rememberExternalApp(app)
        }
    }

    private func rememberFrontmostAppBeforeHistory() {
        if let app = NSWorkspace.shared.frontmostApplication,
           rememberExternalApp(app) {
            appBeforeHistoryBundleIdentifier = app.bundleIdentifier
            appBeforeHistoryProcessIdentifier = app.processIdentifier
        } else {
            appBeforeHistoryBundleIdentifier = lastExternalAppBundleIdentifier
            appBeforeHistoryProcessIdentifier = lastExternalAppProcessIdentifier
        }
        model.pasteTargetName = appBeforeHistoryTarget()?.localizedName
    }

    @discardableResult
    private func rememberExternalApp(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }
        lastExternalAppBundleIdentifier = app.bundleIdentifier
        lastExternalAppProcessIdentifier = app.processIdentifier
        return true
    }

    @discardableResult
    private func rememberExternalApp(bundleIdentifier: String?, processIdentifier: pid_t, isTerminated: Bool) -> Bool {
        guard !isTerminated,
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            return false
        }
        lastExternalAppBundleIdentifier = bundleIdentifier
        lastExternalAppProcessIdentifier = processIdentifier
        return true
    }

    private func appBeforeHistoryTarget() -> NSRunningApplication? {
        if let pid = appBeforeHistoryProcessIdentifier,
           let app = NSRunningApplication(processIdentifier: pid),
           !app.isTerminated {
            return app
        }
        if let bundleID = appBeforeHistoryBundleIdentifier {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first { !$0.isTerminated }
        }
        return nil
    }

    private func waitUntilFrontmost(_ app: NSRunningApplication) async {
        for _ in 0..<12 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    private func sendPasteKeystroke() {
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissionOnce()
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else {
            return
        }
        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = .maskCommand

        commandDown.post(tap: .cgAnnotatedSessionEventTap)
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        commandUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func requestAccessibilityPermissionOnce() {
        guard !didRequestAccessibilityPermission else { return }
        didRequestAccessibilityPermission = true
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func openSettingsWindow() {
        if let settingsWindow {
            preferences.refreshLaunchAtLogin()
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        preferences.refreshLaunchAtLogin()
        let window = makeSettingsPanel(
            title: preferences.text(.settings),
            size: NSSize(width: 560, height: 620)
        )
        window.contentView = NSHostingView(rootView: SettingsView(
            model: model,
            preferences: preferences,
            updater: updaterController.updater,
            checkForUpdates: { [weak self] in self?.checkForUpdates(closing: self?.settingsWindow) }
        ))
        settingsWindow = window
        showCentered(window)
    }

    /// A borderless palette: the search field row is the top edge, and Esc or clicking away closes it.
    private func makeHistoryPanel(title: String, size: NSSize) -> NSPanel {
        let window = NonActivatingHistoryPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.delegate = self
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return window
    }

    private func makeSettingsPanel(title: String, size: NSSize) -> NSPanel {
        let window = CenteredPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.level = .floating
        window.delegate = self
        return window
    }

    private func showCentered(_ window: NSWindow) {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showNonActivatingHistoryWindow(_ window: NSWindow) {
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
    }
}

enum ClipboardPayload {
    case text(String)
    case file(URL)
    case image(URL)
}

final class CenteredPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class NonActivatingHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Gentle reminders: a menu bar app is rarely active, so an update alert from a background check
/// would open behind other apps. Only checks near launch show the alert; later ones mark the menu and
/// history window instead, and the alert opens when the user asks for it.
extension AppDelegate: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            model.availableUpdateVersion = update.displayVersionString
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        model.availableUpdateVersion = nil
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === historyWindow || window === settingsWindow {
            window.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === historyWindow {
            historyWindow = nil
        }
        if window === settingsWindow {
            settingsWindow = nil
        }
    }
}
