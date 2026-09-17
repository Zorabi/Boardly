import SwiftUI

struct NewProjectSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "folder"
    @State private var colorName = "violet"
    @FocusState private var focusedField: Field?

    private enum Field { case name }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardlySheetHeader(
                title: "新建项目",
                subtitle: "用名称、图标和颜色区分不同的任务集合。"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BoardlyFormSection("基本信息") {
                        TextField("项目名称", text: $name, prompt: Text("例如：家庭改造"))
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .focused($focusedField, equals: .name)
                            .onSubmit(createProject)
                            .accessibilityHint("必填")
                    }

                    BoardlyFormSection("外观") {
                        BoardlyFormRow(label: "图标") {
                            Picker("图标", selection: $symbol) {
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
            .boardlyScrollers()

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(BoardlySecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("创建项目") { createProject() }
                    .buttonStyle(BoardlyPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(16)
        }
        .frame(width: 420, height: 360)
        .onAppear { focusedField = .name }
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

    private func createProject() {
        guard canSubmit else { return }
        // addProject 内部会将 selectedScope 切到新项目，满足“新建后立即选中”。
        store.addProject(name: name, symbol: symbol, colorName: colorName)
        dismiss()
    }
}
