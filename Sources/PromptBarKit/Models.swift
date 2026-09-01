import Foundation
import SwiftData

public enum ThemeMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case softRose
    case solitudeBlue
    case breezyDay

    public var id: String { rawValue }
}

public enum WorkspaceThemeMode: String, Codable, CaseIterable, Identifiable {
    case followPrimary
    case light
    case dark
    case softRose
    case solitudeBlue
    case breezyDay

    public var id: String { rawValue }
}

public enum FontMode: String, Codable, CaseIterable, Identifiable {
    case standard
    case drunkRiverGrass
    case telma

    public var id: String { rawValue }
}

public enum PromptLibraryImportFormat: String, Codable, CaseIterable, Identifiable {
    case json
    case csv

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .json:
            "JSON"
        case .csv:
            "CSV"
        }
    }
}

public enum PanelModuleKind: String, Codable, CaseIterable, Identifiable {
    case categories
    case tags
    case promptList

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .categories:
            "分类"
        case .tags:
            "标签"
        case .promptList:
            "提示词列表"
        }
    }
}

public struct PanelModuleConfiguration: Codable, Equatable, Identifiable {
    public var kind: PanelModuleKind
    public var isEnabled: Bool
    public var sortOrder: Int

    public init(kind: PanelModuleKind, isEnabled: Bool, sortOrder: Int) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    public var id: PanelModuleKind { kind }
}

public enum ShortcutTriggerKind: String, Codable, Equatable, Sendable {
    case keyDown
    case flagsChanged
}

public struct RecordedShortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiersRawValue: UInt
    public var triggerKind: ShortcutTriggerKind
    public var displayName: String

    public init(
        keyCode: UInt16,
        modifiersRawValue: UInt = 0,
        triggerKind: ShortcutTriggerKind,
        displayName: String
    ) {
        self.keyCode = keyCode
        self.modifiersRawValue = modifiersRawValue
        self.triggerKind = triggerKind
        self.displayName = displayName
    }

    public static let defaultTab = RecordedShortcut(
        keyCode: 48,
        modifiersRawValue: 0,
        triggerKind: .keyDown,
        displayName: "Tab"
    )

    public static let defaultG = RecordedShortcut(
        keyCode: 5,
        modifiersRawValue: 0,
        triggerKind: .keyDown,
        displayName: "G"
    )
}

public struct SidebarCategoryConfiguration: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var matchesAll: Bool

    public init(id: UUID = UUID(), name: String, matchesAll: Bool = false) {
        self.id = id
        self.name = name
        self.matchesAll = matchesAll
    }
}

public struct AppSettingsSnapshot: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case themeMode
        case fontMode
        case workspaceThemeMode
        case workspaceGlassEnabled
        case tabTriggerEnabled
        case doubleTabThresholdMs
        case confirmByDualMouse
        case isSecondaryNavigationEnabled
        case singleConfirmShortcut
        case doubleOpenShortcut
        case workspaceTransferShortcut
        case panelModules
        case sidebarCategories
    }

    public var themeMode: ThemeMode
    public var fontMode: FontMode
    public var workspaceThemeMode: WorkspaceThemeMode
    public var workspaceGlassEnabled: Bool
    public var tabTriggerEnabled: Bool
    public var doubleTabThresholdMs: Int
    public var confirmByDualMouse: Bool
    public var isSecondaryNavigationEnabled: Bool
    public var singleConfirmShortcut: RecordedShortcut
    public var doubleOpenShortcut: RecordedShortcut
    public var workspaceTransferShortcut: RecordedShortcut
    public var panelModules: [PanelModuleConfiguration]
    public var sidebarCategories: [SidebarCategoryConfiguration]

    public init(
        themeMode: ThemeMode = .light,
        fontMode: FontMode = .standard,
        workspaceThemeMode: WorkspaceThemeMode = .followPrimary,
        workspaceGlassEnabled: Bool = false,
        tabTriggerEnabled: Bool = true,
        doubleTabThresholdMs: Int = 260,
        confirmByDualMouse: Bool = true,
        isSecondaryNavigationEnabled: Bool = true,
        singleConfirmShortcut: RecordedShortcut = .defaultTab,
        doubleOpenShortcut: RecordedShortcut = .defaultTab,
        workspaceTransferShortcut: RecordedShortcut = .defaultG,
        sidebarCategories: [SidebarCategoryConfiguration] = [],
        panelModules: [PanelModuleConfiguration] = PanelModuleKind.allCases.enumerated().map { index, kind in
            PanelModuleConfiguration(
                kind: kind,
                isEnabled: true,
                sortOrder: index
            )
        }
    ) {
        self.themeMode = themeMode
        self.fontMode = fontMode
        self.workspaceThemeMode = workspaceThemeMode
        self.workspaceGlassEnabled = workspaceGlassEnabled
        self.tabTriggerEnabled = tabTriggerEnabled
        self.doubleTabThresholdMs = doubleTabThresholdMs
        self.confirmByDualMouse = confirmByDualMouse
        self.isSecondaryNavigationEnabled = isSecondaryNavigationEnabled
        self.singleConfirmShortcut = singleConfirmShortcut
        self.doubleOpenShortcut = doubleOpenShortcut
        self.workspaceTransferShortcut = workspaceTransferShortcut
        self.sidebarCategories = sidebarCategories
        self.panelModules = panelModules
    }

    public var orderedModules: [PanelModuleConfiguration] {
        normalized().panelModules.sorted { lhs, rhs in
            lhs.sortOrder < rhs.sortOrder
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        themeMode = try container.decodeIfPresent(ThemeMode.self, forKey: .themeMode) ?? .system
        fontMode = try container.decodeIfPresent(FontMode.self, forKey: .fontMode) ?? .standard
        workspaceThemeMode = try container.decodeIfPresent(WorkspaceThemeMode.self, forKey: .workspaceThemeMode) ?? .followPrimary
        workspaceGlassEnabled = try container.decodeIfPresent(Bool.self, forKey: .workspaceGlassEnabled) ?? false
        tabTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .tabTriggerEnabled) ?? true
        doubleTabThresholdMs = try container.decodeIfPresent(Int.self, forKey: .doubleTabThresholdMs) ?? 260
        confirmByDualMouse = try container.decodeIfPresent(Bool.self, forKey: .confirmByDualMouse) ?? true
        isSecondaryNavigationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSecondaryNavigationEnabled) ?? true
        singleConfirmShortcut = try container.decodeIfPresent(RecordedShortcut.self, forKey: .singleConfirmShortcut) ?? .defaultTab
        doubleOpenShortcut = try container.decodeIfPresent(RecordedShortcut.self, forKey: .doubleOpenShortcut) ?? .defaultTab
        workspaceTransferShortcut = try container.decodeIfPresent(RecordedShortcut.self, forKey: .workspaceTransferShortcut) ?? .defaultG
        panelModules = try container.decodeIfPresent([PanelModuleConfiguration].self, forKey: .panelModules) ?? PanelModuleKind.allCases.enumerated().map { index, kind in
            PanelModuleConfiguration(kind: kind, isEnabled: true, sortOrder: index)
        }
        sidebarCategories = try container.decodeIfPresent([SidebarCategoryConfiguration].self, forKey: .sidebarCategories) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(themeMode, forKey: .themeMode)
        try container.encode(fontMode, forKey: .fontMode)
        try container.encode(workspaceThemeMode, forKey: .workspaceThemeMode)
        try container.encode(workspaceGlassEnabled, forKey: .workspaceGlassEnabled)
        try container.encode(tabTriggerEnabled, forKey: .tabTriggerEnabled)
        try container.encode(doubleTabThresholdMs, forKey: .doubleTabThresholdMs)
        try container.encode(confirmByDualMouse, forKey: .confirmByDualMouse)
        try container.encode(isSecondaryNavigationEnabled, forKey: .isSecondaryNavigationEnabled)
        try container.encode(singleConfirmShortcut, forKey: .singleConfirmShortcut)
        try container.encode(doubleOpenShortcut, forKey: .doubleOpenShortcut)
        try container.encode(workspaceTransferShortcut, forKey: .workspaceTransferShortcut)
        try container.encode(panelModules, forKey: .panelModules)
        try container.encode(sidebarCategories, forKey: .sidebarCategories)
    }

    public func normalized() -> AppSettingsSnapshot {
        var modulesByKind = Dictionary(uniqueKeysWithValues: panelModules.map { ($0.kind, $0) })
        for (index, kind) in PanelModuleKind.allCases.enumerated() {
            if modulesByKind[kind] == nil {
                modulesByKind[kind] = PanelModuleConfiguration(
                    kind: kind,
                    isEnabled: kind == .promptList,
                    sortOrder: index
                )
            }
        }

        var modules = PanelModuleKind.allCases.compactMap { modulesByKind[$0] }
        modules.sort { lhs, rhs in
            lhs.sortOrder < rhs.sortOrder
        }

        modules = modules.enumerated().map { index, module in
            PanelModuleConfiguration(
                kind: module.kind,
                isEnabled: module.kind == .promptList ? true : module.isEnabled,
                sortOrder: index
            )
        }

        let categories = sidebarCategories.map { category in
            SidebarCategoryConfiguration(
                id: category.id,
                name: category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名" : category.name.trimmingCharacters(in: .whitespacesAndNewlines),
                matchesAll: category.matchesAll
            )
        }

        let normalizedThemeMode: ThemeMode = themeMode == .system ? .light : themeMode

        return AppSettingsSnapshot(
            themeMode: normalizedThemeMode,
            fontMode: fontMode,
            workspaceThemeMode: workspaceThemeMode,
            workspaceGlassEnabled: workspaceGlassEnabled,
            tabTriggerEnabled: tabTriggerEnabled,
            doubleTabThresholdMs: max(120, min(doubleTabThresholdMs, 600)),
            confirmByDualMouse: confirmByDualMouse,
            isSecondaryNavigationEnabled: isSecondaryNavigationEnabled,
            singleConfirmShortcut: singleConfirmShortcut,
            doubleOpenShortcut: doubleOpenShortcut,
            workspaceTransferShortcut: workspaceTransferShortcut,
            sidebarCategories: categories,
            panelModules: modules
        )
    }
}

@Model
public final class PromptCategory {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var isVisible: Bool
    public var isSystemHidden: Bool?

    @Relationship(deleteRule: .nullify, inverse: \PromptItem.category)
    public var prompts: [PromptItem]

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        isVisible: Bool = true,
        isSystemHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isVisible = isVisible
        self.isSystemHidden = isSystemHidden
        self.prompts = []
    }
}

@Model
public final class PromptTag {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var isVisible: Bool

    @Relationship(inverse: \PromptItem.tags)
    public var prompts: [PromptItem]

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isVisible = isVisible
        self.prompts = []
    }
}

@Model
public final class PromptSecondaryCategory {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortOrder: Int
    public var isSystemHidden: Bool?

    public var mainCategory: PromptCategory?

    @Relationship(deleteRule: .nullify, inverse: \PromptItem.secondaryCategory)
    public var prompts: [PromptItem]

    public init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int,
        mainCategory: PromptCategory? = nil,
        isSystemHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.mainCategory = mainCategory
        self.isSystemHidden = isSystemHidden
        self.prompts = []
    }
}

@Model
public final class PromptLibrarySource {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var fileName: String
    public var formatRawValue: String
    public var importedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PromptLibraryEntry.source)
    public var entries: [PromptLibraryEntry]

    public var format: PromptLibraryImportFormat {
        get { PromptLibraryImportFormat(rawValue: formatRawValue) ?? .json }
        set { formatRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        format: PromptLibraryImportFormat,
        importedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.formatRawValue = format.rawValue
        self.importedAt = importedAt
        self.entries = []
    }
}

@Model
public final class PromptLibraryEntry {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var content: String
    public var groupName: String?
    public var sortOrder: Int
    public var source: PromptLibrarySource?

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        groupName: String? = nil,
        sortOrder: Int,
        source: PromptLibrarySource? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.groupName = groupName
        self.sortOrder = sortOrder
        self.source = source
    }
}

@Model
public final class PromptItem {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var content: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isPinned: Bool
    public var sortOrder: Int

    public var category: PromptCategory?
    public var secondaryCategory: PromptSecondaryCategory?

    @Relationship
    public var tags: [PromptTag]

    public init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isPinned: Bool = false,
        sortOrder: Int,
        category: PromptCategory? = nil,
        secondaryCategory: PromptSecondaryCategory? = nil,
        tags: [PromptTag] = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.sortOrder = sortOrder
        self.category = category
        self.secondaryCategory = secondaryCategory
        self.tags = tags
    }
}

public struct PromptDraft: Equatable {
    public var title: String = ""
    public var content: String = ""
    public var isPinned: Bool = false

    public init(
        title: String = "",
        content: String = "",
        isPinned: Bool = false
    ) {
        self.title = title
        self.content = content
        self.isPinned = isPinned
    }
}

public struct SelectionNavigator {
    public static func nextIndex(current: Int?, count: Int, delta: Int) -> Int? {
        guard count > 0 else { return nil }
        let baseline = current ?? 0
        return min(max(baseline + delta, 0), count - 1)
    }
}

public enum PromptMetadataParser {
    public static func uniqueNames(from input: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，\n")
        var seen: Set<String> = []
        var result: [String] = []

        for component in input.components(separatedBy: separators) {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }

        return result
    }
}
