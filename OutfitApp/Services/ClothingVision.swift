import UIKit
import Vision
import CoreImage

/// 本机识别：品类 + 主色。全部在手机本地跑 Vision，不联网、不花钱、不上传照片。
struct ClothingGuess {
    let category: ItemCategory?
    let colorName: String?
    let matchedLabel: String?

    var isEmpty: Bool { category == nil && colorName == nil }
}

enum ClothingVision {

    /// 识别衣物品类与主色；失败返回空结果，由界面回落到手动填写。
    static func recognize(_ image: UIImage) async -> ClothingGuess {
        await Task.detached(priority: .userInitiated) {
            analyze(image)
        }.value
    }

    /// 去背景：iOS 17 原生前景分割。失败返回 nil，界面保留原图。
    static func removeBackground(from image: UIImage) async -> UIImage? {
        guard #available(iOS 17.0, *) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            cutout(image)
        }.value
    }

    // MARK: - 识别

    private static func analyze(_ image: UIImage) -> ClothingGuess {
        let normalized = normalizedImage(image)
        guard let cgImage = normalized.cgImage else {
            return ClothingGuess(category: nil, colorName: nil, matchedLabel: nil)
        }

        var category: ItemCategory?
        var matchedLabel: String?

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            let observations = (request.results ?? []).filter { $0.confidence >= 0.2 }
            for observation in observations.prefix(15) {
                if let mapped = itemCategory(for: observation.identifier) {
                    category = mapped
                    matchedLabel = observation.identifier
                    break
                }
            }
        } catch {
            // 识别失败不阻塞录入
        }

        let colorName = dominantColorName(in: cgImage)
        return ClothingGuess(category: category, colorName: colorName, matchedLabel: matchedLabel)
    }

    /// 关键词按长度从长到短匹配，避免 "shirt" 抢在 "t-shirt" 前面之类的误判。
    private static let categoryKeywords: [(keyword: String, category: ItemCategory)] = [
        ("sweatshirt", .top),
        ("t-shirt", .top),
        ("trousers", .bottom),
        ("trouser", .bottom),
        ("leggings", .bottom),
        ("sneaker", .shoes),
        ("cardigan", .outerwear),
        ("overcoat", .outerwear),
        ("sweater", .top),
        ("jumpsuit", .dress),
        ("hoodie", .top),
        ("jacket", .outerwear),
        ("blazer", .outerwear),
        ("jersey", .top),
        ("blouse", .top),
        ("shorts", .bottom),
        ("skirt", .bottom),
        ("jeans", .bottom),
        ("chino", .bottom),
        ("slacks", .bottom),
        ("shirt", .top),
        ("pants", .bottom),
        ("pant", .bottom),
        ("dress", .dress),
        ("gown", .dress),
        ("coat", .outerwear),
        ("parka", .outerwear),
        ("trench", .outerwear),
        ("boot", .shoes),
        ("shoe", .shoes),
        ("sandal", .shoes),
        ("loafer", .shoes),
        ("slipper", .shoes),
        ("footwear", .shoes),
        ("polo", .top),
        ("tank", .top),
        ("vest", .top),
        ("tee", .top),
        ("handbag", .accessory),
        ("sunglass", .accessory),
        ("scarf", .accessory),
        ("glove", .accessory),
        ("belt", .accessory),
        ("watch", .accessory),
        ("necklace", .accessory),
        ("bracelet", .accessory),
        ("earring", .accessory),
        ("backpack", .accessory),
        ("hat", .accessory),
        ("cap", .accessory),
        ("bag", .accessory),
        ("tie", .accessory),
        ("ring", .accessory)
    ]

    private static func itemCategory(for identifier: String) -> ItemCategory? {
        let lower = identifier.lowercased()
        for entry in categoryKeywords where lower.contains(entry.keyword) {
            return entry.category
        }
        return nil
    }

    // MARK: - 主色

    /// 取画面中心区域的像素，剔除与四角背景相近的颜色，再映射到 12 个常用色名。
    /// 只是近似值，界面会提示用户自行修改。
    private static func dominantColorName(in cgImage: CGImage) -> String? {
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var averaged: (r: Double, g: Double, b: Double)?
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: side * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            let bytes = base.assumingMemoryBound(to: UInt8.self)

            // 四角各取 4×4 小块，估算背景色
            var bgR = 0.0, bgG = 0.0, bgB = 0.0, bgCount = 0.0
            let cornerOrigins = [(0, 0), (side - 4, 0), (0, side - 4), (side - 4, side - 4)]
            for origin in cornerOrigins {
                for y in origin.1..<(origin.1 + 4) {
                    for x in origin.0..<(origin.0 + 4) {
                        let offset = (y * side + x) * 4
                        bgR += Double(bytes[offset]) / 255.0
                        bgG += Double(bytes[offset + 1]) / 255.0
                        bgB += Double(bytes[offset + 2]) / 255.0
                        bgCount += 1
                    }
                }
            }
            guard bgCount > 0 else { return }
            bgR /= bgCount; bgG /= bgCount; bgB /= bgCount

            // 只统计中心 50% 区域，和背景色差异足够大的像素
            let lower = side / 4
            let upper = side - side / 4
            var sumR = 0.0, sumG = 0.0, sumB = 0.0, count = 0.0
            var fallbackR = 0.0, fallbackG = 0.0, fallbackB = 0.0, fallbackCount = 0.0

            for y in lower..<upper {
                for x in lower..<upper {
                    let offset = (y * side + x) * 4
                    let r = Double(bytes[offset]) / 255.0
                    let g = Double(bytes[offset + 1]) / 255.0
                    let b = Double(bytes[offset + 2]) / 255.0

                    fallbackR += r; fallbackG += g; fallbackB += b; fallbackCount += 1

                    let distance = sqrt(pow(r - bgR, 2) + pow(g - bgG, 2) + pow(b - bgB, 2))
                    if distance > 0.18 {
                        sumR += r; sumG += g; sumB += b; count += 1
                    }
                }
            }

            if count >= fallbackCount * 0.2 {
                averaged = (sumR / count, sumG / count, sumB / count)
            } else if fallbackCount > 0 {
                averaged = (fallbackR / fallbackCount, fallbackG / fallbackCount, fallbackB / fallbackCount)
            }
        }

        guard let color = averaged else { return nil }
        return colorName(red: color.r, green: color.g, blue: color.b)
    }

    private static func colorName(red: Double, green: Double, blue: Double) -> String {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: 1
        ).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        let h = hue * 360
        let s = Double(saturation)
        let v = Double(brightness)

        if s < 0.08 {
            if v >= 0.9 { return "白" }
            if v >= 0.28 { return "灰" }
            return "黑"
        }
        if v < 0.15 { return "黑" }

        switch h {
        case 0..<12, 348..<360:
            return s < 0.3 && v > 0.7 ? "粉" : "红"
        case 12..<40:
            if v > 0.82 && s < 0.35 { return "米" }
            if s < 0.45 { return v > 0.55 ? "驼" : "棕" }
            return v > 0.6 ? "驼" : "棕"
        case 40..<70:
            if v > 0.85 && s < 0.25 { return "米" }
            return "黄"
        case 70..<165:
            return "绿"
        case 165..<200:
            return v < 0.45 ? "藏青" : "蓝"
        case 200..<255:
            return v < 0.4 ? "藏青" : "蓝"
        case 255..<330:
            return v > 0.7 && s < 0.35 ? "粉" : "蓝"
        default:
            return "红"
        }
    }

    // MARK: - 去背景

    @available(iOS 17.0, *)
    private static func cutout(_ image: UIImage) -> UIImage? {
        let normalized = normalizedImage(image)
        guard let cgImage = normalized.cgImage else { return nil }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let context = CIContext(options: nil)
            guard let output = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return UIImage(cgImage: output)
        } catch {
            return nil
        }
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
