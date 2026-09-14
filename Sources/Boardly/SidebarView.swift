import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: BoardStore

    var body: some View {
        List(selection: $store.selectedScope) {
            Section("任务") {
                SidebarRow(title: "收件箱", systemImage: "tray", count: inboxCount)
                    .tag(SidebarScope.inbox)
                SidebarRow(title: "今天", systemImage: "sun.max", count: todayCount)
                    .tag(SidebarScope.today)
                SidebarRow(title: "所有任务", systemImage: "rectangle.stack", count: store.tasks.count)
                    .tag(SidebarScope.all)
            }

            Section("项目") {
                ForEach(store.projects) { project in
                    Label {
                        Text(project.name)
                    } icon: {
                        Image(systemName: project.symbol)
                            .foregroundStyle(BoardlyTheme.projectColor(named: project.colorName))
                    }
                    .tag(SidebarScope.project(project.id))
                    .accessibilityLabel("项目：\(project.name)")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(BoardlyTheme.sidebar)
        .navigationTitle("Boardly")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                Text("所有更改已保存")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
    }

    private var inboxCount: Int {
        store.tasks.filter { $0.projectID == nil && $0.status != .done }.count
    }

    private var todayCount: Int {
        store.tasks.filter { task in
            guard let date = task.dueDate else { return false }
            return Calendar.current.isDateInToday(date) && task.status != .done
        }.count
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(count) 个任务")
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .accessibilityElement(children: .combine)
    }
}
