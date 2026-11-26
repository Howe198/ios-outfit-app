import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo

enum GarmentPart {
    case upper
    case lower
    case dress

    var priorCategory: ItemCategory {
        switch self {
        case .upper: return .top
        case .lower: return .bottom
        case .dress: return .dress
        }
    }

    /// 上装平铺时主轴向水平；下装/连衣裙主轴向垂直。
    var verticalMajorAxis: Bool {
        switch self {
        case .upper: return false
        case .lower, .dress: return true
        }
    }
}

struct GarmentCandidate: Identifiable {
    let id = UUID()
    let image: UIImage
    let category: ItemCategory
    let colorName: String?
    let part: GarmentPart

    var suggestedName: String {
        if let colorName = colorName, !colorName.isEmpty {
            return "\(colorName)色\(category.rawValue)"
        }
        return category.rawValue
    }
}

struct PipelineOutcome {
    let candidates: [GarmentCandidate]
    let message: String?
}

/// 本机照片流水线：人物检测 → 姿态区域 + 人像分割 → 上/下装分件 → 摆正裁剪。
/// 全部用 iOS 原生 Vision / Core Image；不联网、不上传、不下载第三方模型。
enum GarmentPipeline {

    // MARK: - 人物检测与选人

    /// 返回 Vision 坐标系（原点左下）的归一化人物框，按面积从大到小。
    static func detectPersons(in image: UIImage) async -> [CGRect] {
        await Task.detached(priority: .userInitiated) {
            let normalized = normalizedImage(image)
            guard let cgImage = normalized.cgImage else { return [] }
            let request = VNDetectHumanRectanglesRequest()
            request.upperBodyOnly = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                let boxes = (request.results ?? []).map(\.boundingBox)
                return boxes.sorted { $0.width * $0.height > $1.width * $1.height }
            } catch {
                return []
            }
        }.value
    }

    /// 把 Vision 归一化人物框（原点左下）裁成一张 UIImage，四周留少量余量。
    static func cropPerson(from image: UIImage, visionRect: CGRect, padding: CGFloat = 0.04) -> UIImage? {
        let normalized = normalizedImage(image)
        guard let cgImage = normalized.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let expanded = visionRect.insetBy(dx: -padding, dy: -padding)
        let x = max(0, expanded.minX * width)
        let y = max(0, (1 - expanded.maxY) * height)
        let maxX = min(width, expanded.maxX * width)
        let maxY = min(height, (1 - expanded.minY) * height)
        let rect = CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
        guard rect.width >= 20, rect.height >= 20,
              let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    // MARK: - 主流程

    static func process(_ image: UIImage) async -> PipelineOutcome {
        await Task.detached(priority: .userInitiated) {
            await processSync(image)
        }.value
    }

    private static func processSync(_ image: UIImage) async -> PipelineOutcome {
        let source = resized(normalizedImage(image), maxSide: 2560)
        guard let cgImage = source.cgImage else {
            return PipelineOutcome(candidates: [], message: "图片读取失败，已保留原图。")
        }
        let sourceExtent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        // 1. 人体姿态
        let poseRequest = VNDetectHumanBodyPoseRequest()
        do {
            try handler.perform([poseRequest])
        } catch {
            return PipelineOutcome(candidates: [], message: "没能识别到完整人物姿态，已保留原图，请手动填写。")
        }
        guard let observation = poseRequest.results?.first,
              let joints = Joints(observation: observation) else {
            return PipelineOutcome(candidates: [], message: "没检测到清晰的人体姿态，已保留原图，请手动填写。")
        }

        // 2. 人像分割（只区分人与背景）
        let segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .accurate
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try handler.perform([segmentationRequest])
        } catch {
            return PipelineOutcome(candidates: [], message: "本机分割失败，已保留原图，请手动填写。")
        }
        guard let maskBuffer = segmentationRequest.results?.first?.pixelBuffer else {
            return PipelineOutcome(candidates: [], message: "本机分割没有结果，已保留原图，请手动填写。")
        }

        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        let sourceCIImage = CIImage(cgImage: cgImage)
        let personMask = alignedMask(from: maskBuffer, to: sourceExtent)

        // 3. 全身先判一次是否是连衣裙/一体式
        if let fullRect = joints.fullRect(in: sourceExtent),
           let fullCutout = cutout(source: sourceCIImage, mask: personMask, region: fullRect, extent: sourceExtent, context: ciContext),
           hasContent(fullCutout) {
            let guess = await ClothingVision.recognize(fullCutout)
            if guess.category == .dress {
                let flattened = flatten(fullCutout, part: .dress)
                return PipelineOutcome(candidates: [
                    GarmentCandidate(
                        image: flattened,
                        category: .dress,
                        colorName: guess.colorName,
                        part: .dress
                    )
                ], message: nil)
            }
        }

        // 4. 上装 / 下装分别出图
        var candidates: [GarmentCandidate] = []
        if let upperRect = joints.upperRect(in: sourceExtent),
           let cutoutImage = cutout(source: sourceCIImage, mask: personMask, region: upperRect, extent: sourceExtent, context: ciContext),
           hasContent(cutoutImage) {
            let guess = await ClothingVision.recognize(cutoutImage, categoryHint: .top)
            let category = resolvedCategory(guess.category, prior: .top)
            candidates.append(
                GarmentCandidate(
                    image: flatten(cutoutImage, part: .upper),
                    category: category,
                    colorName: guess.colorName,
                    part: .upper
                )
            )
        }

        if let lowerRect = joints.lowerRect(in: sourceExtent),
           let cutoutImage = cutout(source: sourceCIImage, mask: personMask, region: lowerRect, extent: sourceExtent, context: ciContext),
           hasContent(cutoutImage) {
            let guess = await ClothingVision.recognize(cutoutImage, categoryHint: .bottom)
            let category = resolvedCategory(guess.category, prior: .bottom)
            candidates.append(
                GarmentCandidate(
                    image: flatten(cutoutImage, part: .lower),
                    category: category,
                    colorName: guess.colorName,
                    part: .lower
                )
            )
        }

        if candidates.isEmpty {
            return PipelineOutcome(candidates: [], message: "没能把衣物从人物中分离出来，已保留原图，请手动填写。")
        }

        let message = candidates.count == 1
            ? "只分离出 1 件衣物；如果照片里还有另一件，请手动再添加一条。"
            : nil
        return PipelineOutcome(candidates: candidates, message: message)
    }

    private static func resolvedCategory(_ guessed: ItemCategory?, prior: ItemCategory) -> ItemCategory {
        guard let guessed = guessed else { return prior }
        switch prior {
        case .top:
            if guessed == .top || guessed == .outerwear || guessed == .dress { return guessed }
            return .top
        case .bottom:
            if guessed == .bottom || guessed == .dress { return guessed }
            return .bottom
        default:
            return guessed
        }
    }

    // MARK: - 遮罩与裁剪

    private static func alignedMask(from pixelBuffer: CVPixelBuffer, to extent: CGRect) -> CIImage {
        let mask = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX = extent.width / max(mask.extent.width, 1)
        let scaleY = extent.height / max(mask.extent.height, 1)
        return mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }

    private static func cutout(
        source: CIImage,
        mask: CIImage,
        region: CGRect,
        extent: CGRect,
        context: CIContext
    ) -> UIImage? {
        let safeRegion = region.intersection(extent)
        guard safeRegion.width > 8, safeRegion.height > 8 else { return nil }

        let regionMask = CIImage(color: CIColor.white)
            .cropped(to: safeRegion)
            .applyingGaussianBlur(sigma: 3)
            .cropped(to: extent)
        guard let combined = CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: mask,
            kCIInputBackgroundImageKey: regionMask
        ])?.outputImage else { return nil }

        let clear = CIImage(color: CIColor.clear).cropped(to: extent)
        guard let blend = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: source,
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: combined
        ])?.outputImage else { return nil }

        let cropRect = safeRegion.insetBy(dx: -6, dy: -6).intersection(extent)
        guard let output = context.createCGImage(blend, from: cropRect) else { return nil }
        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    private static func hasContent(_ image: UIImage) -> Bool {
        guard let box = alphaBoundingBox(image), let cg = image.cgImage else { return false }
        let area = CGFloat(cg.width * cg.height)
        return box.width * box.height > area * 0.02
    }

    // MARK: - 摆正 / 干净底

    /// 任务书允许的回落方案：alpha 裁边 + 主轴角度校正（限 ±20°）+ 等比缩到 1800 + 6% 留白。
    /// 不做生成式补全，褶皱不会消失。
    static func flatten(_ image: UIImage, part: GarmentPart) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let trimmed: UIImage
        if let box = alphaBoundingBox(image), box.width > 4, box.height > 4,
           let cropped = cgImage.cropping(to: box) {
            trimmed = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        } else {
            trimmed = image
        }

        let angle = majorAxisAngle(of: trimmed)
        let desired: CGFloat = part.verticalMajorAxis ? 90 : 0
        var delta = desired - angle
        while delta > 90 { delta -= 180 }
        while delta < -90 { delta += 180 }
        if abs(delta) <= 20, abs(delta) >= 1 {
            let rotated = rotate(trimmed, degrees: delta)
            return paddedAndScaled(rotated)
        }
        return paddedAndScaled(trimmed)
    }

    private static func paddedAndScaled(_ image: UIImage) -> UIImage {
        var content = image
        if let box = alphaBoundingBox(image), let cg = image.cgImage,
           box.width > 4, box.height > 4,
           let cropped = cg.cropping(to: box) {
            content = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        }

        let maxSide: CGFloat = 1800
        let size = content.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let padding = max(target.width, target.height) * 0.06
        let canvas = CGSize(width: target.width + padding * 2, height: target.height + padding * 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        return renderer.image { _ in
            content.draw(in: CGRect(
                x: (canvas.width - target.width) / 2,
                y: (canvas.height - target.height) / 2,
                width: target.width,
                height: target.height
            ))
        }
    }

    private static func rotate(_ image: UIImage, degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180
        let width = image.size.width
        let height = image.size.height
        let newSize = CGSize(
            width: abs(width * cos(radians)) + abs(height * sin(radians)),
            height: abs(width * sin(radians)) + abs(height * cos(radians))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: radians)
            image.draw(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        }
    }

    /// 用 alpha 像素的二阶中心矩估计主轴角度（度）。
    private static func majorAxisAngle(of image: UIImage) -> CGFloat {
        guard let samples = alphaSamples(image, targetSide: 48), samples.count > 20 else { return 0 }
        let n = CGFloat(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / n
        let meanY = samples.reduce(0) { $0 + $1.y } / n
        var covXX: CGFloat = 0
        var covYY: CGFloat = 0
        var covXY: CGFloat = 0
        for point in samples {
            let dx = point.x - meanX
            let dy = point.y - meanY
            covXX += dx * dx
            covYY += dy * dy
            covXY += dx * dy
        }
        let angle = 0.5 * atan2(2 * covXY, covXX - covYY)
        return angle * 180 / .pi
    }

    private static func alphaSamples(_ image: UIImage, targetSide: Int) -> [CGPoint]? {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data),
              cgImage.bitsPerPixel >= 32,
              cgImage.bitsPerComponent == 8 else { return nil }
        let alphaOffset = alphaOffset(for: cgImage.alphaInfo)
        guard alphaOffset >= 0 else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let stepX = max(1, width / targetSide)
        let stepY = max(1, height / targetSide)
        var points: [CGPoint] = []
        points.reserveCapacity(targetSide * targetSide)
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = y * bytesPerRow + x * 4 + alphaOffset
                if pointer[offset] > 24 {
                    points.append(CGPoint(x: CGFloat(x) / CGFloat(width), y: CGFloat(y) / CGFloat(height)))
                }
            }
        }
        return points
    }

    /// 返回 CGImage 像素坐标（左上原点）中的非透明包围盒。
    private static func alphaBoundingBox(_ image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data),
              cgImage.bitsPerPixel >= 32,
              cgImage.bitsPerComponent == 8 else { return nil }
        let alphaOffset = alphaOffset(for: cgImage.alphaInfo)
        guard alphaOffset >= 0 else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let offset = y * bytesPerRow + x * 4 + alphaOffset
                if pointer[offset] > 20 {
                    found = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard found else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private static func alphaOffset(for info: CGImageAlphaInfo) -> Int {
        switch info {
        case .premultipliedFirst, .first:
            return 0
        case .premultipliedLast, .last:
            return 3
        default:
            return -1
        }
    }

    // MARK: - 本机增强（低清源图可选）

    static func enhance(_ image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return nil }
            let input = CIImage(cgImage: cgImage)
            let filter = CIFilter.unsharpMask()
            filter.inputImage = input
            filter.radius = 2.2
            filter.intensity = 0.55
            guard let output = filter.outputImage else { return nil }
            let context = CIContext(options: nil)
            guard let result = context.createCGImage(output, from: input.extent) else { return nil }
            return UIImage(cgImage: result, scale: image.scale, orientation: image.imageOrientation)
        }.value
    }

    // MARK: - 工具

    static func pixelSize(of image: UIImage) -> CGSize {
        if let cg = image.cgImage { return CGSize(width: cg.width, height: cg.height) }
        return CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = pixelSize(of: image)
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

// MARK: - 姿态区域

private struct Joints {
    let points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]

    init?(observation: VNHumanBodyPoseObservation) {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }
        self.points = points.filter { $0.value.confidence >= 0.3 }
    }

    private func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        points[name]?.location
    }

    func upperRect(in extent: CGRect) -> CGRect? {
        guard let neck = point(.neck),
              let leftShoulder = point(.leftShoulder),
              let rightShoulder = point(.rightShoulder),
              let leftHip = point(.leftHip) ?? point(.root),
              let rightHip = point(.rightHip) ?? point(.root) else { return nil }
        let xMin = min(leftShoulder.x, rightShoulder.x, leftHip.x, rightHip.x) - 0.08
        let xMax = max(leftShoulder.x, rightShoulder.x, leftHip.x, rightHip.x) + 0.08
        let top = neck.y + 0.04
        let bottom = min(leftHip.y, rightHip.y) - 0.06
        return normalizedRect(xMin: xMin, xMax: xMax, yBottom: bottom, yTop: top, extent: extent)
    }

    func lowerRect(in extent: CGRect) -> CGRect? {
        guard let leftHip = point(.leftHip) ?? point(.root),
              let rightHip = point(.rightHip) ?? point(.root) else { return nil }
        let knees = [point(.leftKnee), point(.rightKnee)].compactMap { $0 }
        let ankles = [point(.leftAnkle), point(.rightAnkle)].compactMap { $0 }
        let bottomPoints = ankles.isEmpty ? knees : ankles
        guard let bottom = bottomPoints.min(by: { $0.y < $1.y }) else { return nil }

        let xMin = min(leftHip.x, rightHip.x, bottom.x) - 0.1
        let xMax = max(leftHip.x, rightHip.x, bottom.x) + 0.1
        let top = max(leftHip.y, rightHip.y) + 0.03
        let yBottom = bottom.y - 0.03
        return normalizedRect(xMin: xMin, xMax: xMax, yBottom: yBottom, yTop: top, extent: extent)
    }

    func fullRect(in extent: CGRect) -> CGRect? {
        guard let neck = point(.neck),
              let leftShoulder = point(.leftShoulder),
              let rightShoulder = point(.rightShoulder),
              let leftHip = point(.leftHip) ?? point(.root),
              let rightHip = point(.rightHip) ?? point(.root) else { return nil }
        let knees = [point(.leftKnee), point(.rightKnee)].compactMap { $0 }
        let ankles = [point(.leftAnkle), point(.rightAnkle)].compactMap { $0 }
        let bottoms = ankles.isEmpty ? knees : ankles
        guard let bottom = bottoms.min(by: { $0.y < $1.y }) else { return nil }
        let xMin = min(leftShoulder.x, rightShoulder.x, leftHip.x, rightHip.x) - 0.1
        let xMax = max(leftShoulder.x, rightShoulder.x, leftHip.x, rightHip.x) + 0.1
        return normalizedRect(
            xMin: xMin,
            xMax: xMax,
            yBottom: bottom.y - 0.03,
            yTop: neck.y + 0.03,
            extent: extent
        )
    }

    private func normalizedRect(xMin: CGFloat, xMax: CGFloat, yBottom: CGFloat, yTop: CGFloat, extent: CGRect) -> CGRect? {
        let x0 = max(0, min(1, xMin)) * extent.width
        let x1 = max(0, min(1, xMax)) * extent.width
        let y0 = max(0, min(1, yBottom)) * extent.height
        let y1 = max(0, min(1, yTop)) * extent.height
        guard x1 - x0 > 8, y1 - y0 > 8 else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
