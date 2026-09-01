import AppKit
import Combine
import SwiftUI
import SwiftData

@MainActor
public final class PanelCoordinator: ObservableObject {
    public enum PanelPage {
        case library
        case settings
    }

    @Published public private(set) var isPresented = false
    @Published public var selectedPromptID: UUID?
    @Published public var hoveredPromptID: UUID?
    @Published public var selectedCategoryID: UUID?
    @Published public var selectedTagID: UUID?
    @Published public var isPromptEditorPresented = false
    @Published public var editingPrompt: PromptItem?
    @Published public private(set) var promptEditorMainCategoryID: UUID?
    @Published public private(set) var promptEditorSecondaryCategoryID: UUID?
    @Published public var isSearchPresented = false
    @Published public var searchQuery = ""
    @Published public var isShortcutRecording = false
    @Published public var toastMessage: String?
    @Published public var scrollGlowVisible = false
    @Published public var panelPage: PanelPage = .library

    private let promptRepository: PromptRepository
    private let settingsRepository: SettingsRepository
    private let permissionService: PermissionService
    private let pasteService: PasteService
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private weak var statusButton: NSStatusBarButton?
    private var cancellables: Set<AnyCancellable> = []
    private var previousFrontmostApp: NSRunningApplication?
    private var visiblePromptIDs: [UUID]?

    public init(
        promptRepository: PromptRepository,
        settingsRepository: SettingsRepository,
        permissionService: PermissionService,
        pasteService: PasteService
    ) {
        self.promptRepository = promptRepository
        self.settingsRepository = settingsRepository
        self.permissionService = permissionService
        self.pasteService = pasteService

        promptRepository.$prompts
            .sink { [weak self] _ in
                self?.reconcileSelection()
            }
            .store(in: &cancellables)
    }

    public func attachStatusButton(_ button: NSStatusBarButton?) {
        self.statusButton = button
    }

    public func attachPanel(_ panel: NSPanel) {
        self.panel = panel
        updateAppearance()
    }

    public func attachSettingsWindow(_ window: NSWindow) {
        self.settingsWindow = window
        updateAppearance()
    }

    public func updateAppearance() {
        let appearance = settingsRepository.settings.themeMode.nsAppearance
        panel?.appearance = appearance
        settingsWindow?.appearance = appearance
    }

    public func togglePanel() {
        isPresented ? hidePanel() : showPanel()
    }

    public func showPanel(resetPage: Bool = true) {
        guard let panel else { return }
        previousFrontmostApp = NSWorkspace.shared.frontmostApplication
        permissionService.refresh()
        visiblePromptIDs = nil
        reconcileSelection()
        if resetPage {
            panelPage = .library
        }
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isPresented = true
    }

    public func hidePanel(resetUIState: Bool = true) {
        panel?.orderOut(nil)
        if resetUIState {
            hoveredPromptID = nil
            dismissPromptEditor()
            dismissSearch()
            panelPage = .library
        }
        isPresented = false
    }

    public func openSettings() {
        panelPage = .settings
    }

    public func openLibrary() {
        panelPage = .library
    }

    public func toggleSettingsPage() {
        panelPage = panelPage == .settings ? .library : .settings
    }

    public func promptCreation(mainCategoryID: UUID, secondaryCategoryID: UUID?) {
        dismissSearch()
        panelPage = .library
        editingPrompt = nil
        promptEditorMainCategoryID = mainCategoryID
        promptEditorSecondaryCategoryID = secondaryCategoryID
        isPromptEditorPresented = true
    }

    public func promptEditing(_ prompt: PromptItem) {
        dismissSearch()
        panelPage = .library
        editingPrompt = prompt
        promptEditorMainCategoryID = prompt.category?.id
        promptEditorSecondaryCategoryID = prompt.secondaryCategory?.id
        isPromptEditorPresented = true
    }

    public func dismissPromptEditor() {
        editingPrompt = nil
        promptEditorMainCategoryID = nil
        promptEditorSecondaryCategoryID = nil
        isPromptEditorPresented = false
    }

    public func openSearch() {
        dismissPromptEditor()
        isSearchPresented = true
    }

    public func dismissSearch() {
        isSearchPresented = false
        searchQuery = ""
    }

    public func visiblePromptList() -> [PromptItem] {
        if let visiblePromptIDs {
            return visiblePromptIDs.compactMap { id in
                promptRepository.prompts.first(where: { $0.id == id })
            }
        }

        return promptRepository.prompts(
            mainCategoryID: selectedCategoryID,
            secondaryCategoryID: selectedTagID
        )
    }

    public func setVisiblePromptIDs(_ ids: [UUID]) {
        visiblePromptIDs = ids
        reconcileSelection()
    }

    public func cycleSelection(delta: Int) {
        let prompts = visiblePromptList()
        let currentIndex = prompts.firstIndex(where: { $0.id == selectedPromptID })
        let nextIndex = SelectionNavigator.nextIndex(current: currentIndex, count: prompts.count, delta: delta)
        hoveredPromptID = nil
        selectedPromptID = nextIndex.flatMap { prompts[$0].id }
        pulseScrollGlow()
    }

    public func selectPrompt(_ prompt: PromptItem) {
        selectedPromptID = prompt.id
    }

    public func setHoveredPrompt(_ prompt: PromptItem?) {
        hoveredPromptID = prompt?.id
    }

    public var activePromptID: UUID? {
        hoveredPromptID ?? selectedPromptID
    }

    public func confirmCurrentSelection() {
        let prompts = visiblePromptList()
        guard let prompt = prompts.first(where: { $0.id == activePromptID }) ?? prompts.first else {
            return
        }

        confirmPrompt(prompt)
    }

    public func confirmPrompt(_ prompt: PromptItem) {
        dismissSearch()

        pasteService.copyToClipboard(prompt.content)
        hidePanel()
        previousFrontmostApp?.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            do {
                try self.pasteService.pasteCopiedContent(permissionService: self.permissionService)
                self.showToast("已粘贴：\(prompt.title)")
            } catch PasteError.noPermission {
                self.showToast("已复制到剪贴板，请授权辅助功能")
            } catch {
                self.showToast("已复制到剪贴板，可手动粘贴")
            }
        }
    }

    public func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard self?.toastMessage == message else { return }
            self?.toastMessage = nil
        }
    }

    public func pulseScrollGlow() {
        scrollGlowVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.scrollGlowVisible = false
        }
    }

    private func reconcileSelection() {
        let prompts = visiblePromptList()
        if prompts.isEmpty {
            selectedPromptID = nil
            hoveredPromptID = nil
            return
        }

        if let hoveredPromptID, !prompts.contains(where: { $0.id == hoveredPromptID }) {
            self.hoveredPromptID = nil
        }

        if let selectedPromptID, prompts.contains(where: { $0.id == selectedPromptID }) {
            return
        }

        selectedPromptID = prompts.first?.id
    }

    private func positionPanel() {
        guard let panel else { return }
        if let preferredFrame = preferredPanelFrame(for: panel.frame.size) {
            panel.setFrame(preferredFrame, display: false)
        }
    }

    public func preferredPanelFrame(for size: NSSize) -> NSRect? {
        if
            let button = statusButton,
            let buttonWindow = button.window
        {
            let buttonFrameInWindow = button.convert(button.bounds, to: nil)
            let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
            let x = max(buttonFrameOnScreen.midX - size.width + 20, 12)
            let y = buttonFrameOnScreen.minY - size.height - 10
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            return NSRect(
                x: frame.maxX - size.width - 20,
                y: frame.maxY - size.height - 20,
                width: size.width,
                height: size.height
            )
        }

        return nil
    }
}
