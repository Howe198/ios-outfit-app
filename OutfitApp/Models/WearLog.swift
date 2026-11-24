import Foundation
import SwiftData

/// 今日穿搭记录：一天一条，可改。
@Model
final class WearLog {
    @Attribute(.unique) var id: UUID
    /// 总是存当天 00:00，便于按天去重
    var date: Date
    var outfitName: String
    /// 来自「我的搭配」时记录搭配 ID；来自推荐时为空
    var outfitID: UUID?
    var itemIDs: [UUID]
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date,
        outfitName: String,
        outfitID: UUID? = nil,
        itemIDs: [UUID],
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.outfitName = outfitName
        self.outfitID = outfitID
        self.itemIDs = itemIDs
        self.note = note
        self.createdAt = createdAt
    }
}

extension WearLog {
    /// 记录某天穿了什么：同一天已有记录就覆盖，保证一天一条。
    @discardableResult
    static func record(
        date: Date = Date(),
        itemIDs: [UUID],
        outfitName: String,
        outfitID: UUID? = nil,
        in context: ModelContext,
        existing logs: [WearLog]
    ) -> WearLog {
        let day = Calendar.current.startOfDay(for: date)
        if let existing = logs.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            existing.itemIDs = itemIDs
            existing.outfitName = outfitName
            existing.outfitID = outfitID
            return existing
        }
        let log = WearLog(date: day, outfitName: outfitName, outfitID: outfitID, itemIDs: itemIDs, note: "")
        context.insert(log)
        return log
    }
}
