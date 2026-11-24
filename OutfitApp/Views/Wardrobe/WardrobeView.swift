import SwiftUI
import SwiftData

/// 衣橱：网格浏览、筛选、新增入口。
struct WardrobeView: View {
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]

    @State private var search = ""
    @State private var category: ItemCategory?
    @State private var status: ItemStatus?
    @State private var showAdd = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    private var filtered: [ClothingItem] {
        items.filter { item in
            if let category = category, item.category != category { return false }
            if let status = status, item.status != status { return false }
            let keyword = search.trimmingCharacters(in: .whitespaces)
            if !keyword.isEmpty {
                let matched = item.name.localizedCaseInsensitiveContains(keyword)
                    || item.primaryColor.localizedCaseInsensitiveContains(keyword)
                    || item.categoryValue.contains(keyword)
                if !matched { return false }
            }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                filterBar

                if items.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    Text("没有符合条件的衣物，换个筛选试试。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardBackground()
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(filtered) { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                itemCard(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("衣橱")
        .searchable(text: $search, prompt: "搜名称、颜色、品类")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增衣物")
            }
        }
        .sheet(isPresented: $showAdd) {
            ItemFormView(mode: .create)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("品类", selection: $category) {
                Text("全部品类").tag(Optional<ItemCategory>.none)
                ForEach(ItemCategory.allCases) { option in
                    Text(option.rawValue).tag(Optional<ItemCategory>.some(option))
                }
            }
            .pickerStyle(.menu)

            Picker("状态", selection: $status) {
                Text("全部状态").tag(Optional<ItemStatus>.none)
                ForEach(ItemStatus.allCases) { option in
                    Text(option.rawValue).tag(Optional<ItemStatus>.some(option))
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Text("\(filtered.count) / \(items.count) 件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("衣橱还是空的", systemImage: "tshirt")
                .font(.headline)
            Text("先按阶段 1 的拍照规范录入 5 件试试：平铺、纯色背景、自然光、一件一张。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                showAdd = true
            } label: {
                Label("添加第一件衣物", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .cardBackground()
    }

    private func itemCard(_ item: ClothingItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemImage(fileName: item.imageFile, maxPixel: 500)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.name)
                .font(.subheadline)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(item.categoryValue)
                Text("·")
                Text(item.primaryColor)
                if item.status == .archived {
                    Spacer(minLength: 0)
                    Text("已归档")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardBackground(padding: 10)
    }
}
