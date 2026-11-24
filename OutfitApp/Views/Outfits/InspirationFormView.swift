import SwiftUI
import SwiftData

/// 灵感收藏表单：图片 + 一句可借鉴点 + 来源 + 关联衣物（至少 1 件）。
/// 不做自动抓取，图片只能手动从相册选或拍屏。
struct InspirationFormView: View {
    enum Mode {
        case create
        case edit(Inspiration)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]

    @State private var title = ""
    @State private var note = ""
    @State private var platform = "小红书"
    @State private var useSourceDate = true
    @State private var sourceDate = Date()
    @State private var photoData: Data?
    @State private var existingFile: String?
    @State private var linked: Set<UUID> = []
    @State private var message: String?

    private let platforms = ["小红书", "杂志", "其他"]

    private var formTitle: String {
        if case .edit = mode { return "编辑灵感" }
        return "收藏灵感"
    }

    private var activeItems: [ClothingItem] { items.filter { $0.status == .active } }

    var body: some View {
        NavigationStack {
            Form {
                Section("图片（必填）") {
                    PhotoInput(data: $photoData, existingFile: $existingFile)
                }

                Section("来源与要点") {
                    TextField("标题，如：灰蓝叠穿的层次", text: $title)

                    Picker("来源平台", selection: $platform) {
                        ForEach(platforms, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }

                    Toggle("记录来源日期", isOn: $useSourceDate)
                    if useSourceDate {
                        DatePicker("日期", selection: $sourceDate, displayedComponents: .date)
                    }

                    TextField("可借鉴点（必填，一句话）", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach(ItemCategory.allCases) { category in
                        categorySection(category)
                    }
                } header: {
                    Text("关联自有衣物（至少 1 件，已选 \(linked.count) 件）")
                }

                Section {
                    Text("只存自己看的图与笔记，不转发、不商用；来源不清的图片不入库。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(formTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear(perform: loadExisting)
            .alert("还不能保存", isPresented: alertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ category: ItemCategory) -> some View {
        let list = activeItems.filter { $0.category == category }
        if !list.isEmpty {
            DisclosureGroup("\(category.rawValue)（\(list.count)）") {
                ForEach(list) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: ClothingItem) -> some View {
        Button {
            if linked.contains(item.id) {
                linked.remove(item.id)
            } else {
                linked.insert(item.id)
            }
        } label: {
            HStack(spacing: 10) {
                ItemThumbnail(fileName: item.imageFile, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("\(item.categoryValue) · \(item.primaryColor)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: linked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(linked.contains(item.id) ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadExisting() {
        guard case .edit(let inspiration) = mode, title.isEmpty else { return }
        title = inspiration.title
        note = inspiration.note
        platform = inspiration.platform
        if let date = inspiration.sourceDate {
            useSourceDate = true
            sourceDate = date
        } else {
            useSourceDate = false
        }
        existingFile = inspiration.imageFile
        linked = Set(inspiration.linkedItemIDs)
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            message = "请给这条灵感起一个标题。"
            return
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else {
            message = "请写一句可借鉴点，否则收藏了也用不上。"
            return
        }
        guard !linked.isEmpty else {
            message = "至少关联 1 件自有衣物，灵感才能落地。"
            return
        }

        var file = existingFile ?? ""
        if let photoData = photoData {
            do {
                let savedName = try ImageStore.shared.save(data: photoData)
                if !file.isEmpty, file != savedName {
                    ImageStore.shared.delete(named: file)
                }
                file = savedName
            } catch {
                message = error.localizedDescription
                return
            }
        }
        guard !file.isEmpty else {
            message = "请先选一张灵感图片。"
            return
        }

        let date: Date? = useSourceDate ? sourceDate : nil

        switch mode {
        case .create:
            let inspiration = Inspiration(
                title: trimmedTitle,
                note: trimmedNote,
                platform: platform,
                sourceDate: date,
                imageFile: file,
                linkedItemIDs: Array(linked)
            )
            context.insert(inspiration)
        case .edit(let inspiration):
            inspiration.title = trimmedTitle
            inspiration.note = trimmedNote
            inspiration.platform = platform
            inspiration.sourceDate = date
            inspiration.imageFile = file
            inspiration.linkedItemIDs = Array(linked)
        }

        dismiss()
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { newValue in if !newValue { message = nil } }
        )
    }
}
