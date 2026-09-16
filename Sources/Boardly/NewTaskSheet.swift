import SwiftUI

struct NewTaskSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var columnID: BoardColumn.ID?
    @State private var priority: TaskPriority = .medium
    @State private var projectID: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @FocusState private var focusedField: Field?

    private enum Field { case title }

    /// 从列头进入时预填该列；从工具栏进入为 nil，默认第一列。
    init(initialColumnID: BoardColumn.ID? = nil) {
        _columnID = State(initialValue: initialColumnID)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardlySheetHeader(
                title: "新建任务",
                subtitle: "只需填写标题，其余内容可以稍后补充。"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BoardlyFormSection("任务内容") {
                        TextField("标题", text: $title, prompt: Text("例如：整理季度计划"))
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .focused($focusedField, equals: .title)
                            .onSubmit(submit)
                            .accessibilityHint("必填")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("描述")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            BoardlyTextEditor(text: $notes, minHeight: 84, prompt: "补充背景或完成标准")
                        }
                    }

                    BoardlyFormSection("组织") {
                        BoardlyFormRow(label: "列") {
                            Picker("列", selection: $columnID) {
                                ForEach(store.orderedColumns) { column in
                                    Label(column.name, systemImage: column.symbol)
                                        .tag(BoardColumn.ID?.some(column.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        BoardlyFormRow(label: "优先级") {
                            Picker("优先级", selection: $priority) {
                                ForEach(TaskPriority.allCases) { item in
                                    Label(item.title, systemImage: item.systemImage).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        BoardlyFormRow(label: "项目") {
                            Picker("项目", selection: $projectID) {
                                Text("未分类").tag(UUID?.none)
                                ForEach(store.projects) { project in
                                    Label(project.name, systemImage: project.symbol)
                                        .tag(UUID?.some(project.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        BoardlyFormRow(label: "截止") {
                            Toggle("设置截止日期", isOn: $hasDueDate)
                        }
                        if hasDueDate {
                            DatePicker(
                                "截止日期",
                                selection: $dueDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                Button("添加任务") { submit() }
                    .buttonStyle(BoardlyPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
            .padding(16)
        }
        .frame(width: 480, height: 560)
        .onAppear {
            if columnID == nil {
                columnID = store.orderedColumns.first?.id
            }
            if case let .project(id) = store.selectedScope { projectID = id }
            focusedField = .title
        }
    }

    private func submit() {
        guard canSubmit, let columnID else { return }
        store.addTask(
            title: title,
            notes: notes,
            columnID: columnID,
            priority: priority,
            projectID: projectID,
            dueDate: hasDueDate ? dueDate : nil
        )
        dismiss()
    }
}
