import SwiftUI
import SwiftData
import UIKit

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

    @State private var cutout: UIImage?
    @State private var cutoutState: CutoutState = .idle
    @State private var useCutout = true
    @State private var recognitionNote: String?
    @State private var isRecognizing = false
    @State private var analysisToken = 0

    private enum CutoutState {
        case idle
        case processing
        case ready
        case failed
    }

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

                if cutoutState != .idle {
                    Section {
                        switch cutoutState {
                        case .processing:
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在去背景…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        case .ready:
                            if let cutout = cutout {
                                VStack(alignment: .leading, spacing: 10) {
                                    ZStack {
                                        Color(.tertiarySystemFill)
                                        Image(uiImage: cutout)
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    Toggle("使用去背景后的图片", isOn: $useCutout)
                                    Text("已自动去背景，只保留衣服本身，保存为透明 PNG。不满意可关掉开关，保留原图。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        case .failed:
                            Text("这张图没抠出衣服，已保留原图，不影响继续填写和保存。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .idle:
                            EmptyView()
                        }
                    } header: {
                        Text("自动去背景（本机 Vision）")
                    } footer: {
                        Text("抠图只在本机完成，照片不上传；失败时保留原图。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
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
                } header: {
                    Text("基本信息")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动识别不一定准确，请自行修改。")
                        if isRecognizing {
                            Text("正在识别衣物…")
                        }
                        if let recognitionNote = recognitionNote {
                            Text(recognitionNote)
                        }
                    }
                    .font(.caption)
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
            .onChange(of: photoData) { _, newValue in
                guard let data = newValue, let image = UIImage(data: data) else { return }
                analyze(image)
            }
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

    /// 选完照片后在本机跑识别与抠图；任何一步失败都不影响手动录入。
    private func analyze(_ image: UIImage) {
        analysisToken += 1
        let token = analysisToken
        isRecognizing = true
        recognitionNote = nil
        cutout = nil
        cutoutState = .processing
        useCutout = true

        Task {
            let guess = await ClothingVision.recognize(image)
            let cut = await ClothingVision.removeBackground(from: image)
            await MainActor.run {
                guard token == analysisToken else { return }
                applyGuess(guess)
                cutout = cut
                cutoutState = cut == nil ? .failed : .ready
                useCutout = cut != nil
                isRecognizing = false
            }
        }
    }

    private func applyGuess(_ guess: ClothingGuess) {
        var parts: [String] = []
        if let category = guess.category {
            self.category = category
            parts.append(category.rawValue)
        }
        if let colorName = guess.colorName, colorOptions.contains(colorName) {
            primaryColor = colorName
            parts.append(colorName)
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let category = guess.category,
           let colorName = guess.colorName {
            name = "\(colorName)色\(category.rawValue)"
        }

        if parts.isEmpty {
            recognitionNote = "没识别出品类和主色，请手动选择。"
        } else {
            recognitionNote = "已按识别预填：\(parts.joined(separator: " · "))。"
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
        var savedName: String?
        if useCutout, let cutout = cutout {
            do {
                savedName = try ImageStore.shared.saveCutout(cutout)
            } catch {
                message = error.localizedDescription
                return
            }
        } else if let photoData = photoData {
            do {
                savedName = try ImageStore.shared.save(data: photoData)
            } catch {
                message = error.localizedDescription
                return
            }
        }
        if let savedName = savedName {
            if !file.isEmpty, file != savedName {
                ImageStore.shared.delete(named: file)
            }
            file = savedName
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
