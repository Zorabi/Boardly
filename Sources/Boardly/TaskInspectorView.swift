import SwiftUI

struct TaskInspectorView: View {
    @EnvironmentObject private var store: BoardStore
    @State private var draft: BoardTask
    @State private var isConfirmingDiscard = false
    private let originalTask: BoardTask
    let onSave: (BoardTask) -> Void
    let onClose: () -> Void
    let onDelete: () -> Void

    init(
        task: BoardTask,
        onSave: @escaping (BoardTask) -> Void,
        onClose: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        originalTask = task
        _draft = State(initialValue: task)
        self.onSave = onSave
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
                        TextField("标题", text: $draft.title, axis: .vertical)
                            .textFieldStyle(BoardlyTextFieldStyle())
                            .lineLimit(1...3)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("描述")
                                .boardlyFont(.caption)
                                .foregroundStyle(.secondary)
                            BoardlyTextEditor(text: $draft.notes, height: 110, prompt: "补充背景或完成标准")
                        }
                    }

                    BoardlyFormSection("组织") {
                        BoardlyFormRow(label: "列") {
                            Picker("列", selection: $draft.columnID) {
                                ForEach(store.orderedColumns) { column in
                                    Label(column.name, systemImage: column.symbol).tag(column.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        BoardlyFormRow(label: "优先级") {
                            Picker("优先级", selection: $draft.priority) {
                                ForEach(TaskPriority.allCases) { priority in
                                    Label(priority.title, systemImage: priority.systemImage)
                                        .foregroundStyle(BoardlyTheme.priorityColor(for: priority))
                                        .tag(priority)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                        BoardlyFormRow(label: "项目") {
                            Picker("项目", selection: $draft.projectID) {
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
                        if draft.dueDate != nil {
                            DatePicker(
                                "截止日期",
                                selection: Binding(
                                    get: { draft.dueDate ?? .now },
                                    set: { draft.dueDate = $0 }
                                ),
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !draft.tags.isEmpty {
                        BoardlyFormSection("标签") {
                            FlowTags(tags: draft.tags)
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

            Divider()
                .overlay(BoardlyTheme.border)

            HStack(spacing: 8) {
                if hasChanges {
                    Text("有未保存的更改")
                        .boardlyFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: requestClose)
                    .buttonStyle(BoardlySecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .buttonStyle(BoardlyPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .background(BoardlyTheme.canvas)
        // macOS inspector 不会自动把 Esc 传给自定义关闭按钮；
        // 使用原生退出命令保留输入控件内的键盘行为，同时关闭详情面板。
        .onExitCommand(perform: requestClose)
        .alert("放弃未保存的更改？", isPresented: $isConfirmingDiscard) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃更改", role: .destructive, action: onClose)
        } message: {
            Text("尚未保存的任务修改将会丢失。")
        }
    }

    private var header: some View {
        HStack {
            Label("任务详情", systemImage: "slider.horizontal.3")
                .boardlyFont(.headline)
            Spacer()
            Button(action: requestClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(BoardlyIconButtonStyle())
            .accessibilityLabel("关闭任务详情")
        }
        .padding(16)
    }

    private var hasChanges: Bool {
        draft != originalTask
    }

    private var canSave: Bool {
        hasChanges && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var dueDateEnabled: Binding<Bool> {
        Binding(
            get: { draft.dueDate != nil },
            set: { enabled in
                draft.dueDate = enabled ? (draft.dueDate ?? .now) : nil
            }
        )
    }

    private func save() {
        guard canSave else { return }
        onSave(draft)
    }

    private func requestClose() {
        if hasChanges {
            isConfirmingDiscard = true
        } else {
            onClose()
        }
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Label(tag, systemImage: "tag")
                    .boardlyFont(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}
