import SwiftUI

struct NewTaskSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var status: TaskStatus = .todo
    @State private var priority: TaskPriority = .medium
    @State private var projectID: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @FocusState private var focusedField: Field?

    private enum Field { case title }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("新建任务")
                        .font(.title2.weight(.semibold))
                    Text("只需填写标题，其余内容可以稍后补充。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section("任务内容") {
                    TextField("标题", text: $title, prompt: Text("例如：整理季度计划"))
                        .focused($focusedField, equals: .title)
                        .accessibilityHint("必填")
                    TextField("描述", text: $notes, prompt: Text("补充背景或完成标准"), axis: .vertical)
                        .lineLimit(3...7)
                }

                Section("组织") {
                    Picker("状态", selection: $status) {
                        ForEach(TaskStatus.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item)
                        }
                    }
                    Picker("优先级", selection: $priority) {
                        ForEach(TaskPriority.allCases) { item in
                            Label(item.title, systemImage: item.systemImage).tag(item)
                        }
                    }
                    Picker("项目", selection: $projectID) {
                        Text("收件箱").tag(UUID?.none)
                        ForEach(store.projects) { project in
                            Label(project.name, systemImage: project.symbol).tag(UUID?.some(project.id))
                        }
                    }
                    Toggle("设置截止日期", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("截止日期", selection: $dueDate, displayedComponents: .date)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加任务") {
                    store.addTask(
                        title: title,
                        notes: notes,
                        status: status,
                        priority: priority,
                        projectID: projectID,
                        dueDate: hasDueDate ? dueDate : nil
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
            .padding(16)
        }
        .frame(width: 500, height: 560)
        .onAppear {
            if case let .project(id) = store.selectedScope { projectID = id }
            focusedField = .title
        }
    }
}
