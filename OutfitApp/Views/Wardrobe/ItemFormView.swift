import SwiftUI
import SwiftData
import UIKit

/// 新增 / 编辑衣物。照片先在本机做人物检测、衣物分件与摆正，再进入手动确认。
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

    @State private var garments: [GarmentCandidate] = []
    @State private var selectedGarmentIDs: Set<UUID> = []
    @State private var useProcessedImage = true
    @State private var useOriginalInstead = false
    @State private var pipelineState: PipelineState = .idle
    @State private var pipelineMessage: String?
    @State private var recognitionNote: String?
    @State private var analysisToken = 0

    @State private var originalImage: UIImage?
    @State private var preparedImage: UIImage?
    @State private var sourceIsLowRes = false
    @State private var enhanceLowRes = false

    @State private var personImage: UIImage?
    @State private var personBoxes: [CGRect] = []
    @State private var showPersonPicker = false

    private enum PipelineState {
        case idle
        case detecting
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
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
    private var selectedGarments: [GarmentCandidate] {
        garments.filter { selectedGarmentIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("照片（必填）") {
                    PhotoInput(data: $photoData, existingFile: $existingFile)

                    if sourceIsLowRes {
                        Toggle("本机增强清晰度（源图偏糊时用）", isOn: $enhanceLowRes)
                            .disabled(pipelineState == .processing || pipelineState == .detecting)
                        Text("只做锐化，不生成细节；不改变保存的分辨率。可随时关闭。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if pipelineState == .detecting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在检测人物…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if photoData != nil {
                    Section {
                        switch pipelineState {
                        case .idle:
                            Text("等待选择人物。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .detecting:
                            Text("正在检测画面里有几个人…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .processing:
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在本机提取衣物、裁剪摆正…")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        case .failed:
                            Text(pipelineMessage ?? "没提取出衣物，已保留原图，可继续手动填写。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .ready:
                            garmentContent
                        }
                    } header: {
                        Text("自动提取衣物（本机 Vision）")
                    } footer: {
                        Text("照片只在本机处理，不上传。原生能力没有人像衣物语义分割，袖口、短裤边缘可能不完美；自动识别不一定准确，请自行修改。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Section {
                    TextField(
                        garments.count > 1 ? "名称（可留空，按品类主色自动命名）" : "名称，如：藏青通勤西裤",
                        text: $name
                    )

                    if garments.count <= 1 {
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
                    } else {
                        LabeledContent("分件", value: "已选 \(selectedGarments.count) / \(garments.count) 件")
                        Text("多件会按各自的识别品类和主色分别保存；需要改品类或颜色，请保存后在衣橱逐件修改。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                        if let recognitionNote = recognitionNote {
                            Text(recognitionNote)
                        }
                        if isEditing && garments.count > 1 {
                            Text("编辑现有衣物时只更新当前这一条；其余分件请另建新衣物。")
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
                beginPhotoFlow(image)
            }
            .onChange(of: enhanceLowRes) { _, _ in
                guard photoData != nil, originalImage != nil,
                      pipelineState != .detecting, pipelineState != .processing else { return }
                reprocessPhoto()
            }
            .sheet(isPresented: $showPersonPicker) {
                if let personImage = personImage {
                    PersonPickerView(
                        image: personImage,
                        boxes: personBoxes,
                        onSelect: { rect in
                            showPersonPicker = false
                            guard let cropped = GarmentPipeline.cropPerson(from: personImage, visionRect: rect) else {
                                pipelineState = .failed
                                pipelineMessage = "裁出选中人物失败，已保留原图。"
                                return
                            }
                            originalImage = cropped
                            sourceIsLowRes = max(
                                GarmentPipeline.pixelSize(of: cropped).width,
                                GarmentPipeline.pixelSize(of: cropped).height
                            ) < 1600
                            enhanceLowRes = false
                            analysisToken += 1
                            processPhoto(cropped, token: analysisToken)
                        },
                        onCancel: {
                            showPersonPicker = false
                            pipelineState = .failed
                            pipelineMessage = "未选择人物，已保留整张原图；可手动填写或重新选图。"
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
            .alert("还不能保存", isPresented: alertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: - 分件预览

    @ViewBuilder
    private var garmentContent: some View {
        if garments.isEmpty {
            Text(pipelineMessage ?? "没有可预览的衣物，已保留原图。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if useOriginalInstead || (garments.count == 1 && !useProcessedImage) {
            VStack(alignment: .leading, spacing: 8) {
                Text("将保存整张原图，不做衣物裁切。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if garments.count > 1 {
                    Button("恢复分件保存") { useOriginalInstead = false }
                }
            }
        } else if garments.count == 1, let garment = garments.first {
            VStack(alignment: .leading, spacing: 10) {
                garmentPreview(garment.image, height: 180)
                Toggle("使用提取后的衣物图（透明 PNG）", isOn: $useProcessedImage)
                Text("预览放在浅灰干净底上；实际保存为透明背景，四周已裁掉空白并尽量摆正。褶皱不会被消除。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("识别到 \(garments.count) 件衣物，分别保存为独立衣物；关闭某件则不保存它。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(garments) { garment in
                    HStack(spacing: 10) {
                        garmentPreview(garment.image, height: 64, width: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(garment.suggestedName)
                                .font(.subheadline.weight(.medium))
                            Text("\(garment.category.rawValue) · \(garment.colorName.map { "\($0)色" } ?? "主色未识别")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: selectionBinding(for: garment.id))
                            .labelsHidden()
                    }
                }

                Button("改用整张原图保存一件") {
                    useOriginalInstead = true
                }
                .font(.footnote)
            }
        }
    }

    private func garmentPreview(_ image: UIImage, height: CGFloat, width: CGFloat? = nil) -> some View {
        ZStack {
            Color(white: 0.96)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(4)
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedGarmentIDs.contains(id) },
            set: { isOn in
                if isOn {
                    selectedGarmentIDs.insert(id)
                } else {
                    selectedGarmentIDs.remove(id)
                }
            }
        )
    }

    // MARK: - 载入与照片流水线

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

    private func beginPhotoFlow(_ image: UIImage) {
        analysisToken += 1
        let token = analysisToken
        originalImage = image
        preparedImage = nil
        sourceIsLowRes = max(
            GarmentPipeline.pixelSize(of: image).width,
            GarmentPipeline.pixelSize(of: image).height
        ) < 1600
        enhanceLowRes = false
        garments = []
        selectedGarmentIDs = []
        useProcessedImage = true
        useOriginalInstead = false
        recognitionNote = nil
        pipelineMessage = nil
        pipelineState = .detecting

        Task {
            let boxes = await GarmentPipeline.detectPersons(in: image)
            await MainActor.run {
                guard token == analysisToken else { return }
                if boxes.count > 1 {
                    personImage = image
                    personBoxes = boxes
                    pipelineState = .idle
                    showPersonPicker = true
                } else {
                    processPhoto(image, token: token)
                }
            }
        }
    }

    private func reprocessPhoto() {
        guard let originalImage = originalImage else { return }
        analysisToken += 1
        processPhoto(originalImage, token: analysisToken)
    }

    private func processPhoto(_ image: UIImage, token: Int) {
        pipelineState = .processing
        garments = []
        selectedGarmentIDs = []
        recognitionNote = nil
        pipelineMessage = nil
        let shouldEnhance = enhanceLowRes

        Task {
            var source = image
            if shouldEnhance, let enhanced = await GarmentPipeline.enhance(image) {
                source = enhanced
            }
            let outcome = await GarmentPipeline.process(source)
            await MainActor.run {
                guard token == analysisToken else { return }
                preparedImage = source
                applyOutcome(outcome)
            }
        }
    }

    private func applyOutcome(_ outcome: PipelineOutcome) {
        garments = outcome.candidates
        selectedGarmentIDs = Set(outcome.candidates.map(\.id))
        pipelineMessage = outcome.message

        if outcome.candidates.isEmpty {
            pipelineState = .failed
            recognitionNote = "没提取出衣物，已保留原图，请手动选择品类和主色。"
            return
        }

        if outcome.candidates.count == 1, let first = outcome.candidates.first {
            applyGuess(first)
        } else {
            recognitionNote = "已在本机分出 \(outcome.candidates.count) 件衣物，可逐件开关。"
        }
        pipelineState = .ready
    }

    private func applyGuess(_ garment: GarmentCandidate) {
        category = garment.category
        if let color = garment.colorName, colorOptions.contains(color) {
            primaryColor = color
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = garment.suggestedName
        }
        recognitionNote = "已按衣物区域预填：\(garment.category.rawValue) · \(garment.colorName.map { "\($0)色" } ?? "主色未识别")。"
    }

    // MARK: - 保存

    private func save() {
        var effectiveName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !seasons.isEmpty else {
            message = "请至少选择一个季节，否则推荐时无法判断。"
            return
        }
        guard !occasions.isEmpty else {
            message = "请至少选择一个场合。"
            return
        }

        let low = limitTemp ? min(tempMin, tempMax) : nil
        let high = limitTemp ? max(tempMin, tempMax) : nil

        // 没有新照片：只更新已有衣物的文字字段
        guard photoData != nil else {
            guard case .edit(let item) = mode else {
                message = "请先拍照或从相册选一张照片，图片是必填项。"
                return
            }
            guard !effectiveName.isEmpty else {
                message = "请填写衣物名称，例如「藏青通勤西裤」。"
                return
            }
            update(item, name: effectiveName, file: item.imageFile, category: category, color: primaryColor, low: low, high: high)
            dismiss()
            return
        }

        let chosen = selectedGarments
        let useSingleProcessed = garments.count == 1 && useProcessedImage && !useOriginalInstead
        let saveOriginal = useOriginalInstead || garments.isEmpty || (garments.count == 1 && !useProcessedImage)

        if saveOriginal {
            guard let file = saveOriginalPhoto() else { return }
            if effectiveName.isEmpty {
                message = "请填写衣物名称，例如「藏青通勤西裤」。"
                return
            }
            saveSingle(file: file, name: effectiveName, category: category, color: primaryColor, low: low, high: high)
            dismiss()
            return
        }

        if useSingleProcessed {
            guard let garment = garments.first else {
                message = "没有可保存的衣物图，请重选照片。"
                return
            }
            if effectiveName.isEmpty { effectiveName = garment.suggestedName }
            guard let file = saveCutout(garment.image) else { return }
            saveSingle(file: file, name: effectiveName, category: category, color: primaryColor, low: low, high: high)
            dismiss()
            return
        }

        // 多件：逐件保存为独立衣物
        guard !chosen.isEmpty else {
            message = "请至少打开一件要保存的衣物。"
            return
        }

        if isEditing {
            guard let garment = chosen.first else { return }
            guard let file = saveCutout(garment.image) else { return }
            guard case .edit(let item) = mode else { return }
            if effectiveName.isEmpty { effectiveName = garment.suggestedName }
            update(item, name: effectiveName, file: file, category: category, color: primaryColor, low: low, high: high)
            dismiss()
            return
        }

        for (index, garment) in chosen.enumerated() {
            guard let file = saveCutout(garment.image) else { return }
            let itemName: String
            if index == 0, !effectiveName.isEmpty {
                itemName = effectiveName
            } else {
                itemName = garment.suggestedName
            }
            let item = ClothingItem(
                name: itemName,
                category: garment.category,
                primaryColor: garment.colorName ?? primaryColor,
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
        }
        dismiss()
    }

    private func saveOriginalPhoto() -> String? {
        guard let photoData = photoData,
              let image = preparedImage ?? UIImage(data: photoData) else {
            message = "图片读取失败，请重选照片。"
            return nil
        }
        do {
            return try ImageStore.shared.save(image: image)
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    private func saveCutout(_ image: UIImage) -> String? {
        do {
            return try ImageStore.shared.saveCutout(image)
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    private func saveSingle(file: String, name: String, category: ItemCategory, color: String, low: Int?, high: Int?) {
        switch mode {
        case .create:
            let item = ClothingItem(
                name: name,
                category: category,
                primaryColor: color,
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
            if !item.imageFile.isEmpty, item.imageFile != file {
                ImageStore.shared.delete(named: item.imageFile)
            }
            update(item, name: name, file: file, category: category, color: color, low: low, high: high)
        }
    }

    private func update(
        _ item: ClothingItem,
        name: String,
        file: String,
        category: ItemCategory,
        color: String,
        low: Int?,
        high: Int?
    ) {
        item.name = name
        item.categoryValue = category.rawValue
        item.primaryColor = color
        item.seasonsValue = seasons
        item.thicknessValue = thickness.rawValue
        item.occasionsValue = occasions
        item.statusValue = status.rawValue
        item.note = note
        item.imageFile = file
        item.tempMin = low
        item.tempMax = high
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { newValue in if !newValue { message = nil } }
        )
    }
}

// MARK: - 多人照片选人

private struct PersonPickerView: View {
    let image: UIImage
    let boxes: [CGRect]
    let onSelect: (CGRect) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("照片里有 \(boxes.count) 个人。点选要提取衣物的那一位。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                GeometryReader { geometry in
                    let fitted = fittedRect(in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: fitted.midX, y: fitted.midY)

                        ForEach(boxes.indices, id: \.self) { index in
                            let box = boxes[index]
                            let rect = CGRect(
                                x: fitted.minX + box.minX * fitted.width,
                                y: fitted.minY + (1 - box.maxY) * fitted.height,
                                width: box.width * fitted.width,
                                height: box.height * fitted.height
                            )
                            Button {
                                onSelect(box)
                                dismiss()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.accentColor, lineWidth: 2.5)
                                    Text("选这位")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(.regularMaterial, in: Capsule())
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(width: max(54, rect.width), height: max(44, rect.height))
                            .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Text("只会裁出选中的人，再在本机提取衣物；照片不会上传。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            .navigationTitle("选择人物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
