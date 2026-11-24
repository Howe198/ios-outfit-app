import SwiftUI
import SwiftData

/// 规则列表：可开关、可编辑、可删除，新增规则时记录来源灵感与启用日期。
struct RulesView: View {
    private enum Route: Identifiable {
        case create
        case edit(StyleRule)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let rule): return rule.id.uuidString
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \StyleRule.createdAt, order: .reverse) private var rules: [StyleRule]
    @Query private var items: [ClothingItem]

    @State private var route: Route?

    var body: some View {
        List {
            Section {
                if rules.isEmpty {
                    Text("还没有规则。建议先把 P0 稳定用两周，再从灵感里提炼 1–2 条，启用后观察一周再决定保留。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    row(rule)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("规则在这里随时开关。停用只影响之后的推荐，不改历史记录。")
            }
        }
        .navigationTitle("穿搭规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    route = .create
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $route) { destination in
            switch destination {
            case .create:
                RuleFormView()
            case .edit(let rule):
                RuleFormView(editing: rule)
            }
        }
    }

    private func row(_ rule: StyleRule) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title)
                    .font(.subheadline)
                Text(summary(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if rule.sourceInspirationID != nil {
                        Text("来自灵感")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    Text("\(DateText.short(rule.createdAt)) 启用")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                route = .edit(rule)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { rule.isEnabled = $0 }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func summary(_ rule: StyleRule) -> String {
        var text = "\(rule.kind.rawValue) · \(rule.dimension.rawValue)：\(valueText(rule))"
        if rule.kind != .exclude {
            text += " · \(rule.points) 分"
        }
        if !rule.note.isEmpty {
            text += " · \(rule.note)"
        }
        return text
    }

    private func valueText(_ rule: StyleRule) -> String {
        if rule.dimension == .item {
            return items.first { $0.id.uuidString == rule.value }?.name ?? "已删除的衣物"
        }
        return rule.value
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(rules[index])
        }
    }
}

/// 新建 / 编辑规则。
struct RuleFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]

    private let presetTitle: String
    private let inspirationID: UUID?
    private let editingRule: StyleRule?

    @State private var title = ""
    @State private var note = ""
    @State private var kind: RuleKind = .bonus
    @State private var dimension: RuleDimension = .color
    @State private var value = ""
    @State private var points = 2
    @State private var enabled = true
    @State private var message: String?

    init(presetTitle: String = "", inspirationID: UUID? = nil, editing: StyleRule? = nil) {
        self.presetTitle = presetTitle
        self.inspirationID = inspirationID
        self.editingRule = editing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则内容") {
                    TextField("名称，如：黑白配更稳", text: $title)

                    Picker("类型", selection: $kind) {
                        ForEach(RuleKind.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    Picker("作用维度", selection: $dimension) {
                        ForEach(RuleDimension.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }

                    if dimension == .item {
                        if items.isEmpty {
                            Text("衣橱里还没有衣物，先添加衣物再指定。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("指定衣物", selection: $value) {
                                ForEach(items) { item in
                                    Text(item.name).tag(item.id.uuidString)
                                }
                            }
                        }
                    } else {
                        Picker("取值", selection: $value) {
                            ForEach(Vocabulary.options(for: dimension), id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                    }

                    if kind != .exclude {
                        Stepper("分值 \(points)", value: $points, in: 1...10)
                    }

                    Toggle("启用", isOn: $enabled)
                }

                Section("说明与来源") {
                    TextField("一句话说明这条规则", text: $note, axis: .vertical)
                        .lineLimit(2...4)

                    if inspirationID != nil {
                        Text("来源：来自一条灵感收藏，启用日期记为今天。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("规则来源与启用日期会自动记录，便于以后判断哪条真正有用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(editingRule == nil ? "新增规则" : "编辑规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onChange(of: dimension) { _, newValue in
                guard editingRule == nil else { return }
                if newValue == .item {
                    value = items.first?.id.uuidString ?? ""
                } else {
                    value = Vocabulary.options(for: newValue).first ?? ""
                }
            }
            .onAppear(perform: loadInitial)
            .alert("还不能保存", isPresented: alertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func loadInitial() {
        if let editingRule, title.isEmpty {
            title = editingRule.title
            note = editingRule.note
            kind = editingRule.kind
            dimension = editingRule.dimension
            value = editingRule.value
            points = editingRule.points
            enabled = editingRule.isEnabled
            return
        }
        guard editingRule == nil, title.isEmpty else { return }
        title = presetTitle
        value = Vocabulary.options(for: dimension).first ?? ""
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "给规则起一个能看懂的名字。"
            return
        }
        guard !value.isEmpty else {
            message = "请选择规则作用的取值。"
            return
        }

        if let editingRule {
            editingRule.title = trimmed
            editingRule.note = note
            editingRule.kindValue = kind.rawValue
            editingRule.dimensionValue = dimension.rawValue
            editingRule.value = value
            editingRule.points = points
            editingRule.isEnabled = enabled
        } else {
            let rule = StyleRule(
                title: trimmed,
                note: note,
                kind: kind,
                dimension: dimension,
                value: value,
                points: points,
                isEnabled: enabled,
                sourceInspirationID: inspirationID
            )
            context.insert(rule)
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
