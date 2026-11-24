import SwiftUI
import SwiftData

/// 手动组套：勾选衣物，命名保存。
struct OutfitEditorView: View {
    enum Mode {
        case create
        case edit(Outfit)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]

    @State private var name = ""
    @State private var occasion = "通勤上班"
    @State private var selected: Set<UUID> = []
    @State private var note = ""
    @State private var useTemp = false
    @State private var tempMin = 10
    @State private var tempMax = 25
    @State private var message: String?

    private var title: String {
        if case .edit = mode { return "编辑搭配" }
        return "新建搭配"
    }

    private var activeItems: [ClothingItem] { items.filter { $0.status == .active } }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("搭配名称，如：周一提案", text: $name)

                    Picker("场合", selection: $occasion) {
                        ForEach(VocabularyStore.shared.options(for: "场合"), id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }

                    Toggle("限定适用温度", isOn: $useTemp)
                    if useTemp {
                        Stepper("最低 \(tempMin)℃", value: $tempMin, in: -20...tempMax)
                        Stepper("最高 \(tempMax)℃", value: $tempMax, in: tempMin...45)
                    }
                }

                Section {
                    ForEach(ItemCategory.allCases) { category in
                        categorySection(category)
                    }
                } header: {
                    Text("选择衣物（至少 2 件，已选 \(selected.count) 件）")
                }

                Section("备注（选填）") {
                    TextField("这套适合什么日子、和什么鞋配", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(title)
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
            toggle(item.id)
        } label: {
            HStack(spacing: 10) {
                ItemThumbnail(fileName: item.imageFile, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("\(item.primaryColor) · \(item.thicknessValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(item.id) ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func loadExisting() {
        guard case .edit(let outfit) = mode, name.isEmpty else { return }
        name = outfit.name
        occasion = outfit.occasion
        selected = Set(outfit.itemIDs)
        note = outfit.note
        if let low = outfit.tempMin, let high = outfit.tempMax, low <= high {
            useTemp = true
            tempMin = low
            tempMax = high
        }
    }

    private func save() {
        guard selected.count >= 2 else {
            message = "一套搭配至少要有 2 件衣物。"
            return
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "搭配 \(DateText.monthDay(Date()))" : trimmed
        let itemIDs = Array(selected)
        let low = useTemp ? min(tempMin, tempMax) : nil
        let high = useTemp ? max(tempMin, tempMax) : nil

        switch mode {
        case .create:
            let outfit = Outfit(
                name: finalName,
                itemIDs: itemIDs,
                occasion: occasion,
                tempMin: low,
                tempMax: high,
                source: .manual,
                note: note
            )
            context.insert(outfit)
        case .edit(let outfit):
            outfit.name = finalName
            outfit.itemIDs = itemIDs
            outfit.occasionValue = occasion
            outfit.tempMin = low
            outfit.tempMax = high
            outfit.note = note
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
