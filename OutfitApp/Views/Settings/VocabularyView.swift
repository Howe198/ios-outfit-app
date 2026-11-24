import SwiftUI

/// 五组标签词表：默认项固定，自定义项可增删，只存在本机。
struct VocabularyView: View {
    @ObservedObject private var store = VocabularyStore.shared

    @State private var addingDimension: String?
    @State private var newTag = ""

    var body: some View {
        Form {
            Section {
                Text("默认词表在阶段 0 冻结，每组不超过 12 个。自定义标签只存在本机，删除后不影响已录入衣物的历史标签。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Vocabulary.dimensions, id: \.self) { dimension in
                Section(dimension) {
                    ForEach(store.options(for: dimension), id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            if store.isCustom(tag, in: dimension) {
                                Button(role: .destructive) {
                                    store.remove(tag, from: dimension)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("默认")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Button {
                        addingDimension = dimension
                        newTag = ""
                    } label: {
                        Label("新增自定义标签", systemImage: "plus")
                    }
                }
            }
        }
        .navigationTitle("标签词表")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "新增「\(addingDimension ?? "")」标签",
            isPresented: Binding(
                get: { addingDimension != nil },
                set: { newValue in if !newValue { addingDimension = nil } }
            )
        ) {
            TextField("标签名", text: $newTag)
            Button("添加") {
                if let dimension = addingDimension {
                    store.add(newTag, to: dimension)
                }
                addingDimension = nil
                newTag = ""
            }
            Button("取消", role: .cancel) {
                addingDimension = nil
                newTag = ""
            }
        }
    }
}
