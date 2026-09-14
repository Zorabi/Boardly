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
            header
            Divider()
                .overlay(BoardlyTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BoardlyFormSection("内容") {
                        TextField("标题", text: $task.title, axis: .vertical)
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .lineLimit(1...3)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("描述")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            BoardlyTextEditor(text: $task.notes, minHeight: 110, prompt: "补充背景或完成标准")
                        }
                    }

                    BoardlyFormSection("组织") {
                        BoardlyFormRow(label: "状态") {
                            Picker("状态", selection: $task.status) {
                                ForEach(TaskStatus.allCases) { status in
                                    Label(status.title, systemImage: status.systemImage).tag(status)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        BoardlyFormRow(label: "优先级") {
                            Picker("优先级", selection: $task.priority) {
                                ForEach(TaskPriority.allCases) { priority in
                                    Label(priority.title, systemImage: priority.systemImage).tag(priority)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        BoardlyFormRow(label: "项目") {
                            Picker("项目", selection: $task.projectID) {
                                Text("收件箱").tag(UUID?.none)
                                ForEach(store.projects) { project in
                                    Label(project.name, systemImage: project.symbol)
                                        .tag(UUID?.some(project.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    BoardlyFormSection("日期") {
                        BoardlyFormRow(label: "截止") {
                            Toggle("设置截止日期", isOn: dueDateEnabled)
                        }
                        if task.dueDate != nil {
                            DatePicker(
                                "截止日期",
                                selection: Binding(
                                    get: { task.dueDate ?? .now },
                                    set: { task.dueDate = $0 }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !task.tags.isEmpty {
                        BoardlyFormSection("标签") {
                            FlowTags(tags: task.tags)
                        }
                    }

                    Button("删除任务", role: .destructive, action: onDelete)
                        .buttonStyle(BoardlyDestructiveButtonStyle())
                        .padding(.top, 4)
                        .accessibilityHint("删除后无法撤销")
                }
                .padding(16)
            }
        }
        .background(BoardlyTheme.canvas)
    }

    private var header: some View {
        HStack {
            Label("任务详情", systemImage: "slider.horizontal.3")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(BoardlyIconButtonStyle())
            .accessibilityLabel("关闭任务详情")
        }
        .padding(16)
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
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}
