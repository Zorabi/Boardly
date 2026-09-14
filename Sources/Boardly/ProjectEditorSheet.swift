import SwiftUI

/// 重命名项目与调整图标、颜色的编辑弹窗。
struct ProjectEditorSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Project
    @FocusState private var focusedField: Field?

    private enum Field { case name }

    init(project: Project) {
        _draft = State(initialValue: project)
    }

    private var canSubmit: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        let original = store.project(withID: draft.id)
        return original != draft && canSubmit
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardlySheetHeader(
                title: "编辑项目",
                subtitle: "调整名称、图标或颜色，现有任务会保持归属不变。"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BoardlyFormSection("基本信息") {
                        TextField("项目名称", text: $draft.name, prompt: Text("例如：家庭改造"))
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .focused($focusedField, equals: .name)
                            .onSubmit(saveProject)
                            .accessibilityHint("必填")
                    }

                    BoardlyFormSection("外观") {
                        BoardlyFormRow(label: "图标") {
                            Picker("图标", selection: $draft.symbol) {
                                ForEach(BoardlyTheme.projectSymbolOptions, id: \.self) { option in
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
                Button("保存") { saveProject() }
                    .buttonStyle(BoardlyPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges)
            }
            .padding(16)
        }
        .frame(width: 420, height: 360)
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

    private func saveProject() {
        guard hasChanges else { return }
        store.updateProject(draft)
        dismiss()
    }
}
