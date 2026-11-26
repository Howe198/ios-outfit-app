import SwiftUI
import SwiftData

private struct CategoryCount: Identifiable {
    let category: ItemCategory
    let count: Int
    var id: String { category.rawValue }
}

private struct WornEntry: Identifiable {
    let item: ClothingItem
    let count: Int
    var id: UUID { item.id }
}

/// 我的：偏好设置、本地统计、设置与导出入口 + 穿搭记录（按日期倒序的列表，点进可改备注 / 删记录）。
struct MyView: View {
    @Query(sort: \WearLog.date, order: .reverse) private var logs: [WearLog]
    @Query private var items: [ClothingItem]

    @AppStorage("settings.temperatureUnit") private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage("settings.inspirationWeatherFirst") private var inspirationWeatherFirst = true

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private var activeCount: Int { items.filter(\.isActive).count }
    private var archivedCount: Int { items.count - activeCount }

    private var categoryCounts: [CategoryCount] {
        ItemCategory.allCases.map { category in
            CategoryCount(category: category, count: items.filter { $0.category == category }.count)
        }
    }

    /// 最常穿：按 WearLog 的 itemIDs 出现次数统计，次数相同按名称排。
    private var mostWorn: [WornEntry] {
        var counts: [UUID: Int] = [:]
        for log in logs {
            for id in log.itemIDs {
                counts[id, default: 0] += 1
            }
        }
        return counts.compactMap { id, count in
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            return WornEntry(item: item, count: count)
        }
        .sorted {
            if $0.count == $1.count { return $0.item.name < $1.item.name }
            return $0.count > $1.count
        }
        .prefix(5)
        .map { $0 }
    }

    /// 本月记录天数：按 WearLog 日期落在本月的不同「天」计数。
    private var monthRecordDays: Int {
        let calendar = DateText.calendar
        let now = Date()
        guard let month = calendar.dateInterval(of: .month, for: now) else { return 0 }
        let days = logs.filter { month.contains($0.date) }
            .map { calendar.startOfDay(for: $0.date) }
        return Set(days).count
    }

    /// 连续记录天数：从今天往前数；今天还没记录时从昨天起算，避免把「今天还没记」算成断签。
    private var streakDays: Int {
        let calendar = DateText.calendar
        let daySet = Set(logs.map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: Date())
        if !daySet.contains(cursor),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        var count = 0
        while daySet.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            if count > logs.count { break }
        }
        return count
    }

    /// 衣物照片占用：只统计当前衣物引用的沙盒图片文件。
    private var photoBytes: Int64 {
        items.reduce(0) { partial, item in
            let path = ImageStore.shared.url(for: item.imageFile).path
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            return partial + size
        }
    }

    private var photoSizeText: String {
        ByteCountFormatter.string(fromByteCount: photoBytes, countStyle: .file)
    }

    var body: some View {
        List {
            Section("偏好设置") {
                Picker("温度显示", selection: $temperatureUnitRaw) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit.rawValue)
                    }
                }
                Toggle("灵感先看适合今天天气", isOn: $inspirationWeatherFirst)
                Text("关闭后，搭配灵感与今日灵感恢复普通顺序；设置只存在本机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("穿搭统计") {
                LabeledContent("本月记录天数", value: "\(monthRecordDays) 天")
                LabeledContent("连续记录天数", value: "\(streakDays) 天")
                Text("连续记录从今天往前数；今天还没记录时从昨天起算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("衣物统计") {
                LabeledContent("衣物总数", value: "\(items.count) 件")
                LabeledContent("在用 / 归档", value: "\(activeCount) / \(archivedCount) 件")
                ForEach(categoryCounts, id: \.category) { entry in
                    LabeledContent(entry.category.rawValue, value: "\(entry.count) 件")
                }
                LabeledContent("照片占用", value: photoSizeText)
            }

            Section("最常穿") {
                if mostWorn.isEmpty {
                    Text("还没有穿搭记录。先在「今日」页点「记今日穿搭」，这里会按出现次数排出最常穿的单品。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mostWorn, id: \.item.id) { entry in
                        HStack(spacing: 10) {
                            ItemThumbnail(fileName: entry.item.imageFile, size: 36)
                            Text(entry.item.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.count) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("按穿搭记录中出现次数统计；次数相同按名称排序。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("标签与规则设置、导出备份", systemImage: "gearshape")
                }
            }

            Section("穿搭记录") {
                if logs.isEmpty {
                    Text("还没有穿搭记录。在「今日」页点「记今日穿搭」就会出现在这里。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        NavigationLink {
                            WearLogDetailView(log: log)
                        } label: {
                            row(log)
                        }
                    }
                }
            }
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ log: WearLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(DateText.full(log.date))
                    .font(.subheadline).bold()
                Spacer()
                Text(DateText.weekday(log.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(log.outfitName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !log.itemIDs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(log.itemIDs.prefix(5), id: \.self) { id in
                        if let item = items.first(where: { $0.id == id }) {
                            ItemThumbnail(fileName: item.imageFile, size: 36)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 穿搭记录详情

private struct WearLogDetailView: View {
    let log: WearLog

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [ClothingItem]

    @State private var note = ""
    @State private var loaded = false
    @State private var showDelete = false
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DateText.full(log.date))
                        .font(.title3).bold()
                    Text(log.outfitName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !log.itemIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(log.itemIDs, id: \.self) { id in
                                if let item = items.first(where: { $0.id == id }) {
                                    VStack(spacing: 4) {
                                        ItemThumbnail(fileName: item.imageFile, size: 64)
                                        Text(item.name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 64)
                                    }
                                }
                            }
                        }
                    }
                    .cardBackground()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("当天备注")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("冷不冷、舒不舒服、要不要再穿", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    Button("保存备注") {
                        log.note = note
                        saved = true
                    }
                    .buttonStyle(.bordered)
                    if saved {
                        Text("已保存")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .cardBackground()

                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("删除这条记录", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("穿搭记录")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded {
                note = log.note
                loaded = true
            }
        }
        .confirmationDialog("删除这条记录？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                context.delete(log)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除这一天的记录，衣物和搭配不受影响。")
        }
    }
}
