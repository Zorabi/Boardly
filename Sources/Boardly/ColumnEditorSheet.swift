import SwiftUI

/// 重命名列与调整图标、颜色的编辑弹窗。
struct ColumnEditorSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BoardColumn
    @FocusState private var focusedField: Field?

    private enum Field { case name }

    init(column: BoardColumn) {
        _draft = State(initialValue: column)
    }

    private var canSubmit: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 该列是当前唯一的完成列：关闭完成语义的开关被禁用（至少保留一个完成列）。
    private var isOnlyDoneColumn: Bool {
        store.column(withID: draft.id)?.isDone == true && store.doneColumnIDs.count == 1
    }

    private var hasChanges: Bool {
        let original = store.column(withID: draft.id)
        return original != draft && canSubmit
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardlySheetHeader(
                title: "编辑列",
                subtitle: "调整名称、图标或颜色，列内任务保持不变。"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BoardlyFormSection("基本信息") {
                        TextField("列名称", text: $draft.name, prompt: Text("例如：验证中"))
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .focused($focusedField, equals: .name)
                            .onSubmit(save)
                            .accessibilityHint("必填")
                    }

                    BoardlyFormSection("外观") {
                        BoardlyFormRow(label: "图标") {
                            Picker("图标", selection: $draft.symbol) {
                                ForEach(BoardlyTheme.columnSymbolOptions, id: \.self) { option in
                                    Label(option, systemImage: option).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }

                        BoardlyFormRow(label: "颜色") {
                            LazyHGrid(rows: [GridItem(.fixed(30))], spacing: 8) {
                                ForEach(BoardlyTheme.projectColorOptions) { option in
                                    colorSwatch(option)
                                }
                            }
                        }
                    }

                    BoardlyFormSection("语义") {
                        Toggle(isOn: $draft.isDone) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("完成列")
                                Text("该列任务视为已完成：不计入侧栏未完成数，看板中置灰显示。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(isOnlyDoneColumn)
                        if isOnlyDoneColumn {
                            Text("这是最后一个完成列，至少需要保留一个；可先把其他列设为完成列。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(BoardlySecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .buttonStyle(BoardlyPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
            .padding(16)
        }
        .frame(width: 420, height: 440)
        .onAppear { focusedField = .name }
    }

    private func colorSwatch(_ option: BoardlyTheme.ProjectColorOption) -> some View {
        Button {
            draft.colorName = option.name
        } label: {
            ZStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 22, height: 22)
                if draft.colorName == option.name {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(draft.colorName == option.name ? .isSelected : [])
    }

    private func save() {
        guard hasChanges else { return }
        guard store.updateColumn(draft) else { return }
        dismiss()
    }
}
