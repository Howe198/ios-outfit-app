import Foundation
import Combine

/// 五组标签词表 + 用户自定义标签。
/// 默认词表在 Vocabulary 中冻结；自定义标签只存在本机 UserDefaults。
final class VocabularyStore: ObservableObject {
    static let shared = VocabularyStore()

    @Published private(set) var custom: [String: [String]]

    private let storageKey = "custom_tags_v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            custom = decoded
        } else {
            custom = [:]
        }
    }

    func options(for dimension: String) -> [String] {
        var list = Vocabulary.defaults[dimension] ?? []
        for tag in custom[dimension] ?? [] where !list.contains(tag) {
            list.append(tag)
        }
        return list
    }

    func isCustom(_ tag: String, in dimension: String) -> Bool {
        (custom[dimension] ?? []).contains(tag)
    }

    func add(_ rawTag: String, to dimension: String) {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        var list = custom[dimension] ?? []
        guard !list.contains(tag), !(Vocabulary.defaults[dimension] ?? []).contains(tag) else { return }
        list.append(tag)
        objectWillChange.send()
        custom[dimension] = list
        persist()
    }

    func remove(_ tag: String, from dimension: String) {
        guard var list = custom[dimension], let index = list.firstIndex(of: tag) else { return }
        list.remove(at: index)
        objectWillChange.send()
        custom[dimension] = list
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
