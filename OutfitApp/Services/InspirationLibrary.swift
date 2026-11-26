import Foundation
import UIKit

/// 内置搭配灵感：只做离线浏览参考，不联网、不抓取任何平台内容、不带货。
struct StyleSample: Identifiable, Hashable {
    let id: String
    let title: String
    let note: String
    let imageName: String
    let minTemp: Int
    let maxTemp: Int
    let occasion: String
    let season: Season

    var tempText: String { "\(minTemp)–\(maxTemp)℃" }

    func contains(_ temperature: Int) -> Bool {
        temperature >= minTemp && temperature <= maxTemp
    }

    func distance(to temperature: Int) -> Int {
        if temperature < minTemp { return minTemp - temperature }
        if temperature > maxTemp { return temperature - maxTemp }
        return 0
    }
}

/// 灵感分区：featured 是适合今天/本季的，remaining 是不匹配的，两者不混排。
struct InspirationSection {
    let featured: [StyleSample]
    let remaining: [StyleSample]
    let usesTemperature: Bool
    let temperature: Int?
}

enum InspirationLibrary {
    /// 30 张本地示例图，覆盖四季与日常休闲、通勤上班、正式场合；全部随包分发。
    static let all: [StyleSample] = [
        StyleSample(
            id: "sample-01",
            title: "白T＋直筒牛仔",
            note: "白 T 配浅蓝直筒牛仔，鞋子和上衣同色，干净不出错。",
            imageName: "sample-01",
            minTemp: 22,
            maxTemp: 32,
            occasion: "日常休闲",
            season: .summer
        ),
        StyleSample(
            id: "sample-02",
            title: "米色针织＋深蓝阔腿裤",
            note: "上浅下深，针织开衫配阔腿裤，通勤不沉闷。",
            imageName: "sample-02",
            minTemp: 14,
            maxTemp: 22,
            occasion: "通勤上班",
            season: .spring
        ),
        StyleSample(
            id: "sample-03",
            title: "浅蓝衬衫＋灰西裤",
            note: "版型利落，衬衫配西裤，适合会议或见客户的日子。",
            imageName: "sample-03",
            minTemp: 15,
            maxTemp: 24,
            occasion: "通勤上班",
            season: .spring
        ),
        StyleSample(
            id: "sample-04",
            title: "驼色大衣＋黑高领",
            note: "黑色高领打底，外搭驼色大衣，冷了加一件就够。",
            imageName: "sample-04",
            minTemp: -5,
            maxTemp: 12,
            occasion: "通勤上班",
            season: .winter
        ),
        StyleSample(
            id: "sample-05",
            title: "亚麻衬衫＋米色半裙",
            note: "同色系搭配，周末出门轻便，不需要复杂配饰。",
            imageName: "sample-05",
            minTemp: 20,
            maxTemp: 30,
            occasion: "日常休闲",
            season: .summer
        ),
        StyleSample(
            id: "sample-06",
            title: "灰卫衣＋黑色运动裤",
            note: "走路多的日子穿它，运动鞋同色，简单舒服。",
            imageName: "sample-06",
            minTemp: 8,
            maxTemp: 20,
            occasion: "运动健身",
            season: .spring
        ),

        // MARK: - 春（新增）

        StyleSample(
            id: "sample-07",
            title: "米色风衣＋白T＋浅蓝牛仔",
            note: "风衣配白 T 和直筒牛仔，春天早晚温差大时刚好。",
            imageName: "sample-07",
            minTemp: 12,
            maxTemp: 22,
            occasion: "日常休闲",
            season: .spring
        ),
        StyleSample(
            id: "sample-08",
            title: "浅灰西装＋白衬衫＋黑西裤",
            note: "浅灰西装不压人，白衬衫和黑西裤做内搭，通勤利落。",
            imageName: "sample-08",
            minTemp: 14,
            maxTemp: 24,
            occasion: "通勤上班",
            season: .spring
        ),
        StyleSample(
            id: "sample-09",
            title: "深蓝西装套装＋白衬衫",
            note: "深蓝套装加白衬衫，见客户或正式会议稳妥。",
            imageName: "sample-09",
            minTemp: 16,
            maxTemp: 25,
            occasion: "正式场合",
            season: .spring
        ),
        StyleSample(
            id: "sample-10",
            title: "浅灰西装套装＋黑西裤",
            note: "浅灰西装套装，颜色比黑色轻，正式场合不显沉闷。",
            imageName: "sample-10",
            minTemp: 14,
            maxTemp: 24,
            occasion: "正式场合",
            season: .spring
        ),
        StyleSample(
            id: "sample-11",
            title: "米色针织＋白衬衫＋棕西裤",
            note: "米色针织叠白衬衫，配棕西裤，通勤温和有层次。",
            imageName: "sample-11",
            minTemp: 12,
            maxTemp: 22,
            occasion: "通勤上班",
            season: .spring
        ),

        // MARK: - 夏（新增）

        StyleSample(
            id: "sample-12",
            title: "白T＋卡其短裤＋白帆布鞋",
            note: "白 T 配卡其短裤，夏天出门最省心的一套。",
            imageName: "sample-12",
            minTemp: 24,
            maxTemp: 34,
            occasion: "日常休闲",
            season: .summer
        ),
        StyleSample(
            id: "sample-13",
            title: "浅蓝短袖衬衫＋灰西裤",
            note: "浅蓝短袖衬衫配灰西裤，热天通勤也保持清爽。",
            imageName: "sample-13",
            minTemp: 23,
            maxTemp: 32,
            occasion: "通勤上班",
            season: .summer
        ),
        StyleSample(
            id: "sample-14",
            title: "薄款深蓝西装＋白衬衫",
            note: "薄款深蓝西装，夏天正式场合比厚西装透气。",
            imageName: "sample-14",
            minTemp: 24,
            maxTemp: 33,
            occasion: "正式场合",
            season: .summer
        ),
        StyleSample(
            id: "sample-15",
            title: "白亚麻衬衫＋卡其阔腿裤",
            note: "亚麻衬衫配阔腿裤，热天走路不黏身。",
            imageName: "sample-15",
            minTemp: 25,
            maxTemp: 35,
            occasion: "日常休闲",
            season: .summer
        ),
        StyleSample(
            id: "sample-16",
            title: "米色亚麻衬衫＋直筒裤",
            note: "同色系亚麻衬衫和直筒裤，夏天通勤看起来干净。",
            imageName: "sample-16",
            minTemp: 23,
            maxTemp: 33,
            occasion: "通勤上班",
            season: .summer
        ),
        StyleSample(
            id: "sample-17",
            title: "浅灰薄西装套装＋白衬衫",
            note: "浅灰薄西装套装，夏天正式场合的轻量选择。",
            imageName: "sample-17",
            minTemp: 24,
            maxTemp: 32,
            occasion: "正式场合",
            season: .summer
        ),

        // MARK: - 秋（新增）

        StyleSample(
            id: "sample-18",
            title: "卡其工装外套＋白T＋深蓝牛仔",
            note: "工装外套配白 T 和牛仔，秋天周末出门耐穿。",
            imageName: "sample-18",
            minTemp: 12,
            maxTemp: 22,
            occasion: "日常休闲",
            season: .autumn
        ),
        StyleSample(
            id: "sample-19",
            title: "藏青针织＋白衬衫＋灰西裤",
            note: "藏青针织配白衬衫和灰西裤，秋日通勤稳住不花。",
            imageName: "sample-19",
            minTemp: 10,
            maxTemp: 20,
            occasion: "通勤上班",
            season: .autumn
        ),
        StyleSample(
            id: "sample-20",
            title: "深灰西装＋浅蓝衬衫",
            note: "深灰西装配浅蓝衬衫，秋天正式场合不沉闷。",
            imageName: "sample-20",
            minTemp: 12,
            maxTemp: 22,
            occasion: "正式场合",
            season: .autumn
        ),
        StyleSample(
            id: "sample-21",
            title: "棕色皮夹克＋黑T＋牛仔",
            note: "皮夹克配黑 T 和牛仔，秋天日常带一点硬朗。",
            imageName: "sample-21",
            minTemp: 8,
            maxTemp: 18,
            occasion: "日常休闲",
            season: .autumn
        ),
        StyleSample(
            id: "sample-22",
            title: "驼色开衫＋白衬衫＋棕西裤",
            note: "驼色开衫配棕西裤，秋天通勤的同色系搭法。",
            imageName: "sample-22",
            minTemp: 14,
            maxTemp: 24,
            occasion: "通勤上班",
            season: .autumn
        ),
        StyleSample(
            id: "sample-23",
            title: "黑西装套装＋白衬衫",
            note: "黑西装套装加白衬衫，正式场合最直接的选择。",
            imageName: "sample-23",
            minTemp: 10,
            maxTemp: 20,
            occasion: "正式场合",
            season: .autumn
        ),
        StyleSample(
            id: "sample-24",
            title: "米色卫衣＋卡其直筒裤",
            note: "米色卫衣配卡其裤，秋天日常宽松舒服。",
            imageName: "sample-24",
            minTemp: 15,
            maxTemp: 25,
            occasion: "日常休闲",
            season: .autumn
        ),

        // MARK: - 冬（新增）

        StyleSample(
            id: "sample-25",
            title: "黑羽绒＋灰毛衣＋黑直筒裤",
            note: "黑羽绒配灰毛衣和黑裤，冬天出门保暖不臃肿。",
            imageName: "sample-25",
            minTemp: -5,
            maxTemp: 10,
            occasion: "日常休闲",
            season: .winter
        ),
        StyleSample(
            id: "sample-26",
            title: "驼色大衣＋黑高领＋灰西裤",
            note: "驼色大衣配黑高领，冬天通勤既暖又利落。",
            imageName: "sample-26",
            minTemp: -5,
            maxTemp: 10,
            occasion: "通勤上班",
            season: .winter
        ),
        StyleSample(
            id: "sample-27",
            title: "深灰大衣＋黑西装＋白衬衫",
            note: "深灰大衣叠黑西装，冬天正式场合扛得住冷。",
            imageName: "sample-27",
            minTemp: -10,
            maxTemp: 5,
            occasion: "正式场合",
            season: .winter
        ),
        StyleSample(
            id: "sample-28",
            title: "深蓝大衣＋灰西装套装",
            note: "深蓝大衣配灰西装套装，冬天见客户体面。",
            imageName: "sample-28",
            minTemp: -8,
            maxTemp: 6,
            occasion: "正式场合",
            season: .winter
        ),
        StyleSample(
            id: "sample-29",
            title: "深蓝大衣＋米色针织＋黑裤",
            note: "深蓝大衣配米色针织，冬天通勤不显沉闷。",
            imageName: "sample-29",
            minTemp: -5,
            maxTemp: 12,
            occasion: "通勤上班",
            season: .winter
        ),
        StyleSample(
            id: "sample-30",
            title: "黑色长款大衣＋灰西装",
            note: "黑色长款大衣配灰西装，冬天正式场合稳妥。",
            imageName: "sample-30",
            minTemp: -10,
            maxTemp: 8,
            occasion: "正式场合",
            season: .winter
        )
    ]

    private static let cache = NSCache<NSString, UIImage>()

    static func image(for sample: StyleSample) -> UIImage? {
        if let cached = cache.object(forKey: sample.imageName as NSString) {
            return cached
        }
        guard let url = Bundle.main.url(
            forResource: sample.imageName,
            withExtension: "jpg",
            subdirectory: "InspirationSamples"
        ), let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        cache.setObject(image, forKey: sample.imageName as NSString)
        return image
    }

    /// 今日页用：温度命中的优先，其次场合命中的；都不命中时取温度最接近的，保证不空。
    static func samples(matching temperature: Int, occasion: String? = nil, limit: Int = 3) -> [StyleSample] {
        let tempMatches = all.filter { $0.contains(temperature) }
        if let occasion = occasion {
            let exact = tempMatches.filter { $0.occasion == occasion }
            if !exact.isEmpty { return Array(exact.prefix(limit)) }
        }
        if !tempMatches.isEmpty { return Array(tempMatches.prefix(limit)) }

        let nearest = all.sorted {
            if $0.distance(to: temperature) == $1.distance(to: temperature) {
                return $0.id < $1.id
            }
            return $0.distance(to: temperature) < $1.distance(to: temperature)
        }
        return Array(nearest.prefix(limit))
    }

    /// 灵感页用：返回互不混排的两段。weatherFirst 关闭时 remaining 就是原始顺序。
    static func section(
        temperature: Int?,
        weatherFirst: Bool,
        season: Season = currentSeason()
    ) -> InspirationSection {
        guard weatherFirst else {
            return InspirationSection(featured: [], remaining: all, usesTemperature: false, temperature: nil)
        }

        if let temperature = temperature {
            let matches = all.filter { $0.contains(temperature) }
            let others = all.filter { !$0.contains(temperature) }.sorted {
                if $0.distance(to: temperature) == $1.distance(to: temperature) {
                    return $0.id < $1.id
                }
                return $0.distance(to: temperature) < $1.distance(to: temperature)
            }
            return InspirationSection(
                featured: matches,
                remaining: others,
                usesTemperature: true,
                temperature: temperature
            )
        }

        let inSeason = all.filter { $0.season == season }
        let outSeason = all.filter { $0.season != season }
        return InspirationSection(
            featured: inSeason,
            remaining: outSeason,
            usesTemperature: false,
            temperature: nil
        )
    }

    /// 以中国常用口径按月份划分四季。
    static func currentSeason(_ date: Date = Date()) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }
}
