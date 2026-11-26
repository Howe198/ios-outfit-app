import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ItemDetailView: View {
    @Bindable var item: ClothingItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var outfits: [Outfit]
    @Query private var logs: [WearLog]
    @Query private var inspirations: [Inspiration]

    @State private var showEdit = false
    @State private var showDelete = false
    @State private var replacementSelection: PhotosPickerItem?
    @State private var pendingReplacement: UIImage?
    @State private var showReplaceConfirm = false
    @State private var showRestoreConfirm = false
    @State private var replaceMessage: String?

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

                PhotosPicker(selection: $replacementSelection, matching: .images, photoLibrary: .shared()) {
                    Label("换图（从相册选一张）", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if item.previousImageFile != nil {
                    Button {
                        showRestoreConfirm = true
                    } label: {
                        Label("恢复替换前的照片", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Text("换图只从你的相册手动选择，不会抓取任何平台图片；替换图按高清口径原样保存，不走抠图和平整。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

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
        .sheet(isPresented: $showReplaceConfirm) {
            if let pendingReplacement = pendingReplacement {
                ReplacePhotoConfirmView(
                    image: pendingReplacement,
                    hasBackup: item.previousImageFile != nil,
                    onConfirm: {
                        replacePhoto(with: pendingReplacement)
                        self.pendingReplacement = nil
                    },
                    onCancel: {
                        self.pendingReplacement = nil
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: replacementSelection) { _, newValue in
            guard let newValue = newValue else { return }
            Task {
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        throw BackupError.imageUnreadable
                    }
                    await MainActor.run {
                        pendingReplacement = image
                        showReplaceConfirm = true
                        replacementSelection = nil
                    }
                } catch {
                    await MainActor.run {
                        replaceMessage = "图片读取失败，请换一张。"
                        replacementSelection = nil
                    }
                }
            }
        }
        .confirmationDialog("恢复替换前的照片？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复原图") { restorePreviousPhoto() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前照片会保留为备份，恢复后仍可再换回来。")
        }
        .alert("换图失败", isPresented: replaceAlertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(replaceMessage ?? "")
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
        if let previous = item.previousImageFile {
            ImageStore.shared.delete(named: previous)
        }
        context.delete(item)
        dismiss()
    }

    private func replacePhoto(with image: UIImage) {
        do {
            let newFile = try ImageStore.shared.save(image: image)
            let oldFile = item.imageFile
            if item.previousImageFile == nil, !oldFile.isEmpty {
                item.previousImageFile = oldFile
            } else if let previous = item.previousImageFile,
                      !oldFile.isEmpty, oldFile != previous {
                ImageStore.shared.delete(named: oldFile)
            }
            item.imageFile = newFile
            try context.save()
        } catch {
            replaceMessage = error.localizedDescription
        }
    }

    private func restorePreviousPhoto() {
        guard let previous = item.previousImageFile,
              ImageStore.shared.exists(named: previous) else {
            item.previousImageFile = nil
            replaceMessage = "原图备份已经不存在，无法恢复。"
            return
        }
        let current = item.imageFile
        item.imageFile = previous
        item.previousImageFile = current
        do {
            try context.save()
        } catch {
            replaceMessage = error.localizedDescription
        }
    }

    private var replaceAlertBinding: Binding<Bool> {
        Binding(
            get: { replaceMessage != nil },
            set: { newValue in if !newValue { replaceMessage = nil } }
        )
    }
}

// MARK: - 换图确认

private struct ReplacePhotoConfirmView: View {
    let image: UIImage
    let hasBackup: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Color(white: 0.96)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)

                Text(hasBackup
                     ? "将替换当前照片。已保留的原图备份不会被覆盖；本次替换仍可再换回来。"
                     : "将替换当前照片。当前照片会保留为原图备份，之后可在详情页恢复。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("换图按高清口径保存，不走抠图和平整流水线。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 0)

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("确认替换")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle("确认换图")
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
}
