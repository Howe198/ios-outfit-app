import Foundation

// MARK: - 衣物品类
/// 附录A「品类」字段的取值范围。连衣裙、连体裤统一归到「一体」，不拆分。
enum ItemCategory: String, CaseIterable, Identifiable, Codable {
    case top = "上装"
    case bottom = "下装"
    case outerwear = "外套"
    case dress = "一体"
    case shoes = "鞋"
    case accessory = "配饰"

    var id: String { rawValue }
}

// MARK: - 季节
enum Season: String, CaseIterable, Identifiable, Codable {
    case spring = "春"
    case summer = "夏"
    case autumn = "秋"
    case winter = "冬"

    var id: String { rawValue }
}

// MARK: - 厚度
enum Thickness: String, CaseIterable, Identifiable, Codable {
    case thin = "薄"
    case medium = "中"
    case thick = "厚"

    var id: String { rawValue }
}

// MARK: - 状态
/// 阶段0冻结：只保留「在用 / 归档」。「待洗」是否纳入 P0 仍待本人确认（附录B）。
enum ItemStatus: String, CaseIterable, Identifiable, Codable {
    case active = "在用"
    case archived = "归档"

    var id: String { rawValue }
}

// MARK: - 颜色分组
/// 只用于「颜色协调」打分，不做专业色彩理论。
enum ColorGroup: String, Codable {
    case neutral = "中性色"
    case warm = "暖色"
    case cool = "冷色"
}

// MARK: - 温度档
enum TempBand: String, CaseIterable, Identifiable, Codable {
    case cold = "冷"
    case mild = "适中"
    case hot = "热"

    var id: String { rawValue }

    /// 温度手动输入后换算成档位，用于完整性判断（见 docs/03-推荐规则说明.md）
    static func from(celsius: Int) -> TempBand {
        if celsius <= 10 { return .cold }
        if celsius <= 22 { return .mild }
        return .hot
    }

    var seasons: [Season] {
        switch self {
        case .cold: return [.winter, .autumn]
        case .mild: return [.spring, .autumn]
        case .hot: return [.summer, .spring]
        }
    }

    var hint: String {
        switch self {
        case .cold: return "10℃ 及以下"
        case .mild: return "11–22℃"
        case .hot: return "23℃ 及以上"
        }
    }
}

// MARK: - 温度显示单位
/// 内部计算始终用摄氏；这里只决定界面显示口径。
enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius = "°C"
    case fahrenheit = "°F"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .celsius: return "摄氏（°C）"
        case .fahrenheit: return "华氏（°F）"
        }
    }

    func value(fromCelsius celsius: Int) -> Int {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return Int((Double(celsius) * 9.0 / 5.0 + 32.0).rounded())
        }
    }

    func text(fromCelsius celsius: Int) -> String {
        "\(value(fromCelsius: celsius))\(rawValue)"
    }
}

// MARK: - 搭配来源
enum OutfitSource: String, CaseIterable, Codable {
    case manual = "手动"
    case inspiration = "灵感"
    case recommendation = "推荐"
}

// MARK: - 规则
enum RuleKind: String, CaseIterable, Identifiable, Codable {
    case exclude = "排除"
    case bonus = "加分"
    case penalty = "减分"

    var id: String { rawValue }
}

enum RuleDimension: String, CaseIterable, Identifiable, Codable {
    case category = "品类"
    case color = "主色"
    case occasion = "场合"
    case season = "季节"
    case thickness = "厚度"
    case item = "指定衣物"

    var id: String { rawValue }
}

// MARK: - 词表
/// 阶段0冻结的五组标签，每组不超过 12 个。用户新增的自定义标签另存在 VocabularyStore。
enum Vocabulary {
    static let colors: [String] = ["黑", "白", "灰", "米", "棕", "驼", "藏青", "蓝", "绿", "红", "粉", "黄"]
    static let neutralColors: Set<String> = ["黑", "白", "灰", "米", "棕", "驼"]
    static let warmColors: Set<String> = ["红", "粉", "黄"]
    static let coolColors: Set<String> = ["藏青", "蓝", "绿"]

    static let occasions: [String] = ["通勤上班", "日常休闲", "运动健身", "正式场合", "居家"]
    /// 阶段0 暂定最常用的两个场合，待本人确认后替换
    static let commonOccasions: [String] = ["通勤上班", "日常休闲"]

    static let dimensions: [String] = ["品类", "主色", "季节", "场合", "厚度"]

    static let defaults: [String: [String]] = [
        "品类": ItemCategory.allCases.map(\.rawValue),
        "主色": colors,
        "季节": Season.allCases.map(\.rawValue),
        "场合": occasions,
        "厚度": Thickness.allCases.map(\.rawValue)
    ]

    static func colorGroup(for color: String) -> ColorGroup {
        if neutralColors.contains(color) { return .neutral }
        if warmColors.contains(color) { return .warm }
        if coolColors.contains(color) { return .cool }
        return .neutral
    }

    static func options(for dimension: RuleDimension) -> [String] {
        switch dimension {
        case .category: return ItemCategory.allCases.map(\.rawValue)
        case .color: return colors
        case .occasion: return occasions
        case .season: return Season.allCases.map(\.rawValue)
        case .thickness: return Thickness.allCases.map(\.rawValue)
        case .item: return []
        }
    }
}
