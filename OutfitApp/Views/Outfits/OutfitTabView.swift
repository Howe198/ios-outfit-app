import SwiftUI
import SwiftData

/// 搭配页：我的搭配 / 搭配灵感（内置示例）/ 灵感收藏（自己的收藏）。
struct OutfitTabView: View {
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("内容", selection: $segment) {
                Text("我的搭配").tag(0)
                Text("搭配灵感").tag(1)
                Text("灵感收藏").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if segment == 0 {
                OutfitListSection()
            } else if segment == 1 {
                InspirationGallerySection()
            } else {
                InspirationListSection()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("搭配")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 搭配灵感（内置示例）

private struct InspirationGallerySection: View {
    @State private var selected: StyleSample?
    @AppStorage("settings.inspirationWeatherFirst") private var weatherFirst = true
    @AppStorage("today.temperature") private var temperature = 22
    @AppStorage("today.hasActiveTemperature") private var hasActiveTemperature = false

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 12),
        GridItem(.flexible(minimum: 0), spacing: 12)
    ]

    private var section: InspirationSection {
        InspirationLibrary.section(
            temperature: hasActiveTemperature ? temperature : nil,
            weatherFirst: weatherFirst
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("内置的日常搭配示例，只作灵感参考，可离线查看；不带货、不抓取任何平台内容。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if weatherFirst && !section.featured.isEmpty {
                    sectionTitle(
                        section.usesTemperature
                            ? "适合今天 · \(section.temperature ?? temperature)℃"
                            : "适合本季",
                        count: section.featured.count
                    )
                    grid(section.featured, badge: section.usesTemperature ? "适合今天" : "适合本季")

                    if !section.remaining.isEmpty {
                        Text("其他灵感")
                            .font(.subheadline).bold()
                            .padding(.top, 4)
                        grid(section.remaining, badge: "灵感")
                    }
                } else {
                    if weatherFirst && section.usesTemperature && section.featured.isEmpty {
                        Text("今天没有完全落在温度区间的示例，下面按接近温度排序。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    grid(section.remaining, badge: "灵感")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .sheet(item: $selected) { sample in
            StyleSampleDetailView(sample: sample)
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline).bold()
            Text("\(count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func grid(_ samples: [StyleSample], badge: String) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(samples) { sample in
                Button {
                    selected = sample
                } label: {
                    StyleSampleCard(sample: sample, badgeText: badge)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 今日页与搭配页共用的灵感网格（只读）。
struct InspirationGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: StyleSample?
    @AppStorage("settings.inspirationWeatherFirst") private var weatherFirst = true
    @AppStorage("today.temperature") private var temperature = 22
    @AppStorage("today.hasActiveTemperature") private var hasActiveTemperature = false

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 12),
        GridItem(.flexible(minimum: 0), spacing: 12)
    ]

    private var section: InspirationSection {
        InspirationLibrary.section(
            temperature: hasActiveTemperature ? temperature : nil,
            weatherFirst: weatherFirst
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("内置的日常搭配示例，只作灵感参考，可离线查看；不带货、不抓取任何平台内容。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if weatherFirst && !section.featured.isEmpty {
                        sectionTitle(
                            section.usesTemperature
                                ? "适合今天 · \(section.temperature ?? temperature)℃"
                                : "适合本季",
                            count: section.featured.count
                        )
                        grid(section.featured, badge: section.usesTemperature ? "适合今天" : "适合本季")

                        if !section.remaining.isEmpty {
                            Text("其他灵感")
                                .font(.subheadline).bold()
                                .padding(.top, 4)
                            grid(section.remaining, badge: "灵感")
                        }
                    } else {
                        if weatherFirst && section.usesTemperature && section.featured.isEmpty {
                            Text("今天没有完全落在温度区间的示例，下面按接近温度排序。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        grid(section.remaining, badge: "灵感")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("搭配灵感")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $selected) { sample in
                StyleSampleDetailView(sample: sample)
            }
        }
    }

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.subheadline).bold()
            Text("\(count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func grid(_ samples: [StyleSample], badge: String) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(samples) { sample in
                Button {
                    selected = sample
                } label: {
                    StyleSampleCard(sample: sample, badgeText: badge)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct StyleSampleCard: View {
    let sample: StyleSample
    var badgeText: String = "灵感"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color(.tertiarySystemFill))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        StyleSampleImage(sample: sample)
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(badgeText)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }

            Text(sample.title)
                .font(.subheadline).bold()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text(sample.occasion)
                Text(sample.tempText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(sample.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

struct StyleSampleImage: View {
    let sample: StyleSample

    var body: some View {
        Group {
            if let image = InspirationLibrary.image(for: sample) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StyleSampleDetailView: View {
    let sample: StyleSample
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StyleSampleImage(sample: sample)
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text(sample.title)
                        .font(.title3).bold()

                    HStack(spacing: 10) {
                        Text(sample.occasion)
                        Text(sample.tempText)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(sample.note)
                        .font(.subheadline)

                    Text("这是内置示例，仅作灵感参考；不能一键穿上，也不代表你已有这些衣物。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("灵感详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 我的搭配

private struct OutfitListSection: View {
    private enum Route: Identifiable {
        case create
        case edit(Outfit)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let outfit): return outfit.id.uuidString
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @Query private var items: [ClothingItem]
    @Query(sort: \WearLog.date, order: .reverse) private var logs: [WearLog]

    @State private var route: Route?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if outfits.isEmpty {
                    emptyState
                } else {
                    ForEach(outfits) { outfit in
                        card(outfit)
                    }
                }
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    route = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增搭配")
            }
        }
        .sheet(item: $route) { destination in
            switch destination {
            case .create:
                OutfitEditorView(mode: .create)
            case .edit(let outfit):
                OutfitEditorView(mode: .edit(outfit))
            }
        }
        .alert("提示", isPresented: alertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("还没有保存的搭配", systemImage: "square.grid.2x2")
                .font(.headline)
            Text("手动挑几件凑成一套，命名后保存；之后可以一键设为今日穿搭。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                route = .create
            } label: {
                Label("新建搭配", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .cardBackground()
    }

    private func card(_ outfit: Outfit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(outfit.name)
                    .font(.headline)
                    .lineLimit(1)
                if outfit.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Menu {
                    Button {
                        setAsToday(outfit)
                    } label: {
                        Label("设为今日穿搭", systemImage: "checkmark.circle")
                    }
                    Button {
                        route = .edit(outfit)
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        context.delete(outfit)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            HStack(spacing: 8) {
                Text(outfit.occasion)
                if !outfit.tempText.isEmpty { Text(outfit.tempText) }
                Text("\(outfit.itemIDs.count) 件")
                Text(outfit.source.rawValue)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(outfit.itemIDs, id: \.self) { id in
                        if let item = items.first(where: { $0.id == id }) {
                            ItemThumbnail(fileName: item.imageFile, size: 56)
                        }
                    }
                }
            }

            if !outfit.note.isEmpty {
                Text(outfit.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    outfit.isFavorite.toggle()
                } label: {
                    Label(outfit.isFavorite ? "已收藏" : "收藏", systemImage: outfit.isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.bordered)
                .font(.footnote)

                Spacer()

                Button {
                    setAsToday(outfit)
                } label: {
                    Label("设为今日", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
        }
        .cardBackground()
    }

    private func setAsToday(_ outfit: Outfit) {
        WearLog.record(
            itemIDs: outfit.itemIDs,
            outfitName: outfit.name,
            outfitID: outfit.id,
            in: context,
            existing: logs
        )
        message = "已设为今天的穿搭"
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { newValue in if !newValue { message = nil } }
        )
    }
}

// MARK: - 灵感收藏

private struct InspirationListSection: View {
    private enum Route: Identifiable {
        case create
        case edit(Inspiration)
        case rule(Inspiration)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let inspiration): return "edit-" + inspiration.id.uuidString
            case .rule(let inspiration): return "rule-" + inspiration.id.uuidString
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Inspiration.createdAt, order: .reverse) private var inspirations: [Inspiration]
    @Query private var items: [ClothingItem]

    @State private var route: Route?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if inspirations.isEmpty {
                    emptyState
                } else {
                    ForEach(inspirations) { inspiration in
                        card(inspiration)
                    }
                }
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    route = .create
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增灵感")
            }
        }
        .sheet(item: $route) { destination in
            switch destination {
            case .create:
                InspirationFormView(mode: .create)
            case .edit(let inspiration):
                InspirationFormView(mode: .edit(inspiration))
            case .rule(let inspiration):
                RuleFormView(presetTitle: inspiration.title, inspirationID: inspiration.id)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("还没有灵感收藏", systemImage: "sparkles")
                .font(.headline)
            Text("看到杂志或小红书上可借鉴的搭配，手动保存图片，写一句能照着穿的要点，并关联自己衣柜里的衣物。不做自动抓取。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                route = .create
            } label: {
                Label("收藏第一条灵感", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .cardBackground()
    }

    private func card(_ inspiration: Inspiration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ItemImage(fileName: inspiration.imageFile, maxPixel: 900)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Text(inspiration.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Button {
                        route = .edit(inspiration)
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    Button {
                        route = .rule(inspiration)
                    } label: {
                        Label("提炼为规则", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        context.delete(inspiration)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }

            HStack(spacing: 8) {
                Text(inspiration.platform)
                if let sourceDate = inspiration.sourceDate {
                    Text(DateText.full(sourceDate))
                }
                Text("关联 \(inspiration.linkedItemIDs.count) 件")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !inspiration.note.isEmpty {
                Text("可借鉴：\(inspiration.note)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !inspiration.linkedItemIDs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(inspiration.linkedItemIDs, id: \.self) { id in
                            if let item = items.first(where: { $0.id == id }) {
                                HStack(spacing: 6) {
                                    ItemThumbnail(fileName: item.imageFile, size: 32)
                                    Text(item.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .cardBackground()
    }
}
