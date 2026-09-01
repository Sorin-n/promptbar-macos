import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum PromptBarMotion {
    static let interactive = Animation.easeInOut(duration: 0.18)
    static let bear = Animation.easeInOut(duration: 0.22)
    static let listFade = Animation.easeInOut(duration: 0.16)
    static let galaxy = Animation.easeInOut(duration: 4.8)
}

public enum PromptPanelDisplayStyle {
    case panel
    case workspaceEmbedded
}

public struct PromptPanelView: View {
    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var promptLibraryRepository: PromptLibraryRepository
    @EnvironmentObject private var settingsRepository: SettingsRepository
    @EnvironmentObject private var permissionService: PermissionService
    @EnvironmentObject private var panelCoordinator: PanelCoordinator
    @EnvironmentObject private var workspaceCoordinator: WorkspaceCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var newMainCategoryName = ""
    @State private var newSecondaryCategoryName = ""
    @State private var isCreatingMainCategory = false
    @State private var isCreatingSecondaryCategory = false
    @State private var draggingMainCategoryID: UUID?
    @State private var dropMainCategoryID: UUID?
    @State private var draggingSecondaryCategoryID: UUID?
    @State private var dropSecondaryCategoryID: UUID?
    @State private var isLibraryImportTargeted = false
    private let style: PromptPanelDisplayStyle

    private var isWorkspaceEmbeddedStyle: Bool {
        style == .workspaceEmbedded
    }

    private var isSecondaryNavigationEnabled: Bool {
        settingsRepository.settings.isSecondaryNavigationEnabled
    }

    private var isOverlayPresented: Bool {
        panelCoordinator.isPromptEditorPresented || panelCoordinator.isSearchPresented
    }

    public init(style: PromptPanelDisplayStyle = .panel) {
        self.style = style
    }

    public var body: some View {
        let theme = isWorkspaceEmbeddedStyle
            ? PromptBarTheme.resolveWorkspace(
                workspaceMode: settingsRepository.settings.workspaceThemeMode,
                primaryMode: settingsRepository.settings.themeMode,
                fontMode: settingsRepository.settings.fontMode,
                systemScheme: colorScheme
            )
            : PromptBarTheme.resolve(
                for: settingsRepository.settings.themeMode,
                fontMode: settingsRepository.settings.fontMode,
                systemScheme: colorScheme
            )

        ZStack {
            panelBackground(theme: theme)
                .overlay {
                    if settingsRepository.settings.themeMode == .solitudeBlue && !isWorkspaceEmbeddedStyle {
                        CompactSolitudeBlueBackground(theme: theme)
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    } else if theme.isDark && !isWorkspaceEmbeddedStyle {
                        GalaxyBackground(theme: theme)
                            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    }
                }

            content(theme: theme)
            .allowsHitTesting(!isOverlayPresented)

            if panelCoordinator.isSearchPresented {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.16)))

                SearchOverlay(theme: theme)
                    .environmentObject(promptRepository)
                    .environmentObject(panelCoordinator)
                    .transition(.opacity.animation(.easeInOut(duration: 0.16)))
            }

            if panelCoordinator.isPromptEditorPresented {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.16)))

                PromptEditorOverlay(theme: theme)
                    .environmentObject(promptRepository)
                    .environmentObject(panelCoordinator)
                    .transition(.opacity.animation(.easeInOut(duration: 0.16)))
            }

            if style == .panel && isCreatingMainCategory {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.16)))
                    .onTapGesture {
                        cancelTopLevelCategoryCreation()
                    }

                CategoryCreationOverlay(
                    theme: theme,
                    text: $newMainCategoryName,
                    onCancel: { cancelTopLevelCategoryCreation() },
                    onConfirm: { commitTopLevelCategory() }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.16)))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(containerOutline(theme: theme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .preferredColorScheme(preferredColorScheme)
        .modifier(CompactPromptFrameModifier(style: style))
        .onAppear {
            syncActiveMainCategory()
            syncActiveSecondaryCategory()
            panelCoordinator.updateAppearance()
        }
        .onChange(of: mainCategories.map(\.id)) { _, _ in
            syncActiveMainCategory()
        }
        .onChange(of: panelCoordinator.selectedCategoryID) { _, _ in
            syncActiveSecondaryCategory()
            resetSecondaryDraftState()
        }
        .onChange(of: visibleSecondaryCategories.map(\.id)) { _, _ in
            syncActiveSecondaryCategory()
        }
        .onChange(of: panelCoordinator.panelPage) { _, _ in
            resetDraftStates()
        }
        .onChange(of: isSecondaryNavigationEnabled) { _, enabled in
            if !enabled {
                isCreatingSecondaryCategory = false
                newSecondaryCategoryName = ""
            } else {
                syncActiveSecondaryCategory()
            }
        }
        .onChange(of: settingsRepository.settings.themeMode) { _, _ in
            panelCoordinator.updateAppearance()
        }
        .onDrop(
            of: [UTType.promptBarLibraryEntry],
            isTargeted: $isLibraryImportTargeted,
            perform: importLibraryEntries
        )
    }

    private var mainCategories: [PromptCategory] {
        promptRepository.visibleCategories()
    }

    private var activeMainCategoryBinding: Binding<UUID?> {
        Binding(
            get: { panelCoordinator.selectedCategoryID },
            set: { panelCoordinator.selectedCategoryID = $0 }
        )
    }

    private var activeSecondaryCategoryBinding: Binding<UUID?> {
        Binding(
            get: { panelCoordinator.selectedTagID },
            set: { panelCoordinator.selectedTagID = $0 }
        )
    }

    private var activeMainCategory: PromptCategory? {
        mainCategories.first(where: { $0.id == panelCoordinator.selectedCategoryID }) ?? mainCategories.first
    }

    private var visibleSecondaryCategories: [PromptSecondaryCategory] {
        promptRepository.visibleSecondaryCategories(in: panelCoordinator.selectedCategoryID)
    }

    private var activeSecondaryCategory: PromptSecondaryCategory? {
        visibleSecondaryCategories.first(where: { $0.id == panelCoordinator.selectedTagID }) ?? visibleSecondaryCategories.first
    }

    private func syncActiveMainCategory() {
        let categories = mainCategories
        if let selectedCategoryID = panelCoordinator.selectedCategoryID, categories.contains(where: { $0.id == selectedCategoryID }) {
            return
        }
        panelCoordinator.selectedCategoryID = categories.first?.id
    }

    private func syncActiveSecondaryCategory() {
        let categoryIDs = Set(visibleSecondaryCategories.map(\.id))
        if let selectedTagID = panelCoordinator.selectedTagID, categoryIDs.contains(selectedTagID) {
            return
        }
        panelCoordinator.selectedTagID = visibleSecondaryCategories.first?.id
    }

    private func sidebar(theme: PromptBarTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MainCategoryList(
                categories: mainCategories,
                activeCategoryID: activeMainCategoryBinding,
                draggingCategoryID: $draggingMainCategoryID,
                dropTargetCategoryID: $dropMainCategoryID,
                isCreatingCategory: $isCreatingMainCategory,
                draftName: $newMainCategoryName,
                theme: theme
            )
            .environmentObject(promptRepository)
            .frame(maxHeight: .infinity)

            if style == .panel {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        panelCoordinator.toggleSettingsPage()
                    }
                } label: {
                    BearSettingsLabel(theme: theme)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 84)
        .background(sidebarBackground(theme: theme))
        .overlay(alignment: .top) {
            if shouldBlendTopBand {
                theme.surface
                    .frame(height: 56)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.navigationDivider)
                .frame(width: 1)
                .padding(.top, shouldHideTopNavigationDivider ? 56 : 0)
        }
    }

    private var shouldHideTopNavigationDivider: Bool {
        themeUsesSurfaceHeaderBand
    }

    private var shouldBlendTopBand: Bool {
        themeUsesSurfaceHeaderBand
    }

    @ViewBuilder
    private func content(theme: PromptBarTheme) -> some View {
        switch panelCoordinator.panelPage {
        case .library:
            VStack(spacing: 0) {
                libraryHeader(theme: theme)

                if mainCategories.isEmpty {
                    EmptyLibraryState(theme: theme)
                } else {
                    if isWorkspaceEmbeddedStyle || style == .panel {
                        VStack(spacing: 0) {
                            topNavigationBars(theme: theme)

                            PromptListView(
                                theme: theme,
                                mainCategoryID: panelCoordinator.selectedCategoryID,
                                secondaryCategoryID: isSecondaryNavigationEnabled ? panelCoordinator.selectedTagID : nil,
                                isSecondaryNavigationEnabled: isSecondaryNavigationEnabled,
                                onCreatePrompt: presentPromptCreation
                            )
                            .environmentObject(promptRepository)
                            .environmentObject(panelCoordinator)
                        }
                    } else {
                        HStack(spacing: 0) {
                            if isSecondaryNavigationEnabled {
                                SecondaryCategoryColumn(
                                    categories: visibleSecondaryCategories,
                                    activeCategoryID: activeSecondaryCategoryBinding,
                                    draggingCategoryID: $draggingSecondaryCategoryID,
                                    dropTargetCategoryID: $dropSecondaryCategoryID,
                                    isCreatingCategory: $isCreatingSecondaryCategory,
                                    draftName: $newSecondaryCategoryName,
                                    mainCategory: activeMainCategory,
                                    theme: theme,
                                    usesWorkspaceEmbeddedBackground: isWorkspaceEmbeddedStyle
                                )
                                .environmentObject(promptRepository)
                                .environmentObject(panelCoordinator)
                            }

                            PromptListView(
                                theme: theme,
                                mainCategoryID: panelCoordinator.selectedCategoryID,
                                secondaryCategoryID: isSecondaryNavigationEnabled ? panelCoordinator.selectedTagID : nil,
                                isSecondaryNavigationEnabled: isSecondaryNavigationEnabled,
                                onCreatePrompt: presentPromptCreation
                            )
                            .environmentObject(promptRepository)
                            .environmentObject(panelCoordinator)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                resetDraftStates()
            }
            .contextMenu {
                if style == .panel {
                    Button("新建分类") {
                        beginCreatingTopLevelCategory()
                    }
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.16)))
        case .settings:
            SettingsPageView(
                theme: theme,
                style: style == .panel ? .compact : .workspace,
                newCategoryName: $newMainCategoryName,
                activeSectionID: activeMainCategoryBinding
            )
            .environmentObject(promptRepository)
            .environmentObject(promptLibraryRepository)
            .environmentObject(settingsRepository)
            .environmentObject(panelCoordinator)
            .environmentObject(workspaceCoordinator)
            .contentShape(Rectangle())
            .onTapGesture {
                resetDraftStates()
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.16)))
        }
    }

    private func libraryHeader(theme: PromptBarTheme) -> some View {
        HStack(spacing: 18) {
            if isWorkspaceEmbeddedStyle {
                HStack(spacing: 10) {
                    Text("Prompt Library")
                        .font(theme.titleFont(size: 20))
                        .foregroundStyle(theme.textPrimary)

                    workspaceToggleButton(theme: theme)
                }
            } else {
                Text("Prompt Library")
                    .font(theme.titleFont(size: 20))
                    .foregroundStyle(theme.textPrimary)
            }

            Spacer()

            Button {
                panelCoordinator.openSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(theme.textPrimary)
            }
            .buttonStyle(.plain)

            Button(action: presentPromptCreation) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(theme.textPrimary)
            }
            .buttonStyle(.plain)

            if !isWorkspaceEmbeddedStyle {
                workspaceToggleButton(theme: theme)

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        panelCoordinator.toggleSettingsPage()
                    }
                } label: {
                    Text("设置")
                        .font(theme.bodyFont(size: 14))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(headerBackground(theme: theme))
        .overlay(alignment: .bottom) {
            if theme.headerUsesSurfaceBand {
                Rectangle()
                    .fill(theme.separator)
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func headerBackground(theme: PromptBarTheme) -> some View {
        if isWorkspaceEmbeddedStyle {
            Color.clear
        } else if theme.headerUsesSurfaceBand {
            theme.surface
        } else {
            Color.clear
        }
    }

    private func sidebarBackground(theme: PromptBarTheme) -> Color {
        if isWorkspaceEmbeddedStyle {
            return theme.background
        }
        return theme.sidebarBackground
    }

    private func secondarySidebarBackground(theme: PromptBarTheme) -> Color {
        if isWorkspaceEmbeddedStyle {
            return theme.background
        }
        return theme.secondarySidebarBackground
    }

    private func containerOutline(theme: PromptBarTheme) -> Color {
        if isWorkspaceEmbeddedStyle {
            return theme.navigationDivider.opacity(theme.isDark ? 0.55 : 0.65)
        }
        return theme.outline
    }

    private var preferredColorScheme: ColorScheme? {
        if isWorkspaceEmbeddedStyle {
            settingsRepository.settings.workspaceThemeMode.preferredColorScheme
                ?? settingsRepository.settings.themeMode.preferredColorScheme
        } else {
            settingsRepository.settings.themeMode.preferredColorScheme
        }
    }

    private var themeUsesSurfaceHeaderBand: Bool {
        settingsRepository.settings.themeMode == .softRose && !isWorkspaceEmbeddedStyle
    }

    @ViewBuilder
    private func panelBackground(theme: PromptBarTheme) -> some View {
        if isWorkspaceEmbeddedStyle && settingsRepository.settings.workspaceGlassEnabled {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.surface.opacity(theme.isDark ? 0.42 : 0.74))
            }
        } else {
            theme.background
        }
    }

    private func presentPromptCreation() {
        if let activeMainCategoryID = panelCoordinator.selectedCategoryID {
            if isSecondaryNavigationEnabled {
                guard let activeSecondaryCategoryID = panelCoordinator.selectedTagID else {
                    panelCoordinator.showToast("请先创建并选择次级导航")
                    return
                }
                panelCoordinator.promptCreation(mainCategoryID: activeMainCategoryID, secondaryCategoryID: activeSecondaryCategoryID)
            } else {
                panelCoordinator.promptCreation(mainCategoryID: activeMainCategoryID, secondaryCategoryID: nil)
            }
        } else {
            panelCoordinator.showToast("请先创建并选择主导航")
        }
    }

    private func resetDraftStates() {
        isCreatingMainCategory = false
        newMainCategoryName = ""
        resetSecondaryDraftState()
    }

    private func resetSecondaryDraftState() {
        isCreatingSecondaryCategory = false
        newSecondaryCategoryName = ""
    }

    @ViewBuilder
    private func topNavigationBars(theme: PromptBarTheme) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HorizontalNavigationStrip(
                    titles: mainCategories.map(\.name),
                    selectedID: panelCoordinator.selectedCategoryID,
                    ids: mainCategories.map(\.id),
                    theme: theme,
                    onDelete: style == .panel ? { categoryID in
                        deleteTopLevelCategory(categoryID)
                    } : nil
                ) { categoryID in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        panelCoordinator.selectedCategoryID = categoryID
                    }
                }
                .contentShape(Rectangle())
                .contextMenu {
                    if style == .panel {
                        Button("新建分类") {
                            beginCreatingTopLevelCategory()
                        }
                    }
                }
            }

            if isSecondaryNavigationEnabled && !visibleSecondaryCategories.isEmpty {
                Rectangle()
                    .fill(theme.separator)
                    .frame(height: 1)

                HorizontalNavigationStrip(
                    titles: visibleSecondaryCategories.map(\.name),
                    selectedID: panelCoordinator.selectedTagID,
                    ids: visibleSecondaryCategories.map(\.id),
                    theme: theme,
                    onDelete: style == .panel ? { categoryID in
                        deleteTopSecondaryCategory(categoryID)
                    } : nil
                ) { categoryID in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        panelCoordinator.selectedTagID = categoryID
                    }
                }
            }

            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)
        }
        .background(theme.background)
    }

    private func beginCreatingTopLevelCategory() {
        guard style == .panel else { return }
        newMainCategoryName = ""
        isCreatingMainCategory = true
    }

    private func cancelTopLevelCategoryCreation() {
        isCreatingMainCategory = false
        newMainCategoryName = ""
    }

    private func commitTopLevelCategory() {
        let beforeIDs = mainCategories.map(\.id)
        try? promptRepository.createMainCategory(named: newMainCategoryName)
        let afterCategories = promptRepository.visibleCategories()
        if afterCategories.map(\.id) != beforeIDs {
            panelCoordinator.selectedCategoryID = afterCategories.last?.id
            newMainCategoryName = ""
            isCreatingMainCategory = false
        } else {
            panelCoordinator.showToast("分类名称不能为空或重复")
        }
    }

    private func deleteTopLevelCategory(_ categoryID: UUID) {
        try? promptRepository.deleteMainCategoryAndArchiveContent(id: categoryID)
        if panelCoordinator.selectedCategoryID == categoryID {
            syncActiveMainCategory()
        }
        syncActiveSecondaryCategory()
    }

    private func deleteTopSecondaryCategory(_ categoryID: UUID) {
        try? promptRepository.deleteSecondaryCategoryAndArchiveContent(id: categoryID)
        if panelCoordinator.selectedTagID == categoryID {
            syncActiveSecondaryCategory()
        }
    }

    @ViewBuilder
    private func workspaceToggleButton(theme: PromptBarTheme) -> some View {
        let iconName = style == .panel ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        Button {
            if style == .panel {
                workspaceCoordinator.showWorkspace()
            } else {
                workspaceCoordinator.hideWorkspaceToPanel()
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func importLibraryEntries(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.promptBarLibraryEntry.identifier) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.promptBarLibraryEntry.identifier) { data, _ in
            guard
                let data,
                let identifier = String(data: data, encoding: .utf8),
                let entryID = UUID(uuidString: identifier)
            else {
                return
            }

            Task { @MainActor in
                guard let mainCategoryID = panelCoordinator.selectedCategoryID else {
                    panelCoordinator.showToast("请先创建并选择主导航")
                    return
                }

                let secondaryCategoryID = isSecondaryNavigationEnabled ? panelCoordinator.selectedTagID : nil
                if isSecondaryNavigationEnabled && secondaryCategoryID == nil {
                    panelCoordinator.showToast("请先创建并选择次级导航")
                    return
                }

                guard let entry = promptLibraryRepository.entry(id: entryID) else {
                    panelCoordinator.showToast("找不到拖拽的提示词")
                    return
                }

                if promptRepository.containsPrompt(
                    title: entry.title,
                    content: entry.content,
                    mainCategoryID: mainCategoryID,
                    secondaryCategoryID: secondaryCategoryID
                ) {
                    panelCoordinator.showToast("当前分类中已存在相同提示词")
                    return
                }

                panelCoordinator.openLibrary()

                try? promptRepository.createPrompt(
                    from: PromptDraft(title: entry.title, content: entry.content),
                    mainCategoryID: mainCategoryID,
                    secondaryCategoryID: secondaryCategoryID
                )
                panelCoordinator.showToast("已加入快捷提示词：\(entry.title)")
            }
        }

        return true
    }
}

private struct CompactPromptFrameModifier: ViewModifier {
    let style: PromptPanelDisplayStyle

    func body(content: Content) -> some View {
        switch style {
        case .panel:
            content.frame(width: 440, height: 560)
        case .workspaceEmbedded:
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MainCategoryList: View {
    let categories: [PromptCategory]
    @Binding var activeCategoryID: UUID?
    @Binding var draggingCategoryID: UUID?
    @Binding var dropTargetCategoryID: UUID?
    @Binding var isCreatingCategory: Bool
    @Binding var draftName: String
    let theme: PromptBarTheme

    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var panelCoordinator: PanelCoordinator
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                navigationStack
                    .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("新建主分类") {
                    beginCreatingCategory()
                }
            }
            .onTapGesture {
                isDraftFocused = false
                cancelDraftIfNeeded()
            }
            .onChange(of: isDraftFocused) { wasFocused, nowFocused in
                if wasFocused && !nowFocused {
                    cancelDraftIfNeeded()
                }
            }
        }
    }

    private var navigationStack: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                SidebarItem(
                    title: category.name,
                    isSelected: activeCategoryID == category.id,
                    isDropTarget: dropTargetCategoryID == category.id,
                    isDragging: draggingCategoryID == category.id,
                    theme: theme,
                    isDraggable: true
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        activeCategoryID = category.id
                    }
                } onHoverSelection: {
                    guard draggingCategoryID == nil else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        activeCategoryID = category.id
                    }
                } onDragStart: {
                    draggingCategoryID = category.id
                    dropTargetCategoryID = nil
                }
                .contextMenu {
                    Button("删除", role: .destructive) {
                        deleteMainCategory(category)
                    }
                }
                .id(category.id)
                .onDrop(
                    of: [UTType.text],
                    delegate: MainCategoryDropDelegate(
                        targetCategoryID: category.id,
                        visibleCategoryIDs: categories.map(\.id),
                        draggingCategoryID: $draggingCategoryID,
                        dropTargetCategoryID: $dropTargetCategoryID,
                        promptRepository: promptRepository
                    )
                )

                if index < categories.count - 1 || isCreatingCategory {
                    navigationDivider(theme: theme)
                }
            }

            if isCreatingCategory {
                NavigationDraftRow(theme: theme, placeholder: "新建主分类", text: $draftName)
                    .focused($isDraftFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .onSubmit {
                        commitMainCategory()
                    }
            }

            SidebarEndDropZone(theme: theme, isActive: dropTargetCategoryID == nil && draggingCategoryID != nil)
                .onDrop(
                    of: [UTType.text],
                    delegate: MainCategoryDropDelegate(
                        targetCategoryID: nil,
                        visibleCategoryIDs: categories.map(\.id),
                        draggingCategoryID: $draggingCategoryID,
                        dropTargetCategoryID: $dropTargetCategoryID,
                        promptRepository: promptRepository
                    )
                )
                .contextMenu {
                    Button("新建主分类") {
                        beginCreatingCategory()
                    }
                }
                .id("main-category-end")
        }
        .padding(.vertical, 16)
    }

    private func beginCreatingCategory() {
        draftName = ""
        isCreatingCategory = true
        DispatchQueue.main.async {
            isDraftFocused = true
        }
    }

    private func cancelDraftIfNeeded() {
        if draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isCreatingCategory = false
            draftName = ""
        }
    }

    private func commitMainCategory() {
        let beforeIDs = categories.map(\.id)
        try? promptRepository.createMainCategory(named: draftName)
        let afterCategories = promptRepository.visibleCategories()
        if afterCategories.map(\.id) != beforeIDs {
            activeCategoryID = afterCategories.last?.id
            draftName = ""
            isCreatingCategory = false
        } else {
            panelCoordinator.showToast("主分类名称不能为空或重复")
            cancelDraftIfNeeded()
        }
    }

    private func deleteMainCategory(_ category: PromptCategory) {
        try? promptRepository.deleteMainCategoryAndArchiveContent(id: category.id)
        if activeCategoryID == category.id {
            activeCategoryID = promptRepository.visibleCategories().first?.id
        }
    }
}

private struct SecondaryCategoryColumn: View {
    let categories: [PromptSecondaryCategory]
    @Binding var activeCategoryID: UUID?
    @Binding var draggingCategoryID: UUID?
    @Binding var dropTargetCategoryID: UUID?
    @Binding var isCreatingCategory: Bool
    @Binding var draftName: String
    let mainCategory: PromptCategory?
    let theme: PromptBarTheme
    let usesWorkspaceEmbeddedBackground: Bool

    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var panelCoordinator: PanelCoordinator
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                navigationStack
                    .frame(minHeight: geometry.size.height, alignment: .center)
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("新建次级分类") {
                    beginCreatingCategory()
                }
            }
            .onTapGesture {
                isDraftFocused = false
                cancelDraftIfNeeded()
            }
            .onChange(of: isDraftFocused) { wasFocused, nowFocused in
                if wasFocused && !nowFocused {
                    cancelDraftIfNeeded()
                }
            }
        }
        .frame(width: 76)
        .background(usesWorkspaceEmbeddedBackground ? theme.background : theme.secondarySidebarBackground)
        .overlay(
            Rectangle()
                .fill(theme.navigationDivider)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private var navigationStack: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                SidebarItem(
                    title: category.name,
                    isSelected: activeCategoryID == category.id,
                    isDropTarget: dropTargetCategoryID == category.id,
                    isDragging: draggingCategoryID == category.id,
                    theme: theme,
                    isDraggable: true
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        activeCategoryID = category.id
                    }
                } onHoverSelection: {
                    guard draggingCategoryID == nil else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        activeCategoryID = category.id
                    }
                } onDragStart: {
                    draggingCategoryID = category.id
                    dropTargetCategoryID = nil
                }
                .contextMenu {
                    Button("删除", role: .destructive) {
                        deleteSecondaryCategory(category)
                    }
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: SecondaryCategoryDropDelegate(
                        targetCategoryID: category.id,
                        mainCategoryID: mainCategory?.id,
                        visibleCategoryIDs: categories.map(\.id),
                        draggingCategoryID: $draggingCategoryID,
                        dropTargetCategoryID: $dropTargetCategoryID,
                        promptRepository: promptRepository
                    )
                )

                if index < categories.count - 1 || isCreatingCategory {
                    navigationDivider(theme: theme)
                }
            }

            if isCreatingCategory {
                NavigationDraftRow(theme: theme, placeholder: "新建次级分类", text: $draftName)
                    .focused($isDraftFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .onSubmit {
                        commitSecondaryCategory()
                    }
            }

            SidebarEndDropZone(theme: theme, isActive: dropTargetCategoryID == nil && draggingCategoryID != nil)
                .onDrop(
                    of: [UTType.text],
                    delegate: SecondaryCategoryDropDelegate(
                        targetCategoryID: nil,
                        mainCategoryID: mainCategory?.id,
                        visibleCategoryIDs: categories.map(\.id),
                        draggingCategoryID: $draggingCategoryID,
                        dropTargetCategoryID: $dropTargetCategoryID,
                        promptRepository: promptRepository
                    )
                )
                .contextMenu {
                    Button("新建次级分类") {
                        beginCreatingCategory()
                    }
                }
        }
        .padding(.vertical, 16)
    }

    private func beginCreatingCategory() {
        guard mainCategory != nil else { return }
        draftName = ""
        isCreatingCategory = true
        DispatchQueue.main.async {
            isDraftFocused = true
        }
    }

    private func cancelDraftIfNeeded() {
        if draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isCreatingCategory = false
            draftName = ""
        }
    }

    private func commitSecondaryCategory() {
        guard let mainCategoryID = mainCategory?.id else { return }
        let beforeIDs = categories.map(\.id)
        try? promptRepository.createSecondaryCategory(named: draftName, in: mainCategoryID)
        let afterCategories = promptRepository.visibleSecondaryCategories(in: mainCategoryID)
        if afterCategories.map(\.id) != beforeIDs {
            activeCategoryID = afterCategories.last?.id
            draftName = ""
            isCreatingCategory = false
        } else {
            panelCoordinator.showToast("次级分类名称不能为空或重复")
            cancelDraftIfNeeded()
        }
    }

    private func deleteSecondaryCategory(_ category: PromptSecondaryCategory) {
        try? promptRepository.deleteSecondaryCategoryAndArchiveContent(id: category.id)
        if activeCategoryID == category.id {
            activeCategoryID = promptRepository.visibleSecondaryCategories(in: mainCategory?.id).first?.id
        }
    }
}

private struct HorizontalNavigationStrip: View {
    let titles: [String]
    let selectedID: UUID?
    let ids: [UUID]
    let theme: PromptBarTheme
    let onDelete: ((UUID) -> Void)?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(zip(ids, titles)), id: \.0) { id, title in
                    HorizontalNavigationChip(
                        title: title,
                        isSelected: selectedID == id,
                        theme: theme,
                        onDelete: selectedID == id ? { onDelete?(id) } : nil
                    ) {
                        onSelect(id)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}

private struct HorizontalNavigationChip: View {
    let title: String
    let isSelected: Bool
    let theme: PromptBarTheme
    let onDelete: (() -> Void)?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.bodyFont(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(background)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                action()
            }
        }
        .contextMenu {
            if let onDelete {
                Button("删除", role: .destructive) {
                    onDelete()
                }
            }
        }
        .animation(.easeInOut(duration: 0.14), value: isHovered)
        .animation(.easeInOut(duration: 0.14), value: isSelected)
    }

    private var background: Color {
        if isSelected {
            return theme.selection
        }
        if isHovered {
            return theme.hover
        }
        return theme.surface.opacity(theme.isDark ? 0.28 : 0.42)
    }
}

private struct NavigationDraftRow: View {
    let theme: PromptBarTheme
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(theme.navigationFont(size: 16))
            .foregroundStyle(theme.textPrimary)
    }
}

private func navigationDivider(theme: PromptBarTheme) -> some View {
    Rectangle()
        .fill(theme.separator)
        .frame(height: 1)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
}

private struct MainCategoryDropDelegate: DropDelegate {
    let targetCategoryID: UUID?
    let visibleCategoryIDs: [UUID]
    @Binding var draggingCategoryID: UUID?
    @Binding var dropTargetCategoryID: UUID?
    let promptRepository: PromptRepository

    func validateDrop(info: DropInfo) -> Bool { draggingCategoryID != nil }

    func dropEntered(info: DropInfo) {
        guard let draggingCategoryID, draggingCategoryID != targetCategoryID else { return }
        dropTargetCategoryID = targetCategoryID
        reorder(draggingCategoryID: draggingCategoryID, targetCategoryID: targetCategoryID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetCategoryID = nil
        draggingCategoryID = nil
        return true
    }

    private func reorder(draggingCategoryID: UUID, targetCategoryID: UUID?) {
        let ids = visibleCategoryIDs
        guard let fromIndex = ids.firstIndex(of: draggingCategoryID) else { return }
        let toIndex = targetCategoryID.flatMap { ids.firstIndex(of: $0) } ?? (ids.count - 1)
        if fromIndex == toIndex { return }
        let direction = toIndex > fromIndex ? 1 : -1
        try? promptRepository.moveMainCategory(id: draggingCategoryID, direction: direction)
    }
}

private struct SecondaryCategoryDropDelegate: DropDelegate {
    let targetCategoryID: UUID?
    let mainCategoryID: UUID?
    let visibleCategoryIDs: [UUID]
    @Binding var draggingCategoryID: UUID?
    @Binding var dropTargetCategoryID: UUID?
    let promptRepository: PromptRepository

    func validateDrop(info: DropInfo) -> Bool { draggingCategoryID != nil && mainCategoryID != nil }

    func dropEntered(info: DropInfo) {
        guard let draggingCategoryID, let mainCategoryID, draggingCategoryID != targetCategoryID else { return }
        dropTargetCategoryID = targetCategoryID
        let ids = visibleCategoryIDs
        guard let fromIndex = ids.firstIndex(of: draggingCategoryID) else { return }
        let toIndex = targetCategoryID.flatMap { ids.firstIndex(of: $0) } ?? (ids.count - 1)
        if fromIndex == toIndex { return }
        let direction = toIndex > fromIndex ? 1 : -1
        try? promptRepository.moveSecondaryCategory(id: draggingCategoryID, in: mainCategoryID, direction: direction)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dropTargetCategoryID = nil
        draggingCategoryID = nil
        return true
    }
}

private struct PromptListView: View {
    let theme: PromptBarTheme
    let mainCategoryID: UUID?
    let secondaryCategoryID: UUID?
    let isSecondaryNavigationEnabled: Bool
    let onCreatePrompt: () -> Void

    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var panelCoordinator: PanelCoordinator

    private var prompts: [PromptItem] {
        filter(promptRepository.prompts)
    }

    private var promptIDs: [UUID] {
        prompts.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                listBody
            }
            .id(listIdentity)
            .background(theme.background)
            .contentShape(Rectangle())
            .contextMenu {
                Button("新建提示词") {
                    onCreatePrompt()
                }
            }
            .transition(.opacity)
            .animation(PromptBarMotion.listFade, value: listIdentity)
            .onAppear {
                panelCoordinator.setVisiblePromptIDs(promptIDs)
                scrollToSelection(proxy, animated: false)
            }
            .onChange(of: promptIDs) { _, ids in
                panelCoordinator.setVisiblePromptIDs(ids)
            }
            .onChange(of: listIdentity) { _, _ in
                scrollToSelection(proxy, animated: false)
            }
            .onChange(of: panelCoordinator.selectedPromptID) { _, _ in
                scrollToSelection(proxy, animated: true)
            }
            .background(
                ScrollWheelCaptureView { delta in
                    panelCoordinator.cycleSelection(delta: delta)
                }
            )
        }
    }

    private var listIdentity: String {
        let main = mainCategoryID?.uuidString ?? "none"
        let secondary = secondaryCategoryID?.uuidString ?? "none"
        return "\(main)-\(secondary)-\(isSecondaryNavigationEnabled)"
    }

    private var listBody: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, prompt in
                promptRow(for: prompt)

                if index < prompts.count - 1 {
                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }

            if prompts.isEmpty {
                EmptyPromptState(
                    theme: theme,
                    isSecondaryNavigationEnabled: isSecondaryNavigationEnabled
                )
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func filter(_ prompts: [PromptItem]) -> [PromptItem] {
        guard let mainCategoryID else { return [] }
        return prompts.filter { prompt in
            let mainCategoryMatch = prompt.category?.id == mainCategoryID
            let secondaryCategoryMatch = !isSecondaryNavigationEnabled || secondaryCategoryID == nil || prompt.secondaryCategory?.id == secondaryCategoryID
            return mainCategoryMatch && secondaryCategoryMatch
        }
    }

    private func metaTags(for prompt: PromptItem) -> [String] {
        []
    }

    private func promptRow(for prompt: PromptItem) -> some View {
        PromptTextRow(
            theme: theme,
            prompt: prompt,
            tags: metaTags(for: prompt),
            isSelected: prompt.id == panelCoordinator.activePromptID,
            isHovered: prompt.id == panelCoordinator.hoveredPromptID
        )
        .id(prompt.id)
        .contentShape(Rectangle())
        .onTapGesture {
            panelCoordinator.confirmPrompt(prompt)
        }
        .onHover { isHovered in
            panelCoordinator.setHoveredPrompt(isHovered ? prompt : nil)
        }
        .contextMenu {
            Button("编辑") {
                panelCoordinator.promptEditing(prompt)
            }
            Button("删除", role: .destructive) {
                try? promptRepository.deletePrompt(prompt)
            }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = panelCoordinator.selectedPromptID else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.16)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}

enum SettingsPageStyle {
    case compact
    case workspace
}

struct SettingsPageView: View {
    let theme: PromptBarTheme
    let style: SettingsPageStyle
    @Binding var newCategoryName: String
    @Binding var activeSectionID: UUID?

    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var promptLibraryRepository: PromptLibraryRepository
    @EnvironmentObject private var settingsRepository: SettingsRepository
    @EnvironmentObject private var panelCoordinator: PanelCoordinator
    @EnvironmentObject private var workspaceCoordinator: WorkspaceCoordinator
    @State private var expandedCategoryIDs: Set<UUID> = []
    @State private var recordingShortcutKind: ShortcutSettingKind?
    @State private var isImportPromptLibraryPresented = false
    @State private var isSmallUISectionExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("设置")
                    .font(theme.titleFont(size: 20))
                    .foregroundStyle(theme.textPrimary)

                Spacer(minLength: 0)

                Button {
                    panelCoordinator.openSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(theme.textPrimary)
                }
                .buttonStyle(.plain)

                workspaceToggleButton

                if style == .compact {
                    Button("返回") {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            panelCoordinator.openLibrary()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)
                    .font(theme.bodyFont(size: 14))
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .background(headerBackground)
            .overlay(alignment: .bottom) {
                if theme.headerUsesSurfaceBand {
                    Rectangle()
                        .fill(theme.separator)
                        .frame(height: 1)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionTitle("共享")
                        .padding(.top, 22)

                    toggleRow(
                        title: "导入提示词库",
                        value: "导入",
                        action: { isImportPromptLibraryPresented = true }
                    )
                    placeholderDivider
                    toggleRow(
                        title: "字体",
                        value: fontModeLabel(settingsRepository.settings.fontMode),
                        action: cycleFontMode
                    )
                    placeholderDivider
                    toggleRow(
                        title: "主题",
                        value: themeModeLabel(settingsRepository.settings.themeMode),
                        action: cycleTheme
                    )
                    placeholderDivider
                    placeholderRow("模式")
                    placeholderDivider

                    sectionTitle("大UI")
                        .padding(.top, 22)

                    toggleRow(
                        title: "大UI主题",
                        value: workspaceThemeModeLabel(settingsRepository.settings.workspaceThemeMode),
                        action: cycleWorkspaceTheme
                    )
                    placeholderDivider
                    toggleRow(
                        title: "大UI毛玻璃",
                        value: settingsRepository.settings.workspaceGlassEnabled ? "开启" : "关闭",
                        action: {
                            settingsRepository.setWorkspaceGlassEnabled(!settingsRepository.settings.workspaceGlassEnabled)
                        }
                    )
                    placeholderDivider
                    shortcutRow(
                        title: "提示词转移快捷键",
                        shortcut: settingsRepository.settings.workspaceTransferShortcut,
                        isRecording: recordingShortcutKind == .workspaceTransfer
                    ) {
                        toggleRecording(.workspaceTransfer)
                    }
                    placeholderDivider

                    sectionTitle("小UI")
                        .padding(.top, 22)

                    expandableGroupRow(
                        title: "小UI",
                        isExpanded: isSmallUISectionExpanded
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isSmallUISectionExpanded.toggle()
                        }
                    }

                    if isSmallUISectionExpanded {
                        placeholderDivider

                        sectionTitle("分类管理")
                            .padding(.top, 22)

                        ForEach(promptRepository.visibleCategories(), id: \.id) { category in
                            EditableCategorySection(
                                category: category,
                                secondaryCategories: promptRepository.visibleSecondaryCategories(in: category.id),
                                isExpanded: expandedCategoryIDs.contains(category.id),
                                theme: theme,
                                onNameChange: { commitName in
                                    renameCategory(category, to: commitName)
                                },
                                onSecondaryNameChange: { secondaryCategory, commitName in
                                    renameSecondaryCategory(secondaryCategory, to: commitName)
                                },
                                onToggleExpand: {
                                    toggleExpandedCategory(category.id)
                                },
                                onDelete: {
                                    deleteCategory(category)
                                },
                                onDeleteSecondaryCategory: { secondaryCategory in
                                    deleteSecondaryCategory(secondaryCategory)
                                }
                            )
                            Rectangle()
                                .fill(theme.separator)
                                .frame(height: 1)
                        }

                        HStack(spacing: 12) {
                            TextField("新增分类", text: $newCategoryName)
                                .textFieldStyle(.plain)
                                .font(theme.bodyFont(size: 15))
                                .foregroundStyle(theme.textPrimary)

                            Button("新增") {
                                addCategory()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.textSecondary)
                            .font(theme.bodyFont(size: 14))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                        Rectangle()
                            .fill(theme.separator)
                            .frame(height: 1)

                        sectionTitle("功能")
                            .padding(.top, 22)

                        toggleRow(
                            title: "次级导航",
                            value: settingsRepository.settings.isSecondaryNavigationEnabled ? "开启" : "关闭",
                            action: {
                                settingsRepository.setSecondaryNavigationEnabled(!settingsRepository.settings.isSecondaryNavigationEnabled)
                            }
                        )

                        placeholderDivider
                        shortcutRow(
                            title: "单击粘贴快捷键",
                            shortcut: settingsRepository.settings.singleConfirmShortcut,
                            isRecording: recordingShortcutKind == .singleConfirm
                        ) {
                            toggleRecording(.singleConfirm)
                        }
                        placeholderDivider
                        shortcutRow(
                            title: "双击打开快捷键",
                            shortcut: settingsRepository.settings.doubleOpenShortcut,
                            isRecording: recordingShortcutKind == .doubleOpen
                        ) {
                            toggleRecording(.doubleOpen)
                        }

                        placeholderDivider
                    }

                    Spacer(minLength: 16)
                }
                .padding(.bottom, 16)
            }
        }
        .background(theme.background)
        .overlay {
            if let recordingShortcutKind {
                ShortcutCaptureOverlay(
                    kind: recordingShortcutKind,
                    onCapture: { shortcut in
                        applyShortcut(shortcut, for: recordingShortcutKind)
                    },
                    onCancel: {
                        stopRecording()
                    }
                )
            }
        }
        .onChange(of: recordingShortcutKind) { _, newValue in
            panelCoordinator.isShortcutRecording = newValue != nil
        }
        .onDisappear {
            stopRecording()
        }
        .fileImporter(
            isPresented: $isImportPromptLibraryPresented,
            allowedContentTypes: [.json, .commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else { return }
                do {
                    try promptLibraryRepository.importFiles(at: urls)
                    panelCoordinator.showToast("已导入 \(urls.count) 份提示词库")
                } catch {
                    panelCoordinator.showToast(error.localizedDescription)
                }
            case .failure:
                panelCoordinator.showToast("导入提示词库失败")
            }
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if theme.headerUsesSurfaceBand {
            theme.surface
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var workspaceToggleButton: some View {
        let iconName = style == .compact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        Button {
            if style == .compact {
                workspaceCoordinator.showWorkspace()
            } else {
                workspaceCoordinator.hideWorkspaceToPanel()
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(theme.bodyFont(size: 15, weight: .medium))
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
    }

    private func placeholderRow(_ title: String) -> some View {
        Text(title)
            .font(theme.bodyFont(size: 15))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
    }

    private func toggleRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(theme.bodyFont(size: 15))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 0)

            Button(value) {
                action()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textPrimary)
            .font(theme.bodyFont(size: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func expandableGroupRow(title: String, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(theme.bodyFont(size: 15))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 0)

            Button(isExpanded ? "收起" : "展开") {
                action()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textPrimary)
            .font(theme.bodyFont(size: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func shortcutRow(
        title: String,
        shortcut: RecordedShortcut,
        isRecording: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(theme.bodyFont(size: 15))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 0)

            Button(isRecording ? "按下快捷键" : shortcut.displayName) {
                action()
            }
            .buttonStyle(.plain)
            .foregroundStyle(isRecording ? theme.textPrimary : theme.textSecondary)
            .font(theme.bodyFont(size: 14))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var placeholderDivider: some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func addCategory() {
        let beforeCount = promptRepository.visibleCategories().count
        try? promptRepository.createMainCategory(named: newCategoryName)
        let categories = promptRepository.visibleCategories()
        guard categories.count > beforeCount else {
            panelCoordinator.showToast("分类名称不能为空或重复")
            return
        }
        newCategoryName = ""
        activeSectionID = categories.last?.id
    }

    private func renameCategory(_ category: PromptCategory, to name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return category.name }
        guard trimmed != category.name else { return category.name }

        do {
            let didRename = try promptRepository.renamePromptCategory(id: category.id, to: trimmed)
            if didRename == false {
                panelCoordinator.showToast("分类名称已存在")
                return category.name
            }
        } catch {
            panelCoordinator.showToast("分类重命名失败")
            return category.name
        }

        return trimmed
    }

    private func renameSecondaryCategory(_ category: PromptSecondaryCategory, to name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return category.name }
        guard trimmed != category.name else { return category.name }

        do {
            let didRename = try promptRepository.renameSecondaryCategory(id: category.id, to: trimmed)
            if didRename == false {
                panelCoordinator.showToast("次级分类名称已存在")
                return category.name
            }
        } catch {
            panelCoordinator.showToast("次级分类重命名失败")
            return category.name
        }

        return trimmed
    }

    private func deleteCategory(_ category: PromptCategory) {
        try? promptRepository.deleteMainCategoryAndArchiveContent(id: category.id)
        expandedCategoryIDs.remove(category.id)
        if activeSectionID == category.id {
            activeSectionID = promptRepository.visibleCategories().first?.id
        }
    }

    private func deleteSecondaryCategory(_ category: PromptSecondaryCategory) {
        try? promptRepository.deleteSecondaryCategoryAndArchiveContent(id: category.id)
    }

    private func toggleExpandedCategory(_ id: UUID) {
        if expandedCategoryIDs.contains(id) {
            expandedCategoryIDs.remove(id)
        } else {
            expandedCategoryIDs.insert(id)
        }
    }

    private func themeModeLabel(_ mode: ThemeMode) -> String {
        switch mode {
        case .system:
            "浅色"
        case .light:
            "浅色"
        case .dark:
            "黑暗"
        case .softRose:
            "柔粉"
        case .solitudeBlue:
            "寒蓝"
        }
    }

    private func fontModeLabel(_ mode: FontMode) -> String {
        switch mode {
        case .standard:
            "默认"
        case .drunkRiverGrass:
            "醉汉江行草"
        case .telma:
            "Telma"
        }
    }

    private func workspaceThemeModeLabel(_ mode: WorkspaceThemeMode) -> String {
        switch mode {
        case .followPrimary:
            "跟随主主题"
        case .light:
            "浅色"
        case .dark:
            "黑暗"
        case .softRose:
            "柔粉"
        case .solitudeBlue:
            "寒蓝"
        }
    }

    private func cycleTheme() {
        let nextTheme: ThemeMode
        switch settingsRepository.settings.themeMode {
        case .system:
            nextTheme = .dark
        case .light:
            nextTheme = .dark
        case .dark:
            nextTheme = .softRose
        case .softRose:
            nextTheme = .solitudeBlue
        case .solitudeBlue:
            nextTheme = .light
        }
        settingsRepository.updateTheme(nextTheme)
        panelCoordinator.updateAppearance()
        workspaceCoordinator.updateAppearance()
    }

    private func cycleFontMode() {
        let nextMode: FontMode
        switch settingsRepository.settings.fontMode {
        case .standard:
            nextMode = .drunkRiverGrass
        case .drunkRiverGrass:
            nextMode = .telma
        case .telma:
            nextMode = .standard
        }
        settingsRepository.updateFontMode(nextMode)
    }

    private func cycleWorkspaceTheme() {
        let nextMode: WorkspaceThemeMode
        switch settingsRepository.settings.workspaceThemeMode {
        case .followPrimary:
            nextMode = .light
        case .light:
            nextMode = .dark
        case .dark:
            nextMode = .softRose
        case .softRose:
            nextMode = .solitudeBlue
        case .solitudeBlue:
            nextMode = .followPrimary
        }
        settingsRepository.updateWorkspaceTheme(nextMode)
        workspaceCoordinator.updateAppearance()
    }

    private func toggleRecording(_ kind: ShortcutSettingKind) {
        if recordingShortcutKind == kind {
            stopRecording()
        } else {
            recordingShortcutKind = kind
        }
    }

    private func stopRecording() {
        recordingShortcutKind = nil
        panelCoordinator.isShortcutRecording = false
    }

    private func applyShortcut(_ shortcut: RecordedShortcut, for kind: ShortcutSettingKind) {
        switch kind {
        case .singleConfirm:
            settingsRepository.setSingleConfirmShortcut(shortcut)
        case .doubleOpen:
            settingsRepository.setDoubleOpenShortcut(shortcut)
        case .workspaceTransfer:
            settingsRepository.setWorkspaceTransferShortcut(shortcut)
        }
        stopRecording()
    }
}

private struct EditableCategorySection: View {
    let category: PromptCategory
    let secondaryCategories: [PromptSecondaryCategory]
    let isExpanded: Bool
    let theme: PromptBarTheme
    let onNameChange: (String) -> String
    let onSecondaryNameChange: (PromptSecondaryCategory, String) -> String
    let onToggleExpand: () -> Void
    let onDelete: () -> Void
    let onDeleteSecondaryCategory: (PromptSecondaryCategory) -> Void

    @State private var mainDraftName: String

    init(
        category: PromptCategory,
        secondaryCategories: [PromptSecondaryCategory],
        isExpanded: Bool,
        theme: PromptBarTheme,
        onNameChange: @escaping (String) -> String,
        onSecondaryNameChange: @escaping (PromptSecondaryCategory, String) -> String,
        onToggleExpand: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDeleteSecondaryCategory: @escaping (PromptSecondaryCategory) -> Void
    ) {
        self.category = category
        self.secondaryCategories = secondaryCategories
        self.isExpanded = isExpanded
        self.theme = theme
        self.onNameChange = onNameChange
        self.onSecondaryNameChange = onSecondaryNameChange
        self.onToggleExpand = onToggleExpand
        self.onDelete = onDelete
        self.onDeleteSecondaryCategory = onDeleteSecondaryCategory
        _mainDraftName = State(initialValue: category.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditableCategoryLine(
                text: $mainDraftName,
                placeholder: "",
                theme: theme,
                trailingLabel: isExpanded ? "收起" : "展开",
                trailingAction: onToggleExpand,
                deleteAction: onDelete,
                onCommit: {
                    mainDraftName = onNameChange(mainDraftName)
                }
            )

            if isExpanded {
                ForEach(secondaryCategories, id: \.id) { secondaryCategory in
                    EditableSecondaryCategoryLine(
                        category: secondaryCategory,
                        theme: theme,
                        onNameChange: { commitName in
                            onSecondaryNameChange(secondaryCategory, commitName)
                        },
                        onDelete: {
                            onDeleteSecondaryCategory(secondaryCategory)
                        }
                    )
                }
            }
        }
        .onChange(of: category.name) { _, newValue in
            if newValue != mainDraftName {
                mainDraftName = newValue
            }
        }
    }
}

private struct EditableCategoryLine: View {
    @Binding var text: String
    let placeholder: String
    let theme: PromptBarTheme
    let trailingLabel: String
    let trailingAction: () -> Void
    let deleteAction: () -> Void
    let onCommit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(theme.bodyFont(size: 15, weight: .medium))
                .foregroundStyle(theme.textPrimary)
                .focused($isFocused)
                .onSubmit {
                    onCommit()
                }
                .onChange(of: isFocused) { wasFocused, nowFocused in
                    if wasFocused && !nowFocused {
                        onCommit()
                    }
                }

            Button(trailingLabel) {
                trailingAction()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
            .font(theme.bodyFont(size: 14))

            Button("删除") {
                deleteAction()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textSecondary)
            .font(theme.bodyFont(size: 14))
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }
}

private struct EditableSecondaryCategoryLine: View {
    let category: PromptSecondaryCategory
    let theme: PromptBarTheme
    let onNameChange: (String) -> String
    let onDelete: () -> Void

    @State private var draftName: String
    @FocusState private var isFocused: Bool

    init(
        category: PromptSecondaryCategory,
        theme: PromptBarTheme,
        onNameChange: @escaping (String) -> String,
        onDelete: @escaping () -> Void
    ) {
        self.category = category
        self.theme = theme
        self.onNameChange = onNameChange
        self.onDelete = onDelete
        _draftName = State(initialValue: category.name)
    }

    var body: some View {
        HStack(spacing: 12) {
            TextField("", text: $draftName)
                .textFieldStyle(.plain)
                .font(theme.bodyFont(size: 14))
                .foregroundStyle(theme.textSecondary)
                .focused($isFocused)
                .onSubmit {
                    draftName = onNameChange(draftName)
                }
                .onChange(of: isFocused) { wasFocused, nowFocused in
                    if wasFocused && !nowFocused {
                        draftName = onNameChange(draftName)
                    }
                }

            Button("删除") {
                onDelete()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textTertiary)
            .font(theme.bodyFont(size: 13))
        }
        .padding(.leading, 36)
        .padding(.trailing, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .onChange(of: category.name) { _, newValue in
            if newValue != draftName {
                draftName = newValue
            }
        }
    }
}

private enum ShortcutSettingKind {
    case singleConfirm
    case doubleOpen
    case workspaceTransfer
}

private struct ShortcutCaptureOverlay: View {
    let kind: ShortcutSettingKind
    let onCapture: (RecordedShortcut) -> Void
    let onCancel: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .overlay {
                ShortcutCaptureView(onCapture: onCapture, onCancel: onCancel)
                    .frame(width: 1, height: 1)
            }
            .onTapGesture {
                onCancel()
            }
            .accessibilityHidden(true)
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (RecordedShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        nsView.activate()
    }

    static func dismantleNSView(_ nsView: ShortcutCaptureNSView, coordinator: ()) {
        nsView.deactivate()
    }
}

private final class ShortcutCaptureNSView: NSView {
    var onCapture: ((RecordedShortcut) -> Void)?
    var onCancel: (() -> Void)?

    private var localKeyMonitor: Any?
    private var localFlagsMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activate()
    }

    func activate() {
        window?.makeFirstResponder(self)
        startMonitorsIfNeeded()
    }

    func deactivate() {
        stopMonitors()
    }

    private func startMonitorsIfNeeded() {
        guard localKeyMonitor == nil, localFlagsMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func stopMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
        localKeyMonitor = nil
        localFlagsMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            onCancel?()
            return nil
        }

        if let shortcut = ShortcutRecordingFormatter.recordedShortcut(from: event) {
            onCapture?(shortcut)
            return nil
        }

        return nil
    }
}

private enum ShortcutRecordingFormatter {
    static func recordedShortcut(from event: NSEvent) -> RecordedShortcut? {
        switch event.type {
        case .keyDown:
            return keyDownShortcut(from: event)
        case .flagsChanged:
            return modifierShortcut(from: event)
        default:
            return nil
        }
    }

    private static func keyDownShortcut(from event: NSEvent) -> RecordedShortcut? {
        let modifiers = filteredModifiers(from: event)
        let keyName = keyDisplayName(for: event)
        guard !keyName.isEmpty else { return nil }

        return RecordedShortcut(
            keyCode: event.keyCode,
            modifiersRawValue: modifiers.rawValue,
            triggerKind: .keyDown,
            displayName: joinedDisplayName(modifiers: modifiers, keyName: keyName)
        )
    }

    private static func modifierShortcut(from event: NSEvent) -> RecordedShortcut? {
        let modifiers = filteredModifiers(from: event)
        guard !modifiers.isEmpty else { return nil }
        guard let keyName = modifierKeyName(keyCode: event.keyCode, modifiers: modifiers) else { return nil }

        return RecordedShortcut(
            keyCode: event.keyCode,
            modifiersRawValue: modifiers.rawValue,
            triggerKind: .flagsChanged,
            displayName: keyName
        )
    }

    private static func filteredModifiers(from event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    private static func joinedDisplayName(modifiers: NSEvent.ModifierFlags, keyName: String) -> String {
        let modifierNames = orderedModifierNames(for: modifiers)
        if modifierNames.isEmpty {
            return keyName
        }
        return (modifierNames + [keyName]).joined(separator: "+")
    }

    private static func orderedModifierNames(for modifiers: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if modifiers.contains(.control) { result.append("Control") }
        if modifiers.contains(.option) { result.append("Option") }
        if modifiers.contains(.shift) { result.append("Shift") }
        if modifiers.contains(.command) { result.append("Command") }
        if modifiers.contains(.capsLock) { result.append("Caps Lock") }
        if modifiers.contains(.function) { result.append("Fn") }
        return result
    }

    private static func keyDisplayName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default:
            let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return characters.isEmpty ? "" : characters.uppercased()
        }
    }

    private static func modifierKeyName(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        switch keyCode {
        case 54, 55:
            return modifiers.contains(.command) ? "Command" : nil
        case 56, 60:
            return modifiers.contains(.shift) ? "Shift" : nil
        case 58, 61:
            return modifiers.contains(.option) ? "Option" : nil
        case 59, 62:
            return modifiers.contains(.control) ? "Control" : nil
        case 57:
            return modifiers.contains(.capsLock) ? "Caps Lock" : nil
        case 63:
            return modifiers.contains(.function) ? "Fn" : nil
        default:
            return nil
        }
    }
}

private struct CategoryCreationOverlay: View {
    let theme: PromptBarTheme
    @Binding var text: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("新建分类")
                .font(theme.bodyFont(size: 16, weight: .semibold))
                .foregroundStyle(theme.textPrimary)

            TextField("请输入分类名称", text: $text)
                .textFieldStyle(.plain)
                .font(theme.bodyFont(size: 14))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(theme.separator, lineWidth: 1)
                        )
                )
                .focused($isInputFocused)
                .onSubmit {
                    onConfirm()
                }

            HStack(spacing: 16) {
                Spacer()

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .font(theme.bodyFont(size: 14))

                Button("创建") {
                    onConfirm()
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? theme.textTertiary
                        : theme.textPrimary
                )
                .font(theme.bodyFont(size: 14))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.outline, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
    }
}

private struct PromptTextRow: View {
    let theme: PromptBarTheme
    let prompt: PromptItem
    let tags: [String]
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(prompt.title)
                    .font(theme.bodyFont(size: 17, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                if !tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(theme.bodyFont(size: 12))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            Text(prompt.content)
                .font(theme.bodyFont(size: 13))
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(rowBackground)
        .contentTransition(.opacity)
        .scaleEffect((isSelected || isHovered) ? 1 : 0.997)
        .animation(PromptBarMotion.interactive, value: isSelected)
        .animation(PromptBarMotion.interactive, value: isHovered)
    }

    private var rowBackground: Color {
        if isSelected {
            return theme.selection
        }
        if isHovered {
            return theme.hover
        }
        return .clear
    }
}

private struct SidebarItem: View {
    let title: String
    let isSelected: Bool
    let isDropTarget: Bool
    let isDragging: Bool
    let theme: PromptBarTheme
    let isDraggable: Bool
    let action: () -> Void
    let onHoverSelection: () -> Void
    let onDragStart: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(theme.navigationFont(size: 18))
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .fontWeight(isSelected ? .medium : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(background)
            .opacity(isDragging ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                onHoverSelection()
            }
        }
        .modifier(SidebarDragModifier(isEnabled: isDraggable, onDragStart: onDragStart))
        .scaleEffect((isSelected || isHovered || isDropTarget) ? 1 : 0.996)
        .animation(PromptBarMotion.interactive, value: isSelected)
        .animation(PromptBarMotion.interactive, value: isHovered)
        .animation(PromptBarMotion.interactive, value: isDropTarget)
        .animation(PromptBarMotion.interactive, value: isDragging)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(backgroundColor)
            .padding(.horizontal, 10)
    }

    private var backgroundColor: Color {
        if isDropTarget {
            return theme.hover
        }
        if isSelected {
            return theme.selection
        }
        if isHovered {
            return theme.hover
        }
        return .clear
    }
}

private struct SidebarDragModifier: ViewModifier {
    let isEnabled: Bool
    let onDragStart: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.onDrag {
                onDragStart()
                return NSItemProvider(object: NSString(string: UUID().uuidString))
            }
        } else {
            content
        }
    }
}

private struct SidebarEndDropZone: View {
    let theme: PromptBarTheme
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isActive ? theme.hover : .clear)
            .frame(height: 18)
            .padding(.horizontal, 12)
            .padding(.top, 4)
    }
}

private struct EmptyPromptState: View {
    let theme: PromptBarTheme
    let isSecondaryNavigationEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("没有匹配的提示词")
                .font(theme.bodyFont(size: 17, weight: .medium))
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(theme.bodyFont(size: 13))
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private var message: String {
        if isSecondaryNavigationEnabled {
            return "请先选择次级导航，或在空白处右键新建提示词。"
        }
        return "当前主导航下还没有提示词，可在空白处右键新建提示词。"
    }
}

private struct EmptyLibraryState: View {
    let theme: PromptBarTheme

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            CompanionImage(theme: theme, isHovered: false, showsBackdrop: false)
                .scaleEffect(2.8)

            Text("还没有导航")
                .font(theme.bodyFont(size: 18, weight: .medium))
                .foregroundStyle(theme.textPrimary)

            Text("可在空白区域右键新建分类。")
                .font(theme.bodyFont(size: 13))
                .foregroundStyle(theme.textSecondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
}

struct BearSettingsLabel: View {
    let theme: PromptBarTheme

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CompanionImage(theme: theme, isHovered: isHovered, showsBackdrop: true)
            Text("设置")
                .font(theme.bodyFont(size: 13))
                .foregroundStyle(theme.textSecondary)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(PromptBarMotion.bear, value: isHovered)
    }
}

private struct CompanionImage: View {
    let theme: PromptBarTheme
    let isHovered: Bool
    let showsBackdrop: Bool

    var body: some View {
        ZStack {
            if showsBackdrop {
                BearInkBackdrop(theme: theme, isHovered: isHovered)
            }

            Rectangle()
                .fill(companionColor)
                .mask {
                    if let companionImage {
                        Image(nsImage: companionImage)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .scaleEffect(isHovered ? 1.01 : 1)
                .offset(y: isHovered ? -0.6 : 0)
        }
        .frame(width: 30, height: 36)
        .animation(PromptBarMotion.bear, value: isHovered)
    }

    private var companionColor: Color {
        theme.isDark ? theme.textSecondary : theme.textTertiary.opacity(0.9)
    }

    private var companionImage: NSImage? {
        guard let url = Bundle.module.promptBarResourceURL(
            forResource: "companion-template",
            withExtension: "png",
            legacySubdirectory: "Images"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct BearInkBackdrop: View {
    let theme: PromptBarTheme
    let isHovered: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.bearAccent.opacity(isHovered ? 0.16 : 0.06))
                .frame(width: isHovered ? 25 : 18, height: isHovered ? 20 : 14)
                .blur(radius: isHovered ? 1.2 : 0.6)
                .offset(x: -4, y: -3)

            Ellipse()
                .fill(theme.bearAccent.opacity(isHovered ? 0.12 : 0.04))
                .frame(width: isHovered ? 20 : 12, height: isHovered ? 15 : 9)
                .blur(radius: isHovered ? 1.4 : 0.7)
                .offset(x: 7, y: 3)

            Circle()
                .fill(theme.bearAccent.opacity(isHovered ? 0.08 : 0.02))
                .frame(width: isHovered ? 12 : 6, height: isHovered ? 12 : 6)
                .blur(radius: isHovered ? 1.8 : 0.8)
                .offset(x: 8, y: -8)
        }
    }
}

struct GalaxyBackground: View {
    let theme: PromptBarTheme

    @State private var glowing = false

    private let stars: [GalaxyStar] = [
        GalaxyStar(x: 0.14, y: 0.19, size: 1.3, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.23, y: 0.31, size: 1.7, twinkles: true, delay: 0.3),
        GalaxyStar(x: 0.36, y: 0.24, size: 1.2, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.49, y: 0.37, size: 1.9, twinkles: true, delay: 0.8),
        GalaxyStar(x: 0.58, y: 0.33, size: 1.1, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.68, y: 0.44, size: 1.6, twinkles: true, delay: 1.1),
        GalaxyStar(x: 0.78, y: 0.39, size: 1.2, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.83, y: 0.53, size: 1.5, twinkles: true, delay: 0.5),
        GalaxyStar(x: 0.29, y: 0.62, size: 1.1, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.41, y: 0.58, size: 1.4, twinkles: true, delay: 0.9),
        GalaxyStar(x: 0.64, y: 0.67, size: 1.1, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.74, y: 0.61, size: 1.6, twinkles: true, delay: 0.4)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        theme.background,
                        theme.background.opacity(0.96),
                        theme.background
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Ellipse()
                    .fill(theme.galaxySecondary.opacity(glowing ? 0.72 : 0.54))
                    .frame(width: geometry.size.width * 1.08, height: geometry.size.height * 0.28)
                    .blur(radius: 42)
                    .rotationEffect(.degrees(-22))
                    .offset(x: geometry.size.width * 0.05, y: geometry.size.height * 0.13)

                Ellipse()
                    .fill(theme.galaxyPrimary.opacity(glowing ? 0.82 : 0.62))
                    .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.18)
                    .blur(radius: 28)
                    .rotationEffect(.degrees(-21))
                    .offset(x: geometry.size.width * 0.03, y: geometry.size.height * 0.16)

                Ellipse()
                    .fill(theme.galaxyGlow.opacity(glowing ? 0.62 : 0.4))
                    .frame(width: geometry.size.width * 0.54, height: geometry.size.height * 0.09)
                    .blur(radius: 22)
                    .rotationEffect(.degrees(-21))
                    .offset(x: geometry.size.width * 0.08, y: geometry.size.height * 0.175)

                ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(star.twinkles ? theme.galaxyGlow : theme.galaxyPrimary)
                        .frame(width: star.size, height: star.size)
                        .opacity(starOpacity(for: star))
                        .blur(radius: star.twinkles ? 0.24 : 0)
                        .position(x: geometry.size.width * star.x, y: geometry.size.height * star.y)
                }
            }
            .onAppear {
                withAnimation(PromptBarMotion.galaxy.repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func starOpacity(for star: GalaxyStar) -> Double {
        guard star.twinkles else { return 0.9 }
        let base = 0.30 + star.delay * 0.06
        return glowing ? min(base + 0.18, 0.72) : base
    }
}

private struct GalaxyStar {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let twinkles: Bool
    let delay: Double
}

private struct CompactSolitudeBlueBackground: View {
    let theme: PromptBarTheme

    @State private var drift = false

    private let stars: [GalaxyStar] = [
        GalaxyStar(x: 0.16, y: 0.16, size: 1.3, twinkles: true, delay: 0.1),
        GalaxyStar(x: 0.31, y: 0.11, size: 1.1, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.52, y: 0.19, size: 1.4, twinkles: true, delay: 0.7),
        GalaxyStar(x: 0.69, y: 0.13, size: 1.0, twinkles: false, delay: 0.0),
        GalaxyStar(x: 0.81, y: 0.23, size: 1.5, twinkles: true, delay: 0.35)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.040, green: 0.074, blue: 0.135),
                        theme.background,
                        Color(red: 0.070, green: 0.118, blue: 0.196)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.18))
                    .frame(width: geometry.size.width * 0.28)
                    .blur(radius: 14)
                    .offset(x: geometry.size.width * 0.22, y: -geometry.size.height * 0.18)

                Ellipse()
                    .fill(theme.galaxySecondary.opacity(drift ? 0.42 : 0.28))
                    .frame(width: geometry.size.width * 0.92, height: geometry.size.height * 0.26)
                    .blur(radius: 28)
                    .rotationEffect(.degrees(-14))
                    .offset(x: geometry.size.width * 0.06, y: geometry.size.height * 0.12)

                Ellipse()
                    .fill(theme.galaxyGlow.opacity(drift ? 0.16 : 0.10))
                    .frame(width: geometry.size.width * 0.54, height: geometry.size.height * 0.12)
                    .blur(radius: 22)
                    .offset(x: -geometry.size.width * 0.08, y: geometry.size.height * 0.36)

                ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(star.twinkles ? theme.galaxyGlow : theme.galaxyPrimary)
                        .frame(width: star.size, height: star.size)
                        .opacity(star.twinkles ? (drift ? 0.88 : 0.42) : 0.72)
                        .position(x: geometry.size.width * star.x, y: geometry.size.height * star.y)
                }
            }
            .onAppear {
                withAnimation(PromptBarMotion.galaxy.repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}


private struct PromptContentTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let font: NSFont
    let textColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> PromptContentScrollView {
        let scrollView = PromptContentScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = PromptContentNSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.focusDelegate = context.coordinator
        configure(textView)
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: PromptContentScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        configure(textView)

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let textLength = (text as NSString).length
            let location = min(selectedRange.location, textLength)
            let length = min(selectedRange.length, textLength - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
        }

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        } else if !isFocused, textView.window?.firstResponder === textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(nil)
            }
        }
    }

    private func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: textColor
        ]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: max(textView.bounds.width, 1),
            height: .greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
    }

    final class Coordinator: NSObject, NSTextViewDelegate, PromptContentNSTextViewFocusDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        weak var textView: NSTextView?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func promptContentTextViewDidFocus() {
            isFocused = true
        }

        func promptContentTextViewDidBlur() {
            isFocused = false
        }
    }
}

private protocol PromptContentNSTextViewFocusDelegate: AnyObject {
    func promptContentTextViewDidFocus()
    func promptContentTextViewDidBlur()
}

private final class PromptContentNSTextView: NSTextView {
    weak var focusDelegate: PromptContentNSTextViewFocusDelegate?

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()

        switch (modifiers, key) {
        case ([.command], "v"):
            paste(nil)
            return true
        case ([.command], "c"):
            copy(nil)
            return true
        case ([.command], "x"):
            cut(nil)
            return true
        case ([.command], "a"):
            selectAll(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            focusDelegate?.promptContentTextViewDidFocus()
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            focusDelegate?.promptContentTextViewDidBlur()
        }
        return resigned
    }
}

private final class PromptContentScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { false }
}

private struct PromptEditorOverlay: View {
    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var panelCoordinator: PanelCoordinator

    @State private var draft = PromptDraft()
    @FocusState private var focusedField: Field?
    @State private var isContentFocused = false

    private enum Field {
        case title
    }

    let theme: PromptBarTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(panelCoordinator.editingPrompt == nil ? "创建提示词" : "编辑提示词")
                    .font(theme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }

            editorLabel("标题")
            TextField("请输入标题", text: $draft.title)
                .textFieldStyle(.plain)
                .font(theme.bodyFont(size: 15))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(fieldBackground)
                .focused($focusedField, equals: .title)
                .onTapGesture {
                    isContentFocused = false
                    focusedField = .title
                }

            Toggle(isOn: $draft.isPinned) {
                Text("置顶")
                    .font(theme.bodyFont(size: 14))
                    .foregroundStyle(theme.textSecondary)
            }
            .toggleStyle(.checkbox)

            editorLabel("内容")
            PromptContentTextView(
                text: $draft.content,
                isFocused: $isContentFocused,
                font: NSFont.systemFont(ofSize: 14),
                textColor: NSColor.labelColor
            )
                .frame(height: 180)
                .background(fieldBackground)

            HStack(spacing: 16) {
                Spacer()

                Button("取消") {
                    panelCoordinator.dismissPromptEditor()
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .font(theme.bodyFont(size: 14))

                Button(panelCoordinator.editingPrompt == nil ? "创建" : "保存") {
                    save()
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSave ? theme.textPrimary : theme.textTertiary)
                .font(theme.bodyFont(size: 14))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 372)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.outline, lineWidth: 1)
        )
        .onAppear {
            loadDraft()
            DispatchQueue.main.async {
                isContentFocused = false
                focusedField = .title
            }
        }
        .onChange(of: focusedField) { _, field in
            if field == .title {
                isContentFocused = false
            }
        }
        .onChange(of: isContentFocused) { _, focused in
            if focused {
                focusedField = nil
            }
        }
    }

    private func loadDraft() {
        guard let prompt = panelCoordinator.editingPrompt else {
            draft = PromptDraft()
            return
        }
        draft.title = prompt.title
        draft.content = prompt.content
        draft.isPinned = prompt.isPinned
    }

    private func save() {
        do {
            if let prompt = panelCoordinator.editingPrompt {
                try promptRepository.updatePrompt(prompt, from: draft)
                panelCoordinator.showToast("已更新提示词")
            } else if let mainCategoryID = panelCoordinator.promptEditorMainCategoryID {
                try promptRepository.createPrompt(
                    from: draft,
                    mainCategoryID: mainCategoryID,
                    secondaryCategoryID: panelCoordinator.promptEditorSecondaryCategoryID
                )
                panelCoordinator.showToast("已创建提示词")
            } else {
                panelCoordinator.showToast("请先切换到主导航后再创建")
                return
            }
            panelCoordinator.dismissPromptEditor()
        } catch {
            panelCoordinator.showToast("保存失败")
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.separator, lineWidth: 1)
            )
    }

    private func editorLabel(_ title: String) -> some View {
        Text(title)
            .font(theme.bodyFont(size: 13, weight: .medium))
            .foregroundStyle(theme.textSecondary)
    }

}

private struct SearchOverlay: View {
    @EnvironmentObject private var promptRepository: PromptRepository
    @EnvironmentObject private var panelCoordinator: PanelCoordinator

    @FocusState private var isSearchFocused: Bool
    let theme: PromptBarTheme

    private var results: [PromptItem] {
        promptRepository.searchPrompts(query: panelCoordinator.searchQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("搜索提示词")
                    .font(theme.bodyFont(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Button("关闭") {
                    panelCoordinator.dismissSearch()
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.textSecondary)
                .font(theme.bodyFont(size: 14))
            }

            TextField("搜索标题或内容", text: $panelCoordinator.searchQuery)
                .textFieldStyle(.plain)
                .font(theme.bodyFont(size: 15))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(fieldBackground)
                .focused($isSearchFocused)

            Group {
                if panelCoordinator.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入任意文字后，将显示标题或内容里包含这些字的提示词。")
                        .font(theme.bodyFont(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                        .padding(.top, 4)
                } else if results.isEmpty {
                    Text("没有匹配的提示词。")
                        .font(theme.bodyFont(size: 13))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, 4)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, prompt in
                                PromptTextRow(
                                    theme: theme,
                                    prompt: prompt,
                                    tags: [],
                                    isSelected: false,
                                    isHovered: false
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    panelCoordinator.confirmPrompt(prompt)
                                }
                                .contextMenu {
                                    Button("编辑") {
                                        panelCoordinator.promptEditing(prompt)
                                    }
                                    Button("删除", role: .destructive) {
                                        try? promptRepository.deletePrompt(prompt)
                                    }
                                }

                                if index < results.count - 1 {
                                    Rectangle()
                                        .fill(theme.separator)
                                        .frame(height: 1)
                                        .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(width: 420, height: 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.outline, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.async {
                isSearchFocused = true
            }
        }
        .onPasteCommand(of: [.plainText]) { _ in
            guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
            panelCoordinator.searchQuery += text
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(theme.background)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.separator, lineWidth: 1)
            )
    }
}

private struct ScrollWheelCaptureView: NSViewRepresentable {
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.onStep = onStep
    }
}

private final class ScrollWheelView: NSView {
    var onStep: ((Int) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if abs(delta) < 0.5 {
            super.scrollWheel(with: event)
            return
        }
        onStep?(delta > 0 ? -1 : 1)
    }
}
