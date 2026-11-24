import Foundation

struct RecommendedOutfit: Identifiable {
    let id = UUID()
    let itemIDs: [UUID]
    let names: [String]
    let score: Int
    let reasons: [String]

    var title: String { names.joined(separator: " ＋ ") }
}

struct RecommendationResult {
    let outfits: [RecommendedOutfit]
    let issue: String?
}

/// 本地规则推荐引擎：三层结构（排除 → 完整性 → 打分），每套都能说清理由。
/// 不联网、不依赖任何服务，规则与权重见 docs/03-推荐规则说明.md。
enum RecommendationEngine {

    private struct Evaluation {
        let score: Int
        let reasons: [String]
    }

    static func recommend(
        items: [ClothingItem],
        outfits: [Outfit],
        logs: [WearLog],
        temperature: Int,
        occasion: String,
        rules: [StyleRule],
        limit: Int = 12
    ) -> RecommendationResult {
        let band = TempBand.from(celsius: temperature)
        let active = items.filter { $0.isActive }
        guard !active.isEmpty else {
            return RecommendationResult(outfits: [], issue: "衣橱里还没有「在用」的衣物。先去衣橱添加，再回来生成推荐。")
        }

        let bandSeasons = Set(band.seasons.map(\.rawValue))
        var usable = active.filter { item in
            guard !Set(item.seasonValues).isDisjoint(with: bandSeasons) else { return false }
            if let low = item.tempMin, temperature < low - 3 { return false }
            if let high = item.tempMax, temperature > high + 3 { return false }
            if band == .hot && item.thickness == .thick { return false }
            return true
        }

        // 第一层：用户自定义的「排除」规则，命中即不进候选池
        let excludeRules = rules.filter { $0.isEnabled && $0.kind == .exclude }
        if !excludeRules.isEmpty {
            usable = usable.filter { item in
                !excludeRules.contains { matches($0, item: item) }
            }
        }

        let lastWorn = lastWornMap(logs: logs)
        func byRecency(_ list: [ClothingItem]) -> [ClothingItem] {
            list.sorted { lhs, rhs in
                let left = lastWorn[lhs.id] ?? .distantPast
                let right = lastWorn[rhs.id] ?? .distantPast
                if left == right { return lhs.createdAt > rhs.createdAt }
                return left < right
            }
        }

        let tops = byRecency(usable.filter { $0.category == .top })
        let bottoms = byRecency(usable.filter { $0.category == .bottom })
        let dresses = byRecency(usable.filter { $0.category == .dress })
        let outers = byRecency(usable.filter { $0.category == .outerwear })
        let shoes = byRecency(usable.filter { $0.category == .shoes })

        // 第二层：完整性的硬性部分（冷天必须有外套）
        if band == .cold && outers.isEmpty {
            return RecommendationResult(
                outfits: [],
                issue: "今天偏冷，一套搭配需要外套，但衣橱里没有适合这个温度的外套。先在衣橱添加一件，或把温度调高一档。"
            )
        }

        var bases: [[ClothingItem]] = []
        for dress in dresses.prefix(8) {
            bases.append([dress])
        }
        for top in tops.prefix(10) {
            for bottom in bottoms.prefix(10) {
                bases.append([top, bottom])
            }
        }
        guard !bases.isEmpty else {
            let message: String
            if tops.isEmpty && bottoms.isEmpty && dresses.isEmpty {
                message = "这个温度下没有可用的上装、下装或一体式衣物。先去衣橱补充，或把温度调高一档看看。"
            } else if tops.isEmpty {
                message = "有下装但没有可用的上装，凑不成一套。先在衣橱补充上装。"
            } else if bottoms.isEmpty && dresses.isEmpty {
                message = "有上装但没有可用的下装，凑不成一套。先在衣橱补充下装。"
            } else {
                message = "当前条件下凑不成完整的一套。调整温度档或在衣橱补充单品。"
            }
            return RecommendationResult(outfits: [], issue: message)
        }

        let recentItems = recentItemIDs(logs: logs, days: 7)
        let favoriteIDs = Set(outfits.filter { $0.isFavorite }.flatMap { $0.itemIDs })

        var results: [RecommendedOutfit] = []
        var seen = Set<String>()

        for base in bases {
            var combo = base
            if band == .cold {
                guard let outer = outers.first else { continue }
                combo.append(outer)
            }
            if let shoe = shoes.first {
                combo.append(shoe)
            }
            guard combo.contains(where: { $0.occasionsValue.contains(occasion) }) else { continue }

            let evaluation = evaluate(
                combo: combo,
                occasion: occasion,
                recentItems: recentItems,
                favoriteIDs: favoriteIDs,
                rules: rules
            )

            let key = combo.map { $0.id.uuidString }.sorted().joined(separator: "|")
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            results.append(
                RecommendedOutfit(
                    itemIDs: combo.map { $0.id },
                    names: combo.map { $0.name },
                    score: evaluation.score,
                    reasons: evaluation.reasons
                )
            )
        }

        guard !results.isEmpty else {
            return RecommendationResult(
                outfits: [],
                issue: "没有匹配「\(occasion)」的衣物，或有单品的温度、季节与当前条件不符。检查衣物标签，或把场合换成更常用的那个。"
            )
        }

        results.sort { $0.score > $1.score }
        return RecommendationResult(outfits: Array(results.prefix(limit)), issue: nil)
    }

    // MARK: - 打分

    private static func evaluate(
        combo: [ClothingItem],
        occasion: String,
        recentItems: Set<UUID>,
        favoriteIDs: Set<UUID>,
        rules: [StyleRule]
    ) -> Evaluation {
        var total = 0
        var reasons: [String] = []

        let mainItems = combo.filter { $0.category != .shoes && $0.category != .accessory }
        let groups = Set(mainItems.map { Vocabulary.colorGroup(for: $0.primaryColor) })
        if groups.count <= 1 {
            total += 3
            reasons.append("颜色同属一个色系 +3")
        } else if groups.contains(.neutral) {
            total += 2
            reasons.append("中性色打底，配色稳 +2")
        } else if groups.count == 2 {
            reasons.append("冷暖色混搭 +0")
        } else {
            total += 1
            reasons.append("颜色较杂，但不算冲突 +1")
        }

        let wornCount = combo.filter { recentItems.contains($0.id) }.count
        if wornCount == 0 {
            total += 3
            reasons.append("近 7 天都没穿过 +3")
        } else if wornCount == 1 {
            total += 1
            reasons.append("近 7 天穿过 1 件 +1")
        } else {
            reasons.append("近 7 天穿过 \(wornCount) 件 +0")
        }

        let matched = combo.filter { $0.occasionsValue.contains(occasion) }.count
        if matched == combo.count {
            total += 2
            reasons.append("场合全部匹配「\(occasion)」+2")
        } else if matched > 0 {
            total += 1
            reasons.append("部分单品匹配「\(occasion)」+1")
        } else {
            reasons.append("场合不匹配 +0")
        }

        if combo.contains(where: { favoriteIDs.contains($0.id) }) {
            total += 2
            reasons.append("含收藏搭配里的单品 +2")
        }

        for rule in rules where rule.isEnabled && rule.kind != .exclude {
            guard combo.contains(where: { matches(rule, item: $0) }) else { continue }
            let delta = rule.kind == .bonus ? rule.points : -rule.points
            total += delta
            reasons.append("规则「\(rule.title)」\(delta >= 0 ? "+" : "")\(delta)")
        }

        return Evaluation(score: total, reasons: reasons)
    }

    // MARK: - 规则匹配

    private static func matches(_ rule: StyleRule, item: ClothingItem) -> Bool {
        switch rule.dimension {
        case .category:
            return item.categoryValue == rule.value
        case .color:
            return item.primaryColor == rule.value
        case .occasion:
            return item.occasionsValue.contains(rule.value)
        case .season:
            return item.seasonValues.contains(rule.value)
        case .thickness:
            return item.thicknessValue == rule.value
        case .item:
            return item.id.uuidString == rule.value
        }
    }

    // MARK: - 穿着历史

    private static func lastWornMap(logs: [WearLog]) -> [UUID: Date] {
        var map: [UUID: Date] = [:]
        for log in logs {
            for id in log.itemIDs {
                if let existing = map[id] {
                    map[id] = max(existing, log.date)
                } else {
                    map[id] = log.date
                }
            }
        }
        return map
    }

    private static func recentItemIDs(logs: [WearLog], days: Int) -> Set<UUID> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var ids: Set<UUID> = []
        for log in logs where log.date >= cutoff {
            ids.formUnion(log.itemIDs)
        }
        return ids
    }
}
