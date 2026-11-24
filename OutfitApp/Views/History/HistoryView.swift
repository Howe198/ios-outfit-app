import SwiftUI
import SwiftData

private struct DaySelection: Identifiable {
    let date: Date
    var id: Double { date.timeIntervalSince1970 }
}

/// 穿搭日历 + 我的（设置入口）。一天一条记录，可回看、可改备注。
struct HistoryView: View {
    @Query(sort: \WearLog.date, order: .reverse) private var logs: [WearLog]
    @State private var anchor = Date()
    @State private var selectedDay: DaySelection?

    private var calendar: Calendar { DateText.calendar }

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            weekdayHeader
            monthGrid
            Spacer(minLength: 0)
            NavigationLink {
                SettingsView()
            } label: {
                HStack {
                    Label("标签与规则设置、导出备份", systemImage: "gearshape")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .cardBackground()
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("日历与我的")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDay) { selection in
            DayDetailView(date: selection.date)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(DateText.monthTitle(anchor))
                .font(.headline)
            Spacer()
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal, 24)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<monthCells.count, id: \.self) { index in
                if let day = monthCells[index] {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func dayCell(_ day: Date) -> some View {
        let dayLog = log(on: day)
        let isToday = calendar.isDateInToday(day)
        return Button {
            selectedDay = DaySelection(date: day)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline)
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                Circle()
                    .fill(dayLog == nil ? Color.clear : Color.accentColor)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isToday ? Color(.tertiarySystemFill) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return [] }
        let firstDay = interval.start
        let weekday = calendar.component(.weekday, from: firstDay)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        let range = calendar.range(of: .day, in: .month, for: firstDay) ?? 1..<2
        for offset in range {
            if let date = calendar.date(byAdding: .day, value: offset - 1, to: firstDay) {
                cells.append(date)
            }
        }
        return cells
    }

    private func log(on day: Date) -> WearLog? {
        logs.first { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private func shiftMonth(_ delta: Int) {
        if let newAnchor = calendar.date(byAdding: .month, value: delta, to: anchor) {
            anchor = newAnchor
        }
    }
}

// MARK: - 单日详情

private struct DayDetailView: View {
    let date: Date

    @Environment(\.modelContext) private var context
    @Query private var logs: [WearLog]
    @Query private var items: [ClothingItem]
    @Environment(\.dismiss) private var dismiss

    @State private var note = ""
    @State private var loaded = false
    @State private var showDelete = false

    private var log: WearLog? {
        logs.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(DateText.full(date))
                        .font(.title3).bold()

                    if let log = log {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(log.outfitName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                        }
                        .cardBackground()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("当天备注")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            TextField("冷不冷、舒不舒服、要不要再穿", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                            Button("保存备注") {
                                log.note = note
                            }
                            .buttonStyle(.bordered)
                        }
                        .cardBackground()

                        Button(role: .destructive) {
                            showDelete = true
                        } label: {
                            Label("删除这条记录", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("这天没有记录")
                                .font(.headline)
                            Text("在「今日」页点「记今日穿搭」即可补上当天的穿着。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .cardBackground()
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("当天穿搭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                if !loaded {
                    note = log?.note ?? ""
                    loaded = true
                }
            }
            .confirmationDialog("删除这天的记录？", isPresented: $showDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let log = log {
                        context.delete(log)
                    }
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
