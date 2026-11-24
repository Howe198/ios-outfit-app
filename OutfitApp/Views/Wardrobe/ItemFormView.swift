import SwiftUI
import SwiftData

/// 新增 / 编辑衣物。字段顺序按附录A：照片 → 名称 → 品类 → 主色 → 季节 → 厚度 → 场合 → 温度 → 状态 → 备注。
struct ItemFormView: View {
    enum Mode {
        case create
        case edit(ClothingItem)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: ItemCategory = .top
    @State private var primaryColor = "黑"
    @State private var seasons: [String] = []
    @State private var thickness: Thickness = .medium
    @State private var occasions: [String] = []
    @State private var status: ItemStatus = .active
    @State private var note = ""
    @State private var photoData: Data?
    @State private var existingFile: String?
    @State private var limitTemp = false
    @State private var tempMin = 10
    @State private var tempMax = 25
    @State private var message: String?

    private var title: String {
        if case .edit = mode { return "编辑衣物" }
        return "新增衣物"
    }

    private var colorOptions: [String] { VocabularyStore.shared.options(for: "主色") }
    private var occasionOptions: [String] { VocabularyStore.shared.options(for: "场合") }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片（必填）") {
                    PhotoInput(data: $photoData, existingFile: $existingFile)
                }

                Section("基本信息") {
                    TextField("名称，如：藏青通勤西裤", text: $name)

                    Picker("品类", selection: $category) {
                        ForEach(ItemCategory.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    Picker("主色", selection: $primaryColor) {
                        ForEach(colorOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }

                    Picker("厚度", selection: $thickness) {
                        ForEach(Thickness.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    Picker("状态", selection: $status) {
                        ForEach(ItemStatus.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                }

                Section("季节（至少选一个）") {
                    TagPicker(title: "", options: Season.allCases.map(\.rawValue), selection: $seasons)
                }

                Section("场合（至少选一个）") {
                    TagPicker(title: "", options: occasionOptions, selection: $occasions)
                }

                Section("个人温度区间（可选）") {
                    Toggle("限定适宜温度", isOn: $limitTemp)
                    if limitTemp {
                        Stepper("最低 \(tempMin)℃", value: $tempMin, in: -20...tempMax)
                        Stepper("最高 \(tempMax)℃", value: $tempMax, in: tempMin...45)
                    }
                    Text("与厚度冲突时，以此区间为准。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("备注（选填）") {
                    TextField("洗护、搭配禁忌、次色等，一句以内", text: $note, axis: .vertical)
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

    private func loadExisting() {
        guard case .edit(let item) = mode, name.isEmpty else { return }
        name = item.name
        category = item.category
        primaryColor = item.primaryColor
        seasons = item.seasonsValue
        thickness = item.thickness
        occasions = item.occasionsValue
        status = item.status
        note = item.note
        existingFile = item.imageFile
        if let low = item.tempMin, let high = item.tempMax, low <= high {
            limitTemp = true
            tempMin = low
            tempMax = high
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            message = "请填写衣物名称，例如「藏青通勤西裤」。"
            return
        }
        guard !seasons.isEmpty else {
            message = "请至少选择一个季节，否则推荐时无法判断。"
            return
        }
        guard !occasions.isEmpty else {
            message = "请至少选择一个场合。"
            return
        }

        var file = existingFile ?? ""
        if let photoData {
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
            message = "请先拍照或从相册选一张照片，图片是必填项。"
            return
        }

        let low = limitTemp ? min(tempMin, tempMax) : nil
        let high = limitTemp ? max(tempMin, tempMax) : nil

        switch mode {
        case .create:
            let item = ClothingItem(
                name: trimmedName,
                category: category,
                primaryColor: primaryColor,
                seasons: seasons,
                thickness: thickness,
                occasions: occasions,
                tempMin: low,
                tempMax: high,
                status: status,
                note: note,
                imageFile: file
            )
            context.insert(item)
        case .edit(let item):
            item.name = trimmedName
            item.categoryValue = category.rawValue
            item.primaryColor = primaryColor
            item.seasonsValue = seasons
            item.thicknessValue = thickness.rawValue
            item.occasionsValue = occasions
            item.statusValue = status.rawValue
            item.note = note
            item.imageFile = file
            item.tempMin = low
            item.tempMax = high
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
