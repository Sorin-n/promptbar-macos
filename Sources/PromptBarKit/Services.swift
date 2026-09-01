import AppKit
import ApplicationServices
import Combine
import SwiftUI

public enum PasteError: Error {
    case noPermission
    case eventSourceUnavailable
}

@MainActor
public final class PermissionService: ObservableObject {
    @Published public private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted()

    public init() {}

    public func refresh(promptIfNeeded: Bool = false) {
        let options = ["AXTrustedCheckOptionPrompt": promptIfNeeded] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
public final class PasteService {
    public init() {}

    public func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func pasteCopiedContent(permissionService: PermissionService) throws {
        guard permissionService.isAccessibilityTrusted else {
            throw PasteError.noPermission
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceUnavailable
        }

        let keyCodeV: CGKeyCode = 9
        let commandDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true)
        commandDown?.flags = .maskCommand
        let commandUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        commandUp?.flags = .maskCommand
        commandDown?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
    }
}

private enum ShortcutMatcher {
    static func matches(_ event: NSEvent, shortcut: RecordedShortcut) -> Bool {
        guard shortcut.triggerKind == triggerKind(for: event) else { return false }
        guard event.keyCode == shortcut.keyCode else { return false }
        return filteredModifiers(from: event).rawValue == shortcut.modifiersRawValue
    }

    static func filteredModifiers(from event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    static func triggerKind(for event: NSEvent) -> ShortcutTriggerKind {
        event.type == .flagsChanged ? .flagsChanged : .keyDown
    }
}

@MainActor
public final class HotkeyMonitorService {
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalLeftMouseMonitor: Any?
    private var localLeftMouseMonitor: Any?
    private var globalRightMouseMonitor: Any?
    private var localRightMouseMonitor: Any?

    private let isPanelPresented: () -> Bool
    private let thresholdMilliseconds: () -> Int
    private let isKeyboardShortcutEnabled: () -> Bool
    private let isDualMouseEnabled: () -> Bool
    private let isInputSuspended: () -> Bool
    private let isWorkspacePresented: () -> Bool
    private let singleConfirmShortcut: () -> RecordedShortcut
    private let doubleOpenShortcut: () -> RecordedShortcut
    private let workspaceTransferShortcut: () -> RecordedShortcut
    private let togglePanel: () -> Void
    private let confirmSelection: () -> Void
    private let transferHoveredSelection: () -> Bool

    private var lastOpenShortcutTimestamp: TimeInterval = 0
    private var lastLeftMouseTimestamp: TimeInterval = 0
    private var lastRightMouseTimestamp: TimeInterval = 0
    private var lastDualConfirmTimestamp: TimeInterval = 0

    public init(
        isPanelPresented: @escaping () -> Bool,
        thresholdMilliseconds: @escaping () -> Int,
        isKeyboardShortcutEnabled: @escaping () -> Bool,
        isDualMouseEnabled: @escaping () -> Bool,
        isInputSuspended: @escaping () -> Bool,
        isWorkspacePresented: @escaping () -> Bool,
        singleConfirmShortcut: @escaping () -> RecordedShortcut,
        doubleOpenShortcut: @escaping () -> RecordedShortcut,
        workspaceTransferShortcut: @escaping () -> RecordedShortcut,
        togglePanel: @escaping () -> Void,
        confirmSelection: @escaping () -> Void,
        transferHoveredSelection: @escaping () -> Bool
    ) {
        self.isPanelPresented = isPanelPresented
        self.thresholdMilliseconds = thresholdMilliseconds
        self.isKeyboardShortcutEnabled = isKeyboardShortcutEnabled
        self.isDualMouseEnabled = isDualMouseEnabled
        self.isInputSuspended = isInputSuspended
        self.isWorkspacePresented = isWorkspacePresented
        self.singleConfirmShortcut = singleConfirmShortcut
        self.doubleOpenShortcut = doubleOpenShortcut
        self.workspaceTransferShortcut = workspaceTransferShortcut
        self.togglePanel = togglePanel
        self.confirmSelection = confirmSelection
        self.transferHoveredSelection = transferHoveredSelection
    }

    public func start() {
        guard globalKeyMonitor == nil else { return }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyboardEvent(event, consume: false)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyboardEvent(event, consume: true) ?? event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            _ = self?.handleKeyboardEvent(event, consume: false)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleKeyboardEvent(event, consume: true) ?? event
        }

        globalLeftMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouse(event, isLeft: true)
        }
        localLeftMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouse(event, isLeft: true)
            return event
        }

        globalRightMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleMouse(event, isLeft: false)
        }
        localRightMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleMouse(event, isLeft: false)
            return event
        }
    }

    public func stop() {
        for monitor in [
            globalKeyMonitor,
            localKeyMonitor,
            globalFlagsMonitor,
            localFlagsMonitor,
            globalLeftMouseMonitor,
            localLeftMouseMonitor,
            globalRightMouseMonitor,
            localRightMouseMonitor
        ] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        globalKeyMonitor = nil
        localKeyMonitor = nil
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalLeftMouseMonitor = nil
        localLeftMouseMonitor = nil
        globalRightMouseMonitor = nil
        localRightMouseMonitor = nil
    }

    private func handleKeyboardEvent(_ event: NSEvent, consume: Bool) -> NSEvent? {
        guard !isInputSuspended() else {
            return event
        }

        if isWorkspacePresented(), ShortcutMatcher.matches(event, shortcut: workspaceTransferShortcut()) {
            let handled = transferHoveredSelection()
            return handled && consume ? nil : event
        }

        guard isKeyboardShortcutEnabled() else {
            return event
        }

        if isPanelPresented(), ShortcutMatcher.matches(event, shortcut: singleConfirmShortcut()) {
            confirmSelection()
            return consume ? nil : event
        }

        if !isPanelPresented(), ShortcutMatcher.matches(event, shortcut: doubleOpenShortcut()) {
            let now = event.timestamp
            let threshold = Double(thresholdMilliseconds()) / 1000

            if now - lastOpenShortcutTimestamp <= threshold {
                lastOpenShortcutTimestamp = 0
                togglePanel()
            } else {
                lastOpenShortcutTimestamp = now
            }

            return consume ? nil : event
        }

        return event
    }

    private func handleMouse(_ event: NSEvent, isLeft: Bool) {
        guard isPanelPresented(), isDualMouseEnabled() else { return }
        let now = event.timestamp

        if isLeft {
            lastLeftMouseTimestamp = now
        } else {
            lastRightMouseTimestamp = now
        }

        guard abs(lastLeftMouseTimestamp - lastRightMouseTimestamp) <= 0.2 else { return }
        guard now - lastDualConfirmTimestamp > 0.35 else { return }

        lastDualConfirmTimestamp = now
        confirmSelection()
    }
}

@MainActor
public final class StatusBarController {
    public let statusItem: NSStatusItem
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureButton()
    }

    public var button: NSStatusBarButton? {
        statusItem.button
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "PromptBar")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(togglePanel)
    }

    @objc
    private func togglePanel() {
        action()
    }
}
