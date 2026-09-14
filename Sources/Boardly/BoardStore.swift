import Combine
import Foundation

@MainActor
final class BoardStore: ObservableObject {
    @Published var projects: [Project]
    @Published var tasks: [BoardTask]
    @Published var selectedScope: SidebarScope = .all
    @Published var selectedTaskID: BoardTask.ID?
    private let persistenceURL: URL?

    init(projects: [Project] = [], tasks: [BoardTask] = [], persistenceURL: URL? = nil) {
        self.projects = projects
        self.tasks = tasks
        self.persistenceURL = persistenceURL
    }

    var selectedScopeTitle: String {
        if case let .project(id) = selectedScope {
            return projects.first(where: { $0.id == id })?.name ?? "项目"
        }
        return selectedScope.title
    }

    func tasks(in status: TaskStatus, matching query: String = "", now: Date = .now) -> [BoardTask] {
        tasks
            .filter { $0.status == status }
            .filter { taskMatchesScope($0, now: now) }
            .filter { taskMatchesSearch($0, query: query) }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder { return lhs.title < rhs.title }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func task(withID id: BoardTask.ID?) -> BoardTask? {
        guard let id else { return nil }
        return tasks.first(where: { $0.id == id })
    }

    func project(withID id: Project.ID?) -> Project? {
        guard let id else { return nil }
        return projects.first(where: { $0.id == id })
    }

    func taskCount(in projectID: Project.ID) -> Int {
        tasks.filter { $0.projectID == projectID && $0.status != .done }.count
    }

    @discardableResult
    func addProject(name: String, symbol: String, colorName: String) -> Project.ID? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return nil }

        let project = Project(name: cleanedName, symbol: symbol, colorName: colorName)
        projects.append(project)
        selectedScope = .project(project.id)
        persist()
        return project.id
    }

    func updateProject(_ updatedProject: Project) {
        let cleanedName = updatedProject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              let index = projects.firstIndex(where: { $0.id == updatedProject.id }) else { return }

        projects[index] = Project(
            id: updatedProject.id,
            name: cleanedName,
            symbol: updatedProject.symbol,
            colorName: updatedProject.colorName
        )
        persist()
    }

    func deleteProject(id: Project.ID) {
        projects.removeAll { $0.id == id }
        for index in tasks.indices where tasks[index].projectID == id {
            tasks[index].projectID = nil
        }
        if selectedScope == .project(id) {
            selectedScope = .all
        }
        persist()
    }

    func addTask(
        title: String,
        notes: String,
        status: TaskStatus,
        priority: TaskPriority,
        projectID: UUID?,
        dueDate: Date?
    ) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }

        let nextOrder = (tasks.filter { $0.status == status }.map(\.sortOrder).max() ?? -1) + 1
        let task = BoardTask(
            title: cleanedTitle,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            priority: priority,
            projectID: projectID,
            dueDate: dueDate,
            sortOrder: nextOrder
        )
        tasks.append(task)
        selectedTaskID = task.id
        persist()
    }

    func updateTask(_ updatedTask: BoardTask) {
        guard let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) else { return }
        tasks[index] = updatedTask
        persist()
    }

    func moveTask(id: BoardTask.ID, to status: TaskStatus, before destinationID: BoardTask.ID? = nil) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == id }) else { return }
        let sourceStatus = tasks[taskIndex].status

        var destinationIDs = tasks
            .filter { $0.status == status && $0.id != id }
            .sorted(by: taskSort)
            .map(\.id)

        if let destinationID,
           let destinationIndex = destinationIDs.firstIndex(of: destinationID) {
            destinationIDs.insert(id, at: destinationIndex)
        } else {
            destinationIDs.append(id)
        }

        tasks[taskIndex].status = status
        applySortOrder(to: destinationIDs)
        if sourceStatus != status {
            normalizeSortOrder(in: sourceStatus)
        }
        persist()
    }

    func deleteTask(id: BoardTask.ID) {
        tasks.removeAll { $0.id == id }
        if selectedTaskID == id { selectedTaskID = nil }
        persist()
    }

    private func taskMatchesScope(_ task: BoardTask, now: Date) -> Bool {
        switch selectedScope {
        case .inbox:
            return task.projectID == nil
        case .today:
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDate(dueDate, inSameDayAs: now)
        case .all:
            return true
        case let .project(projectID):
            return task.projectID == projectID
        }
    }

    private func taskMatchesSearch(_ task: BoardTask, query: String) -> Bool {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else { return true }
        let searchableText = ([task.title, task.notes] + task.tags).joined(separator: " ")
        return searchableText.localizedStandardContains(cleanedQuery)
    }

    private func taskSort(_ lhs: BoardTask, _ rhs: BoardTask) -> Bool {
        if lhs.sortOrder == rhs.sortOrder { return lhs.title < rhs.title }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func applySortOrder(to taskIDs: [BoardTask.ID]) {
        for (sortOrder, taskID) in taskIDs.enumerated() {
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { continue }
            tasks[index].sortOrder = sortOrder
        }
    }

    private func normalizeSortOrder(in status: TaskStatus) {
        let orderedIDs = tasks.filter { $0.status == status }.sorted(by: taskSort).map(\.id)
        applySortOrder(to: orderedIDs)
    }

    private func persist() {
        guard let persistenceURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(StoreSnapshot(projects: projects, tasks: tasks))
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            assertionFailure("Unable to persist Boardly data: \(error)")
        }
    }
}

private struct StoreSnapshot: Codable {
    var projects: [Project]
    var tasks: [BoardTask]
}

extension BoardStore {
    static var live: BoardStore {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let persistenceURL = applicationSupport
            .appendingPathComponent("Boardly", isDirectory: true)
            .appendingPathComponent("board.json")

        if let data = try? Data(contentsOf: persistenceURL),
           let snapshot = try? JSONDecoder().decode(StoreSnapshot.self, from: data) {
            return BoardStore(
                projects: snapshot.projects,
                tasks: snapshot.tasks,
                persistenceURL: persistenceURL
            )
        }

        let seed = preview
        return BoardStore(
            projects: seed.projects,
            tasks: seed.tasks,
            persistenceURL: persistenceURL
        )
    }

    static var preview: BoardStore {
        let product = Project(name: "产品迭代", symbol: "sparkles", colorName: "coral")
        let home = Project(name: "生活整理", symbol: "house", colorName: "blue")
        let reading = Project(name: "阅读计划", symbol: "book.closed", colorName: "purple")
        let calendar = Calendar.current
        let today = Date.now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)

        return BoardStore(
            projects: [product, home, reading],
            tasks: [
                BoardTask(
                    title: "梳理下一版看板的信息层级",
                    notes: "把常用操作留在看板上，低频编辑收进右侧检查器。确认窄窗口下侧栏自动收起。",
                    status: .inProgress,
                    priority: .high,
                    projectID: product.id,
                    dueDate: today,
                    tags: ["设计", "macOS"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "整理用户访谈记录",
                    notes: "提取关于任务捕获、状态切换和完成反馈的高频需求。",
                    status: .todo,
                    priority: .medium,
                    projectID: product.id,
                    dueDate: tomorrow,
                    tags: ["研究"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "为项目准备首版验收清单",
                    notes: "覆盖键盘操作、VoiceOver、深浅主题和长文本。",
                    status: .backlog,
                    priority: .medium,
                    projectID: product.id,
                    tags: ["质量"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "预约牙科检查",
                    status: .todo,
                    priority: .high,
                    dueDate: today,
                    sortOrder: 1
                ),
                BoardTask(
                    title: "清理书桌和文件柜",
                    notes: "先处理桌面，再按保留、扫描、回收三个类别整理纸质文件。",
                    status: .backlog,
                    priority: .low,
                    projectID: home.id,
                    tags: ["周末"],
                    sortOrder: 1
                ),
                BoardTask(
                    title: "读完《设计心理学》第三章",
                    status: .done,
                    priority: .low,
                    projectID: reading.id,
                    tags: ["阅读"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "确定 Boardly 的最小任务字段",
                    notes: "保留标题、描述、项目、状态、优先级和截止日期；暂不增加估时与复杂依赖。",
                    status: .done,
                    priority: .medium,
                    projectID: product.id,
                    tags: ["范围"],
                    sortOrder: 1
                )
            ]
        )
    }
}
