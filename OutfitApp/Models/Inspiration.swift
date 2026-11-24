import Foundation
import SwiftData

/// 灵感收藏：只做手动收藏与提炼，不抓取任何平台内容。
/// 每条必须写一句「可借鉴点」，并关联至少 1 件自有衣物或 1 条规则（阶段2 · 2.4）。
@Model
final class Inspiration {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var platform: String
    var sourceDate: Date?
    var imageFile: String
    var linkedItemIDs: [UUID]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        note: String,
        platform: String,
        sourceDate: Date? = nil,
        imageFile: String,
        linkedItemIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.platform = platform
        self.sourceDate = sourceDate
        self.imageFile = imageFile
        self.linkedItemIDs = linkedItemIDs
        self.createdAt = createdAt
    }
}
