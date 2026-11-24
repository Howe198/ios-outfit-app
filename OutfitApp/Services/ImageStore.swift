import Foundation
import UIKit
import ImageIO

/// 图片只存 App 沙盒（Application Support/Images），数据库只存文件名。
/// 备份统一放在 Documents/Backups，配合「文件」App 可直接拷出。
final class ImageStore {
    static let shared = ImageStore()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

    private init() {
        prepare()
    }

    var imagesDirectory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Images", isDirectory: true)
    }

    var backupsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups", isDirectory: true)
    }

    func prepare() {
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
    }

    func url(for name: String) -> URL {
        imagesDirectory.appendingPathComponent(name)
    }

    func exists(named name: String) -> Bool {
        !name.isEmpty && fileManager.fileExists(atPath: url(for: name).path)
    }

    /// 保存照片数据，返回沙盒内的文件名。会统一压到最长边 1600px 的 JPEG，控制体积。
    @discardableResult
    func save(data: Data, name: String? = nil) throws -> String {
        prepare()
        guard let normalized = Self.normalizedJPEG(data) else {
            throw BackupError.imageUnreadable
        }
        let fileName = name ?? (UUID().uuidString + ".jpg")
        try normalized.write(to: url(for: fileName), options: .atomic)
        return fileName
    }

    /// 从沙盒原文件直接拷入（导入备份用，避免二次压缩）
    func copyImage(from source: URL, named name: String) throws {
        prepare()
        let destination = url(for: name)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    func image(named name: String, maxPixel: CGFloat) -> UIImage? {
        guard !name.isEmpty else { return nil }
        let key = "\(name)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let fileURL = url(for: name)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    func delete(named name: String) {
        guard !name.isEmpty else { return }
        try? fileManager.removeItem(at: url(for: name))
    }

    func removeAllImages() {
        try? fileManager.removeItem(at: imagesDirectory)
        prepare()
    }

    static func normalizedJPEG(_ data: Data, maxSide: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        var target = image
        if longest > maxSide {
            let scale = maxSide / longest
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            target = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        return target.jpegData(compressionQuality: quality)
    }
}
