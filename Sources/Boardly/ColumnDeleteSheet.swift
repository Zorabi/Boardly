import SwiftUI

/// 删除列的安全迁移弹窗：非空列必须选择迁移目标列，绝不静默删除任务。
struct ColumnDeleteSheet: View {
    @EnvironmentObject private var store: BoardStore
    @Environment(\.dismiss) private var dismiss
    let column: BoardColumn
    @State private var migrationTargetID: BoardColumn.ID?

    private var columnTaskCount: Int {
        store.tasks.filter { $0.columnID == column.id }.count
    }

    private var otherColumns: [BoardColumn] {
        store.orderedColumns.filter { $0.id != column.id }
    }

    /// 该列是最后一个完成列：删除被禁止（完成语义无法随任务迁移）。
    private var isLastDoneColumn: Bool {
        column.isDone && store.doneColumnIDs.count == 1
    }

    private var canDelete: Bool {
        Self.canConfirm(
            taskCount: columnTaskCount,
            selectedTargetID: migrationTargetID,
            otherColumnCount: otherColumns.count,
            isLastDoneColumn: isLastDoneColumn
        )
    }

    /// 删除门槛（纯函数，供状态测试）：
    /// 非空列必须由用户显式选择迁移目标；最后一个完成列不可删除。
    static func canConfirm(
        taskCount: Int,
        selectedTargetID: BoardColumn.ID?,
        otherColumnCount: Int,
        isLastDoneColumn: Bool
    ) -> Bool {
        if isLastDoneColumn { return false }
        if taskCount == 0 { return otherColumnCount > 0 }
        return selectedTargetID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardlySheetHeader(
                title: "删除列“\(column.name)”",
                subtitle: columnTaskCount == 0
                    ? "该列为空，删除不会影响任何任务。"
                    : "该列有 \(columnTaskCount) 个任务，删除前需将它们迁移到其他列。"
            )

            VStack(alignment: .leading, spacing: 16) {
                if isLastDoneColumn {
                    BoardlyFormSection("无法删除") {
                        Text("这是最后一个完成列，至少需要保留一个。可先把其他列设为完成列，再删除此列。")
                            .boardlyFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if columnTaskCount > 0 {
                    BoardlyFormSection("任务迁移") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("请选择一个列接收这 \(columnTaskCount) 个任务（按原顺序追加到其末尾）。")
                                .boardlyFont(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(otherColumns) { target in
                                migrationRow(target)
                            }
                        }
                    }
                } else {
                    BoardlyFormSection("确认") {
                        Text("此操作不可撤销；列的顺序调整与其他列不受影响。")
                            .boardlyFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(BoardlySecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("删除列", role: .destructive) { delete() }
                    .buttonStyle(BoardlyDestructiveButtonStyle())
                    .disabled(!canDelete)
            }
            .padding(16)
        }
        .frame(width: 420, height: columnTaskCount > 0 ? 400 : 280)
    }

    private func migrationRow(_ target: BoardColumn) -> some View {
        Button {
            migrationTargetID = target.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: target.symbol)
                    .boardlySystemFont(size: 12, weight: .semibold)
                    .foregroundStyle(BoardlyTheme.projectColor(named: target.colorName))
                Text(target.name)
                    .boardlyFont(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(store.tasks.filter { $0.columnID == target.id }.count, format: .number)
                    .boardlyFont(.caption, monospacedDigits: true)
                    .foregroundStyle(.secondary)
                if migrationTargetID == target.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BoardlyTheme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous)
                    .fill(migrationTargetID == target.id ? BoardlyTheme.selectedCard : BoardlyTheme.field)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous)
                    .strokeBorder(
                        migrationTargetID == target.id ? BoardlyTheme.selectedBorder.opacity(0.6) : BoardlyTheme.border
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("迁移到\(target.name)")
        .accessibilityAddTraits(migrationTargetID == target.id ? .isSelected : [])
    }

    private func delete() {
        // 非空列必须使用用户显式选择的目标；空列无任务实际迁移，任选一列接收即可。
        let targetID = columnTaskCount == 0 ? otherColumns.first?.id : migrationTargetID
        guard let targetID, store.deleteColumn(id: column.id, migratingTasksTo: targetID) else { return }
        dismiss()
    }
}
