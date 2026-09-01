import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct PromptWorkspaceView: View {
    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var promptLibraryRepository: PromptLibraryRepository
    @EnvironmentObject private var settingsRepository: SettingsRepository
    @EnvironmentObject private var permissionService: PermissionService
    @EnvironmentObject private var panelCoordinator: PanelCoordinator
    @EnvironmentObject private var workspaceCoordinator: WorkspaceCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var workspaceCategoryDraftName = ""

    public init() {}

    public var body: some View {
        let theme = PromptBarTheme.resolveWorkspace(
            workspaceMode: settingsRepository.settings.workspaceThemeMode,
            primaryMode: settingsRepository.settings.themeMode,
            fontMode: settingsRepository.settings.fontMode,
            systemScheme: colorScheme
        )

        GeometryReader { geometry in
            let metrics = layoutMetrics(for: geometry.size.width)

            VStack(spacing: 0) {
                WindowDragStrip()
                    .frame(height: 18)
                    .background(workspacePaneBackground(theme: theme, tint: theme.background))

                ZStack {
                    workspaceBackground(theme: theme)
                        .opacity(workspaceCoordinator.workspaceBackgroundOpacity)
                        .animation(.easeInOut(duration: 0.22), value: workspaceCoordinator.workspaceBackgroundOpacity)

                    HStack(spacing: 0) {
                        workspaceSidebarControlRail(theme: theme)
                            .frame(width: metrics.leftRailWidth)
                            .background(workspacePaneBackground(theme: theme, tint: theme.sidebarBackground))

                        if metrics.showsLeftSidebar {
                            workspaceSidebar(theme: theme)
                                .frame(width: metrics.leftWidth)
                                .background(workspacePaneBackground(theme: theme, tint: theme.sidebarBackground))
                                .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                        }

                        if metrics.showsLeftDivider {
                            Rectangle()
                                .fill(theme.navigationDivider)
                                .frame(width: metrics.leftDividerWidth)
                        }

                        workspaceMainArea(theme: theme, metrics: metrics)
                            .frame(width: metrics.mainAreaWidth)
                            .background(workspacePaneBackground(theme: theme, tint: theme.background))

                        if metrics.showsRightRail {
                            workspaceRightControlRail(theme: theme)
                                .frame(width: metrics.rightRailWidth)
                                .background(workspacePaneBackground(theme: theme, tint: theme.background))
                        }
                    }
                    .opacity(workspaceCoordinator.workspaceForegroundOpacity)
                    .allowsHitTesting(!workspaceCoordinator.isTransitioning && workspaceCoordinator.workspaceForegroundOpacity > 0.99)
                    .animation(.easeInOut(duration: 0.22), value: workspaceCoordinator.isSidebarCollapsed)
                    .animation(.easeInOut(duration: 0.22), value: workspaceCoordinator.isRightSidebarCollapsed)
                    .animation(.easeInOut(duration: 0.18), value: workspaceCoordinator.page)
                    .animation(.easeInOut(duration: 0.20), value: workspaceCoordinator.workspaceForegroundOpacity)
                }
            }
            .background(workspacePaneBackground(theme: theme, tint: theme.background))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(theme.outline, lineWidth: 1)
                    .opacity(workspaceCoordinator.workspaceForegroundOpacity)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .onAppear {
                workspaceCoordinator.updateAppearance()
                if workspaceCoordinator.page != .settings {
                    panelCoordinator.openLibrary()
                }
            }
            .preferredColorScheme(
                settingsRepository.settings.workspaceThemeMode.preferredColorScheme
                    ?? settingsRepository.settings.themeMode.preferredColorScheme
            )
            .onChange(of: workspaceCoordinator.page) { _, page in
                if page != .settings {
                    panelCoordinator.openLibrary()
                }
            }
            .onChange(of: settingsRepository.settings.workspaceThemeMode) { _, _ in
                workspaceCoordinator.updateAppearance()
            }
            .onChange(of: settingsRepository.settings.themeMode) { _, _ in
                workspaceCoordinator.updateAppearance()
            }
        }
    }

    private func layoutMetrics(for totalWidth: CGFloat) -> WorkspaceLayoutMetrics {
        makeWorkspaceLayoutMetrics(
            totalWidth: totalWidth,
            isSettingsPage: workspaceCoordinator.page == .settings,
            isSidebarCollapsed: workspaceCoordinator.isSidebarCollapsed,
            isRightSidebarCollapsed: workspaceCoordinator.isRightSidebarCollapsed
        )
    }

    @ViewBuilder
    private func workspaceMainArea(theme: PromptBarTheme, metrics: WorkspaceLayoutMetrics) -> some View {
        if workspaceCoordinator.page == .settings {
            SettingsPageView(
                theme: theme,
                style: .workspace,
                newCategoryName: $workspaceCategoryDraftName,
                activeSectionID: Binding(
                    get: { panelCoordinator.selectedCategoryID },
                    set: { panelCoordinator.selectedCategoryID = $0 }
                )
            )
            .environmentObject(promptRepository)
            .environmentObject(promptLibraryRepository)
            .environmentObject(settingsRepository)
            .environmentObject(panelCoordinator)
            .environmentObject(workspaceCoordinator)
        } else {
            HStack(spacing: 0) {
                workspaceCenter(theme: theme)
                    .frame(width: metrics.centerWidth)

                if metrics.showsInnerDivider {
                    Rectangle()
                        .fill(theme.navigationDivider)
                        .frame(width: metrics.innerDividerWidth)
                }

                if metrics.showsRightSidebar {
                    PromptPanelView(style: .workspaceEmbedded)
                        .environmentObject(promptRepository)
                        .environmentObject(promptLibraryRepository)
                        .environmentObject(settingsRepository)
                        .environmentObject(permissionService)
                        .environmentObject(panelCoordinator)
                        .environmentObject(workspaceCoordinator)
                        .padding(18)
                        .frame(width: metrics.rightWidth)
                        .background(theme.mode == .breezyDay ? Color.clear : theme.background)
                        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                .simultaneousGesture(
                    TapGesture().onEnded {
                        workspaceCoordinator.requestLibrarySearchDismissal()
                    }
                )
                }
            }
        }
    }

    private func workspaceSidebarControlRail(theme: PromptBarTheme) -> some View {
        VStack {
            HStack {
                workspaceSidebarToggleButton(theme: theme, isCollapsed: workspaceCoordinator.isSidebarCollapsed)
                Spacer(minLength: 0)
            }
            .padding(.top, 20)
            .padding(.leading, 12)

            Spacer(minLength: 0)
        }
    }

    private func workspaceRightControlRail(theme: PromptBarTheme) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                workspaceRightSidebarToggleButton(theme: theme)
            }
            .padding(.top, 20)
            .padding(.trailing, 12)

            Spacer(minLength: 0)
        }
    }

    private func workspaceSidebar(theme: PromptBarTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
                .frame(height: 56)

            WorkspaceNavigationItem(
                title: "提示词库",
                isSelected: workspaceCoordinator.page == .promptLibrary,
                theme: theme
            ) {
                workspaceCoordinator.setPage(.promptLibrary)
            } onHoverSelection: {
                guard workspaceCoordinator.page != .promptLibrary else { return }
                workspaceCoordinator.setPage(.promptLibrary)
            }

            Spacer(minLength: 0)

            Button {
                workspaceCoordinator.toggleSettingsPage()
            } label: {
                BearSettingsLabel(theme: theme)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .simultaneousGesture(
            TapGesture().onEnded {
                workspaceCoordinator.requestLibrarySearchDismissal()
            }
        )
    }

    private func workspaceSidebarToggleButton(theme: PromptBarTheme, isCollapsed: Bool) -> some View {
        Button {
            workspaceCoordinator.requestLibrarySearchDismissal()
            workspaceCoordinator.toggleSidebarCollapsed()
        } label: {
            Image(systemName: isCollapsed ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(theme.surface.opacity(theme.isDark ? 0.75 : 0.88))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func workspaceRightSidebarToggleButton(theme: PromptBarTheme) -> some View {
        Button {
            workspaceCoordinator.requestLibrarySearchDismissal()
            workspaceCoordinator.toggleRightSidebarCollapsed()
        } label: {
            Image(systemName: "sidebar.trailing")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 34, height: 34)
                .background(theme.surface.opacity(theme.isDark ? 0.75 : 0.88))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func workspaceCenter(theme: PromptBarTheme) -> some View {
        switch workspaceCoordinator.page {
        case .promptLibrary:
            PromptLibraryWorkspaceView(theme: theme)
                .environmentObject(promptLibraryRepository)
                .environmentObject(panelCoordinator)
        case .settings:
            EmptyView()
        }
    }

    @ViewBuilder
    private func workspaceBackground(theme: PromptBarTheme) -> some View {
        WorkspaceBackdropView(
            theme: theme,
            resolvedThemeMode: settingsRepository.settings.workspaceThemeMode.resolvedThemeMode(
                fallback: settingsRepository.settings.themeMode
            )
        )
    }

    @ViewBuilder
    private func workspacePaneBackground(theme: PromptBarTheme, tint: Color) -> some View {
        if settingsRepository.settings.workspaceGlassEnabled {
            WorkspaceGlassPaneFill(theme: theme, tint: tint)
        } else if theme.mode == .breezyDay {
            tint.opacity(0.70)
        } else {
            tint
        }
    }
}

struct WorkspaceLayoutMetrics {
    let showsLeftSidebar: Bool
    let showsRightSidebar: Bool
    let showsLeftDivider: Bool
    let showsInnerDivider: Bool
    let showsRightRail: Bool
    let leftRailWidth: CGFloat
    let rightRailWidth: CGFloat
    let leftDividerWidth: CGFloat
    let innerDividerWidth: CGFloat
    let leftWidth: CGFloat
    let centerWidth: CGFloat
    let rightWidth: CGFloat
    let mainAreaWidth: CGFloat
}

func makeWorkspaceLayoutMetrics(
    totalWidth: CGFloat,
    isSettingsPage: Bool,
    isSidebarCollapsed: Bool,
    isRightSidebarCollapsed: Bool
) -> WorkspaceLayoutMetrics {
    let showsLeftSidebar = !isSidebarCollapsed
    let showsRightSidebar = !isSettingsPage && !isRightSidebarCollapsed
    let leftRailWidth: CGFloat = 52
    let rightRailWidth: CGFloat = isSettingsPage ? 0 : 52
    let leftDividerWidth: CGFloat = showsLeftSidebar ? 1 : 0
    let innerDividerWidth: CGFloat = showsRightSidebar ? 1 : 0
    let availableWidth = max(totalWidth - leftRailWidth - rightRailWidth - leftDividerWidth, 0)
    let widths: (left: CGFloat, center: CGFloat, right: CGFloat) = {
        switch (showsLeftSidebar, showsRightSidebar) {
        case (true, true):
            let splitWidth = max(availableWidth - innerDividerWidth, 0)
            let unit = splitWidth / 5.0
            return (unit, unit * 2.0, unit * 2.0)
        case (false, true):
            let splitWidth = max(availableWidth - innerDividerWidth, 0)
            return (0, splitWidth / 2.0, splitWidth / 2.0)
        case (true, false):
            return (availableWidth / 3.0, availableWidth * (2.0 / 3.0), 0)
        case (false, false):
            return (0, availableWidth, 0)
        }
    }()

    let mainAreaWidth = widths.center + widths.right + innerDividerWidth
    return WorkspaceLayoutMetrics(
        showsLeftSidebar: showsLeftSidebar,
        showsRightSidebar: showsRightSidebar,
        showsLeftDivider: showsLeftSidebar,
        showsInnerDivider: showsRightSidebar,
        showsRightRail: !isSettingsPage,
        leftRailWidth: leftRailWidth,
        rightRailWidth: rightRailWidth,
        leftDividerWidth: leftDividerWidth,
        innerDividerWidth: innerDividerWidth,
        leftWidth: widths.left,
        centerWidth: widths.center,
        rightWidth: widths.right,
        mainAreaWidth: mainAreaWidth
    )
}

private struct WorkspaceNavigationItem: View {
    let title: String
    let isSelected: Bool
    let theme: PromptBarTheme
    let action: () -> Void
    let onHoverSelection: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.bodyFont(size: 16, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                onHoverSelection()
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }

    private var background: Color {
        if isSelected {
            return theme.selection
        }
        if isHovered {
            return theme.hover
        }
        return .clear
    }
}

private struct PromptLibraryWorkspaceView: View {
    let theme: PromptBarTheme

    @EnvironmentObject private var promptLibraryRepository: PromptLibraryRepository
    @EnvironmentObject private var settingsRepository: SettingsRepository
    @EnvironmentObject private var panelCoordinator: PanelCoordinator
    @EnvironmentObject private var workspaceCoordinator: WorkspaceCoordinator
    @State private var searchQuery = ""
    @State private var selectedSourceID: UUID?
    @State private var editingEntryDraft: WorkspaceLibraryEntryDraft?
    @FocusState private var isSearchFocused: Bool

    private var visibleEntries: [PromptLibraryEntry] {
        promptLibraryRepository.filteredEntries(sourceID: selectedSourceID, query: searchQuery)
    }

    private var visibleSources: [PromptLibrarySource] {
        promptLibraryRepository.visibleSources()
    }

    var body: some View {
        let entries = visibleEntries
        let sources = visibleSources
        let recycleSource = sources.first(where: promptLibraryRepository.isRecycleSource)
        let importedSources = sources.filter { !promptLibraryRepository.isRecycleSource($0) }

        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 0) {
                    Text("提示词库")
                        .font(theme.titleFont(size: 22))
                        .foregroundStyle(theme.textPrimary)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    clearSearchFocus()
                }

                Spacer(minLength: 0)

                TextField("搜索提示词库", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(theme.bodyFont(size: 14))
                    .foregroundStyle(theme.textPrimary)
                    .focused($isSearchFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        WorkspaceRoundedSurface(
                            theme: theme,
                            tint: theme.surface,
                            isGlassEnabled: settingsRepository.settings.workspaceGlassEnabled,
                            cornerRadius: 14
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .frame(width: 220)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    workspaceSourceChip(title: "全部", sourceID: nil)

                    if let recycleSource {
                        workspaceSourceChip(title: recycleSource.name, sourceID: recycleSource.id)
                    }

                    workspaceExternalLinkChip(title: "社区导航") {
                        openCommunityPortal()
                    }

                    ForEach(importedSources, id: \.id) { source in
                        workspaceSourceChip(title: source.name, sourceID: source.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                clearSearchFocus()
            }

            Divider()
                .overlay(theme.separator)
                .padding(.horizontal, 24)
                .onTapGesture {
                    clearSearchFocus()
                }

            if promptLibraryRepository.entries.isEmpty {
                WorkspaceLibraryEmptyState(theme: theme)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearSearchFocus()
                    }
            } else if entries.isEmpty {
                WorkspaceLibrarySearchEmptyState(theme: theme)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        clearSearchFocus()
                    }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(entries, id: \.id) { entry in
                            WorkspaceLibraryEntryCard(
                                theme: theme,
                                entry: entry,
                                onEdit: { beginEditing(entry) },
                                onDelete: { deleteEntry(entry) }
                            )
                                .environmentObject(workspaceCoordinator)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        clearSearchFocus()
                    }
                )
            }
        }
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    clearSearchFocus()
                }
        )
        .sheet(item: $editingEntryDraft) { draft in
            WorkspaceLibraryEntryEditorSheet(
                theme: theme,
                draft: draft,
                onCancel: {
                    editingEntryDraft = nil
                },
                onSave: { updatedDraft in
                    saveEntryDraft(updatedDraft)
                }
            )
        }
        .onChange(of: promptLibraryRepository.visibleSources().map(\.id)) { _, sourceIDs in
            guard let selectedSourceID else { return }
            if !sourceIDs.contains(selectedSourceID) {
                self.selectedSourceID = nil
            }
        }
        .onChange(of: workspaceCoordinator.librarySearchDismissalToken) { _, _ in
            clearSearchFocus()
        }
        .onExitCommand {
            clearSearchFocus()
        }
        .onDisappear {
            clearSearchFocus()
            workspaceCoordinator.hoveredLibraryEntryID = nil
        }
    }

    private func beginEditing(_ entry: PromptLibraryEntry) {
        editingEntryDraft = WorkspaceLibraryEntryDraft(
            id: entry.id,
            title: entry.title,
            content: entry.content,
            groupName: entry.groupName ?? ""
        )
    }

    private func saveEntryDraft(_ draft: WorkspaceLibraryEntryDraft) {
        do {
            try promptLibraryRepository.updateEntry(
                id: draft.id,
                title: draft.title,
                content: draft.content,
                groupName: draft.groupName
            )
            editingEntryDraft = nil
        } catch {
            // Keep the editor open on failure.
        }
    }

    private func deleteEntry(_ entry: PromptLibraryEntry) {
        if workspaceCoordinator.hoveredLibraryEntryID == entry.id {
            workspaceCoordinator.hoveredLibraryEntryID = nil
        }
        try? promptLibraryRepository.deleteEntry(id: entry.id)
    }

    private func workspaceSourceChip(title: String, sourceID: UUID?) -> some View {
        let isSelected = selectedSourceID == sourceID

        return Button {
            clearSearchFocus()
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSourceID = sourceID
            }
        } label: {
            Text(title)
                .font(theme.bodyFont(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? theme.selection : theme.hover.opacity(0.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func workspaceExternalLinkChip(title: String, action: @escaping () -> Void) -> some View {
        Button {
            clearSearchFocus()
            action()
        } label: {
            Text(title)
                .font(theme.bodyFont(size: 14, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.hover.opacity(0.45))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func clearSearchFocus() {
        isSearchFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func openCommunityPortal() {
        guard let url = resolvedCommunityPortalURL() else {
            panelCoordinator.showToast("社区导航页面不存在")
            return
        }

        if NSWorkspace.shared.open(url) == false {
            panelCoordinator.showToast("打开社区导航失败")
        }
    }

    private func resolvedCommunityPortalURL() -> URL? {
        let fileManager = FileManager.default
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidates = [
            currentDirectory.appendingPathComponent("PromptBarWeb/index.html"),
            currentDirectory.deletingLastPathComponent().appendingPathComponent("PromptBarWeb/index.html"),
            sourceDerivedCommunityPortalURL()
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func sourceDerivedCommunityPortalURL() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url.appendingPathComponent("PromptBarWeb/index.html")
    }
}

private struct WorkspaceLibraryEntryCard: View {
    let theme: PromptBarTheme
    let entry: PromptLibraryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var settingsRepository: SettingsRepository
    @EnvironmentObject private var workspaceCoordinator: WorkspaceCoordinator
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.title)
                    .font(theme.bodyFont(size: 18, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let sourceName = entry.source?.name {
                    Text(sourceName)
                        .font(theme.bodyFont(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
            }

            if let groupName = entry.groupName, !groupName.isEmpty {
                Text(groupName)
                    .font(theme.bodyFont(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }

            Text(entry.content)
                .font(theme.bodyFont(size: 14))
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .lineLimit(3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            WorkspaceRoundedSurface(
                theme: theme,
                tint: isHovered ? theme.selection : theme.surface,
                isGlassEnabled: settingsRepository.settings.workspaceGlassEnabled,
                cornerRadius: 18
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.outline.opacity(0.45), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                workspaceCoordinator.hoveredLibraryEntryID = entry.id
            } else if workspaceCoordinator.hoveredLibraryEntryID == entry.id {
                workspaceCoordinator.hoveredLibraryEntryID = nil
            }
        }
        .onDrag {
            let provider = NSItemProvider()
            let data = Data(entry.id.uuidString.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.promptBarLibraryEntry.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }
        .contextMenu {
            Button("编辑") {
                onEdit()
            }
            Button("删除", role: .destructive) {
                onDelete()
            }
        }
    }
}

private struct WorkspaceLibraryEntryDraft: Identifiable {
    let id: UUID
    var title: String
    var content: String
    var groupName: String
}

private struct WorkspaceLibraryEntryEditorSheet: View {
    private enum Field {
        case title
        case groupName
        case content
    }

    let theme: PromptBarTheme
    @State var draft: WorkspaceLibraryEntryDraft
    let onCancel: () -> Void
    let onSave: (WorkspaceLibraryEntryDraft) -> Void
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑提示词库条目")
                .font(theme.titleFont(size: 20))
                .foregroundStyle(theme.textPrimary)

            workspaceEditorField(title: "标题") {
                TextField("请输入标题", text: $draft.title)
                    .textFieldStyle(.plain)
                    .font(theme.bodyFont(size: 15))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .focused($focusedField, equals: .title)
            }

            workspaceEditorField(title: "分组名") {
                TextField("可选", text: $draft.groupName)
                    .textFieldStyle(.plain)
                    .font(theme.bodyFont(size: 14))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .focused($focusedField, equals: .groupName)
            }

            workspaceEditorField(title: "内容") {
                TextEditor(text: $draft.content)
                    .font(theme.bodyFont(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .focused($focusedField, equals: .content)
            }

            HStack {
                Spacer(minLength: 0)

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .font(theme.bodyFont(size: 14))

                Button("保存") {
                    onSave(draft)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSave ? theme.textPrimary : theme.textTertiary)
                .font(theme.bodyFont(size: 14, weight: .semibold))
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(theme.background)
        .onPasteCommand(of: [.plainText]) { _ in
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
            switch focusedField {
            case .title:
                draft.title += text
            case .groupName:
                draft.groupName += text
            case .content, .none:
                draft.content += text
            }
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func workspaceEditorField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(theme.bodyFont(size: 14, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            content()
        }
    }
}

private struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragStripView {
        WindowDragStripView()
    }

    func updateNSView(_ nsView: WindowDragStripView, context: Context) {}
}

private final class WindowDragStripView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct WorkspaceLibraryEmptyState: View {
    let theme: PromptBarTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("还没有导入提示词库")
                .font(theme.bodyFont(size: 26, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("到设置里的“导入提示词库”把 JSON 或 CSV 提示词库带进来。之后可以直接拖到右栏的小 UI。")
                .font(theme.bodyFont(size: 15))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: 420, alignment: .leading)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
    }
}

private struct WorkspaceLibrarySearchEmptyState: View {
    let theme: PromptBarTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text("没有匹配的库条目")
                .font(theme.bodyFont(size: 22, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("换个关键词，或者切换来源筛选试试看。")
                .font(theme.bodyFont(size: 14))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 24)
    }
}

private struct WorkspaceBackdropView: View {
    let theme: PromptBarTheme
    let resolvedThemeMode: ThemeMode

    @EnvironmentObject private var workspaceCoordinator: WorkspaceCoordinator

    var body: some View {
        ZStack {
            theme.background

            if resolvedThemeMode == .breezyDay {
                BreezyDayBackground(
                    theme: theme,
                    isCompact: false,
                    isPaused: !workspaceCoordinator.isPresented
                )
                    .transition(.opacity.animation(.easeInOut(duration: 0.28)))
            } else if resolvedThemeMode == .solitudeBlue {
                SolitudeBlueSceneBackground(
                    theme: theme,
                    isPaused: !workspaceCoordinator.isPresented
                )
                    .transition(.opacity.animation(.easeInOut(duration: 0.24)))
            } else if theme.isDark {
                GalaxyBackground(theme: theme, isActive: workspaceCoordinator.isPresented)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }

            if resolvedThemeMode != .breezyDay {
                WorkspaceAtmosphereOverlay(theme: theme, isBlueMode: resolvedThemeMode == .solitudeBlue)
            }
        }
        .ignoresSafeArea()
        .clipped()
    }
}

private struct WorkspaceAtmosphereOverlay: View {
    let theme: PromptBarTheme
    let isBlueMode: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    theme.galaxyGlow.opacity(isBlueMode ? 0.24 : 0.08),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 340
            )
            .blendMode(.screen)

            LinearGradient(
                colors: [
                    .clear,
                    theme.galaxySecondary.opacity(isBlueMode ? 0.08 : 0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

private struct SolitudeBlueSceneBackground: View {
    let theme: PromptBarTheme
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stars: [WorkspaceStar] = [
        .init(x: 0.12, y: 0.14, size: 2.2, twinkleSpeed: 0.17),
        .init(x: 0.22, y: 0.08, size: 1.8, twinkleSpeed: 0.12),
        .init(x: 0.34, y: 0.18, size: 1.6, twinkleSpeed: 0.09),
        .init(x: 0.48, y: 0.11, size: 2.1, twinkleSpeed: 0.15),
        .init(x: 0.61, y: 0.16, size: 1.5, twinkleSpeed: 0.11),
        .init(x: 0.74, y: 0.09, size: 2.3, twinkleSpeed: 0.19),
        .init(x: 0.84, y: 0.13, size: 1.7, twinkleSpeed: 0.10),
        .init(x: 0.90, y: 0.20, size: 1.5, twinkleSpeed: 0.14)
    ]

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 15.0, paused: reduceMotion || isPaused)
        ) { context in
            let t = reduceMotion || isPaused ? 0 : context.date.timeIntervalSinceReferenceDate

            GeometryReader { geometry in
                let size = geometry.size
                let breeze = sin(t * 0.18)
                let fogDrift = CGFloat(sin(t * 0.05)) * 16

                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.070, blue: 0.130),
                            Color(red: 0.060, green: 0.118, blue: 0.214),
                            Color(red: 0.102, green: 0.175, blue: 0.290)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Ellipse()
                        .fill(theme.galaxyPrimary)
                        .frame(width: size.width * 0.52, height: size.height * 0.30)
                        .blur(radius: 54)
                        .offset(x: -size.width * 0.16 + fogDrift, y: -size.height * 0.18)

                    Ellipse()
                        .fill(theme.galaxySecondary)
                        .frame(width: size.width * 0.44, height: size.height * 0.24)
                        .blur(radius: 46)
                        .offset(x: size.width * 0.20 - fogDrift * 0.7, y: -size.height * 0.02)

                    Circle()
                        .fill(Color(red: 0.91, green: 0.96, blue: 1.00).opacity(0.18))
                        .frame(width: 128, height: 128)
                        .blur(radius: 2)
                        .offset(x: size.width * 0.24, y: -size.height * 0.24)

                    Circle()
                        .fill(Color(red: 0.92, green: 0.97, blue: 1.00).opacity(0.09))
                        .frame(width: 240, height: 240)
                        .blur(radius: 32)
                        .offset(x: size.width * 0.24, y: -size.height * 0.24)

                    ForEach(stars) { star in
                        Circle()
                            .fill(Color.white.opacity(0.36 + 0.24 * sin(t * star.twinkleSpeed * 8)))
                            .frame(width: star.size, height: star.size)
                            .shadow(color: theme.galaxyGlow.opacity(0.45), radius: 6)
                            .position(x: size.width * star.x, y: size.height * star.y)
                    }

                    Ellipse()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: size.width * 0.52, height: size.height * 0.14)
                        .blur(radius: 12)
                        .offset(x: -size.width * 0.10, y: size.height * 0.34)

                    Ellipse()
                        .fill(Color(red: 0.05, green: 0.10, blue: 0.16).opacity(0.86))
                        .frame(width: size.width * 0.78, height: size.height * 0.18)
                        .offset(x: 0, y: size.height * 0.38)

                    WorkspaceFigureSilhouette()
                        .fill(Color(red: 0.76, green: 0.86, blue: 0.98).opacity(0.40))
                        .frame(width: 26, height: 60)
                        .offset(x: -size.width * 0.16, y: size.height * 0.30)

                    ForEach(0..<34, id: \.self) { index in
                        let x = size.width * CGFloat(index) / 33.0
                        let height = 20 + CGFloat(index % 6) * 6
                        let sway = sin(t * 0.85 + Double(index) * 0.42) * (1.8 + breeze * 1.4)

                        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                            .fill(Color(red: 0.58, green: 0.75, blue: 0.72).opacity(0.32))
                            .frame(width: 2.1, height: height)
                            .rotationEffect(.degrees(sway), anchor: .bottom)
                            .position(x: x, y: size.height - height * 0.26)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct WorkspaceGlassPaneFill: View {
    let theme: PromptBarTheme
    let tint: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Rectangle()
                .fill(tint.opacity(theme.isDark ? 0.56 : 0.72))
        }
    }
}

private struct WorkspaceRoundedSurface: View {
    let theme: PromptBarTheme
    let tint: Color
    let isGlassEnabled: Bool
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if isGlassEnabled {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(theme.isDark ? 0.58 : 0.78))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            }
        }
    }
}

private struct WorkspaceFigureSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let head = CGRect(x: rect.midX - rect.width * 0.16, y: rect.minY, width: rect.width * 0.32, height: rect.height * 0.22)
        path.addEllipse(in: head)

        let body = RoundedRectangle(cornerRadius: rect.width * 0.14, style: .continuous)
        path.addPath(body.path(in: CGRect(x: rect.midX - rect.width * 0.12, y: rect.minY + rect.height * 0.18, width: rect.width * 0.24, height: rect.height * 0.42)))
        path.addPath(body.path(in: CGRect(x: rect.midX - rect.width * 0.26, y: rect.minY + rect.height * 0.24, width: rect.width * 0.16, height: rect.height * 0.26)))
        path.addPath(body.path(in: CGRect(x: rect.midX + rect.width * 0.10, y: rect.minY + rect.height * 0.24, width: rect.width * 0.16, height: rect.height * 0.26)))
        path.addPath(body.path(in: CGRect(x: rect.midX - rect.width * 0.18, y: rect.minY + rect.height * 0.54, width: rect.width * 0.14, height: rect.height * 0.28)))
        path.addPath(body.path(in: CGRect(x: rect.midX + rect.width * 0.04, y: rect.minY + rect.height * 0.54, width: rect.width * 0.14, height: rect.height * 0.28)))
        return path
    }
}

private struct WorkspaceStar: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let twinkleSpeed: Double
}

extension UTType {
    static let promptBarLibraryEntry = UTType(exportedAs: "com.promptbar.library-entry")
}
