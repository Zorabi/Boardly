import SwiftUI

struct TaskInspectorView: View {
    @EnvironmentObject private var store: BoardStore
    @Binding var task: BoardTask
    let onClose: () -> Void
    let onOpenSettings: (() -> Void)?
    let onDelete: () -> Void

    init(
        task: Binding<BoardTask>,
        onClose: @escaping () -> Void,
        onOpenSettings: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        _task = task
        self.onClose = onClose
        self.onOpenSettings = onOpenSettings
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
                        BoardlyFormRow(label: "列") {
                            Picker("列", selection: columnBinding) {
                                ForEach(store.orderedColumns) { column in
                                    Label(column.name, systemImage: column.symbol).tag(column.id)
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
                                Text("未分类").tag(UUID?.none)
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
            .boardlyScrollers()
        }
        .background(BoardlyTheme.canvas)
    }

    private var header: some View {
        HStack {
            Label("任务详情", systemImage: "slider.horizontal.3")
                .font(.headline)
            Spacer()
            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(BoardlyIconButtonStyle())
                .help("打开看板设置")
                .accessibilityLabel("打开看板设置")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(BoardlyIconButtonStyle())
            .accessibilityLabel("关闭任务详情")
        }
        .padding(16)
    }

    /// 列变更必须走 store.moveTask：目标列尾追加、源列重排，
    /// 直接改 columnID 会绕过排序整理、留下重复 sortOrder。其余字段仍走 updateTask。
    private var columnBinding: Binding<BoardColumn.ID> {
        Binding(
            get: { task.columnID },
            set: { newColumnID in
                guard newColumnID != task.columnID else { return }
                store.moveTask(id: task.id, to: newColumnID)
                if let updated = store.task(withID: task.id) {
                    task = updated
                }
            }
        )
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
