import SwiftUI
import SwiftData

/// 我的：设置与导出备份入口 + 穿搭记录（按日期倒序的列表，点进可改备注 / 删记录）。
struct MyView: View {
    @Query(sort: \WearLog.date, order: .reverse) private var logs: [WearLog]
    @Query private var items: [ClothingItem]

    var body: some View {
        List {
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
