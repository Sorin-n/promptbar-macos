import AppKit
import QuartzCore
import SwiftUI

@MainActor
public final class WorkspaceCoordinator: ObservableObject {
    public enum WorkspacePage {
        case promptLibrary
        case settings
    }

    public enum PanelToWorkspaceTransitionPhase {
        case idle
        case morphingPanelToEmbedded
        case movingEmbeddedToWorkspace
        case revealingWorkspace
    }

    @Published public private(set) var isPresented = false
    @Published public private(set) var isTransitioning = false
    @Published public private(set) var panelToWorkspaceTransitionPhase: PanelToWorkspaceTransitionPhase = .idle
    @Published public private(set) var workspaceBackgroundOpacity: Double = 1
    @Published public private(set) var workspaceForegroundOpacity: Double = 1
    @Published public private(set) var librarySearchDismissalToken: Int = 0
    @Published public var page: WorkspacePage = .promptLibrary
    @Published public var isSidebarCollapsed = false
    @Published public var isRightSidebarCollapsed = false
    @Published public var hoveredLibraryEntryID: UUID?
    private var previousNonSettingsPage: WorkspacePage = .promptLibrary

    private weak var panel: NSPanel?
    private weak var workspaceWindow: NSWindow?
    private weak var transitionPreviewWindow: NSWindow?
    private weak var statusButton: NSStatusBarButton?

    private let panelCoordinator: PanelCoordinator
    private let settingsRepository: SettingsRepository

    public init(
        panelCoordinator: PanelCoordinator,
        settingsRepository: SettingsRepository
    ) {
        self.panelCoordinator = panelCoordinator
        self.settingsRepository = settingsRepository
    }

    public func attachPanel(_ panel: NSPanel) {
        self.panel = panel
    }

    public func attachWorkspaceWindow(_ window: NSWindow) {
        self.workspaceWindow = window
        updateAppearance()
    }

    public func attachTransitionPreviewWindow(_ window: NSWindow) {
        transitionPreviewWindow = window
        updateAppearance()
    }

    public func attachStatusButton(_ button: NSStatusBarButton?) {
        statusButton = button
    }

    public func updateAppearance() {
        let appearance = settingsRepository.settings.workspaceThemeMode.nsAppearance(
            fallback: settingsRepository.settings.themeMode
        )
        workspaceWindow?.appearance = appearance
        transitionPreviewWindow?.appearance = appearance
    }

    public func focusWorkspace() {
        guard let workspaceWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        workspaceWindow.makeKeyAndOrderFront(nil)
        isPresented = true
    }

    public func showWorkspace() {
        updateAppearance()
        if isPresented {
            focusWorkspace()
            return
        }
        isRightSidebarCollapsed = false
        animatePanelToWorkspace()
    }

    public func hideWorkspaceToPanel() {
        animateWorkspaceToPanel()
    }

    public func closeWorkspace() {
        guard let workspaceWindow else { return }
        workspaceWindow.orderOut(nil)
        resetTransitionState()
    }

    public func toggleSidebarCollapsed() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isSidebarCollapsed.toggle()
        }
    }

    public func toggleRightSidebarCollapsed() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isRightSidebarCollapsed.toggle()
        }
    }

    public func requestLibrarySearchDismissal() {
        librarySearchDismissalToken &+= 1
    }

    public func setPage(_ page: WorkspacePage) {
        requestLibrarySearchDismissal()
        if page != .settings {
            previousNonSettingsPage = page
        }

        if page != .promptLibrary {
            hoveredLibraryEntryID = nil
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            self.page = page
        }
    }

    public func toggleSettingsPage() {
        requestLibrarySearchDismissal()
        if page == .settings {
            setPage(previousNonSettingsPage)
        } else {
            previousNonSettingsPage = page
            withAnimation(.easeInOut(duration: 0.18)) {
                page = .settings
            }
        }
    }

    private func animatePanelToWorkspace() {
        guard let panel, let workspaceWindow else {
            animatePanelToWorkspaceLegacy()
            return
        }

        isTransitioning = true
        panelToWorkspaceTransitionPhase = .idle
        workspaceBackgroundOpacity = 1
        workspaceForegroundOpacity = 1
        page = .promptLibrary
        panelCoordinator.openLibrary()

        let endFrame = preferredWorkspaceFrame()
        let startFrame = centeredScaledFrame(from: endFrame, scale: 0.975)

        transitionPreviewWindow?.orderOut(nil)
        transitionPreviewWindow?.alphaValue = 1

        NSApp.activate(ignoringOtherApps: true)
        workspaceWindow.setFrame(startFrame, display: false)
        workspaceWindow.alphaValue = 0
        workspaceWindow.makeKeyAndOrderFront(nil)
        isPresented = true

        panelCoordinator.hidePanel(resetUIState: false)
        panel.alphaValue = 1

        animate(
            window: workspaceWindow,
            to: endFrame,
            alpha: 1,
            duration: 0.22,
            timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
        ) { [weak self] in
            guard let self else { return }
            self.isTransitioning = false
        }
    }

    private func animateWorkspaceToPanel() {
        guard let panel, let workspaceWindow else { return }
        isTransitioning = true

        let finalPanelFrame = panelCoordinator.preferredPanelFrame(for: NSSize(width: 440, height: 560)) ?? panel.frame
        let workspaceFrame = workspaceWindow.frame
        let collapseFrame = NSRect(x: workspaceFrame.minX, y: workspaceFrame.maxY - 1, width: 1, height: 1)
        let panelCollapsedFrame = NSRect(x: finalPanelFrame.minX, y: finalPanelFrame.maxY - 1, width: 1, height: 1)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            workspaceWindow.animator().setFrame(collapseFrame, display: true)
            workspaceWindow.animator().alphaValue = 0.92
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, let workspaceWindow = self.workspaceWindow else { return }
                workspaceWindow.orderOut(nil)
                self.isPresented = false

                panel.setFrame(panelCollapsedFrame, display: false)
                panel.alphaValue = 0.92
                self.panelCoordinator.showPanel(resetPage: false)

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(finalPanelFrame, display: true)
                    panel.animator().alphaValue = 1
                } completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.panelToWorkspaceTransitionPhase = .idle
                        self?.workspaceBackgroundOpacity = 1
                        self?.workspaceForegroundOpacity = 1
                        self?.isTransitioning = false
                    }
                }
            }
        }
    }

    private func preferredWorkspaceFrame() -> NSRect {
        let targetSize = NSSize(width: 1320, height: 780)
        let screenFrame = workspaceWindow?.screen?.visibleFrame
            ?? panel?.screen?.visibleFrame
            ?? statusButton?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 160, y: 160, width: targetSize.width, height: targetSize.height)

        let width = min(targetSize.width, screenFrame.width - 80)
        let height = min(targetSize.height, screenFrame.height - 80)
        let originX = screenFrame.minX + (screenFrame.width - width) / 2
        let originY = screenFrame.minY + (screenFrame.height - height) / 2
        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func centeredScaledFrame(from frame: NSRect, scale: CGFloat) -> NSRect {
        let width = frame.width * scale
        let height = frame.height * scale
        return NSRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    private func animate(
        window: NSWindow,
        to frame: NSRect,
        alpha: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = alpha
        } completionHandler: {
            Task { @MainActor in
                completion()
            }
        }
    }

    private func animatePanelToWorkspaceLegacy() {
        guard let panel, let workspaceWindow else { return }
        isTransitioning = true
        workspaceBackgroundOpacity = 1
        workspaceForegroundOpacity = 1
        let endFrame = preferredWorkspaceFrame()
        let startFrame = centeredScaledFrame(from: endFrame, scale: 0.975)

        NSApp.activate(ignoringOtherApps: true)
        workspaceWindow.setFrame(startFrame, display: false)
        workspaceWindow.alphaValue = 0
        workspaceWindow.makeKeyAndOrderFront(nil)
        isPresented = true

        panelCoordinator.hidePanel(resetUIState: false)
        panel.alphaValue = 1

        animate(
            window: workspaceWindow,
            to: endFrame,
            alpha: 1,
            duration: 0.22,
            timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
        ) { [weak self] in
            guard let self else { return }
            self.isTransitioning = false
        }
    }

    private func resetTransitionState() {
        transitionPreviewWindow?.orderOut(nil)
        transitionPreviewWindow?.alphaValue = 1
        workspaceBackgroundOpacity = 1
        workspaceForegroundOpacity = 1
        panelToWorkspaceTransitionPhase = .idle
        isRightSidebarCollapsed = false
        hoveredLibraryEntryID = nil
        isPresented = false
        isTransitioning = false
    }
}
