import AppKit
import PromptBarKit
import SwiftData
import SwiftUI

final class PromptBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
enum PromptBarMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var modelContainer: ModelContainer!
    private var promptRepository: PromptRepository!
    private var promptLibraryRepository: PromptLibraryRepository!
    private var settingsRepository: SettingsRepository!
    private var permissionService: PermissionService!
    private var pasteService: PasteService!
    private var panelCoordinator: PanelCoordinator!
    private var workspaceCoordinator: WorkspaceCoordinator!
    private var hotkeyMonitorService: HotkeyMonitorService!
    private var statusBarController: StatusBarController!
    private var panel: NSPanel!
    private var workspaceWindow: NSWindow!
    private var transitionPreviewWindow: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try setupDependencies()
            setupPanel()
            setupWorkspaceWindow()
            setupTransitionPreviewWindow()
            setupStatusBar()
            setupHotkeys()
            permissionService.refresh()
        } catch {
            let alert = NSAlert()
            alert.messageText = "PromptBar 启动失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitorService?.stop()
    }

    private func setupDependencies() throws {
        settingsRepository = SettingsRepository()
        FontAssetRegistry.shared.prepare()

        let schema = Schema([
            PromptItem.self,
            PromptCategory.self,
            PromptSecondaryCategory.self,
            PromptTag.self,
            PromptLibrarySource.self,
            PromptLibraryEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try ModelContainer(for: schema, configurations: [configuration])

        promptRepository = PromptRepository(modelContext: modelContainer.mainContext)
        promptLibraryRepository = PromptLibraryRepository(modelContext: modelContainer.mainContext)
        try promptRepository.bootstrap(legacySidebarCategories: settingsRepository.settings.sidebarCategories)
        try promptLibraryRepository.reload()
        permissionService = PermissionService()
        pasteService = PasteService()
        panelCoordinator = PanelCoordinator(
            promptRepository: promptRepository,
            settingsRepository: settingsRepository,
            permissionService: permissionService,
            pasteService: pasteService
        )
        workspaceCoordinator = WorkspaceCoordinator(
            panelCoordinator: panelCoordinator,
            settingsRepository: settingsRepository
        )
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.workspaceCoordinator.isTransitioning {
                    return
                }
                if self.workspaceCoordinator.isPresented {
                    self.workspaceCoordinator.closeWorkspace()
                } else {
                    self.panelCoordinator.togglePanel()
                }
            }
        }
        panelCoordinator.attachStatusButton(statusBarController.button)
        workspaceCoordinator.attachStatusButton(statusBarController.button)
    }

    private func setupPanel() {
        let rootView = PromptPanelView()
            .environmentObject(promptRepository)
            .environmentObject(promptLibraryRepository)
            .environmentObject(settingsRepository)
            .environmentObject(permissionService)
            .environmentObject(panelCoordinator)
            .environmentObject(workspaceCoordinator)

        let hostingController = NSHostingController(rootView: rootView)
        panel = PromptBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isOpaque = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self

        panelCoordinator.attachPanel(panel)
        workspaceCoordinator.attachPanel(panel)
    }

    private func setupWorkspaceWindow() {
        let rootView = PromptWorkspaceView()
            .environmentObject(promptRepository)
            .environmentObject(promptLibraryRepository)
            .environmentObject(settingsRepository)
            .environmentObject(permissionService)
            .environmentObject(panelCoordinator)
            .environmentObject(workspaceCoordinator)

        let hostingController = NSHostingController(rootView: rootView)
        workspaceWindow = PromptBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 780),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        workspaceWindow.contentViewController = hostingController
        workspaceWindow.level = .normal
        workspaceWindow.backgroundColor = .clear
        workspaceWindow.hasShadow = false
        workspaceWindow.isOpaque = false
        workspaceWindow.isMovableByWindowBackground = false
        workspaceWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        workspaceWindow.titleVisibility = .hidden
        workspaceWindow.titlebarAppearsTransparent = true
        workspaceWindow.standardWindowButton(.closeButton)?.isHidden = true
        workspaceWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        workspaceWindow.standardWindowButton(.zoomButton)?.isHidden = true

        workspaceCoordinator.attachWorkspaceWindow(workspaceWindow)
    }

    private func setupTransitionPreviewWindow() {
        let rootView = PromptPanelView(style: .workspaceEmbedded)
            .environmentObject(promptRepository)
            .environmentObject(promptLibraryRepository)
            .environmentObject(settingsRepository)
            .environmentObject(permissionService)
            .environmentObject(panelCoordinator)
            .environmentObject(workspaceCoordinator)

        let hostingController = NSHostingController(rootView: rootView)
        transitionPreviewWindow = PromptBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        transitionPreviewWindow.contentViewController = hostingController
        transitionPreviewWindow.level = .statusBar
        transitionPreviewWindow.backgroundColor = .clear
        transitionPreviewWindow.hasShadow = false
        transitionPreviewWindow.isOpaque = false
        transitionPreviewWindow.ignoresMouseEvents = true
        transitionPreviewWindow.isMovableByWindowBackground = false
        transitionPreviewWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        transitionPreviewWindow.titleVisibility = .hidden
        transitionPreviewWindow.titlebarAppearsTransparent = true
        transitionPreviewWindow.standardWindowButton(.closeButton)?.isHidden = true
        transitionPreviewWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        transitionPreviewWindow.standardWindowButton(.zoomButton)?.isHidden = true
        transitionPreviewWindow.orderOut(nil)

        workspaceCoordinator.attachTransitionPreviewWindow(transitionPreviewWindow)
    }

    private func setupHotkeys() {
        hotkeyMonitorService = HotkeyMonitorService(
            isPanelPresented: { [weak self] in
                self?.panelCoordinator.isPresented ?? false
            },
            thresholdMilliseconds: { [weak self] in
                self?.settingsRepository.settings.doubleTabThresholdMs ?? 260
            },
            isKeyboardShortcutEnabled: { [weak self] in
                self?.settingsRepository.settings.tabTriggerEnabled ?? true
            },
            isDualMouseEnabled: { [weak self] in
                self?.settingsRepository.settings.confirmByDualMouse ?? true
            },
            isInputSuspended: { [weak self] in
                guard let self else { return false }
                if self.panelCoordinator.isShortcutRecording {
                    return true
                }

                if self.panelCoordinator.isPromptEditorPresented || self.panelCoordinator.isSearchPresented {
                    return true
                }

                if self.workspaceCoordinator.isPresented {
                    return self.workspaceWindow?.firstResponder is NSText
                }

                let firstResponder = self.panel?.firstResponder ?? NSApp.keyWindow?.firstResponder
                return firstResponder is NSText
            },
            isWorkspacePresented: { [weak self] in
                self?.workspaceCoordinator.isPresented ?? false
            },
            singleConfirmShortcut: { [weak self] in
                self?.settingsRepository.settings.singleConfirmShortcut ?? .defaultTab
            },
            doubleOpenShortcut: { [weak self] in
                self?.settingsRepository.settings.doubleOpenShortcut ?? .defaultTab
            },
            workspaceTransferShortcut: { [weak self] in
                self?.settingsRepository.settings.workspaceTransferShortcut ?? .defaultG
            },
            togglePanel: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.workspaceCoordinator.isTransitioning {
                        return
                    }
                    if self.workspaceCoordinator.isPresented {
                        self.workspaceCoordinator.closeWorkspace()
                    } else {
                        self.panelCoordinator.togglePanel()
                    }
                }
            },
            confirmSelection: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.panelCoordinator.confirmCurrentSelection()
                }
            },
            transferHoveredSelection: { [weak self] in
                self?.transferHoveredWorkspaceSelection() ?? false
            }
        )
        hotkeyMonitorService.start()
    }

    private func transferHoveredWorkspaceSelection() -> Bool {
        guard workspaceCoordinator.isPresented else { return false }
        guard workspaceCoordinator.page == .promptLibrary else { return false }

        if let hoveredLibraryEntryID = workspaceCoordinator.hoveredLibraryEntryID,
           let entry = promptLibraryRepository.entry(id: hoveredLibraryEntryID) {
            return injectLibraryEntryIntoCurrentPromptLibrary(entry)
        }

        guard !workspaceCoordinator.isRightSidebarCollapsed else { return false }
        guard let hoveredPromptID = panelCoordinator.hoveredPromptID,
              let prompt = promptRepository.prompts.first(where: { $0.id == hoveredPromptID }) else {
            return false
        }

        return recycleWorkspacePrompt(prompt)
    }

    private func injectLibraryEntryIntoCurrentPromptLibrary(_ entry: PromptLibraryEntry) -> Bool {
        guard let mainCategoryID = panelCoordinator.selectedCategoryID else {
            panelCoordinator.showToast("请先创建并选择主导航")
            return false
        }

        let secondaryCategoryID: UUID?
        if settingsRepository.settings.isSecondaryNavigationEnabled {
            guard let selectedTagID = panelCoordinator.selectedTagID else {
                panelCoordinator.showToast("请先创建并选择次级导航")
                return false
            }
            secondaryCategoryID = selectedTagID
        } else {
            secondaryCategoryID = nil
        }

        if promptRepository.containsPrompt(
            title: entry.title,
            content: entry.content,
            mainCategoryID: mainCategoryID,
            secondaryCategoryID: secondaryCategoryID
        ) {
            panelCoordinator.showToast("当前分类中已存在相同提示词")
            return true
        }

        do {
            try promptRepository.createPrompt(
                from: PromptDraft(title: entry.title, content: entry.content),
                mainCategoryID: mainCategoryID,
                secondaryCategoryID: secondaryCategoryID
            )
            panelCoordinator.showToast("已加入快捷提示词：\(entry.title)")
            return true
        } catch {
            panelCoordinator.showToast("提示词转移失败")
            return false
        }
    }

    private func recycleWorkspacePrompt(_ prompt: PromptItem) -> Bool {
        let groupName = promptCategoryPath(for: prompt)

        do {
            let alreadyExists = promptLibraryRepository.containsRecycleEntry(
                title: prompt.title,
                content: prompt.content,
                groupName: groupName
            )
            if !alreadyExists {
                try promptLibraryRepository.createRecycleEntry(from: prompt, groupName: groupName)
            }
            try promptRepository.deletePrompt(prompt)
            panelCoordinator.showToast(alreadyExists ? "已回收并合并重复：\(prompt.title)" : "已移入回收：\(prompt.title)")
            return true
        } catch {
            panelCoordinator.showToast("移入回收失败")
            return false
        }
    }

    private func promptCategoryPath(for prompt: PromptItem) -> String? {
        let mainName = prompt.category?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondaryName = prompt.secondaryCategory?.name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let mainName, !mainName.isEmpty, let secondaryName, !secondaryName.isEmpty {
            return "\(mainName) / \(secondaryName)"
        }

        if let mainName, !mainName.isEmpty {
            return mainName
        }

        return nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if workspaceCoordinator?.isTransitioning == true {
            return
        }
        guard notification.object as? NSWindow === panel, panelCoordinator.isPresented else { return }
        panelCoordinator.hidePanel()
    }
}
