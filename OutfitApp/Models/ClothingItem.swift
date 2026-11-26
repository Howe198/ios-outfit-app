import Foundation
import SwiftData

/// 衣物（附录A 字段表）。
/// 图片只存 App 沙盒文件名，数据库不存二进制，导出时连同图片一起打包。
@Model
final class ClothingItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryValue: String
    var primaryColor: String
    var seasonsValue: [String]
    var thicknessValue: String
    var occasionsValue: [String]
    var tempMin: Int?
    var tempMax: Int?
    var statusValue: String
    var note: String
    var imageFile: String
    /// 「换图」时保留的上一张原图文件名；用户可在详情页恢复。为空表示没有备份。
    var previousImageFile: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: ItemCategory,
        primaryColor: String,
        seasons: [String],
        thickness: Thickness,
        occasions: [String],
        tempMin: Int? = nil,
        tempMax: Int? = nil,
        status: ItemStatus = .active,
        note: String = "",
        imageFile: String,
        previousImageFile: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.categoryValue = category.rawValue
        self.primaryColor = primaryColor
        self.seasonsValue = seasons
        self.thicknessValue = thickness.rawValue
        self.occasionsValue = occasions
        self.tempMin = tempMin
        self.tempMax = tempMax
        self.statusValue = status.rawValue
        self.note = note
        self.imageFile = imageFile
        self.previousImageFile = previousImageFile
        self.createdAt = createdAt
    }

    var category: ItemCategory { ItemCategory(rawValue: categoryValue) ?? .top }
    var thickness: Thickness { Thickness(rawValue: thicknessValue) ?? .medium }
    var status: ItemStatus { ItemStatus(rawValue: statusValue) ?? .active }
    var seasons: [Season] { seasonsValue.compactMap { Season(rawValue: $0) } }
    var occasions: [String] { occasionsValue }

    var isActive: Bool { status == .active }

    var tempText: String {
        if let low = tempMin, let high = tempMax { return "\(low)–\(high)℃" }
        if let low = tempMin { return "≥\(low)℃" }
        if let high = tempMax { return "≤\(high)℃" }
        return "未限定"
    }

    var tagText: String {
        let parts = [categoryValue, primaryColor, thicknessValue] + seasonsValue + occasionsValue
        return parts.joined(separator: " · ")
    }
}
