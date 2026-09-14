import SwiftUI

struct TaskInspectorView: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var task: BoardTask
    let onClose: () -> Void
    let onDelete: () -> Void

    init(task: Binding<BoardTask>, onClose: @escaping () -> Void, onDelete: @escaping () -> Void) {
        _task = task
        self.onClose = onClose
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("任务详情", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .accessibilityLabel("关闭任务详情")
            }
            .padding(16)

            Divider()

            Form {
                Section("内容") {
                    TextField("标题", text: $task.title, axis: .vertical)
                        .lineLimit(1...4)

                    LabeledContent("描述") {
                        TextEditor(text: $task.notes)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("任务描述")
                    }
                }

                Section("组织") {
                    Picker("状态", selection: $task.status) {
                        ForEach(TaskStatus.allCases) { status in
                            Label(status.title, systemImage: status.systemImage).tag(status)
                        }
                    }

                    Picker("优先级", selection: $task.priority) {
                        ForEach(TaskPriority.allCases) { priority in
                            Label(priority.title, systemImage: priority.systemImage).tag(priority)
                        }
                    }

                    Picker("项目", selection: $task.projectID) {
                        Text("收件箱").tag(UUID?.none)
                        ForEach(store.projects) { project in
                            Label(project.name, systemImage: project.symbol).tag(UUID?.some(project.id))
                        }
                    }
                }

                Section("日期") {
                    Toggle("设置截止日期", isOn: dueDateEnabled)
                    if task.dueDate != nil {
                        DatePicker(
                            "截止日期",
                            selection: Binding(
                                get: { task.dueDate ?? .now },
                                set: { task.dueDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                    }
                }

                if !task.tags.isEmpty {
                    Section("标签") {
                        FlowTags(tags: task.tags)
                    }
                }

                Section {
                    Button("删除任务", role: .destructive, action: onDelete)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var dueDateEnabled: Binding<Bool> {
        Binding(
            get: { task.dueDate != nil },
            set: { enabled in
                task.dueDate = enabled ? (task.dueDate ?? .now) : nil
            }
        )
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Label(tag, systemImage: "tag")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}
