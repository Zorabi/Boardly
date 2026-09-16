import SwiftUI

struct NewColumnSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "square.grid.2x2"
    @State private var colorName = "violet"
    @FocusState private var focusedField: Field?

    private enum Field { case name }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardlySheetHeader(
                title: "新增列",
                subtitle: "创建自定义状态列，例如“测试中”或“验证中”。"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BoardlyFormSection("基本信息") {
                        TextField("列名称", text: $name, prompt: Text("例如：测试中"))
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .focused($focusedField, equals: .name)
                            .onSubmit(createColumn)
                            .accessibilityHint("必填")
                    }

                    BoardlyFormSection("外观") {
                        BoardlyFormRow(label: "图标") {
                            Picker("图标", selection: $symbol) {
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
                Button("创建列") { createColumn() }
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
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(colorName == option.name ? .isSelected : [])
    }

    private func createColumn() {
        guard canSubmit else { return }
        store.addColumn(name: name, symbol: symbol, colorName: colorName)
        dismiss()
    }
}
