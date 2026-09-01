import Foundation
import SwiftData

@MainActor
public final class PromptRepository: ObservableObject {
    private enum ArchiveNames {
        static let main = "回收站"
        static let secondary = "回收分组"
    }

    @Published public private(set) var prompts: [PromptItem] = []
    @Published public private(set) var categories: [PromptCategory] = []
    @Published public private(set) var secondaryCategories: [PromptSecondaryCategory] = []
    @Published public private(set) var tags: [PromptTag] = []

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func bootstrap(legacySidebarCategories: [SidebarCategoryConfiguration]) throws {
        try seedIfNeeded(legacySidebarCategories: legacySidebarCategories)
        try reload()
        try migrateLegacySidebarCategories(legacySidebarCategories)
        try reload()
        try migrateLegacyTagsToThreeLevelModel()
        try reload()
    }

    public func reload() throws {
        categories = try modelContext.fetch(FetchDescriptor<PromptCategory>(sortBy: [SortDescriptor(\PromptCategory.sortOrder)]))
        secondaryCategories = try modelContext.fetch(FetchDescriptor<PromptSecondaryCategory>(sortBy: [SortDescriptor(\PromptSecondaryCategory.sortOrder)]))
        tags = try modelContext.fetch(FetchDescriptor<PromptTag>(sortBy: [SortDescriptor(\PromptTag.sortOrder)]))
        prompts = try modelContext.fetch(
            FetchDescriptor<PromptItem>(
                sortBy: [
                    SortDescriptor(\PromptItem.sortOrder, order: .forward),
                    SortDescriptor(\PromptItem.updatedAt, order: .reverse)
                ]
            )
        )
        prompts.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public func visibleCategories() -> [PromptCategory] {
        categories.filter { $0.isVisible && ($0.isSystemHidden != true) }
    }

    public func visibleTags() -> [PromptTag] {
        tags.filter(\.isVisible)
    }

    public func prompts(mainCategoryID: UUID?, secondaryCategoryID: UUID?) -> [PromptItem] {
        prompts.filter { prompt in
            let mainCategoryMatch = mainCategoryID == nil || prompt.category?.id == mainCategoryID
            let secondaryCategoryMatch = secondaryCategoryID == nil || prompt.secondaryCategory?.id == secondaryCategoryID
            return mainCategoryMatch && secondaryCategoryMatch
        }
    }

    public func visibleSecondaryCategories(in mainCategoryID: UUID?) -> [PromptSecondaryCategory] {
        secondaryCategories.filter { secondaryCategory in
            secondaryCategory.isSystemHidden != true &&
            (mainCategoryID == nil || secondaryCategory.mainCategory?.id == mainCategoryID)
        }
    }

    public func searchPrompts(query: String) -> [PromptItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let normalizedQuery = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return prompts.filter { prompt in
            let normalizedTitle = prompt.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let normalizedContent = prompt.content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return normalizedTitle.contains(normalizedQuery) || normalizedContent.contains(normalizedQuery)
        }
    }

    public func createPrompt(from draft: PromptDraft, mainCategoryID: UUID, secondaryCategoryID: UUID?) throws {
        guard let mainCategory = categories.first(where: { $0.id == mainCategoryID }) else { return }
        let secondaryCategory = secondaryCategoryID.flatMap { id in
            secondaryCategories.first(where: { $0.id == id })
        }
        let prompt = PromptItem(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: draft.content.trimmingCharacters(in: .whitespacesAndNewlines),
            isPinned: draft.isPinned,
            sortOrder: (prompts.map(\.sortOrder).max() ?? -1) + 1,
            category: mainCategory,
            secondaryCategory: secondaryCategory,
            tags: []
        )
        modelContext.insert(prompt)
        try persist()
    }

    public func containsPrompt(
        title: String,
        content: String,
        mainCategoryID: UUID,
        secondaryCategoryID: UUID?
    ) -> Bool {
        let normalizedTitle = normalize(title)
        let normalizedContent = normalize(content)
        guard !normalizedTitle.isEmpty, !normalizedContent.isEmpty else { return false }

        return prompts.contains { prompt in
            prompt.category?.id == mainCategoryID &&
            prompt.secondaryCategory?.id == secondaryCategoryID &&
            normalize(prompt.title) == normalizedTitle &&
            normalize(prompt.content) == normalizedContent
        }
    }

    public func updatePrompt(_ prompt: PromptItem, from draft: PromptDraft) throws {
        prompt.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt.content = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt.tags = []
        prompt.isPinned = draft.isPinned
        prompt.updatedAt = .now
        try persist()
    }

    public func deletePrompt(_ prompt: PromptItem) throws {
        modelContext.delete(prompt)
        try persist()
    }

    public func createCategory(named name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard visibleCategories().contains(where: {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false else {
            return
        }
        modelContext.insert(PromptCategory(name: trimmed, sortOrder: categories.count))
        try persist()
    }

    public func createMainCategory(named name: String) throws {
        try createCategory(named: name)
    }

    public func createSecondaryCategory(named name: String, in mainCategoryID: UUID) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let mainCategory = categories.first(where: { $0.id == mainCategoryID }) else { return }
        guard visibleSecondaryCategories(in: mainCategoryID).contains(where: {
            $0.mainCategory?.id == mainCategoryID &&
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false else {
            return
        }

        let sortOrder = visibleSecondaryCategories(in: mainCategoryID).count
        modelContext.insert(PromptSecondaryCategory(name: trimmed, sortOrder: sortOrder, mainCategory: mainCategory))
        try persist()
    }

    public func createTag(named name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard tags.contains(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) == false else {
            return
        }
        modelContext.insert(PromptTag(name: trimmed, sortOrder: tags.count))
        try persist()
    }

    public func renamePromptCategory(from oldName: String, to newName: String) throws -> Bool {
        let trimmedOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOldName.isEmpty, !trimmedNewName.isEmpty else { return false }
        guard trimmedOldName != trimmedNewName else { return true }
        guard visibleCategories().contains(where: {
            $0.name.compare(trimmedNewName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false else {
            return false
        }

        guard let category = visibleCategories().first(where: {
            $0.name.compare(trimmedOldName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            return true
        }

        category.name = trimmedNewName
        try persist()
        return true
    }

    public func renamePromptCategory(id: UUID, to newName: String) throws -> Bool {
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else { return false }
        guard let category = visibleCategories().first(where: { $0.id == id }) else { return false }
        guard trimmedNewName != category.name else { return true }
        guard visibleCategories().contains(where: {
            $0.id != id &&
            $0.name.compare(trimmedNewName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false else {
            return false
        }

        category.name = trimmedNewName
        try persist()
        return true
    }

    public func renameSecondaryCategory(id: UUID, to newName: String) throws -> Bool {
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty else { return false }
        guard let secondaryCategory = secondaryCategories.first(where: { $0.id == id && $0.isSystemHidden != true }) else {
            return false
        }
        guard trimmedNewName != secondaryCategory.name else { return true }
        guard visibleSecondaryCategories(in: secondaryCategory.mainCategory?.id).contains(where: {
            $0.id != id &&
            $0.name.compare(trimmedNewName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false else {
            return false
        }

        secondaryCategory.name = trimmedNewName
        try persist()
        return true
    }

    public func canDeletePromptCategory(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return prompts.contains(where: {
            $0.category?.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false
    }

    public func canDeleteMainCategory(id: UUID) -> Bool {
        categories.contains(where: { $0.id == id && $0.isSystemHidden != true })
    }

    public func canDeleteSecondaryCategory(id: UUID) -> Bool {
        secondaryCategories.contains(where: { $0.id == id && $0.isSystemHidden != true })
    }

    public func deleteCategory(_ category: PromptCategory) throws {
        modelContext.delete(category)
        try persist()
    }

    public func deleteMainCategory(id: UUID) throws {
        guard canDeleteMainCategory(id: id) else { return }
        try deleteMainCategoryAndArchiveContent(id: id)
    }

    public func deleteMainCategoryAndArchiveContent(id: UUID) throws {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        let archiveMainCategory = archiveMainCategory()
        let archiveSecondaryCategory = archiveSecondaryCategory(mainCategory: archiveMainCategory)

        for prompt in prompts where prompt.category?.id == category.id {
            prompt.category = archiveMainCategory
            prompt.secondaryCategory = archiveSecondaryCategory
            prompt.updatedAt = .now
        }

        for secondaryCategory in secondaryCategories where secondaryCategory.mainCategory?.id == category.id {
            modelContext.delete(secondaryCategory)
        }

        modelContext.delete(category)
        try persist()
    }

    public func deleteSecondaryCategory(id: UUID) throws {
        guard canDeleteSecondaryCategory(id: id) else { return }
        try deleteSecondaryCategoryAndArchiveContent(id: id)
    }

    public func deleteSecondaryCategoryAndArchiveContent(id: UUID) throws {
        guard let secondaryCategory = secondaryCategories.first(where: { $0.id == id }) else { return }
        let archiveMainCategory = archiveMainCategory()
        let archiveSecondaryCategory = archiveSecondaryCategory(mainCategory: archiveMainCategory)

        for prompt in prompts where prompt.secondaryCategory?.id == secondaryCategory.id {
            prompt.category = archiveMainCategory
            prompt.secondaryCategory = archiveSecondaryCategory
            prompt.updatedAt = .now
        }

        modelContext.delete(secondaryCategory)
        try persist()
    }

    public func deleteTag(_ tag: PromptTag) throws {
        modelContext.delete(tag)
        try persist()
    }

    public func toggleCategoryVisibility(_ category: PromptCategory) throws {
        category.isVisible.toggle()
        try persist()
    }

    public func toggleTagVisibility(_ tag: PromptTag) throws {
        tag.isVisible.toggle()
        try persist()
    }

    public func moveCategory(id: UUID, direction: Int) throws {
        var visible = visibleCategories()
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard visible.indices.contains(targetIndex) else { return }
        visible.swapAt(index, targetIndex)
        for (offset, item) in visible.enumerated() {
            item.sortOrder = offset
        }
        try persist()
    }

    public func moveMainCategory(id: UUID, direction: Int) throws {
        try moveCategory(id: id, direction: direction)
    }

    public func moveSecondaryCategory(id: UUID, in mainCategoryID: UUID, direction: Int) throws {
        var scoped = visibleSecondaryCategories(in: mainCategoryID)
        guard let index = scoped.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard scoped.indices.contains(targetIndex) else { return }
        scoped.swapAt(index, targetIndex)
        for (offset, item) in scoped.enumerated() {
            item.sortOrder = offset
        }
        try persist()
    }

    public func moveTag(id: UUID, direction: Int) throws {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        let targetIndex = index + direction
        guard tags.indices.contains(targetIndex) else { return }
        tags.swapAt(index, targetIndex)
        for (offset, item) in tags.enumerated() {
            item.sortOrder = offset
        }
        try persist()
    }

    private func persist() throws {
        try modelContext.save()
        try reload()
    }

    private func normalize(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) ?? ""
    }

    private func findOrCreateCategory(named name: String) -> PromptCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let existing = categories.first(where: {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return existing
        }

        let category = PromptCategory(name: trimmed, sortOrder: visibleCategories().count)
        modelContext.insert(category)
        categories.append(category)
        return category
    }

    private func seedIfNeeded(legacySidebarCategories: [SidebarCategoryConfiguration]) throws {
        let hasPrompts = try !modelContext.fetch(FetchDescriptor<PromptItem>()).isEmpty
        let hasCategories = try !modelContext.fetch(FetchDescriptor<PromptCategory>()).isEmpty
        if hasPrompts || hasCategories {
            return
        }

        try modelContext.save()
    }

    private func migrateLegacySidebarCategories(_ legacySidebarCategories: [SidebarCategoryConfiguration]) throws {
        guard categories.isEmpty else { return }
        var created = false
        var nextSortOrder = categories.count

        for legacy in legacySidebarCategories where legacy.matchesAll == false {
            let trimmed = legacy.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard categories.contains(where: {
                $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) == false else {
                continue
            }

            modelContext.insert(PromptCategory(name: trimmed, sortOrder: nextSortOrder))
            nextSortOrder += 1
            created = true
        }

        if created {
            try persist()
        }
    }

    private func migrateLegacyTagsToThreeLevelModel() throws {
        var hasChanges = false

        for prompt in prompts where prompt.secondaryCategory == nil {
            if let mainCategory = prompt.category {
                let legacySecondaryName = "默认分组"
                let secondaryCategory: PromptSecondaryCategory

                if let existing = secondaryCategories.first(where: {
                    $0.mainCategory?.id == mainCategory.id &&
                    $0.name.compare(legacySecondaryName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    secondaryCategory = existing
                } else {
                    let created = PromptSecondaryCategory(
                        name: legacySecondaryName,
                        sortOrder: visibleSecondaryCategories(in: mainCategory.id).count,
                        mainCategory: mainCategory
                    )
                    modelContext.insert(created)
                    secondaryCategories.append(created)
                    secondaryCategory = created
                    hasChanges = true
                }

                prompt.secondaryCategory = secondaryCategory
                hasChanges = true
            }

            if !prompt.tags.isEmpty {
                prompt.tags = []
                hasChanges = true
            }
        }

        if !tags.isEmpty {
            for tag in tags {
                modelContext.delete(tag)
            }
            hasChanges = true
        }

        if hasChanges {
            try persist()
        }
    }

    private func archiveMainCategory() -> PromptCategory {
        if let existing = categories.first(where: { $0.isSystemHidden == true && $0.name == ArchiveNames.main }) {
            return existing
        }

        let category = PromptCategory(
            name: ArchiveNames.main,
            sortOrder: categories.count,
            isVisible: false,
            isSystemHidden: true
        )
        modelContext.insert(category)
        categories.append(category)
        return category
    }

    private func archiveSecondaryCategory(mainCategory: PromptCategory) -> PromptSecondaryCategory {
        if let existing = secondaryCategories.first(where: {
            $0.isSystemHidden == true &&
            $0.mainCategory?.id == mainCategory.id &&
            $0.name == ArchiveNames.secondary
        }) {
            return existing
        }

        let secondaryCategory = PromptSecondaryCategory(
            name: ArchiveNames.secondary,
            sortOrder: secondaryCategories.count,
            mainCategory: mainCategory,
            isSystemHidden: true
        )
        modelContext.insert(secondaryCategory)
        secondaryCategories.append(secondaryCategory)
        return secondaryCategory
    }
}

@MainActor
public final class SettingsRepository: ObservableObject {
    @Published public private(set) var settings: AppSettingsSnapshot

    private let defaults: UserDefaults
    private let key = "promptbar.settings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(AppSettingsSnapshot.self, from: data)
        {
            self.settings = decoded.normalized()
        } else {
            self.settings = AppSettingsSnapshot().normalized()
        }
        persist()
    }

    public func updateTheme(_ theme: ThemeMode) {
        settings.themeMode = theme
        persist()
    }

    public func updateWorkspaceTheme(_ theme: WorkspaceThemeMode) {
        settings.workspaceThemeMode = theme
        persist()
    }

    public func setWorkspaceGlassEnabled(_ enabled: Bool) {
        settings.workspaceGlassEnabled = enabled
        persist()
    }

    public func setTabTriggerEnabled(_ enabled: Bool) {
        settings.tabTriggerEnabled = enabled
        persist()
    }

    public func setDoubleTabThreshold(milliseconds: Int) {
        settings.doubleTabThresholdMs = milliseconds
        persist()
    }

    public func setDualMouseConfirmation(_ enabled: Bool) {
        settings.confirmByDualMouse = enabled
        persist()
    }

    public func setSecondaryNavigationEnabled(_ enabled: Bool) {
        settings.isSecondaryNavigationEnabled = enabled
        persist()
    }

    public func updateFontMode(_ mode: FontMode) {
        settings.fontMode = mode
        persist()
    }

    public func setSingleConfirmShortcut(_ shortcut: RecordedShortcut) {
        settings.singleConfirmShortcut = shortcut
        persist()
    }

    public func setDoubleOpenShortcut(_ shortcut: RecordedShortcut) {
        settings.doubleOpenShortcut = shortcut
        persist()
    }

    public func setWorkspaceTransferShortcut(_ shortcut: RecordedShortcut) {
        settings.workspaceTransferShortcut = shortcut
        persist()
    }

    public func updateSidebarCategoryName(id: UUID, name: String) {
        guard let index = settings.sidebarCategories.firstIndex(where: { $0.id == id }) else { return }
        guard settings.sidebarCategories[index].matchesAll == false else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard settings.sidebarCategories.contains(where: {
            $0.id != id && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false else {
            return
        }
        settings.sidebarCategories[index].name = trimmed
        persist()
    }

    public func addSidebarCategory(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard settings.sidebarCategories.contains(where: {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) == false else {
            return
        }
        settings.sidebarCategories.append(SidebarCategoryConfiguration(name: trimmed))
        persist()
    }

    public func deleteSidebarCategory(id: UUID) {
        guard let category = settings.sidebarCategories.first(where: { $0.id == id }), !category.matchesAll else { return }
        settings.sidebarCategories.removeAll { $0.id == id }
        persist()
    }

    public func moveSidebarCategory(draggedID: UUID, before targetID: UUID?) {
        guard let dragged = settings.sidebarCategories.first(where: { $0.id == draggedID }), !dragged.matchesAll else { return }

        let allCategory = settings.sidebarCategories.first(where: \.matchesAll)
        var customCategories = settings.sidebarCategories.filter { !$0.matchesAll && $0.id != draggedID }

        let insertIndex: Int
        if let targetID {
            if let target = settings.sidebarCategories.first(where: { $0.id == targetID }), target.matchesAll {
                insertIndex = 0
            } else if let targetIndex = customCategories.firstIndex(where: { $0.id == targetID }) {
                insertIndex = targetIndex
            } else {
                insertIndex = customCategories.count
            }
        } else {
            insertIndex = customCategories.count
        }

        customCategories.insert(dragged, at: min(max(insertIndex, 0), customCategories.count))
        let nextOrder = (allCategory.map { [$0] } ?? []) + customCategories

        guard nextOrder.map(\.id) != settings.sidebarCategories.map(\.id) else { return }
        settings.sidebarCategories = nextOrder
        persist()
    }

    public func setModuleEnabled(_ kind: PanelModuleKind, enabled: Bool) {
        guard let index = settings.panelModules.firstIndex(where: { $0.kind == kind }) else { return }
        settings.panelModules[index].isEnabled = kind == .promptList ? true : enabled
        persist()
    }

    public func moveModule(_ kind: PanelModuleKind, direction: Int) {
        guard let index = settings.panelModules.firstIndex(where: { $0.kind == kind }) else { return }
        let targetIndex = index + direction
        guard settings.panelModules.indices.contains(targetIndex) else { return }
        settings.panelModules.swapAt(index, targetIndex)
        persist()
    }

    private func persist() {
        settings = settings.normalized()
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
