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

    private var canDelete: Bool {
        // 空列：任选一列接收（无任务实际移动）；非空列：必须明确选择目标。
        if columnTaskCount == 0 { return !otherColumns.isEmpty }
        return migrationTargetID != nil
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
                if columnTaskCount > 0 {
                    BoardlyFormSection("任务迁移") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(otherColumns) { target in
                                migrationRow(target)
                            }
                        }
                    }
                } else {
                    BoardlyFormSection("确认") {
                        Text("此操作不可撤销；列的顺序调整与其他列不受影响。")
                            .font(.subheadline)
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
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canDelete)
            }
            .padding(16)
        }
        .frame(width: 420, height: columnTaskCount > 0 ? 380 : 260)
        .onAppear {
            migrationTargetID = otherColumns.first?.id
        }
    }

    private func migrationRow(_ target: BoardColumn) -> some View {
        Button {
            migrationTargetID = target.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: target.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BoardlyTheme.projectColor(named: target.colorName))
                Text(target.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(store.tasks.filter { $0.columnID == target.id }.count, format: .number)
                    .font(.caption.monospacedDigit())
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
        guard let targetID = migrationTargetID ?? otherColumns.first?.id else { return }
        guard store.deleteColumn(id: column.id, migratingTasksTo: targetID) else { return }
        dismiss()
    }
}
