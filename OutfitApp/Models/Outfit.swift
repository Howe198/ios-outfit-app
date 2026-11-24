import Foundation
import SwiftData

/// 一套搭配。衣物用 ID 引用，删衣物时由界面提示并同步清理引用。
@Model
final class Outfit {
    @Attribute(.unique) var id: UUID
    var name: String
    var itemIDs: [UUID]
    var occasionValue: String
    var tempMin: Int?
    var tempMax: Int?
    var sourceValue: String
    var isFavorite: Bool
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        itemIDs: [UUID],
        occasion: String,
        tempMin: Int? = nil,
        tempMax: Int? = nil,
        source: OutfitSource = .manual,
        isFavorite: Bool = false,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.itemIDs = itemIDs
        self.occasionValue = occasion
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.sourceValue = source.rawValue
        self.isFavorite = isFavorite
        self.note = note
        self.createdAt = createdAt
    }

    var source: OutfitSource { OutfitSource(rawValue: sourceValue) ?? .manual }
    var occasion: String { occasionValue }

    var tempText: String {
        if let low = tempMin, let high = tempMax { return "\(low)–\(high)℃" }
        if let low = tempMin { return "≥\(low)℃" }
        if let high = tempMax { return "≤\(high)℃" }
        return ""
    }
}
