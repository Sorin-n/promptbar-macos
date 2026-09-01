import Foundation

struct NormalizedSearchDocument {
    let title: String
    let content: String

    init(title: String, content: String) {
        self.title = Self.normalize(title)
        self.content = Self.normalize(content)
    }

    func contains(_ query: String) -> Bool {
        title.contains(query) || content.contains(query)
    }

    static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
