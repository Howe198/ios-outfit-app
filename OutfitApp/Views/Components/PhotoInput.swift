import SwiftUI
import PhotosUI
import UIKit

/// 拍照 / 相册二选一，不申请任何云端权限，照片只留在本机。
struct PhotoInput: View {
    @Binding var data: Data?
    @Binding var existingFile: String?

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraUnavailable = false
    @State private var loadFailed = false

    private var hasImage: Bool {
        data != nil || !(existingFile ?? "").isEmpty
    }

    var body: some View {
        VStack(spacing: 12) {
            preview
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label("相册", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showCamera = true
                    } else {
                        cameraUnavailable = true
                    }
                } label: {
                    Label("拍照", systemImage: "camera")
                }
                .buttonStyle(.bordered)

                if hasImage {
                    Button(role: .destructive) {
                        data = nil
                        existingFile = nil
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if cameraUnavailable {
                Text("当前设备没有可用相机（模拟器常见），请改用相册。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if loadFailed {
                Text("这张图片读取失败，换一张试试。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem = newItem else { return }
            Task {
                loadFailed = false
                if let loaded = try? await newItem.loadTransferable(type: Data.self) {
                    data = loaded
                    existingFile = nil
                } else {
                    loadFailed = true
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { imageData in
                data = imageData
                existingFile = nil
                showCamera = false
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let data = data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let existingFile = existingFile, !existingFile.isEmpty {
                ItemImage(fileName: existingFile, maxPixel: 800)
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    VStack(spacing: 6) {
                        Image(systemName: "tshirt")
                            .font(.largeTitle)
                        Text("还没有照片")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 系统相机封装。免费方案里不接任何第三方拍照 SDK。
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (Data) -> Void

        init(onCapture: @escaping (Data) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85) {
                onCapture(data)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
