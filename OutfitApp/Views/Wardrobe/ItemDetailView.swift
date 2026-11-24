import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: ClothingItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var outfits: [Outfit]
    @Query private var logs: [WearLog]
    @Query private var inspirations: [Inspiration]

    @State private var showEdit = false
    @State private var showDelete = false

    private var relatedOutfits: [Outfit] { outfits.filter { $0.itemIDs.contains(item.id) } }
    private var relatedLogs: [WearLog] { logs.filter { $0.itemIDs.contains(item.id) } }
    private var relatedInspirations: [Inspiration] { inspirations.filter { $0.linkedItemIDs.contains(item.id) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ItemImage(fileName: item.imageFile, maxPixel: 1200)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(item.name)
                    .font(.title3).bold()

                VStack(alignment: .leading, spacing: 10) {
                    row("品类", item.categoryValue)
                    row("主色", item.primaryColor)
                    row("厚度", item.thicknessValue)
                    row("季节", item.seasonsValue.joined(separator: " / "))
                    row("场合", item.occasionsValue.joined(separator: " / "))
                    row("温度区间", item.tempText)
                    row("状态", item.statusValue)
                }
                .cardBackground()

                if !item.note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("备注")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(item.note)
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("使用情况")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("出现在 \(relatedOutfits.count) 套搭配、\(relatedLogs.count) 条穿搭记录、\(relatedInspirations.count) 条灵感中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

                Button {
                    showEdit = true
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label("删除这件衣物", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("归档的衣物会保留数据，但不再进入推荐；删除则会同时从相关搭配和记录中移除。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("衣物详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            ItemFormView(mode: .edit(item))
        }
        .confirmationDialog("删除这件衣物？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteItem() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deleteWarning)
        }
    }

    private var deleteWarning: String {
        if relatedOutfits.isEmpty && relatedLogs.isEmpty && relatedInspirations.isEmpty {
            return "删除后不可恢复，建议先导出一次备份。"
        }
        return "它会同时从 \(relatedOutfits.count) 套搭配、\(relatedLogs.count) 条记录、\(relatedInspirations.count) 条灵感中移除，删除后不可恢复。"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private func deleteItem() {
        for outfit in relatedOutfits {
            outfit.itemIDs.removeAll { $0 == item.id }
        }
        for log in relatedLogs {
            log.itemIDs.removeAll { $0 == item.id }
        }
        for inspiration in relatedInspirations {
            inspiration.linkedItemIDs.removeAll { $0 == item.id }
        }
        ImageStore.shared.delete(named: item.imageFile)
        context.delete(item)
        dismiss()
    }
}
