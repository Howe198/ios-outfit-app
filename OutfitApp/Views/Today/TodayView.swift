import SwiftUI
import SwiftData

/// 今日：定位天气 + 自动判断场合 → 生成 1–3 套 → 一键记为今日穿搭。
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var items: [ClothingItem]
    @Query private var outfits: [Outfit]
    @Query(sort: \WearLog.date, order: .reverse) private var logs: [WearLog]
    @Query private var rules: [StyleRule]

    @AppStorage("today.temperature") private var temperature: Int = 22
    @AppStorage("today.occasion") private var occasion: String = "通勤上班"
    @AppStorage("today.manualTemperature") private var manualTemperature: Bool = false

    @State private var result: RecommendationResult?
    @State private var page = 0
    @State private var message: String?
    @State private var showInspirations = false
    @State private var weatherPhase: WeatherPhase = .idle
    @State private var occasionLocked = false

    private var band: TempBand { TempBand.from(celsius: temperature) }
    private var todayLog: WearLog? { logs.first { Calendar.current.isDateInToday($0.date) } }
    private var todayInspirations: [StyleSample] {
        InspirationLibrary.samples(matching: temperature, occasion: occasion, limit: 3)
    }
    private var isWeekend: Bool {
        let weekday = DateText.calendar.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7
    }

    /// 本地规则判断场合：周末 → 日常休闲；工作日 → 通勤上班；极端气温不强求正式穿着。
    private var autoOccasion: String {
        if temperature <= 3 || temperature >= 33 { return "日常休闲" }
        return isWeekend ? "日常休闲" : "通勤上班"
    }

    private var autoOccasionReason: String {
        if temperature <= 3 || temperature >= 33 { return "极端气温，按日常休闲" }
        return isWeekend ? "周末，按日常休闲" : "工作日，按通勤上班"
    }

    private var pageItems: [RecommendedOutfit] {
        guard let result = result else { return [] }
        let start = page * 3
        guard start < result.outfits.count else { return [] }
        return Array(result.outfits[start..<min(start + 3, result.outfits.count)])
    }

    private var hasMore: Bool { (result?.outfits.count ?? 0) > (page + 1) * 3 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if let todayLog = todayLog {
                    recordedCard(todayLog)
                }
                recommendationSection
                inspirationSection
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("今日")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .idle = weatherPhase, !manualTemperature {
                await refreshWeather()
            }
            if !occasionLocked { occasion = autoOccasion }
            if result == nil { generate() }
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

            weatherBlock

            Divider()

            occasionBlock

            Button(action: generate) {
                Label("生成今日推荐", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text("定位只用于获取当地天气；坐标会发送给 Open-Meteo 查询气温、发送给 Apple CLGeocoder 反查城市名，不会保存到任何自建服务器。断网或没有权限时可手动填温度，推荐照常生成。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    // MARK: - 天气

    @ViewBuilder
    private var weatherBlock: some View {
        switch weatherPhase {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("正在获取定位天气…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .loaded(let snapshot):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("定位天气", systemImage: "location.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(snapshot.cityName ?? "当前位置") \(snapshot.temperature)℃")
                        .font(.headline)
                        .monospacedDigit()
                }
                HStack(spacing: 16) {
                    Button("刷新") {
                        Task { await refreshWeather() }
                    }
                    Button("改用手动温度") {
                        manualTemperature = true
                        weatherPhase = .idle
                    }
                    Spacer()
                }
                .font(.footnote)
            }

        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Text("定位天气不可用：\(reason)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("重试") {
                        Task { await refreshWeather() }
                    }
                    Button("手动填温度") {
                        manualTemperature = true
                        weatherPhase = .idle
                    }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
            }

        case .idle:
            if manualTemperature {
                VStack(alignment: .leading, spacing: 8) {
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
                    Button("改用定位天气") {
                        manualTemperature = false
                        Task { await refreshWeather() }
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    Task { await refreshWeather() }
                } label: {
                    Label("用定位获取天气", systemImage: "location")
                }
                .font(.footnote)
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 场合

    private var occasionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("场合")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(VocabularyStore.shared.options(for: "场合"), id: \.self) { option in
                        Button {
                            occasion = option
                            occasionLocked = true
                            if result != nil { generate() }
                        } label: {
                            if option == occasion {
                                Label(option, systemImage: "checkmark")
                            } else {
                                Text(option)
                            }
                        }
                    }
                    if occasionLocked {
                        Button("恢复自动判断") {
                            occasionLocked = false
                            occasion = autoOccasion
                            if result != nil { generate() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(occasion)
                            .font(.subheadline).bold()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
            }
            Text(occasionLocked ? "已手动指定场合，可随时恢复自动判断。" : "今天按「\(occasion)」推荐 · \(autoOccasionReason)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        if let result = result {
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

    // MARK: - 今日灵感

    @ViewBuilder
    private var inspirationSection: some View {
        let samples = todayInspirations
        if !samples.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("今日灵感")
                        .font(.headline)
                    Text("\(band.rawValue) · \(band.hint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("查看全部") { showInspirations = true }
                        .font(.subheadline)
                }

                Text("内置示例搭配，只作参考，不代表你已有这些衣物。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(samples) { sample in
                            Button {
                                showInspirations = true
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    StyleSampleImage(sample: sample)
                                        .frame(width: 140, height: 168)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    HStack(spacing: 4) {
                                        Text("灵感")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                        Text(sample.tempText)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(sample.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(width: 140, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .cardBackground()
            .sheet(isPresented: $showInspirations) {
                InspirationGalleryView()
            }
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
            Text("可以：调整温度 / 换一个更常用的场合 / 去衣橱补一件符合温度的单品。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .cardBackground()
    }

    // MARK: - 动作

    private func refreshWeather() async {
        if case .loading = weatherPhase { return }
        weatherPhase = .loading
        do {
            let snapshot = try await WeatherService.currentWeather()
            weatherPhase = .loaded(snapshot)
            temperature = snapshot.temperature
            manualTemperature = false
            if result != nil { generate() }
        } catch {
            weatherPhase = .failed(error.localizedDescription)
            manualTemperature = true
        }
    }

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
