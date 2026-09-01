import Foundation
import SwiftData

public enum PromptLibraryImportError: LocalizedError {
    case unsupportedFormat
    case unreadableFile
    case invalidJSON
    case invalidCSV
    case emptyLibrary

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "暂不支持这个文件格式"
        case .unreadableFile:
            "无法读取提示词库文件"
        case .invalidJSON:
            "JSON 提示词库格式不正确"
        case .invalidCSV:
            "CSV 提示词库格式不正确"
        case .emptyLibrary:
            "导入文件里没有可用提示词"
        }
    }
}

@MainActor
public final class PromptLibraryRepository: ObservableObject {
    private enum SystemSource {
        static let recycleName = "回收"
        static let recycleFileName = "__promptbar.recycle__"
    }

    @Published public private(set) var sources: [PromptLibrarySource] = []
    @Published public private(set) var entries: [PromptLibraryEntry] = []

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func reload() throws {
        _ = try ensureRecycleSourceExists()
        sources = try modelContext.fetch(
            FetchDescriptor<PromptLibrarySource>(
                sortBy: [
                    SortDescriptor(\PromptLibrarySource.importedAt, order: .reverse),
                    SortDescriptor(\PromptLibrarySource.name, order: .forward)
                ]
            )
        )
        entries = try modelContext.fetch(
            FetchDescriptor<PromptLibraryEntry>(
                sortBy: [
                    SortDescriptor(\PromptLibraryEntry.sortOrder, order: .forward),
                    SortDescriptor(\PromptLibraryEntry.title, order: .forward)
                ]
            )
        )
    }

    public func visibleSources() -> [PromptLibrarySource] {
        let recycle = sources.first(where: isRecycleSource)
        let imported = sources
            .filter { !isRecycleSource($0) }
            .sorted { lhs, rhs in
                if lhs.importedAt != rhs.importedAt {
                    return lhs.importedAt > rhs.importedAt
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return ([recycle].compactMap { $0 }) + imported
    }

    public func hasImportedSources() -> Bool {
        sources.contains(where: { !isRecycleSource($0) })
    }

    public func filteredEntries(sourceID: UUID?, query: String) -> [PromptLibraryEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = trimmedQuery.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        return entries
            .filter { entry in
                let sourceMatch = sourceID == nil || entry.source?.id == sourceID
                guard sourceMatch else { return false }

                guard !normalizedQuery.isEmpty else { return true }

                let normalizedTitle = entry.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let normalizedContent = entry.content.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                return normalizedTitle.contains(normalizedQuery) || normalizedContent.contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let lhsImportedAt = lhs.source?.importedAt ?? .distantPast
                let rhsImportedAt = rhs.source?.importedAt ?? .distantPast
                if lhsImportedAt != rhsImportedAt {
                    return lhsImportedAt > rhsImportedAt
                }
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    public func source(id: UUID) -> PromptLibrarySource? {
        sources.first(where: { $0.id == id })
    }

    public func recycleSource() -> PromptLibrarySource? {
        sources.first(where: isRecycleSource)
    }

    public func entry(id: UUID) -> PromptLibraryEntry? {
        entries.first(where: { $0.id == id })
    }

    public func importFiles(at urls: [URL]) throws {
        guard !urls.isEmpty else { return }
        for url in urls {
            try importFile(at: url)
        }
        try reload()
    }

    public func importFile(at url: URL) throws {
        let format = try format(for: url)
        let importedEntries = try parseEntries(from: url, format: format)
        guard !importedEntries.isEmpty else {
            throw PromptLibraryImportError.emptyLibrary
        }

        let fileName = url.lastPathComponent
        if let existing = sources.first(where: {
            !isRecycleSource($0) &&
            $0.fileName.compare(fileName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            modelContext.delete(existing)
        }

        let source = PromptLibrarySource(
            name: url.deletingPathExtension().lastPathComponent,
            fileName: fileName,
            format: format,
            importedAt: .now
        )
        modelContext.insert(source)

        for (index, importedEntry) in importedEntries.enumerated() {
            modelContext.insert(
                PromptLibraryEntry(
                    title: importedEntry.title,
                    content: importedEntry.content,
                    groupName: importedEntry.groupName,
                    sortOrder: index,
                    source: source
                )
            )
        }

        try persist()
    }

    public func createRecycleEntry(title: String, content: String, groupName: String?) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else { return }

        let source = try ensureRecycleSourceExists()
        let nextSortOrder = entries
            .filter { $0.source?.id == source.id }
            .map(\.sortOrder)
            .max() ?? -1

        modelContext.insert(
            PromptLibraryEntry(
                title: trimmedTitle,
                content: trimmedContent,
                groupName: groupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                sortOrder: nextSortOrder + 1,
                source: source
            )
        )

        try persist()
    }

    public func createRecycleEntry(from prompt: PromptItem, groupName: String?) throws {
        try createRecycleEntry(title: prompt.title, content: prompt.content, groupName: groupName)
    }

    public func updateEntry(id: UUID, title: String, content: String, groupName: String?) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else { return }

        entry.title = trimmedTitle
        entry.content = trimmedContent
        entry.groupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try persist()
    }

    public func deleteEntry(id: UUID) throws {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        let sourceID = entry.source?.id

        modelContext.delete(entry)
        try modelContext.save()
        try reload()

        guard
            let sourceID,
            let source = source(id: sourceID),
            !isRecycleSource(source),
            entries.contains(where: { $0.source?.id == sourceID }) == false
        else {
            return
        }

        modelContext.delete(source)
        try persist()
    }

    public func containsRecycleEntry(title: String, content: String, groupName: String?) -> Bool {
        guard let recycleSource = recycleSource() else { return false }
        return containsEntry(
            title: title,
            content: content,
            groupName: groupName,
            sourceID: recycleSource.id
        )
    }

    public func isRecycleSource(_ source: PromptLibrarySource) -> Bool {
        source.fileName == SystemSource.recycleFileName
    }

    private func persist() throws {
        try modelContext.save()
        try reload()
    }

    private func containsEntry(title: String, content: String, groupName: String?, sourceID: UUID?) -> Bool {
        let normalizedTitle = normalize(title)
        let normalizedContent = normalize(content)
        let normalizedGroupName = normalize(groupName)

        guard !normalizedTitle.isEmpty, !normalizedContent.isEmpty else { return false }

        return entries.contains { entry in
            let sourceMatches = sourceID == nil || entry.source?.id == sourceID
            guard sourceMatches else { return false }

            return normalize(entry.title) == normalizedTitle &&
                normalize(entry.content) == normalizedContent &&
                normalize(entry.groupName) == normalizedGroupName
        }
    }

    private func normalize(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) ?? ""
    }

    @discardableResult
    private func ensureRecycleSourceExists() throws -> PromptLibrarySource {
        if let existing = sources.first(where: isRecycleSource) {
            return existing
        }

        let fetchedSources = try modelContext.fetch(FetchDescriptor<PromptLibrarySource>())
        if let existing = fetchedSources.first(where: isRecycleSource) {
            return existing
        }

        let source = PromptLibrarySource(
            name: SystemSource.recycleName,
            fileName: SystemSource.recycleFileName,
            format: .json,
            importedAt: .distantPast
        )
        modelContext.insert(source)
        try modelContext.save()
        return source
    }

    private func format(for url: URL) throws -> PromptLibraryImportFormat {
        switch url.pathExtension.lowercased() {
        case "json":
            return .json
        case "csv":
            return .csv
        default:
            throw PromptLibraryImportError.unsupportedFormat
        }
    }

    private func parseEntries(from url: URL, format: PromptLibraryImportFormat) throws -> [ImportedPromptLibraryEntry] {
        let data = try Data(contentsOf: url)

        switch format {
        case .json:
            return try parseJSON(data: data)
        case .csv:
            return try parseCSV(data: data)
        }
    }

    private func parseJSON(data: Data) throws -> [ImportedPromptLibraryEntry] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            throw PromptLibraryImportError.invalidJSON
        }

        let rawItems: [[String: Any]]
        if let array = jsonObject as? [[String: Any]] {
            rawItems = array
        } else if
            let dictionary = jsonObject as? [String: Any],
            let prompts = dictionary["prompts"] as? [[String: Any]]
        {
            rawItems = prompts
        } else {
            throw PromptLibraryImportError.invalidJSON
        }

        let entries = rawItems.compactMap { item -> ImportedPromptLibraryEntry? in
            guard
                let rawTitle = item["title"] as? String,
                let rawContent = item["content"] as? String
            else {
                return nil
            }

            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !content.isEmpty else { return nil }

            let groupName = (item["group"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ImportedPromptLibraryEntry(
                title: title,
                content: content,
                groupName: groupName?.isEmpty == true ? nil : groupName
            )
        }

        guard !entries.isEmpty else {
            throw PromptLibraryImportError.invalidJSON
        }

        return entries
    }

    private func parseCSV(data: Data) throws -> [ImportedPromptLibraryEntry] {
        guard let text = decodedText(from: data) else {
            throw PromptLibraryImportError.unreadableFile
        }

        let rows = CSVParser.parse(text: text).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard rows.count >= 2 else {
            throw PromptLibraryImportError.invalidCSV
        }

        let headers = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard
            let titleIndex = headers.firstIndex(of: "title"),
            let contentIndex = headers.firstIndex(of: "content")
        else {
            throw PromptLibraryImportError.invalidCSV
        }

        let groupIndex = headers.firstIndex(of: "group")

        let entries = rows.dropFirst().compactMap { row -> ImportedPromptLibraryEntry? in
            guard row.indices.contains(titleIndex), row.indices.contains(contentIndex) else { return nil }

            let title = row[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let content = row[contentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !content.isEmpty else { return nil }

            let groupName: String?
            if let groupIndex, row.indices.contains(groupIndex) {
                let trimmed = row[groupIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                groupName = trimmed.isEmpty ? nil : trimmed
            } else {
                groupName = nil
            }

            return ImportedPromptLibraryEntry(title: title, content: content, groupName: groupName)
        }

        guard !entries.isEmpty else {
            throw PromptLibraryImportError.invalidCSV
        }

        return entries
    }

    private func decodedText(from data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .unicode, .utf16, .utf16LittleEndian, .utf16BigEndian]
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ImportedPromptLibraryEntry {
    let title: String
    let content: String
    let groupName: String?
}

private enum CSVParser {
    static func parse(text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        let characters = Array(text)
        var index = 0

        func flushField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func flushRow() {
            if currentRow.isEmpty && currentField.isEmpty {
                return
            }
            flushField()
            rows.append(currentRow)
            currentRow = []
        }

        while index < characters.count {
            let character = characters[index]

            if isInsideQuotes {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\"" {
                        currentField.append("\"")
                        index += 2
                        continue
                    }
                    isInsideQuotes = false
                    index += 1
                    continue
                }

                currentField.append(character)
                index += 1
                continue
            }

            switch character {
            case "\"":
                isInsideQuotes = true
            case ",":
                flushField()
            case "\n":
                flushRow()
            case "\r":
                break
            default:
                currentField.append(character)
            }

            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            flushRow()
        }

        return rows
    }
}
