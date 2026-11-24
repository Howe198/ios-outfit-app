import SwiftUI
import SwiftData

/// 今日：设定气温与场合 → 生成 1–3 套 → 一键记为今日穿搭（主路径不超过 3 步）。
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [ClothingItem]
    @Query private var outfits: [Outfit]
    @Query(sort: \WearLog.date, order: .reverse) private var logs: [WearLog]
    @Query private var rules: [StyleRule]

    @AppStorage("today.temperature") private var temperature: Int = 22
    @AppStorage("today.occasion") private var occasion: String = "通勤上班"

    @State private var result: RecommendationResult?
    @State private var page = 0
    @State private var message: String?

    private var band: TempBand { TempBand.from(celsius: temperature) }
    private var todayLog: WearLog? { logs.first { Calendar.current.isDateInToday($0.date) } }

    private var pageItems: [RecommendedOutfit] {
        guard let result else { return [] }
        let start = page * 3
        guard start < result.outfits.count else { return [] }
        return Array(result.outfits[start..<min(start + 3, result.outfits.count)])
    }

    private var hasMore: Bool { (result?.outfits.count ?? 0) > (page + 1) * 3 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if let todayLog {
                    recordedCard(todayLog)
                }
                recommendationSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("今日")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if result == nil && !items.isEmpty {
                generate()
            }
        }
        .alert("提示", isPresented: alertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: - 顶部

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(DateText.monthDay(Date()))
                    .font(.title2).bold()
                Text(DateText.weekday(Date()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(band.rawValue) · \(band.hint)")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }

            Divider()

            HStack {
                Text("气温")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(value: $temperature, in: -20...45, step: 1) {
                    Text("\(temperature)℃")
                        .font(.headline)
                        .monospacedDigit()
                }
                .fixedSize()
            }

            HStack {
                Text("场合")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("场合", selection: $occasion) {
                    ForEach(VocabularyStore.shared.options(for: "场合"), id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Button(action: generate) {
                Label("生成今日推荐", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("温度手动输入，不接任何天气接口；推荐只用本地规则。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    // MARK: - 今日记录

    private func recordedCard(_ log: WearLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("今天已记录", systemImage: "checkmark.seal")
                    .font(.subheadline).bold()
                Spacer()
                Text(DateText.full(log.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(log.outfitName)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                ForEach(log.itemIDs, id: \.self) { id in
                    if let item = items.first(where: { $0.id == id }) {
                        ItemThumbnail(fileName: item.imageFile, size: 48)
                    }
                }
            }
        }
        .cardBackground()
    }

    // MARK: - 推荐

    @ViewBuilder
    private var recommendationSection: some View {
        if let result {
            if result.outfits.isEmpty {
                issueCard(result.issue ?? "当前条件下没有可用的组合。")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("今日推荐")
                            .font(.headline)
                        Text("\(result.outfits.count) 套")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if hasMore {
                            Button("换一套") { page += 1 }
                                .font(.subheadline)
                        } else if page > 0 {
                            Button("回到第一组") { page = 0 }
                                .font(.subheadline)
                        }
                    }

                    ForEach(pageItems) { recommendation in
                        recommendationCard(recommendation)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没有生成推荐")
                    .font(.headline)
                Text("点上面的「生成今日推荐」，会按当前气温和场合，从衣橱里挑 1–3 套。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .cardBackground()
        }
    }

    private func recommendationCard(_ recommendation: RecommendedOutfit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recommendation.title)
                .font(.subheadline).bold()
                .lineLimit(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recommendation.itemIDs, id: \.self) { id in
                        if let item = items.first(where: { $0.id == id }) {
                            VStack(spacing: 6) {
                                ItemThumbnail(fileName: item.imageFile, size: 72)
                                Text(item.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 72)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(recommendation.reasons.prefix(5)), id: \.self) { reason in
                    Text("· \(reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("得分 \(recommendation.score)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    record(recommendation)
                } label: {
                    Label(todayLog == nil ? "记今日穿搭" : "改穿这套", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
        }
        .cardBackground()
    }

    private func issueCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("暂时推荐不出来", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("可以：调整温度档 / 换一个更常用的场合 / 去衣橱补一件符合温度的单品。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    // MARK: - 动作

    private func generate() {
        result = RecommendationEngine.recommend(
            items: items,
            outfits: outfits,
            logs: logs,
            temperature: temperature,
            occasion: occasion,
            rules: rules
        )
        page = 0
    }

    private func record(_ recommendation: RecommendedOutfit) {
        WearLog.record(
            itemIDs: recommendation.itemIDs,
            outfitName: recommendation.title,
            in: context,
            existing: logs
        )
        message = "已记下今天的穿搭"
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { newValue in if !newValue { message = nil } }
        )
    }
}
