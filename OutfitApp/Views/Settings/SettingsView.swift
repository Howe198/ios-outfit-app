import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 我的：规则、标签词表、导出与恢复、数据概览。
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @Query private var items: [ClothingItem]
    @Query private var outfits: [Outfit]
    @Query private var logs: [WearLog]
    @Query private var inspirations: [Inspiration]
    @Query private var rules: [StyleRule]

    @AppStorage("backup.lastDate") private var lastBackupDate: Double = 0
    @AppStorage("backup.lastPath") private var lastBackupPath: String = ""

    @State private var exportedURL: URL?
    @State private var message: String?
    @State private var showImporter = false
    @State private var pendingImport: URL?
    @State private var showImportConfirm = false

    private var activeItemCount: Int { items.filter { $0.isActive }.count }
    private var imageCount: Int { items.filter { ImageStore.shared.exists(named: $0.imageFile) }.count }

    var body: some View {
        Form {
            Section("数据概览") {
                row("衣物", "\(items.count) 件（在用 \(activeItemCount)）")
                row("搭配", "\(outfits.count) 套")
                row("穿搭记录", "\(logs.count) 条")
                row("灵感", "\(inspirations.count) 条")
                row("规则", "\(rules.count) 条（启用 \(rules.filter { $0.isEnabled }.count)）")
                row("本地图片", "\(imageCount) 张")
            }

            Section("备份与恢复") {
                Button {
                    exportBackup()
                } label: {
                    Label("导出备份（JSON + 图片，单个 zip）", systemImage: "square.and.arrow.up")
                }

                if let exportedURL = exportedURL {
                    ShareLink(item: exportedURL) {
                        Label("分享刚导出的备份文件", systemImage: "paperplane")
                    }
                }

                Button {
                    showImporter = true
                } label: {
                    Label("导入备份并恢复", systemImage: "square.and.arrow.down")
                }

                Text(lastBackupDate > 0 ? "上次导出：\(DateText.full(Date(timeIntervalSince1970: lastBackupDate)))" : "还没有导出过备份")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("备份固定存放在 App 的 Documents/Backups 目录，可在「文件」App → 我的 iPhone → 衣橱穿搭 里直接拷出。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("导入会先校验整个 zip，再替换当前全部数据；校验失败不会动现有数据。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section("标签与规则") {
                NavigationLink {
                    RulesView()
                } label: {
                    Label("穿搭规则", systemImage: "slider.horizontal.3")
                }
                NavigationLink {
                    VocabularyView()
                } label: {
                    Label("标签词表", systemImage: "tag")
                }
            }

            Section("关于") {
                Text("衣物照片、穿搭记录只存在本机 App 沙盒；天气查询会把坐标发送给免费 Open-Meteo 获取气温、发送给 Apple CLGeocoder 反查城市名，不会保存到任何自建服务器；不做付费识别、不做自动抓取。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("全程零费用：仅使用系统自带能力与本机存储。真机安装走免费个人签名，到期需连 Mac 重签。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .confirmationDialog("导入会覆盖当前全部数据", isPresented: $showImportConfirm, titleVisibility: .visible) {
            Button("覆盖并恢复", role: .destructive) {
                if let pendingImport = pendingImport {
                    performImport(pendingImport)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("建议先用当前数据导出一份备份，再执行恢复。")
        }
        .alert("提示", isPresented: alertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func exportBackup() {
        do {
            let url = try BackupService.shared.export(context: context, customTags: VocabularyStore.shared.custom)
            exportedURL = url
            lastBackupDate = Date().timeIntervalSince1970
            lastBackupPath = url.path
            message = "已导出：\(url.lastPathComponent)"
        } catch {
            message = error.localizedDescription
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).zip")
            do {
                if FileManager.default.fileExists(atPath: copy.path) {
                    try FileManager.default.removeItem(at: copy)
                }
                try FileManager.default.copyItem(at: url, to: copy)
                pendingImport = copy
                showImportConfirm = true
            } catch {
                message = "读取备份文件失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func performImport(_ url: URL) {
        do {
            let summary = try BackupService.shared.importBackup(from: url, context: context)
            message = "恢复完成：\(summary.text)"
        } catch {
            message = error.localizedDescription
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { newValue in if !newValue { message = nil } }
        )
    }
}
