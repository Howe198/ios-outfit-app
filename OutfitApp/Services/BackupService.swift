import Foundation
import SwiftData

enum BackupError: LocalizedError {
    case imageUnreadable
    case noBackupEntry
    case invalidPayload(String)
    case writeFailed
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageUnreadable:
            return "图片无法读取或格式不支持"
        case .noBackupEntry:
            return "zip 里没有 backup.json，不是本 App 的备份文件"
        case .invalidPayload(let message):
            return "备份内容不合法：\(message)"
        case .writeFailed:
            return "备份写入后校验失败，请重试"
        case .importFailed(let message):
            return "恢复失败：\(message)"
        }
    }
}

struct BackupSummary {
    let items: Int
    let outfits: Int
    let logs: Int
    let inspirations: Int
    let rules: Int
    let images: Int

    var text: String {
        "衣物 \(items) 件 · 搭配 \(outfits) 套 · 记录 \(logs) 条 · 灵感 \(inspirations) 条 · 规则 \(rules) 条 · 图片 \(images) 张"
    }
}

// MARK: - 备份文件结构

struct BackupPayload: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var items: [ItemRecord]
    var outfits: [OutfitRecord]
    var logs: [LogRecord]
    var inspirations: [InspirationRecord]
    var rules: [RuleRecord]
    var customTags: [String: [String]]
}

struct ItemRecord: Codable {
    var id: UUID
    var name: String
    var category: String
    var color: String
    var seasons: [String]
    var thickness: String
    var occasions: [String]
    var tempMin: Int?
    var tempMax: Int?
    var status: String
    var note: String
    var imageFile: String
    /// 兼容旧备份：旧文件没有这个键，解码为 nil。
    var previousImageFile: String?
    var createdAt: Date
}

struct OutfitRecord: Codable {
    var id: UUID
    var name: String
    var itemIDs: [UUID]
    var occasion: String
    var tempMin: Int?
    var tempMax: Int?
    var source: String
    var isFavorite: Bool
    var note: String
    var createdAt: Date
}

struct LogRecord: Codable {
    var id: UUID
    var date: Date
    var outfitName: String
    var outfitID: UUID?
    var itemIDs: [UUID]
    var note: String
    var createdAt: Date
}

struct InspirationRecord: Codable {
    var id: UUID
    var title: String
    var note: String
    var platform: String
    var sourceDate: Date?
    var imageFile: String
    var linkedItemIDs: [UUID]
    var createdAt: Date
}

struct RuleRecord: Codable {
    var id: UUID
    var title: String
    var note: String
    var kind: String
    var dimension: String
    var value: String
    var points: Int
    var isEnabled: Bool
    var sourceInspirationID: UUID?
    var createdAt: Date
}

// MARK: - 导出 / 导入

/// 一键导出 JSON + 图片为一个 zip；导入时先完整校验再替换，失败不破坏现有数据。
@MainActor
final class BackupService {
    static let shared = BackupService()

    private init() {}

    func export(context: ModelContext, customTags: [String: [String]]) throws -> URL {
        let items = try context.fetch(FetchDescriptor<ClothingItem>())
        let outfits = try context.fetch(FetchDescriptor<Outfit>())
        let logs = try context.fetch(FetchDescriptor<WearLog>())
        let inspirations = try context.fetch(FetchDescriptor<Inspiration>())
        let rules = try context.fetch(FetchDescriptor<StyleRule>())

        let payload = BackupPayload(
            schemaVersion: 1,
            exportedAt: Date(),
            items: items.map { item in
                ItemRecord(
                    id: item.id,
                    name: item.name,
                    category: item.categoryValue,
                    color: item.primaryColor,
                    seasons: item.seasonsValue,
                    thickness: item.thicknessValue,
                    occasions: item.occasionsValue,
                    tempMin: item.tempMin,
                    tempMax: item.tempMax,
                    status: item.statusValue,
                    note: item.note,
                    imageFile: item.imageFile,
                    previousImageFile: item.previousImageFile,
                    createdAt: item.createdAt
                )
            },
            outfits: outfits.map { outfit in
                OutfitRecord(
                    id: outfit.id,
                    name: outfit.name,
                    itemIDs: outfit.itemIDs,
                    occasion: outfit.occasionValue,
                    tempMin: outfit.tempMin,
                    tempMax: outfit.tempMax,
                    source: outfit.sourceValue,
                    isFavorite: outfit.isFavorite,
                    note: outfit.note,
                    createdAt: outfit.createdAt
                )
            },
            logs: logs.map { log in
                LogRecord(
                    id: log.id,
                    date: log.date,
                    outfitName: log.outfitName,
                    outfitID: log.outfitID,
                    itemIDs: log.itemIDs,
                    note: log.note,
                    createdAt: log.createdAt
                )
            },
            inspirations: inspirations.map { inspiration in
                InspirationRecord(
                    id: inspiration.id,
                    title: inspiration.title,
                    note: inspiration.note,
                    platform: inspiration.platform,
                    sourceDate: inspiration.sourceDate,
                    imageFile: inspiration.imageFile,
                    linkedItemIDs: inspiration.linkedItemIDs,
                    createdAt: inspiration.createdAt
                )
            },
            rules: rules.map { rule in
                RuleRecord(
                    id: rule.id,
                    title: rule.title,
                    note: rule.note,
                    kind: rule.kindValue,
                    dimension: rule.dimensionValue,
                    value: rule.value,
                    points: rule.points,
                    isEnabled: rule.isEnabled,
                    sourceInspirationID: rule.sourceInspirationID,
                    createdAt: rule.createdAt
                )
            },
            customTags: customTags
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(payload)

        var entries: [StoreZip.Entry] = [StoreZip.Entry(name: "backup.json", data: jsonData)]
        var packed = Set<String>()

        func appendImage(_ fileName: String) {
            guard !fileName.isEmpty, !packed.contains(fileName) else { return }
            packed.insert(fileName)
            guard let data = try? Data(contentsOf: ImageStore.shared.url(for: fileName)) else { return }
            entries.append(StoreZip.Entry(name: "images/" + fileName, data: data))
        }

        for item in items {
            appendImage(item.imageFile)
            if let previous = item.previousImageFile { appendImage(previous) }
        }
        for inspiration in inspirations { appendImage(inspiration.imageFile) }

        let archive = StoreZip.make(entries: entries)

        ImageStore.shared.prepare()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let fileName = "衣橱备份-\(formatter.string(from: Date())).zip"
        let url = ImageStore.shared.backupsDirectory.appendingPathComponent(fileName)
        try archive.write(to: url, options: .atomic)

        // 写完后立刻回读校验，避免导出一个打不开的备份
        let readBack = try StoreZip.read(archive)
        guard readBack.count == entries.count else { throw BackupError.writeFailed }

        return url
    }

    func importBackup(from url: URL, context: ModelContext) throws -> BackupSummary {
        let data = try Data(contentsOf: url)
        let entries = try StoreZip.read(data)
        guard let jsonEntry = entries.first(where: { $0.name.lowercased() == "backup.json" }) else {
            throw BackupError.noBackupEntry
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: jsonEntry.data)
        guard payload.schemaVersion == 1 else {
            throw BackupError.invalidPayload("不支持的备份版本：\(payload.schemaVersion)")
        }
        return try restore(payload: payload, imageEntries: entries.filter { $0.name.hasPrefix("images/") }, context: context)
    }

    // MARK: - 内部

    private func restore(payload: BackupPayload, imageEntries: [StoreZip.Entry], context: ModelContext) throws -> BackupSummary {
        // 1. 图片先落到临时目录，全部写入成功后才动现有数据
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("outfit-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        var imageNames: [String] = []
        for entry in imageEntries {
            let name = String(entry.name.dropFirst("images/".count))
            guard !name.isEmpty, !name.contains("/") else { continue }
            try entry.data.write(to: tempDirectory.appendingPathComponent(name), options: .atomic)
            imageNames.append(name)
        }

        // 2. 旧 ID 全部换新，避免唯一约束与历史 ID 冲突；引用一并重映射
        var itemMap: [UUID: UUID] = [:]
        for record in payload.items where itemMap[record.id] == nil { itemMap[record.id] = UUID() }
        var outfitMap: [UUID: UUID] = [:]
        for record in payload.outfits where outfitMap[record.id] == nil { outfitMap[record.id] = UUID() }
        var logMap: [UUID: UUID] = [:]
        for record in payload.logs where logMap[record.id] == nil { logMap[record.id] = UUID() }
        var inspirationMap: [UUID: UUID] = [:]
        for record in payload.inspirations where inspirationMap[record.id] == nil { inspirationMap[record.id] = UUID() }
        var ruleMap: [UUID: UUID] = [:]
        for record in payload.rules where ruleMap[record.id] == nil { ruleMap[record.id] = UUID() }

        func mappedItems(_ ids: [UUID]) -> [UUID] {
            ids.compactMap { itemMap[$0] }
        }

        // 3. 清空现有数据
        try deleteEverything(context: context)
        ImageStore.shared.removeAllImages()

        // 4. 写回图片
        for name in imageNames {
            try ImageStore.shared.copyImage(from: tempDirectory.appendingPathComponent(name), named: name)
        }

        // 5. 写回记录
        for record in payload.items {
            let previousFile = record.previousImageFile.flatMap {
                ImageStore.shared.exists(named: $0) ? $0 : nil
            }
            let item = ClothingItem(
                id: itemMap[record.id] ?? UUID(),
                name: record.name,
                category: ItemCategory(rawValue: record.category) ?? .top,
                primaryColor: record.color,
                seasons: record.seasons,
                thickness: Thickness(rawValue: record.thickness) ?? .medium,
                occasions: record.occasions,
                tempMin: record.tempMin,
                tempMax: record.tempMax,
                status: ItemStatus(rawValue: record.status) ?? .active,
                note: record.note,
                imageFile: record.imageFile,
                previousImageFile: previousFile,
                createdAt: record.createdAt
            )
            context.insert(item)
        }

        for record in payload.outfits {
            let outfit = Outfit(
                id: outfitMap[record.id] ?? UUID(),
                name: record.name,
                itemIDs: mappedItems(record.itemIDs),
                occasion: record.occasion,
                tempMin: record.tempMin,
                tempMax: record.tempMax,
                source: OutfitSource(rawValue: record.source) ?? .manual,
                isFavorite: record.isFavorite,
                note: record.note,
                createdAt: record.createdAt
            )
            context.insert(outfit)
        }

        for record in payload.logs {
            let log = WearLog(
                id: logMap[record.id] ?? UUID(),
                date: record.date,
                outfitName: record.outfitName,
                outfitID: record.outfitID.flatMap { outfitMap[$0] },
                itemIDs: mappedItems(record.itemIDs),
                note: record.note,
                createdAt: record.createdAt
            )
            context.insert(log)
        }

        for record in payload.inspirations {
            let inspiration = Inspiration(
                id: inspirationMap[record.id] ?? UUID(),
                title: record.title,
                note: record.note,
                platform: record.platform,
                sourceDate: record.sourceDate,
                imageFile: record.imageFile,
                linkedItemIDs: mappedItems(record.linkedItemIDs),
                createdAt: record.createdAt
            )
            context.insert(inspiration)
        }

        for record in payload.rules {
            let value: String
            if record.dimension == RuleDimension.item.rawValue, let oldID = UUID(uuidString: record.value) {
                value = itemMap[oldID]?.uuidString ?? record.value
            } else {
                value = record.value
            }
            let rule = StyleRule(
                id: ruleMap[record.id] ?? UUID(),
                title: record.title,
                note: record.note,
                kind: RuleKind(rawValue: record.kind) ?? .bonus,
                dimension: RuleDimension(rawValue: record.dimension) ?? .color,
                value: value,
                points: record.points,
                isEnabled: record.isEnabled,
                sourceInspirationID: record.sourceInspirationID.flatMap { inspirationMap[$0] },
                createdAt: record.createdAt
            )
            context.insert(rule)
        }

        try context.save()

        // 6. 回读核对数量
        let itemCount = try context.fetch(FetchDescriptor<ClothingItem>()).count
        let outfitCount = try context.fetch(FetchDescriptor<Outfit>()).count
        let logCount = try context.fetch(FetchDescriptor<WearLog>()).count
        let inspirationCount = try context.fetch(FetchDescriptor<Inspiration>()).count
        let ruleCount = try context.fetch(FetchDescriptor<StyleRule>()).count

        guard itemCount == payload.items.count,
              outfitCount == payload.outfits.count,
              logCount == payload.logs.count,
              inspirationCount == payload.inspirations.count,
              ruleCount == payload.rules.count
        else {
            throw BackupError.importFailed("恢复后数量与备份不一致，请重新导入或先用备份文件核对")
        }

        let restoredImages = imageNames.filter { ImageStore.shared.exists(named: $0) }.count
        return BackupSummary(
            items: itemCount,
            outfits: outfitCount,
            logs: logCount,
            inspirations: inspirationCount,
            rules: ruleCount,
            images: restoredImages
        )
    }

    private func deleteEverything(context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<ClothingItem>()) { context.delete(item) }
        for outfit in try context.fetch(FetchDescriptor<Outfit>()) { context.delete(outfit) }
        for log in try context.fetch(FetchDescriptor<WearLog>()) { context.delete(log) }
        for inspiration in try context.fetch(FetchDescriptor<Inspiration>()) { context.delete(inspiration) }
        for rule in try context.fetch(FetchDescriptor<StyleRule>()) { context.delete(rule) }
        try context.save()
    }
}
