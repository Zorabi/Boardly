import SwiftUI

struct NewColumnSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "square.grid.2x2"
    @State private var colorName = "violet"
    @State private var isDone = false
    /// 插入位置：最前 / 在某列之后（“末列之后”即追加到末尾）。
    /// onAppear 时按“首个完成列之前”初始化；nil 表示尚未初始化。
    @State private var placement: Placement?
    @FocusState private var focusedField: Field?

    private enum Field { case name }

    /// 位置选择用标签：最前，或现有各列之后（末列之后 = 末尾）。
    enum Placement: Hashable {
        case front
        case after(BoardColumn.ID)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedPlacement: Placement {
        placement ?? .front
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardlySheetHeader(
                title: "新增列",
                subtitle: "创建自定义状态列，例如“测试中”或“验证中”。"
            )

            // 原生 Form：LabeledContent 保证字段标签可见；颜色网格 adaptive 换行，
            // 在 420–460pt 宽度下不会横向撑宽或裁切。
            Form {
                Section("基本信息") {
                    LabeledContent("名称") {
                        TextField("例如：测试中", text: $name)
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .focused($focusedField, equals: .name)
                            .onSubmit(createColumn)
                            .accessibilityHint("必填")
                    }
                    LabeledContent("位置") {
                        placementPicker
                    }
                    LabeledContent("图标") {
                        symbolPicker
                    }
                }

                Section("外观") {
                    LabeledContent("颜色") {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 32), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(BoardlyTheme.projectColorOptions) { option in
                                colorSwatch(option)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Section("语义") {
                    Toggle(isOn: $isDone) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("完成列")
                            Text("该列任务视为已完成：不计入侧栏未完成数，看板中置灰显示。")
                                .boardlyFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .boardlyScrollers()
            .background(BoardlyTheme.canvas)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(BoardlySecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("创建列") { createColumn() }
                    .buttonStyle(BoardlyPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(16)
        }
        .frame(width: 440, height: 470)
        .onAppear {
            focusedField = .name
            if placement == nil {
                placement = defaultPlacement
            }
        }
    }

    /// 默认位置：首个完成列之前；无完成列时为末尾。
    private var defaultPlacement: Placement {
        let ordered = store.orderedColumns
        if let doneIndex = ordered.firstIndex(where: \.isDone) {
            return doneIndex == 0 ? .front : .after(ordered[doneIndex - 1].id)
        }
        return ordered.last.map { .after($0.id) } ?? .front
    }

    private var placementPicker: some View {
        Picker(
            "位置",
            selection: Binding(
                get: { selectedPlacement },
                set: { placement = $0 }
            )
        ) {
            Text("最前").tag(Placement.front)
            ForEach(store.orderedColumns) { column in
                Text("“\(column.name)”之后").tag(Placement.after(column.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .accessibilityHint("默认放在首个完成列之前")
    }

    private var symbolPicker: some View {
        Picker("图标", selection: $symbol) {
            ForEach(BoardlyTheme.columnSymbolOptions, id: \.self) { option in
                Label(option, systemImage: option).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }

    private func colorSwatch(_ option: BoardlyTheme.ProjectColorOption) -> some View {
        Button {
            colorName = option.name
        } label: {
            ZStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 22, height: 22)
                if colorName == option.name {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(BoardlyPlainButtonStyle())
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(colorName == option.name ? .isSelected : [])
    }

    private func createColumn() {
        guard canSubmit else { return }
        store.addColumn(
            name: name,
            symbol: symbol,
            colorName: colorName,
            isDone: isDone,
            before: insertionTargetID
        )
        dismiss()
    }

    /// Placement → addColumn 的 before 参数：最前 = 首列之前；
    /// after(X) = X 的下一列之前（X 为末列则 nil = 追加末尾）。
    private var insertionTargetID: BoardColumn.ID? {
        let ordered = store.orderedColumns
        switch selectedPlacement {
        case .front:
            return ordered.first?.id
        case .after(let columnID):
            guard let index = ordered.firstIndex(where: { $0.id == columnID }) else { return nil }
            return index + 1 < ordered.count ? ordered[index + 1].id : nil
        }
    }
}
