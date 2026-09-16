import Combine
import Foundation

@MainActor
final class BoardStore: ObservableObject {
    @Published var projects: [Project]
    @Published var columns: [BoardColumn]
    @Published var tasks: [BoardTask]
    @Published var selectedScope: SidebarScope = .all
    @Published var selectedTaskID: BoardTask.ID?
    private let persistenceURL: URL?

    init(
        projects: [Project] = [],
        columns: [BoardColumn] = DefaultColumns.makeDefaults(),
        tasks: [BoardTask] = [],
        persistenceURL: URL? = nil
    ) {
        self.projects = projects
        self.columns = Self.normalized(columns)
        self.tasks = tasks
        self.persistenceURL = persistenceURL
    }

    nonisolated private static func normalized(_ columns: [BoardColumn]) -> [BoardColumn] {
        columns.isEmpty ? DefaultColumns.makeDefaults() : columns
    }

    var selectedScopeTitle: String {
        if case let .project(id) = selectedScope {
            return projects.first(where: { $0.id == id })?.name ?? "项目"
        }
        return selectedScope.title
    }

    // MARK: - 列

    /// 展示顺序的列（sortOrder 升序，同序按稳定 id 排列）。
    var orderedColumns: [BoardColumn] {
        columns.sorted {
            if $0.sortOrder == $1.sortOrder { return $0.id.uuidString < $1.id.uuidString }
            return $0.sortOrder < $1.sortOrder
        }
    }

    func column(withID id: BoardColumn.ID?) -> BoardColumn? {
        guard let id else { return nil }
        return columns.first(where: { $0.id == id })
    }

    var doneColumnIDs: Set<BoardColumn.ID> {
        Set(columns.filter(\.isDone).map(\.id))
    }

    func isDoneColumn(_ id: BoardColumn.ID) -> Bool {
        doneColumnIDs.contains(id)
    }

    /// 新增列（追加到末尾）。
    @discardableResult
    func addColumn(name: String, symbol: String, colorName: String) -> BoardColumn.ID? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return nil }

        let column = BoardColumn(
            name: cleanedName,
            symbol: symbol,
            colorName: colorName,
            sortOrder: (columns.map(\.sortOrder).max() ?? -1) + 1
        )
        columns.append(column)
        persist()
        return column.id
    }

    /// 重命名列 / 调整图标与颜色。
    func updateColumn(_ updated: BoardColumn) {
        let cleanedName = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              let index = columns.firstIndex(where: { $0.id == updated.id }) else { return }
        columns[index].name = cleanedName
        columns[index].symbol = updated.symbol
        columns[index].colorName = updated.colorName
        persist()
    }

    /// 调整列顺序：插入到 destinationID 之前；destinationID 为 nil 移到末尾。
    func moveColumn(id: BoardColumn.ID, before destinationID: BoardColumn.ID?) {
        let ordered = orderedColumns
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == id }) else { return }

        var orderedIDs = ordered.map(\.id)
        orderedIDs.remove(at: sourceIndex)
        if let destinationID,
           let destinationIndex = orderedIDs.firstIndex(of: destinationID) {
            orderedIDs.insert(id, at: destinationIndex)
        } else {
            orderedIDs.append(id)
        }
        applyColumnOrder(orderedIDs)
        persist()
    }

    /// 删除列并将其任务迁移到目标列（非空列禁止静默删除；最后一列不可删除）。
    /// 返回 false 表示拒绝本次删除。
    @discardableResult
    func deleteColumn(id: BoardColumn.ID, migratingTasksTo targetID: BoardColumn.ID) -> Bool {
        guard id != targetID,
              columns.count > 1,
              columns.contains(where: { $0.id == id }),
              columns.contains(where: { $0.id == targetID }) else { return false }

        let removedTasks = tasks(inRaw: id).sorted { $0.sortOrder < $1.sortOrder }
        let nextOrder = (tasks(inRaw: targetID).map(\.sortOrder).max() ?? -1) + 1
        for (offset, var task) in removedTasks.enumerated() {
            task.columnID = targetID
            task.sortOrder = nextOrder + offset
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
            }
        }
        columns.removeAll { $0.id == id }
        normalizeColumnOrder()
        persist()
        return true
    }

    private func applyColumnOrder(_ orderedIDs: [BoardColumn.ID]) {
        for (order, id) in orderedIDs.enumerated() {
            if let index = columns.firstIndex(where: { $0.id == id }) {
                columns[index].sortOrder = order
            }
        }
    }

    private func normalizeColumnOrder() {
        applyColumnOrder(orderedColumns.map(\.id))
    }

    // MARK: - 任务查询

    func tasks(in columnID: BoardColumn.ID, matching query: String = "", now: Date = .now) -> [BoardTask] {
        tasks
            .filter { $0.columnID == columnID }
            .filter { taskMatchesScope($0, now: now) }
            .filter { taskMatchesSearch($0, query: query) }
            .sorted(by: taskSort)
    }

    /// 不经过范围/搜索过滤的原始列任务（列删除迁移与计数用）。
    private func tasks(inRaw columnID: BoardColumn.ID) -> [BoardTask] {
        tasks.filter { $0.columnID == columnID }
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
        let doneColumns = doneColumnIDs
        return tasks.filter { $0.projectID == projectID && !doneColumns.contains($0.columnID) }.count
    }

    // MARK: - 项目

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

    // MARK: - 任务变更

    func addTask(
        title: String,
        notes: String,
        columnID: BoardColumn.ID,
        priority: TaskPriority,
        projectID: UUID?,
        dueDate: Date?
    ) {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty, columns.contains(where: { $0.id == columnID }) else { return }

        let nextOrder = (tasks(inRaw: columnID).map(\.sortOrder).max() ?? -1) + 1
        let task = BoardTask(
            title: cleanedTitle,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            columnID: columnID,
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

    func moveTask(id: BoardTask.ID, to columnID: BoardColumn.ID, before destinationID: BoardTask.ID? = nil) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == id }) else { return }
        let sourceColumn = tasks[taskIndex].columnID

        var destinationIDs = tasks
            .filter { $0.columnID == columnID && $0.id != id }
            .sorted(by: taskSort)
            .map(\.id)

        if let destinationID,
           let destinationIndex = destinationIDs.firstIndex(of: destinationID) {
            destinationIDs.insert(id, at: destinationIndex)
        } else {
            destinationIDs.append(id)
        }

        tasks[taskIndex].columnID = columnID
        applySortOrder(to: destinationIDs)
        if sourceColumn != columnID {
            normalizeSortOrder(inRaw: sourceColumn)
        }
        persist()
    }

    func deleteTask(id: BoardTask.ID) {
        tasks.removeAll { $0.id == id }
        if selectedTaskID == id { selectedTaskID = nil }
        persist()
    }

    // MARK: - 过滤与排序

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

    private func normalizeSortOrder(inRaw columnID: BoardColumn.ID) {
        let orderedIDs = tasks(inRaw: columnID).sorted(by: taskSort).map(\.id)
        applySortOrder(to: orderedIDs)
    }

    // MARK: - 持久化

    private func persist() {
        guard let persistenceURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(
                StoreSnapshot(projects: projects, columns: columns, tasks: tasks)
            )
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            assertionFailure("Unable to persist Boardly data: \(error)")
        }
    }

    /// 解码快照并做安全回收：缺列时补默认列；任务引用的列不存在时归入首列，
    /// 保证任何历史数据都不丢任务。供加载与单元测试共用。
    nonisolated static func decodeSnapshot(_ data: Data) throws -> (projects: [Project], columns: [BoardColumn], tasks: [BoardTask]) {
        let snapshot = try JSONDecoder().decode(StoreSnapshot.self, from: data)
        let columns = normalized(snapshot.columns)
        let fallback = columns.min { $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder }
        let columnIDs = Set(columns.map(\.id))
        let tasks = snapshot.tasks.map { task in
            var task = task
            if !columnIDs.contains(task.columnID), let fallback {
                task.columnID = fallback.id
            }
            return task
        }
        return (snapshot.projects, columns, tasks)
    }
}

private struct StoreSnapshot: Codable {
    var projects: [Project]
    var columns: [BoardColumn]
    var tasks: [BoardTask]

    enum CodingKeys: String, CodingKey {
        case projects, columns, tasks
    }

    init(projects: [Project], columns: [BoardColumn], tasks: [BoardTask]) {
        self.projects = projects
        self.columns = columns
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 旧快照没有 columns 字段：补默认四列，任务由 BoardTask 兜底映射 columnID。
        projects = (try? container.decode([Project].self, forKey: .projects)) ?? []
        if let decoded = try? container.decode([BoardColumn].self, forKey: .columns), !decoded.isEmpty {
            columns = decoded
        } else {
            columns = DefaultColumns.makeDefaults()
        }
        tasks = (try? container.decode([BoardTask].self, forKey: .tasks)) ?? []
    }
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
           let snapshot = try? decodeSnapshot(data) {
            return BoardStore(
                projects: snapshot.projects,
                columns: snapshot.columns,
                tasks: snapshot.tasks,
                persistenceURL: persistenceURL
            )
        }

        let seed = preview
        return BoardStore(
            projects: seed.projects,
            columns: seed.columns,
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
                    columnID: DefaultColumns.inProgressID,
                    priority: .high,
                    projectID: product.id,
                    dueDate: today,
                    tags: ["设计", "macOS"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "整理用户访谈记录",
                    notes: "提取关于任务捕获、状态切换和完成反馈的高频需求。",
                    columnID: DefaultColumns.todoID,
                    priority: .medium,
                    projectID: product.id,
                    dueDate: tomorrow,
                    tags: ["研究"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "为项目准备首版验收清单",
                    notes: "覆盖键盘操作、VoiceOver、深浅主题和长文本。",
                    columnID: DefaultColumns.backlogID,
                    priority: .medium,
                    projectID: product.id,
                    tags: ["质量"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "预约牙科检查",
                    columnID: DefaultColumns.todoID,
                    priority: .high,
                    dueDate: today,
                    sortOrder: 1
                ),
                BoardTask(
                    title: "清理书桌和文件柜",
                    notes: "先处理桌面，再按保留、扫描、回收三个类别整理纸质文件。",
                    columnID: DefaultColumns.backlogID,
                    priority: .low,
                    projectID: home.id,
                    tags: ["周末"],
                    sortOrder: 1
                ),
                BoardTask(
                    title: "读完《设计心理学》第三章",
                    columnID: DefaultColumns.doneID,
                    priority: .low,
                    projectID: reading.id,
                    tags: ["阅读"],
                    sortOrder: 0
                ),
                BoardTask(
                    title: "确定 Boardly 的最小任务字段",
                    notes: "保留标题、描述、项目、列、优先级和截止日期；暂不增加估时与复杂依赖。",
                    columnID: DefaultColumns.doneID,
                    priority: .medium,
                    projectID: product.id,
                    tags: ["范围"],
                    sortOrder: 1
                )
            ]
        )
    }
}
