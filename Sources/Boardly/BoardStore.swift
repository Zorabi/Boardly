import Combine
import Foundation

@MainActor
final class BoardStore: ObservableObject {
    @Published var projects: [Project]
    @Published var columns: [BoardColumn]
    @Published var tasks: [BoardTask] {
        didSet { invalidateTaskCaches() }
    }
    @Published var selectedScope: SidebarScope = .all
    @Published var selectedTaskID: BoardTask.ID?
    /// 最近一次持久化是否仍在队列中，供 UI 区分“已提交”与“已落盘”。
    @Published private(set) var isPersistencePending = false
    /// 最近一次最新快照的落盘错误。保留错误而不是在后台静默丢弃，供 UI 或诊断日志观察。
    @Published private(set) var persistenceError: String?
    private let persistenceURL: URL?
    /// 所有编码与写盘都在同一串行队列完成，因此后提交的快照绝不会被更早的快照覆盖。
    private let persistenceQueue = DispatchQueue(
        label: "dev.boardly.persistence",
        qos: .utility
    )
    private var pendingPersistenceTask: Task<Void, Never>?
    private var persistenceSequence = 0
    private var taskGroups: [BoardColumn.ID: [BoardTask]]?
    private var taskQueryCache: CachedTaskQuery?

    private struct TaskQueryKey: Hashable {
        let scope: SidebarScope
        let cleanedQuery: String
        /// 只有“今天”范围依赖日期；同一天内复用缓存，即使每次调用传入新的 Date.now。
        let day: Date?
    }

    private struct CachedTaskQuery {
        let key: TaskQueryKey
        let groups: [BoardColumn.ID: [BoardTask]]
    }

    init(
        projects: [Project] = [],
        columns: [BoardColumn] = DefaultColumns.makeDefaults(),
        tasks: [BoardTask] = [],
        persistenceURL: URL? = nil,
        initialPersistenceError: String? = nil
    ) {
        self.projects = projects
        self.columns = Self.normalized(columns)
        self.tasks = tasks
        self.persistenceURL = persistenceURL
        persistenceError = initialPersistenceError
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

    /// 展示顺序的首个完成列：新增列的默认位置在其之前（无完成列则末尾）。
    var firstDoneColumn: BoardColumn? {
        orderedColumns.first(where: \.isDone)
    }

    /// 新增列并插入到指定位置：before 为目标列时插到它之前，nil 追加到末尾。
    /// isDone 声明完成语义列。插入后统一重排 sortOrder 并持久化。
    @discardableResult
    func addColumn(
        name: String,
        symbol: String,
        colorName: String,
        isDone: Bool = false,
        before destinationID: BoardColumn.ID? = nil
    ) -> BoardColumn.ID? {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { return nil }

        var orderedIDs = orderedColumns.map(\.id)
        let column = BoardColumn(
            name: cleanedName,
            symbol: symbol,
            colorName: colorName,
            sortOrder: (columns.map(\.sortOrder).max() ?? -1) + 1,
            isDone: isDone
        )
        columns.append(column)
        if let destinationID,
           let destinationIndex = orderedIDs.firstIndex(of: destinationID) {
            orderedIDs.insert(column.id, at: destinationIndex)
        } else {
            orderedIDs.append(column.id)
        }
        applyColumnOrder(orderedIDs)
        persist()
        return column.id
    }

    /// 重命名列 / 调整图标、颜色与完成语义。
    /// 返回 false 表示拒绝：最后一个完成列不允许关闭完成语义（侧栏计数与置灰依赖它）。
    @discardableResult
    func updateColumn(_ updated: BoardColumn) -> Bool {
        let cleanedName = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              let index = columns.firstIndex(where: { $0.id == updated.id }) else { return false }
        if columns[index].isDone && !updated.isDone && columns.filter(\.isDone).count <= 1 {
            return false
        }
        columns[index].name = cleanedName
        columns[index].symbol = updated.symbol
        columns[index].colorName = updated.colorName
        columns[index].isDone = updated.isDone
        persist()
        return true
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

    /// 相邻移动一位（左移列/右移列菜单）：与邻居交换位置，越界时不做任何更改。
    func moveColumn(id: BoardColumn.ID, byOffset offset: Int) {
        guard offset != 0 else { return }
        var orderedIDs = orderedColumns.map(\.id)
        guard let sourceIndex = orderedIDs.firstIndex(of: id) else { return }
        let destinationIndex = sourceIndex + offset
        guard orderedIDs.indices.contains(destinationIndex) else { return }
        orderedIDs.swapAt(sourceIndex, destinationIndex)
        applyColumnOrder(orderedIDs)
        persist()
    }

    /// 删除列并将其任务迁移到目标列（非空列禁止静默删除；最后一列不可删除；
    /// 最后一个完成列不可删除——完成语义无法迁移，删除会使侧栏计数永久失真）。
    /// 返回 false 表示拒绝本次删除。
    @discardableResult
    func deleteColumn(id: BoardColumn.ID, migratingTasksTo targetID: BoardColumn.ID) -> Bool {
        guard id != targetID,
              columns.count > 1,
              let deleting = columns.first(where: { $0.id == id }),
              columns.contains(where: { $0.id == targetID }) else { return false }
        if deleting.isDone && columns.filter(\.isDone).count <= 1 {
            return false
        }

        let groupedTasks = groupedTasks()
        let removedTasks = groupedTasks[id] ?? []
        let removedTaskIDs = Set(removedTasks.map(\.id))
        let nextOrder = (groupedTasks[targetID]?.map(\.sortOrder).max() ?? -1) + 1
        let migratedOrders = Dictionary(
            uniqueKeysWithValues: removedTasks.enumerated().map { ($0.element.id, nextOrder + $0.offset) }
        )
        // 一次映射并发布，避免迁移每个任务都触发一次 @Published 更新和 ID 反复查找。
        tasks = tasks.map { task in
            guard let sortOrder = migratedOrders[task.id] else { return task }
            var migrated = task
            migrated.columnID = targetID
            migrated.sortOrder = sortOrder
            return migrated
        }
        // 被删列中的任务会迁移到目标列，但不应继续保持“选中”状态，
        // 否则用户会误以为目标列（常见是 Backlog）被高亮选中。
        if let selectedTaskID, removedTaskIDs.contains(selectedTaskID) {
            self.selectedTaskID = nil
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
        filteredTaskGroups(matching: query, now: now)[columnID] ?? []
    }

    /// 不经过范围/搜索过滤的原始列任务（列删除迁移与计数用）。
    private func tasks(inRaw columnID: BoardColumn.ID) -> [BoardTask] {
        groupedTasks()[columnID] ?? []
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
        tasks = tasks.map { task in
            guard task.projectID == id else { return task }
            var task = task
            task.projectID = nil
            return task
        }
        if selectedScope == .project(id) {
            selectedScope = .all
        }
        persist()
    }

    // MARK: - 任务变更

    @discardableResult
    func addTask(
        title: String,
        notes: String,
        columnID: BoardColumn.ID,
        priority: TaskPriority,
        projectID: UUID?,
        dueDate: Date?
    ) -> BoardTask.ID? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty, columns.contains(where: { $0.id == columnID }) else { return nil }

        // 多窗口下项目可能在表单打开后被删除；将失效引用归一为未分类，
        // 避免任务既不属于现有项目、也无法出现在 Inbox。
        let validProjectID = projectID.flatMap { candidate in
            projects.contains(where: { $0.id == candidate }) ? candidate : nil
        }

        let nextOrder = (tasks(inRaw: columnID).map(\.sortOrder).max() ?? -1) + 1
        let task = BoardTask(
            title: cleanedTitle,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            columnID: columnID,
            priority: priority,
            projectID: validProjectID,
            dueDate: dueDate,
            sortOrder: nextOrder
        )
        tasks.append(task)
        selectedTaskID = task.id
        persist()
        return task.id
    }

    func updateTask(_ updatedTask: BoardTask) {
        guard let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) else { return }
        tasks[index] = updatedTask
        persistDebounced()
    }

    /// 详情面板的显式保存入口。普通字段与跨列移动合并为一次任务数组发布，
    /// 避免先写详情、再移动列造成两次持久化及短暂的中间状态。
    func saveTask(_ updatedTask: BoardTask) {
        guard let currentIndex = tasks.firstIndex(where: { $0.id == updatedTask.id }) else { return }

        let currentTask = tasks[currentIndex]
        var taskToSave = updatedTask
        taskToSave.sortOrder = currentTask.sortOrder

        if currentTask.columnID == taskToSave.columnID {
            guard currentTask != taskToSave else { return }
            tasks[currentIndex] = taskToSave
        } else {
            guard let movedTasks = tasksByMoving(
                id: taskToSave.id,
                to: taskToSave.columnID,
                before: nil,
                replacing: taskToSave
            ) else { return }
            tasks = movedTasks
        }
        persist()
    }

    func moveTask(id: BoardTask.ID, to columnID: BoardColumn.ID, before destinationID: BoardTask.ID? = nil) {
        guard let movedTasks = tasksByMoving(id: id, to: columnID, before: destinationID) else { return }
        guard movedTasks != tasks else { return }
        tasks = movedTasks
        persist()
    }

    private func tasksByMoving(
        id: BoardTask.ID,
        to columnID: BoardColumn.ID,
        before destinationID: BoardTask.ID?,
        replacing replacement: BoardTask? = nil
    ) -> [BoardTask]? {
        guard columns.contains(where: { $0.id == columnID }),
              let taskIndex = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let sourceColumn = tasks[taskIndex].columnID

        let groups = groupedTasks()
        var destinationIDs = (groups[columnID] ?? [])
            .filter { $0.id != id }
            .map(\.id)

        if let destinationID,
           let destinationIndex = destinationIDs.firstIndex(of: destinationID) {
            destinationIDs.insert(id, at: destinationIndex)
        } else {
            destinationIDs.append(id)
        }

        var sortOrders = Dictionary(
            uniqueKeysWithValues: destinationIDs.enumerated().map { ($0.element, $0.offset) }
        )
        if sourceColumn != columnID {
            let sourceIDs = (groups[sourceColumn] ?? [])
                .filter { $0.id != id }
                .map(\.id)
            for (sortOrder, taskID) in sourceIDs.enumerated() {
                sortOrders[taskID] = sortOrder
            }
        }
        // 拖放可同时影响两列；合并为一次数组更新，避免逐 ID 搜索及多次发布中间状态。
        return tasks.map { existingTask in
            var task = existingTask.id == id ? (replacement ?? existingTask) : existingTask
            if task.id == id { task.columnID = columnID }
            if let sortOrder = sortOrders[task.id] { task.sortOrder = sortOrder }
            return task
        }
    }

    func deleteTask(id: BoardTask.ID) {
        tasks.removeAll { $0.id == id }
        if selectedTaskID == id { selectedTaskID = nil }
        persist()
    }

    // MARK: - 过滤与排序

    private func taskMatchesScope(_ task: BoardTask, now: Date, calendar: Calendar) -> Bool {
        switch selectedScope {
        case .inbox:
            return task.projectID == nil
        case .today:
            guard let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: now)
        case .all:
            return true
        case let .project(projectID):
            return task.projectID == projectID
        }
    }

    private func taskMatchesSearch(_ task: BoardTask, cleanedQuery: String) -> Bool {
        guard !cleanedQuery.isEmpty else { return true }
        return task.title.localizedStandardContains(cleanedQuery)
            || task.notes.localizedStandardContains(cleanedQuery)
            || task.tags.contains { $0.localizedStandardContains(cleanedQuery) }
    }

    private func taskSort(_ lhs: BoardTask, _ rhs: BoardTask) -> Bool {
        if lhs.sortOrder == rhs.sortOrder { return lhs.title < rhs.title }
        return lhs.sortOrder < rhs.sortOrder
    }

    private func applySortOrder(to taskIDs: [BoardTask.ID]) {
        guard !taskIDs.isEmpty else { return }
        let sortOrders = Dictionary(uniqueKeysWithValues: taskIDs.enumerated().map { ($0.element, $0.offset) })
        var updatedTasks = tasks
        var didChange = false
        for index in updatedTasks.indices {
            guard let sortOrder = sortOrders[updatedTasks[index].id],
                  updatedTasks[index].sortOrder != sortOrder else { continue }
            updatedTasks[index].sortOrder = sortOrder
            didChange = true
        }
        if didChange {
            tasks = updatedTasks
        }
    }

    private func normalizeSortOrder(inRaw columnID: BoardColumn.ID) {
        let orderedIDs = tasks(inRaw: columnID).sorted(by: taskSort).map(\.id)
        applySortOrder(to: orderedIDs)
    }

    private func invalidateTaskCaches() {
        taskGroups = nil
        taskQueryCache = nil
    }

    private func groupedTasks() -> [BoardColumn.ID: [BoardTask]] {
        if let taskGroups { return taskGroups }
        var grouped: [BoardColumn.ID: [BoardTask]] = [:]
        for task in tasks {
            grouped[task.columnID, default: []].append(task)
        }
        for columnID in grouped.keys {
            grouped[columnID]?.sort(by: taskSort)
        }
        taskGroups = grouped
        return grouped
    }

    private func filteredTaskGroups(matching query: String, now: Date) -> [BoardColumn.ID: [BoardTask]] {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let day = selectedScope == .today ? calendar.startOfDay(for: now) : nil
        let key = TaskQueryKey(scope: selectedScope, cleanedQuery: cleanedQuery, day: day)
        if let cached = taskQueryCache, cached.key == key {
            return cached.groups
        }

        if selectedScope == .all, cleanedQuery.isEmpty {
            let groups = groupedTasks()
            taskQueryCache = CachedTaskQuery(key: key, groups: groups)
            return groups
        }

        var filtered: [BoardColumn.ID: [BoardTask]] = [:]
        for (columnID, columnTasks) in groupedTasks() {
            let matches = columnTasks.filter {
                taskMatchesScope($0, now: now, calendar: calendar)
                    && taskMatchesSearch($0, cleanedQuery: cleanedQuery)
            }
            if !matches.isEmpty { filtered[columnID] = matches }
        }
        // 看板同一时间只使用一个查询结果；单项缓存避免搜索历史无限增长。
        taskQueryCache = CachedTaskQuery(key: key, groups: filtered)
        return filtered
    }

    // MARK: - 持久化

    private func persist() {
        schedulePersistence(after: nil)
    }

    /// 只用于高频字段编辑：在主 actor 合并 120ms 内的输入；编码和写盘始终在 utility 队列。
    private func persistDebounced() {
        schedulePersistence(after: 0.12)
    }

    private func schedulePersistence(after delay: TimeInterval?) {
        guard let persistenceURL else { return }
        pendingPersistenceTask?.cancel()
        persistenceSequence &+= 1
        let sequence = persistenceSequence
        if !isPersistencePending { isPersistencePending = true }
        if persistenceError != nil { persistenceError = nil }
        if let delay {
            let nanoseconds = UInt64(delay * 1_000_000_000)
            // 延迟任务只负责等待；最新快照在等待结束后才截取，避免连续编辑触发
            // 大数组的 Copy-on-Write 复制。
            pendingPersistenceTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard let self,
                      !Task.isCancelled,
                      self.persistenceSequence == sequence else { return }
                self.pendingPersistenceTask = nil
                self.enqueuePersistence(sequence: sequence, to: persistenceURL)
            }
        } else {
            enqueuePersistence(sequence: sequence, to: persistenceURL)
        }
    }

    private func enqueuePersistence(sequence: Int, to url: URL) {
        let snapshot = StoreSnapshot(projects: projects, columns: columns, tasks: tasks)
        let store = self
        persistenceQueue.async { [snapshot, url, sequence, weak store] in
            do {
                try Self.persist(snapshot, to: url)
                Task { @MainActor [weak store] in
                    store?.recordPersistenceResult(sequence: sequence, message: nil)
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak store] in
                    store?.recordPersistenceResult(sequence: sequence, message: message)
                }
            }
        }
    }

    /// 退出路径使用：取消尚未提交的延迟写入，并同步排空队列后落盘当前快照。
    func flushPersistence() {
        guard let persistenceURL else { return }
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil
        persistenceSequence &+= 1
        let sequence = persistenceSequence
        if !isPersistencePending { isPersistencePending = true }
        if persistenceError != nil { persistenceError = nil }
        let snapshot = StoreSnapshot(projects: projects, columns: columns, tasks: tasks)
        do {
            try persistenceQueue.sync {
                try Self.persist(snapshot, to: persistenceURL)
            }
            recordPersistenceResult(sequence: sequence, message: nil)
        } catch {
            recordPersistenceResult(sequence: sequence, message: error.localizedDescription)
        }
    }

    private func recordPersistenceResult(sequence: Int, message: String?) {
        guard sequence == persistenceSequence else { return }
        isPersistencePending = false
        persistenceError = message.map { "Unable to persist Boardly data: \($0)" }
    }

    nonisolated private static func persist(_ snapshot: StoreSnapshot, to url: URL) throws {
        let data = try JSONEncoder().encode(snapshot)
        try writeSnapshot(data, to: url)
    }

    nonisolated private static func writeSnapshot(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    /// 解码后的快照：schemaVersion 标记来源版本，供加载侧决定是否写迁移备份。
    struct DecodedSnapshot: Sendable {
        var projects: [Project]
        var columns: [BoardColumn]
        var tasks: [BoardTask]
        var schemaVersion: Int
    }

    /// 解码快照并做安全回收：v1 缺列时补默认列（旧版迁移）；没有任何完成列时
    /// 恢复已知默认完成列或追加独立“已完成”列（不改写任何现有列的语义）；
    /// 任务引用的列不存在时归入首列。字段缺失按空集合/默认值兼容（仅限 v1），
    /// 字段存在但格式错误会抛出——绝不静默丢弃整个集合。供加载与单元测试共用。
    nonisolated static func decodeSnapshot(_ data: Data) throws -> DecodedSnapshot {
        let snapshot = try JSONDecoder().decode(StoreSnapshot.self, from: data)
        var columns = normalized(snapshot.columns)
        if !columns.contains(where: \.isDone) {
            // 不改写任何现有列的语义：优先恢复已知默认完成列；
            // 否则追加一个独立的“已完成”列，保留全部自定义列与其任务的未完成语义。
            if let doneIndex = columns.firstIndex(where: { $0.id == DefaultColumns.doneID }) {
                columns[doneIndex].isDone = true
            } else {
                columns.append(BoardColumn(
                    id: DefaultColumns.doneID,
                    name: "已完成",
                    symbol: "checkmark.circle.fill",
                    colorName: "green",
                    sortOrder: (columns.map(\.sortOrder).max() ?? -1) + 1,
                    isDone: true
                ))
            }
        }
        let fallback = columns.min {
            $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder
        }
        let columnIDs = Set(columns.map(\.id))
        let projectIDs = Set(snapshot.projects.map(\.id))
        let tasks = snapshot.tasks.map { task in
            var task = task
            if !columnIDs.contains(task.columnID), let fallback {
                task.columnID = fallback.id
            }
            if let projectID = task.projectID, !projectIDs.contains(projectID) {
                task.projectID = nil
            }
            return task
        }
        return DecodedSnapshot(
            projects: snapshot.projects,
            columns: columns,
            tasks: tasks,
            schemaVersion: snapshot.schemaVersion
        )
    }
}

private struct StoreSnapshot: Codable, Sendable {
    /// 当前写入版本：v1 = 旧版（status 字段、无 columns），v2 = 自定义列 + isDone。
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var projects: [Project]
    var columns: [BoardColumn]
    var tasks: [BoardTask]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, projects, columns, tasks
    }

    init(projects: [Project], columns: [BoardColumn], tasks: [BoardTask]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.projects = projects
        self.columns = columns
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 键完全缺失按 v1 兼容；键存在（含显式 null）必须严格解码，null/类型错误触发恢复路径。
        let version: Int
        if container.contains(.schemaVersion) {
            version = try container.decode(Int.self, forKey: .schemaVersion)
        } else {
            version = 1
        }
        guard (1...Self.currentSchemaVersion).contains(version) else {
            // 更新的未来版本（例如降级运行旧 App）：显式拒绝，触发备份而非误覆盖。
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.schemaVersion],
                debugDescription: "board.json schemaVersion \(version) 高于本版本支持的 \(Self.currentSchemaVersion)"
            ))
        }
        schemaVersion = version
        if version >= 2 {
            // v2 起三个集合键均为必需：缺任一键直接抛错，绝不降级为空集合后让保存覆盖原数据。
            projects = try container.decode([Project].self, forKey: .projects)
            columns = try container.decode([BoardColumn].self, forKey: .columns)
            tasks = try container.decode([BoardTask].self, forKey: .tasks)
        } else {
            // v1：只有 columns 允许缺失（触发旧版迁移补默认列）；projects/tasks 缺失视为空集合。
            if container.contains(.projects) {
                projects = try container.decode([Project].self, forKey: .projects)
            } else {
                projects = []
            }
            if container.contains(.columns) {
                columns = try container.decode([BoardColumn].self, forKey: .columns)
            } else {
                columns = []
            }
            if container.contains(.tasks) {
                tasks = try container.decode([BoardTask].self, forKey: .tasks)
            } else {
                tasks = []
            }
        }
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
        return load(persistenceURL: persistenceURL)
    }

    /// 从磁盘加载。旧版数据升级前、以及任何解码失败（畸形/未来版本）时，
    /// 都先把原始字节复制为旁路备份，保证真实快照永远可以找回、不会被静默覆盖。
    /// 解码失败时以默认列 + 空集合启动（不以示例数据冒充用户数据）。
    /// 备份写入失败时走安全失败路径：返回不绑定原文件的内存 store（persistenceURL = nil），
    /// 后续任何修改都不会落盘覆盖原 board.json。
    static func load(persistenceURL: URL) -> BoardStore {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else {
            // 文件不存在：正常首启，示例种子 + 绑定路径。
            let seed = preview
            return BoardStore(
                projects: seed.projects,
                columns: seed.columns,
                tasks: seed.tasks,
                persistenceURL: persistenceURL
            )
        }
        // 文件存在但读取失败（权限/卷错误等）：原始字节拿不到、也无法备份，
        // 必须返回不绑定路径的安全内存 store，避免后续写入覆盖不可读的原文件。
        guard let data = try? Data(contentsOf: persistenceURL) else {
            return BoardStore(
                persistenceURL: nil,
                initialPersistenceError: "无法读取数据文件；当前修改仅保存在本次运行中。"
            )
        }

        do {
            let decoded = try decodeSnapshot(data)
            if decoded.schemaVersion < StoreSnapshot.currentSchemaVersion {
                if writeBackup(data, nextTo: persistenceURL, label: "v\(decoded.schemaVersion)-migration") == nil {
                    // 备份失败：数据可用但仅存内存，绝不让首次写入覆盖未备份的原始文件。
                    return BoardStore(
                        projects: decoded.projects,
                        columns: decoded.columns,
                        tasks: decoded.tasks,
                        persistenceURL: nil,
                        initialPersistenceError: "无法创建迁移备份；当前修改仅保存在本次运行中。"
                    )
                }
            }
            return BoardStore(
                projects: decoded.projects,
                columns: decoded.columns,
                tasks: decoded.tasks,
                persistenceURL: persistenceURL
            )
        } catch {
            if writeBackup(data, nextTo: persistenceURL, label: "recovery") == nil {
                return BoardStore(
                    persistenceURL: nil,
                    initialPersistenceError: "无法备份损坏的数据文件；当前修改仅保存在本次运行中。"
                )
            }
            return BoardStore(persistenceURL: persistenceURL)
        }
    }

    /// 把原始字节复制为 `board.json.<label>.backup`；recovery 备份附 UUID 避免覆盖历史备份。
    /// 返回备份文件 URL；失败返回 nil，由调用方决定安全失败路径。
    @discardableResult
    nonisolated static func writeBackup(_ data: Data, nextTo url: URL, label: String) -> URL? {
        let unique = label == "recovery" ? "-\(UUID().uuidString)" : ""
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).\(label)\(unique).backup")
        do {
            try FileManager.default.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: backupURL, options: .atomic)
            return backupURL
        } catch {
            return nil
        }
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
