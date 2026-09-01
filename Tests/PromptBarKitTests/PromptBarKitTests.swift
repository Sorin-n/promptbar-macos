import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import PromptBarKit

final class PromptBarKitTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        super.tearDown()
    }

    func testSettingsNormalizationKeepsPromptListEnabled() {
        let snapshot = AppSettingsSnapshot(
            themeMode: .dark,
            tabTriggerEnabled: true,
            doubleTabThresholdMs: 90,
            confirmByDualMouse: true,
            isSecondaryNavigationEnabled: true,
            panelModules: [
                PanelModuleConfiguration(kind: .tags, isEnabled: true, sortOrder: 3),
                PanelModuleConfiguration(kind: .promptList, isEnabled: false, sortOrder: 2)
            ]
        )

        let normalized = snapshot.normalized()

        XCTAssertEqual(normalized.doubleTabThresholdMs, 120)
        XCTAssertTrue(normalized.panelModules.contains(where: { $0.kind == .promptList && $0.isEnabled }))
        XCTAssertEqual(normalized.panelModules.count, 3)
    }

    func testSettingsNormalizationMapsLegacySystemThemeToLight() {
        let snapshot = AppSettingsSnapshot(themeMode: .system)

        XCTAssertEqual(snapshot.normalized().themeMode, .light)
    }

    func testSettingsNormalizationKeepsDefaultFontMode() {
        let snapshot = AppSettingsSnapshot(themeMode: .softRose)

        XCTAssertEqual(snapshot.normalized().fontMode, .standard)
    }

    func testSettingsNormalizationKeepsSolitudeBlueTheme() {
        let snapshot = AppSettingsSnapshot(themeMode: .solitudeBlue)

        XCTAssertEqual(snapshot.normalized().themeMode, .solitudeBlue)
    }

    func testSettingsNormalizationKeepsWorkspaceDefaults() {
        let snapshot = AppSettingsSnapshot(themeMode: .light)

        let normalized = snapshot.normalized()

        XCTAssertEqual(normalized.workspaceThemeMode, .followPrimary)
        XCTAssertFalse(normalized.workspaceGlassEnabled)
    }

    func testSolitudeBlueThemeUsesDarkAppearance() {
        XCTAssertEqual(ThemeMode.solitudeBlue.preferredColorScheme, .dark)
        XCTAssertEqual(ThemeMode.solitudeBlue.nsAppearance?.name, .darkAqua)
    }

    func testWorkspaceThemeFollowPrimaryDefersColorSchemeButResolvesFallback() {
        XCTAssertNil(WorkspaceThemeMode.followPrimary.preferredColorScheme)
        XCTAssertEqual(WorkspaceThemeMode.followPrimary.resolvedThemeMode(fallback: .solitudeBlue), .solitudeBlue)
        XCTAssertEqual(
            WorkspaceThemeMode.followPrimary.nsAppearance(fallback: .solitudeBlue)?.name,
            .darkAqua
        )
    }

    func testSelectionNavigatorClampsBounds() {
        XCTAssertEqual(SelectionNavigator.nextIndex(current: nil, count: 3, delta: 1), 1)
        XCTAssertEqual(SelectionNavigator.nextIndex(current: 0, count: 3, delta: -1), 0)
        XCTAssertEqual(SelectionNavigator.nextIndex(current: 2, count: 3, delta: 2), 2)
        XCTAssertNil(SelectionNavigator.nextIndex(current: 0, count: 0, delta: 1))
    }

    func testPromptMetadataParserDeduplicatesAndTrims() {
        let parsed = PromptMetadataParser.uniqueNames(from: " 推理,推理，  新标签 \n产品 ")

        XCTAssertEqual(parsed, ["推理", "新标签", "产品"])
    }

    @MainActor
    func testSettingsRepositoryStartsWithoutDefaultSidebarCategories() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.removePersistentDomain(forName: testSuiteName)
        let repository = SettingsRepository(defaults: defaults)

        XCTAssertTrue(repository.settings.sidebarCategories.isEmpty)
    }

    @MainActor
    func testSettingsRepositoryAddsAndDeletesCustomSidebarCategories() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.removePersistentDomain(forName: testSuiteName)
        let repository = SettingsRepository(defaults: defaults)

        repository.addSidebarCategory(named: "hi")
        let hiID = try! XCTUnwrap(repository.settings.sidebarCategories.first(where: { $0.name == "hi" })?.id)
        repository.deleteSidebarCategory(id: hiID)

        XCTAssertFalse(repository.settings.sidebarCategories.contains(where: { $0.name == "hi" }))
    }

    @MainActor
    func testSettingsRepositoryPersistsSecondaryNavigationToggle() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.removePersistentDomain(forName: testSuiteName)
        let repository = SettingsRepository(defaults: defaults)

        XCTAssertTrue(repository.settings.isSecondaryNavigationEnabled)
        repository.setSecondaryNavigationEnabled(false)

        XCTAssertFalse(repository.settings.isSecondaryNavigationEnabled)
    }

    @MainActor
    func testSettingsRepositoryPersistsRecordedShortcuts() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.removePersistentDomain(forName: testSuiteName)
        let repository = SettingsRepository(defaults: defaults)

        let confirmShortcut = RecordedShortcut(
            keyCode: 49,
            modifiersRawValue: 0,
            triggerKind: .keyDown,
            displayName: "Space"
        )
        let openShortcut = RecordedShortcut(
            keyCode: 59,
            modifiersRawValue: NSEvent.ModifierFlags.control.rawValue,
            triggerKind: .flagsChanged,
            displayName: "Control"
        )
        let transferShortcut = RecordedShortcut(
            keyCode: 5,
            modifiersRawValue: NSEvent.ModifierFlags.command.rawValue,
            triggerKind: .keyDown,
            displayName: "Command+G"
        )

        repository.setSingleConfirmShortcut(confirmShortcut)
        repository.setDoubleOpenShortcut(openShortcut)
        repository.setWorkspaceTransferShortcut(transferShortcut)

        XCTAssertEqual(repository.settings.singleConfirmShortcut, confirmShortcut)
        XCTAssertEqual(repository.settings.doubleOpenShortcut, openShortcut)
        XCTAssertEqual(repository.settings.workspaceTransferShortcut, transferShortcut)
    }

    @MainActor
    func testSettingsRepositoryPersistsFontMode() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.removePersistentDomain(forName: testSuiteName)
        let repository = SettingsRepository(defaults: defaults)

        repository.updateFontMode(.telma)

        XCTAssertEqual(repository.settings.fontMode, .telma)
    }

    @MainActor
    func testSettingsRepositoryPersistsWorkspaceAppearanceSettings() {
        let defaults = UserDefaults(suiteName: testSuiteName)!
        defaults.removePersistentDomain(forName: testSuiteName)
        let repository = SettingsRepository(defaults: defaults)

        repository.updateWorkspaceTheme(.softRose)
        repository.setWorkspaceGlassEnabled(true)

        XCTAssertEqual(repository.settings.workspaceThemeMode, .softRose)
        XCTAssertTrue(repository.settings.workspaceGlassEnabled)
    }

    func testLegacyWallpaperKeyIsIgnoredOnDecodeAndDroppedOnEncode() throws {
        let legacyJSON = """
        {
          "themeMode":"light",
          "fontMode":"standard",
          "workspaceThemeMode":"solitudeBlue",
          "workspaceWallpaperBookmark":"AQID",
          "workspaceGlassEnabled":true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettingsSnapshot.self, from: legacyJSON)
        let encoded = try JSONEncoder().encode(decoded)
        let encodedString = String(data: encoded, encoding: .utf8) ?? ""

        XCTAssertEqual(decoded.workspaceThemeMode, .solitudeBlue)
        XCTAssertTrue(decoded.workspaceGlassEnabled)
        XCTAssertFalse(encodedString.contains("workspaceWallpaperBookmark"))
    }

    @MainActor
    func testPromptLibraryRepositoryImportsJSONFile() throws {
        let container = try makeLibraryContainer()
        let repository = PromptLibraryRepository(modelContext: container.mainContext)
        let url = try writeTemporaryFile(
            named: "library.json",
            contents: """
            [
              {"title":"方案拆解","content":"请拆解这个需求","group":"产品"},
              {"title":"代码审查","content":"请按严重程度列出问题"}
            ]
            """
        )

        try repository.importFile(at: url)

        XCTAssertEqual(repository.sources.count, 2)
        XCTAssertEqual(repository.visibleSources().first?.name, "回收")
        XCTAssertEqual(repository.entries.count, 2)
        XCTAssertEqual(repository.entries.first?.groupName, "产品")
    }

    @MainActor
    func testPromptLibraryRepositoryImportsCSVFile() throws {
        let container = try makeLibraryContainer()
        let repository = PromptLibraryRepository(modelContext: container.mainContext)
        let url = try writeTemporaryFile(
            named: "library.csv",
            contents: """
            title,content,group
            网页文案压缩,请压缩下面文案,产品
            异常讲解,请解释这段异常,研发
            """
        )

        try repository.importFile(at: url)

        XCTAssertEqual(repository.sources.count, 2)
        XCTAssertEqual(repository.visibleSources().first?.name, "回收")
        XCTAssertEqual(repository.entries.count, 2)
        XCTAssertEqual(repository.entries.last?.groupName, "研发")
    }

    @MainActor
    func testPromptLibraryRepositoryEnsuresRecycleSourceExistsOnReload() throws {
        let container = try makeLibraryContainer()
        let repository = PromptLibraryRepository(modelContext: container.mainContext)

        try repository.reload()

        XCTAssertEqual(repository.sources.count, 1)
        XCTAssertEqual(repository.visibleSources().first?.name, "回收")
        XCTAssertTrue(repository.hasImportedSources() == false)
    }

    @MainActor
    func testPromptLibraryRepositoryCreatesRecycleEntry() throws {
        let container = try makeLibraryContainer()
        let repository = PromptLibraryRepository(modelContext: container.mainContext)

        try repository.reload()
        try repository.createRecycleEntry(title: "归档提示词", content: "这是回收内容", groupName: "角色 / 推理")

        let recycle = try XCTUnwrap(repository.recycleSource())
        let recycleEntries = repository.filteredEntries(sourceID: recycle.id, query: "")

        XCTAssertEqual(recycleEntries.count, 1)
        XCTAssertEqual(recycleEntries.first?.title, "归档提示词")
        XCTAssertEqual(recycleEntries.first?.groupName, "角色 / 推理")
    }

    @MainActor
    func testPromptLibraryRepositoryImportDoesNotReplaceRecycleSource() throws {
        let container = try makeLibraryContainer()
        let repository = PromptLibraryRepository(modelContext: container.mainContext)
        let url = try writeTemporaryFile(
            named: "library.json",
            contents: """
            [
              {"title":"方案拆解","content":"请拆解这个需求"}
            ]
            """
        )

        try repository.reload()
        let recycleSourceID = repository.recycleSource()?.id
        try repository.importFile(at: url)

        XCTAssertEqual(repository.recycleSource()?.id, recycleSourceID)
        XCTAssertEqual(repository.visibleSources().count, 2)
    }

    @MainActor
    func testPromptLibraryRepositoryUpdatesAndDeletesEntry() throws {
        let container = try makeLibraryContainer()
        let repository = PromptLibraryRepository(modelContext: container.mainContext)
        let url = try writeTemporaryFile(
            named: "library.json",
            contents: """
            [
              {"title":"旧标题","content":"旧内容","group":"旧分组"}
            ]
            """
        )

        try repository.importFile(at: url)
        let entry = try XCTUnwrap(repository.entries.first)
        let sourceID = try XCTUnwrap(entry.source?.id)

        try repository.updateEntry(id: entry.id, title: "新标题", content: "新内容", groupName: "新分组")

        XCTAssertEqual(repository.entry(id: entry.id)?.title, "新标题")
        XCTAssertEqual(repository.entry(id: entry.id)?.content, "新内容")
        XCTAssertEqual(repository.entry(id: entry.id)?.groupName, "新分组")

        try repository.deleteEntry(id: entry.id)

        XCTAssertNil(repository.entry(id: entry.id))
        XCTAssertNil(repository.source(id: sourceID))
        XCTAssertEqual(repository.visibleSources().count, 1)
        XCTAssertEqual(repository.visibleSources().first?.name, "回收")
    }

    @MainActor
    func testPromptLibraryRepositoryDetectsNormalizedRecycleDuplicates() throws {
        let container = try makeLibraryContainer()
        let repository = PromptLibraryRepository(modelContext: container.mainContext)

        try repository.reload()
        try repository.createRecycleEntry(title: "  方案拆解 ", content: "请拆解这个需求", groupName: "角色 / 推理")

        XCTAssertTrue(
            repository.containsRecycleEntry(
                title: "方案拆解",
                content: "请拆解这个需求",
                groupName: "角色 / 推理"
            )
        )
        XCTAssertTrue(
            repository.containsRecycleEntry(
                title: "方案拆解",
                content: "请拆解这个需求",
                groupName: "  角色 / 推理 "
            )
        )
        XCTAssertFalse(
            repository.containsRecycleEntry(
                title: "方案拆解",
                content: "不一样的内容",
                groupName: "角色 / 推理"
            )
        )
    }

    @MainActor
    func testPromptRepositoryDetectsDuplicatesInSameCategoryPath() throws {
        let container = try makePromptContainer()
        let repository = PromptRepository(modelContext: container.mainContext)
        let mainCategory = PromptCategory(name: "角色", sortOrder: 0)
        let secondaryCategory = PromptSecondaryCategory(name: "推理", sortOrder: 0, mainCategory: mainCategory)
        let prompt = PromptItem(
            title: "方案拆解",
            content: "请拆解这个需求",
            sortOrder: 0,
            category: mainCategory,
            secondaryCategory: secondaryCategory
        )

        container.mainContext.insert(mainCategory)
        container.mainContext.insert(secondaryCategory)
        container.mainContext.insert(prompt)
        try container.mainContext.save()
        try repository.reload()

        XCTAssertTrue(
            repository.containsPrompt(
                title: "  方案拆解 ",
                content: "请拆解这个需求",
                mainCategoryID: mainCategory.id,
                secondaryCategoryID: secondaryCategory.id
            )
        )
        XCTAssertFalse(
            repository.containsPrompt(
                title: "方案拆解",
                content: "请拆解这个需求",
                mainCategoryID: mainCategory.id,
                secondaryCategoryID: nil
            )
        )
    }

    private var testSuiteName: String {
        "PromptBarKitTests.\(name)"
    }

    private func makeLibraryContainer() throws -> ModelContainer {
        let schema = Schema([
            PromptLibrarySource.self,
            PromptLibraryEntry.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makePromptContainer() throws -> ModelContainer {
        let schema = Schema([
            PromptItem.self,
            PromptCategory.self,
            PromptSecondaryCategory.self,
            PromptTag.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func writeTemporaryFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.data(using: .utf8).map { try $0.write(to: url) }
        return url
    }
}
