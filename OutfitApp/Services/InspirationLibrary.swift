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

    var tempText: String { "\(minTemp)–\(maxTemp)℃" }
}

enum InspirationLibrary {
    /// 6 张本地示例图，均为日常简约搭配，放在 Resources/InspirationSamples 里随包分发。
    static let all: [StyleSample] = [
        StyleSample(
            id: "sample-01",
            title: "白T＋直筒牛仔",
            note: "白 T 配浅蓝直筒牛仔，鞋子和上衣同色，干净不出错。",
            imageName: "sample-01",
            minTemp: 22,
            maxTemp: 32,
            occasion: "日常休闲"
        ),
        StyleSample(
            id: "sample-02",
            title: "米色针织＋深蓝阔腿裤",
            note: "上浅下深，针织开衫配阔腿裤，通勤不沉闷。",
            imageName: "sample-02",
            minTemp: 14,
            maxTemp: 22,
            occasion: "通勤上班"
        ),
        StyleSample(
            id: "sample-03",
            title: "浅蓝衬衫＋灰西裤",
            note: "版型利落，衬衫配西裤，适合会议或见客户的日子。",
            imageName: "sample-03",
            minTemp: 15,
            maxTemp: 24,
            occasion: "通勤上班"
        ),
        StyleSample(
            id: "sample-04",
            title: "驼色大衣＋黑高领",
            note: "黑色高领打底，外搭驼色大衣，冷了加一件就够。",
            imageName: "sample-04",
            minTemp: -5,
            maxTemp: 12,
            occasion: "通勤上班"
        ),
        StyleSample(
            id: "sample-05",
            title: "亚麻衬衫＋米色半裙",
            note: "同色系搭配，周末出门轻便，不需要复杂配饰。",
            imageName: "sample-05",
            minTemp: 20,
            maxTemp: 30,
            occasion: "日常休闲"
        ),
        StyleSample(
            id: "sample-06",
            title: "灰卫衣＋黑色运动裤",
            note: "走路多的日子穿它，运动鞋同色，简单舒服。",
            imageName: "sample-06",
            minTemp: 8,
            maxTemp: 20,
            occasion: "运动健身"
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

    /// 按当前温度优先匹配；温度区间和场合都不命中时，退回温度最接近的示例，保证今日页不空。
    static func samples(matching temperature: Int, occasion: String? = nil, limit: Int = 3) -> [StyleSample] {
        let tempMatches = all.filter { temperature >= $0.minTemp && temperature <= $0.maxTemp }
        if let occasion = occasion {
            let exact = tempMatches.filter { $0.occasion == occasion }
            if !exact.isEmpty { return Array(exact.prefix(limit)) }
        }
        if !tempMatches.isEmpty { return Array(tempMatches.prefix(limit)) }

        let nearest = all.sorted { distance($0, to: temperature) < distance($1, to: temperature) }
        return Array(nearest.prefix(limit))
    }

    private static func distance(_ sample: StyleSample, to temperature: Int) -> Int {
        if temperature < sample.minTemp { return sample.minTemp - temperature }
        if temperature > sample.maxTemp { return temperature - sample.maxTemp }
        return 0
    }
}
