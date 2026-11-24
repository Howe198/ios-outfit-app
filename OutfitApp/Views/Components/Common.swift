import SwiftUI
import UIKit

// MARK: - 日期文案

enum DateText {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2  // 周一为一周起点
        return calendar
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = format
        return formatter
    }

    static func monthDay(_ date: Date) -> String { formatter("M月d日").string(from: date) }
    static func weekday(_ date: Date) -> String { formatter("EEEE").string(from: date) }
    static func full(_ date: Date) -> String { formatter("yyyy年M月d日").string(from: date) }
    static func monthTitle(_ date: Date) -> String { formatter("yyyy年M月").string(from: date) }
    static func short(_ date: Date) -> String { formatter("M/d").string(from: date) }
}

// MARK: - 图片

/// 自适应图片：外层给尺寸，内部裁切，缺图时显示占位。
struct ItemImage: View {
    let fileName: String
    var maxPixel: CGFloat = 600

    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if loaded {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.title3)
                    Text("图片缺失")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task(id: fileName) {
            image = ImageStore.shared.image(named: fileName, maxPixel: maxPixel)
            loaded = true
        }
    }
}

struct ItemThumbnail: View {
    let fileName: String
    var size: CGFloat = 64

    var body: some View {
        ItemImage(fileName: fileName, maxPixel: size * 3)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - 标签

struct TagChip: View {
    let text: String
    var selected: Bool = false

    var body: some View {
        Text(text)
            .font(.footnote)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
    }
}

/// 多选标签，用自适应网格排列，避免长标签被挤断。
struct TagPicker: View {
    let title: String
    let options: [String]
    @Binding var selection: [String]

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        toggle(option)
                    } label: {
                        TagChip(text: option, selected: selection.contains(option))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ value: String) {
        if let index = selection.firstIndex(of: value) {
            selection.remove(at: index)
        } else {
            selection.append(value)
        }
    }
}

// MARK: - 卡片样式

extension View {
    func cardBackground(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }
}
