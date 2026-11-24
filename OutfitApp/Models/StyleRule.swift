import Foundation
import SwiftData

/// 可解释的推荐规则。由阶段2 的硬性排除 / 打分固定项之外，用户自己沉淀的规则。
/// 规则从灵感提炼时必须记录来源灵感 ID 与启用时间（阶段2 · 2.5）。
@Model
final class StyleRule {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var kindValue: String
    var dimensionValue: String
    var value: String
    var points: Int
    var isEnabled: Bool
    var sourceInspirationID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        kind: RuleKind,
        dimension: RuleDimension,
        value: String,
        points: Int = 2,
        isEnabled: Bool = true,
        sourceInspirationID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.kindValue = kind.rawValue
        self.dimensionValue = dimension.rawValue
        self.value = value
        self.points = points
        self.isEnabled = isEnabled
        self.sourceInspirationID = sourceInspirationID
        self.createdAt = createdAt
    }

    var kind: RuleKind { RuleKind(rawValue: kindValue) ?? .bonus }
    var dimension: RuleDimension { RuleDimension(rawValue: dimensionValue) ?? .color }
}
