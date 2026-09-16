import XCTest
@testable import Boardly

@MainActor
final class BoardStoreTests: XCTestCase {
    // MARK: - 快照迁移与数据安全

    /// 构造旧版 board.json（status 字段、无 columns 字段）验证向后兼容迁移。
    func testLegacySnapshotMigratesStatusesToDefaultColumns() throws {
        let legacyJSON = """
        {
          "projects": [
            {"id": "11111111-1111-1111-1111-111111111111", "name": "项目", "symbol": "folder", "colorName": "blue"}
          ],
          "tasks": [
            {"id": "aaaaaaaa-0000-0000-0000-000000000001", "title": "积压", "status": "backlog", "sortOrder": 0},
            {"id": "aaaaaaaa-0000-0000-0000-000000000002", "title": "待办", "status": "todo", "sortOrder": 0},
            {"id": "aaaaaaaa-0000-0000-0000-000000000003", "title": "进行", "status": "inProgress", "sortOrder": 0},
            {"id": "aaaaaaaa-0000-0000-0000-000000000004", "title": "完成", "status": "done", "sortOrder": 0}
          ]
        }
        """
        let data = Data(legacyJSON.utf8)

        let snapshot = try BoardStore.decodeSnapshot(data)

        // 补默认四列，任务按旧 status 映射，无丢失。
        XCTAssertEqual(snapshot.columns.count, 4)
        XCTAssertEqual(snapshot.columns.map(\.name), ["Backlog", "待办", "进行中", "已完成"])
        XCTAssertEqual(snapshot.tasks.count, 4)
        XCTAssertEqual(
            snapshot.tasks.first(where: { $0.title == "积压" })?.columnID,
            DefaultColumns.backlogID
        )
        XCTAssertEqual(
            snapshot.tasks.first(where: { $0.title == "完成" })?.columnID,
            DefaultColumns.doneID
        )
        XCTAssertEqual(snapshot.projects.first?.name, "项目")
    }

    func testLegacyBoardTaskDecodingPerStatus() throws {
        for (status, expected) in [
            (TaskStatus.backlog, DefaultColumns.backlogID),
            (TaskStatus.todo, DefaultColumns.todoID),
            (TaskStatus.inProgress, DefaultColumns.inProgressID),
            (TaskStatus.done, DefaultColumns.doneID)
        ] {
            let json = #"{"id": "bbbbbbbb-0000-0000-0000-000000000001", "title": "T", "status": "\#(status.rawValue)"}"#
            let task = try JSONDecoder().decode(BoardTask.self, from: Data(json.utf8))
            XCTAssertEqual(task.columnID, expected, "旧 status \(status.rawValue) 应映射到默认列")
        }
    }

    func testSnapshotRoundTripKeepsCustomColumnsAndTaskReferences() throws {
        let testing = BoardColumn(name: "测试中", symbol: "testtube.2", colorName: "teal", sortOrder: 4)
        let verifying = BoardColumn(name: "验证中", symbol: "eyeglasses", colorName: "pink", sortOrder: 5)
        let task = BoardTask(title: "自定义列任务", columnID: verifying.id)
        let store = BoardStore(columns: DefaultColumns.makeDefaults() + [testing, verifying], tasks: [task])

        let data = try JSONEncoder().encode(
            StoreSnapshotEncodable(projects: store.projects, columns: store.columns, tasks: store.tasks)
        )
        let decoded = try BoardStore.decodeSnapshot(data)

        XCTAssertEqual(decoded.columns.count, 6)
        XCTAssertEqual(orderedColumnNames(of: decoded.columns), ["Backlog", "待办", "进行中", "已完成", "测试中", "验证中"])
        XCTAssertEqual(decoded.tasks.first?.columnID, verifying.id)
    }

    /// 任务引用了不存在的列（异常数据）：安全回收进首列，不丢任务。
    func testTaskReferencingMissingColumnIsReassigned() throws {
        let ghost = UUID()
        let json = """
        {
          "columns": [
            {"id": "cccccccc-0000-0000-0000-000000000001", "name": "A", "symbol": "circle", "colorName": "blue", "sortOrder": 0},
            {"id": "cccccccc-0000-0000-0000-000000000002", "name": "B", "symbol": "clock", "colorName": "amber", "sortOrder": 1}
          ],
          "tasks": [
            {"id": "dddddddd-0000-0000-0000-000000000001", "title": "孤儿", "columnID": "\(ghost.uuidString)", "sortOrder": 0}
          ]
        }
        """
        let snapshot = try BoardStore.decodeSnapshot(Data(json.utf8))

        XCTAssertEqual(snapshot.tasks.count, 1, "引用缺失列的任务不得被丢弃")
        XCTAssertEqual(snapshot.tasks.first?.columnID, snapshot.columns.minByOrder()?.id)
    }

    /// 缺 isDone 的自定义列必须原样保留（不退回默认列）；isDone 缺省 false，
    /// 且解码恢复“至少一个完成列”不变量：末列被标记为完成列。
    func testCustomColumnMissingIsDoneIsPreserved() throws {
        let firstID = "eeeeeeee-0000-0000-0000-000000000001"
        let secondID = "eeeeeeee-0000-0000-0000-000000000002"
        let json = """
        {
          "schemaVersion": 2,
          "columns": [
            {"id": "\(firstID)", "name": "测试中", "symbol": "testtube.2", "colorName": "teal", "sortOrder": 0},
            {"id": "\(secondID)", "name": "验证中", "symbol": "eyeglasses", "colorName": "pink", "sortOrder": 1}
          ],
          "tasks": [
            {"id": "dddddddd-0000-0000-0000-000000000002", "title": "自定义列任务", "columnID": "\(secondID)", "sortOrder": 0}
          ]
        }
        """
        let snapshot = try BoardStore.decodeSnapshot(Data(json.utf8))

        XCTAssertEqual(snapshot.columns.map(\.name), ["测试中", "验证中"], "缺 isDone 的自定义列不得退回默认列")
        XCTAssertEqual(snapshot.columns.first?.isDone, false)
        XCTAssertEqual(snapshot.columns.last?.isDone, true, "无任何完成列时恢复末列为完成列")
        XCTAssertEqual(snapshot.tasks.first?.columnID, UUID(uuidString: secondID))
        XCTAssertEqual(snapshot.schemaVersion, 2)
    }

    /// 集合字段存在但格式错误：必须抛错，而不是静默清空后让保存覆盖原数据。
    func testMalformedCollectionsThrowInsteadOfSilentlyDropping() {
        let badTask = """
        {"columns": [{"id": "cccccccc-0000-0000-0000-000000000001", "name": "A", "symbol": "circle", "colorName": "blue", "sortOrder": 0}],
         "tasks": [{"id": "dddddddd-0000-0000-0000-000000000003", "title": 123, "sortOrder": 0}]}
        """
        XCTAssertThrowsError(try BoardStore.decodeSnapshot(Data(badTask.utf8)), "tasks 内元素畸形必须抛错")

        let badColumn = """
        {"columns": [{"id": "cccccccc-0000-0000-0000-000000000002", "name": "A", "symbol": "circle", "colorName": "blue"}]}
        """
        XCTAssertThrowsError(try BoardStore.decodeSnapshot(Data(badColumn.utf8)), "columns 内元素缺 sortOrder 必须抛错")

        let badColumnFieldType = """
        {"columns": [{"id": "cccccccc-0000-0000-0000-000000000003", "name": "A", "symbol": "circle", "colorName": "blue", "sortOrder": 0, "isDone": "yes"}]}
        """
        XCTAssertThrowsError(try BoardStore.decodeSnapshot(Data(badColumnFieldType.utf8)), "isDone 类型错误必须抛错")

        let badProject = """
        {"projects": [{"id": "11111111-1111-1111-1111-111111111112", "name": 42}]}
        """
        XCTAssertThrowsError(try BoardStore.decodeSnapshot(Data(badProject.utf8)), "projects 内元素畸形必须抛错")

        let badLegacyStatus = """
        {"tasks": [{"id": "dddddddd-0000-0000-0000-000000000004", "title": "T", "status": "weird"}]}
        """
        XCTAssertThrowsError(try BoardStore.decodeSnapshot(Data(badLegacyStatus.utf8)), "旧 status 取值畸形必须抛错")
    }

    /// 高于本版本支持的 schemaVersion（降级运行旧 App）：显式拒绝而不是误迁移。
    func testFutureSchemaVersionSnapshotIsRejected() {
        let json = """
        {"schemaVersion": 99,
         "columns": [{"id": "cccccccc-0000-0000-0000-000000000009", "name": "A", "symbol": "circle", "colorName": "blue", "sortOrder": 0}]}
        """
        XCTAssertThrowsError(try BoardStore.decodeSnapshot(Data(json.utf8)))
    }

    /// 旧版快照加载：升级前写迁移备份；加载本身不改写原文件。
    func testLegacyLoadWritesMigrationBackupWithoutTouchingOriginal() throws {
        let legacyJSON = """
        {"projects": [], "tasks": [{"id": "aaaaaaaa-0000-0000-0000-000000000010", "title": "旧任务", "status": "todo", "sortOrder": 0}]}
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = dir.appendingPathComponent("board.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let originalData = Data(legacyJSON.utf8)
        try originalData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = BoardStore.load(persistenceURL: fileURL)

        XCTAssertEqual(store.columns.count, 4, "旧版数据迁移到默认四列")
        XCTAssertEqual(store.tasks.first?.columnID, DefaultColumns.todoID)
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData, "加载阶段不得改写原文件")

        let backupURL = dir.appendingPathComponent("board.json.v1-migration.backup")
        XCTAssertEqual(try Data(contentsOf: backupURL), originalData, "迁移前必须保留原始字节备份")
    }

    /// 畸形快照加载：写 recovery 备份、以默认列+空集合启动（不以示例数据冒充），
    /// 且加载阶段不覆盖原文件。
    func testCorruptLoadWritesRecoveryBackupAndStartsClean() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = dir.appendingPathComponent("board.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let corruptData = Data("{ this is not json".utf8)
        try corruptData.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = BoardStore.load(persistenceURL: fileURL)

        XCTAssertEqual(store.columns.count, 4)
        XCTAssertTrue(store.tasks.isEmpty, "解码失败不得以示例任务冒充用户数据")
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), corruptData, "加载阶段不得覆盖原文件")

        let backups = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("board.json.recovery-") }
        XCTAssertEqual(backups.count, 1, "必须写入 recovery 备份")
        XCTAssertEqual(try Data(contentsOf: backups[0]), corruptData, "备份必须保留原始字节")
    }

    // MARK: - 列 CRUD 与排序

    func testAddRenameAndMoveColumnOrdering() {
        let store = BoardStore(columns: DefaultColumns.makeDefaults())

        // 新增列追加到末尾。
        let testingID = store.addColumn(name: "  测试中  ", symbol: "testtube.2", colorName: "teal")
        XCTAssertEqual(store.orderedColumns.map(\.name).last, "测试中")
        XCTAssertEqual(store.column(withID: testingID)?.name, "测试中", "列名需去除首尾空白")

        // 空白名称拒绝创建。
        XCTAssertNil(store.addColumn(name: "   ", symbol: "circle", colorName: "blue"))

        // 重命名。
        var renamed = try! XCTUnwrap(store.column(withID: testingID))
        renamed.name = "验证中"
        store.updateColumn(renamed)
        XCTAssertEqual(store.orderedColumns.last?.name, "验证中")

        // 移到最前（插入到 Backlog 之前）。
        store.moveColumn(id: testingID!, before: DefaultColumns.backlogID)
        XCTAssertEqual(store.orderedColumns.first?.name, "验证中")
        XCTAssertEqual(
            store.orderedColumns.map(\.name),
            ["验证中", "Backlog", "待办", "进行中", "已完成"]
        )

        // 移到末尾。
        store.moveColumn(id: testingID!, before: nil)
        XCTAssertEqual(store.orderedColumns.last?.name, "验证中")
    }

    /// 相邻左移/右移必须真正交换位置（此前后移把右邻作为 before 目标，顺序不变）。
    func testMoveColumnByAdjacentOffset() {
        let a = BoardColumn(name: "A", symbol: "circle", colorName: "blue", sortOrder: 0)
        let b = BoardColumn(name: "B", symbol: "clock", colorName: "amber", sortOrder: 1)
        let c = BoardColumn(name: "C", symbol: "bolt", colorName: "teal", sortOrder: 2)
        let d = BoardColumn(name: "D", symbol: "tray", colorName: "coral", sortOrder: 3, isDone: true)
        let store = BoardStore(columns: [a, b, c, d])

        // B 右移一位：A C B D。
        store.moveColumn(id: b.id, byOffset: 1)
        XCTAssertEqual(store.orderedColumns.map(\.name), ["A", "C", "B", "D"])

        // B 再左移一位还原：A B C D。
        store.moveColumn(id: b.id, byOffset: -1)
        XCTAssertEqual(store.orderedColumns.map(\.name), ["A", "B", "C", "D"])

        // A 左移 / D 右移：越界不更改。
        store.moveColumn(id: a.id, byOffset: -1)
        store.moveColumn(id: d.id, byOffset: 1)
        XCTAssertEqual(store.orderedColumns.map(\.name), ["A", "B", "C", "D"])

        // A 连右移两位到末尾。
        store.moveColumn(id: a.id, byOffset: 1)
        store.moveColumn(id: a.id, byOffset: 1)
        XCTAssertEqual(store.orderedColumns.map(\.name), ["B", "C", "A", "D"])
    }

    // MARK: - 列删除安全策略

    func testDeleteColumnMigratesTasksToTargetPreservingOrder() {
        let target = BoardColumn(name: "目标", symbol: "circle", colorName: "blue", sortOrder: 4)
        let source = BoardColumn(name: "被删列", symbol: "tray", colorName: "coral", sortOrder: 5)
        let first = BoardTask(title: "A", columnID: source.id, sortOrder: 0)
        let second = BoardTask(title: "B", columnID: source.id, sortOrder: 1)
        let existing = BoardTask(title: "已有", columnID: target.id, sortOrder: 7)
        let store = BoardStore(columns: DefaultColumns.makeDefaults() + [target, source], tasks: [first, second, existing])

        XCTAssertTrue(store.deleteColumn(id: source.id, migratingTasksTo: target.id))
        XCTAssertNil(store.column(withID: source.id))
        // 迁移任务追加到目标列尾部且保持相对顺序。
        XCTAssertEqual(store.tasks(in: target.id).map(\.title), ["已有", "A", "B"])
    }

    func testDeleteColumnRejectsUnsafeRequests() {
        let extra = BoardColumn(name: "额外", symbol: "bolt", colorName: "teal", sortOrder: 4)
        let onlyStore = BoardStore(columns: [extra])
        // 仅剩一列时禁止删除。
        XCTAssertFalse(onlyStore.deleteColumn(id: extra.id, migratingTasksTo: extra.id))

        let store = BoardStore(columns: DefaultColumns.makeDefaults() + [extra])
        // 目标列与被删列相同、或目标不存在：拒绝。
        XCTAssertFalse(store.deleteColumn(id: DefaultColumns.todoID, migratingTasksTo: DefaultColumns.todoID))
        XCTAssertFalse(store.deleteColumn(id: DefaultColumns.todoID, migratingTasksTo: UUID()))
        // 被删列不存在：拒绝。
        XCTAssertFalse(store.deleteColumn(id: UUID(), migratingTasksTo: DefaultColumns.todoID))
        XCTAssertEqual(store.columns.count, 5, "被拒绝的删除不得改变列集合")
    }

    // MARK: - 完成列语义不变量

    /// 最后一个完成列不能被关闭完成语义，也不能被删除；出现第二个完成列后才允许。
    func testUpdateAndDeletePreserveAtLeastOneDoneColumn() throws {
        let store = BoardStore(columns: DefaultColumns.makeDefaults())
        let doneColumn = try XCTUnwrap(store.column(withID: DefaultColumns.doneID))

        // 关闭唯一完成列的完成语义：拒绝。
        var turnedOff = doneColumn
        turnedOff.isDone = false
        XCTAssertFalse(store.updateColumn(turnedOff))
        XCTAssertTrue(store.column(withID: DefaultColumns.doneID)!.isDone)

        // 删除唯一完成列：拒绝（即使迁移目标合法）。
        XCTAssertFalse(store.deleteColumn(id: DefaultColumns.doneID, migratingTasksTo: DefaultColumns.todoID))
        XCTAssertNotNil(store.column(withID: DefaultColumns.doneID))

        // 新增一个完成列后，原完成列可以关闭/删除。
        let archiveID = try XCTUnwrap(store.addColumn(name: "归档", symbol: "shippingbox", colorName: "purple", isDone: true))
        XCTAssertTrue(store.updateColumn(turnedOff))
        XCTAssertFalse(store.column(withID: DefaultColumns.doneID)!.isDone)
        XCTAssertTrue(store.deleteColumn(id: DefaultColumns.doneID, migratingTasksTo: DefaultColumns.todoID))
        XCTAssertEqual(store.doneColumnIDs, Set([archiveID]))
    }

    /// 删除弹窗门槛：非空列必须显式选择迁移目标（初始 nil 不可删）；最后一个完成列不可删。
    func testColumnDeleteSheetRequiresExplicitMigrationTarget() {
        let target = UUID()
        // 非空 + 未选择：不可删。
        XCTAssertFalse(ColumnDeleteSheet.canConfirm(
            taskCount: 2, selectedTargetID: nil, otherColumnCount: 3, isLastDoneColumn: false
        ))
        // 非空 + 显式选择：可删。
        XCTAssertTrue(ColumnDeleteSheet.canConfirm(
            taskCount: 2, selectedTargetID: target, otherColumnCount: 3, isLastDoneColumn: false
        ))
        // 空列：无需迁移目标。
        XCTAssertTrue(ColumnDeleteSheet.canConfirm(
            taskCount: 0, selectedTargetID: nil, otherColumnCount: 3, isLastDoneColumn: false
        ))
        // 最后一个完成列：无论如何不可删。
        XCTAssertFalse(ColumnDeleteSheet.canConfirm(
            taskCount: 0, selectedTargetID: target, otherColumnCount: 3, isLastDoneColumn: true
        ))
    }

    /// Inspector 改列的等价 store 流程：必须走 moveTask（目标列尾追加 + 源列重排），
    /// 而不是直接 updateTask 改 columnID（会留下重复 sortOrder 与不确定顺序）。
    func testInspectorColumnChangeFlowPreservesOrdering() {
        let sourceTask0 = BoardTask(title: "S0", columnID: DefaultColumns.todoID, sortOrder: 0)
        let sourceTask1 = BoardTask(title: "S1", columnID: DefaultColumns.todoID, sortOrder: 1)
        let targetTask = BoardTask(title: "T0", columnID: DefaultColumns.backlogID, sortOrder: 1)
        let moverID = sourceTask1.id
        let store = BoardStore(tasks: [sourceTask0, sourceTask1, targetTask])

        // Inspector 列 Picker 的新值 → store.moveTask（列尾追加）。
        store.moveTask(id: moverID, to: DefaultColumns.backlogID)
        if let updated = store.task(withID: moverID) {
            // 回写草稿（与 columnBinding 一致）。
            store.updateTask(updated)
        }

        XCTAssertEqual(store.tasks(in: DefaultColumns.backlogID).map(\.id), [targetTask.id, moverID], "改列后追加到目标列末尾")
        XCTAssertEqual(store.tasks(in: DefaultColumns.todoID).map(\.id), [sourceTask0.id])
        let sourceOrders = store.tasks.filter { $0.columnID == DefaultColumns.todoID }.map(\.sortOrder)
        let targetOrders = store.tasks.filter { $0.columnID == DefaultColumns.backlogID }.map(\.sortOrder)
        XCTAssertEqual(sourceOrders, sourceOrders.sorted(), "源列重排后顺序连续")
        XCTAssertEqual(Set(targetOrders).count, targetOrders.count, "目标列不得出现重复 sortOrder")
        XCTAssertEqual(targetOrders.sorted(), [0, 1])
    }

    // MARK: - 任务移动与计数

    func testMoveTaskAcrossCustomColumnsAndReorderBeforeDestination() {
        let testing = BoardColumn(name: "测试中", symbol: "testtube.2", colorName: "teal", sortOrder: 4)
        let first = BoardTask(title: "First", columnID: testing.id, sortOrder: 0)
        let second = BoardTask(title: "Second", columnID: testing.id, sortOrder: 1)
        let mover = BoardTask(title: "Mover", columnID: DefaultColumns.backlogID, sortOrder: 0)
        let store = BoardStore(columns: DefaultColumns.makeDefaults() + [testing], tasks: [first, second, mover])

        // 跨列移动并插入到目标卡之前。
        store.moveTask(id: mover.id, to: testing.id, before: first.id)
        XCTAssertEqual(store.tasks(in: testing.id).map(\.id), [mover.id, first.id, second.id])
        XCTAssertTrue(store.tasks(in: DefaultColumns.backlogID).isEmpty)

        // 空列投放：追加列尾。
        let verifying = BoardColumn(name: "验证中", symbol: "eyeglasses", colorName: "pink", sortOrder: 5)
        store.columns.append(verifying)
        store.moveTask(id: mover.id, to: verifying.id)
        XCTAssertEqual(store.tasks(in: verifying.id).map(\.id), [mover.id])
    }

    func testTaskCountExcludesDoneColumns() {
        let project = Project(name: "P", symbol: "folder", colorName: "blue")
        let customDone = BoardColumn(name: "归档完成", symbol: "shippingbox", colorName: "purple", sortOrder: 4, isDone: true)
        let active = BoardTask(title: "进行中任务", columnID: DefaultColumns.inProgressID, projectID: project.id)
        let done = BoardTask(title: "已完成任务", columnID: DefaultColumns.doneID, projectID: project.id)
        let archived = BoardTask(title: "归档任务", columnID: customDone.id, projectID: project.id)
        let store = BoardStore(
            projects: [project],
            columns: DefaultColumns.makeDefaults() + [customDone],
            tasks: [active, done, archived]
        )

        XCTAssertEqual(store.taskCount(in: project.id), 1, "完成语义列（含自定义）的任务不计入未完成计数")
    }

    // MARK: - 拖放载荷与手势映射

    func testTaskDragTypeIsDeclaredWithoutForceUnwrap() {
        XCTAssertEqual(BoardlyTheme.taskDragType.identifier, "com.boardly.task")
        XCTAssertFalse(BoardlyTheme.taskDragType.identifier.isEmpty)
    }

    func testTaskDragPayloadCodableRoundTrip() throws {
        let payload = TaskDragPayload(taskID: BoardTask.ID())
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(TaskDragPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func testDropActionMovesTaskBeforeDestinationCard() {
        let first = BoardTask(title: "First", columnID: DefaultColumns.todoID, sortOrder: 0)
        let second = BoardTask(title: "Second", columnID: DefaultColumns.todoID, sortOrder: 1)
        let backlogTask = BoardTask(title: "Backlog item", columnID: DefaultColumns.backlogID, sortOrder: 0)
        let store = BoardStore(tasks: [first, second, backlogTask])

        let accepted = TaskDropHandler.handle(
            [TaskDragPayload(taskID: backlogTask.id)],
            store: store,
            to: DefaultColumns.todoID,
            before: first.id
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(store.tasks(in: DefaultColumns.todoID).map(\.id), [backlogTask.id, first.id, second.id])
        XCTAssertTrue(store.tasks(in: DefaultColumns.backlogID).isEmpty)
    }

    func testDropActionAppendsToColumnEndAndRejectsSelfDrop() {
        let task = BoardTask(title: "Solo", columnID: DefaultColumns.backlogID, sortOrder: 0)
        let store = BoardStore(tasks: [task])

        XCTAssertTrue(
            TaskDropHandler.handle(
                [TaskDragPayload(taskID: task.id)],
                store: store, to: DefaultColumns.todoID, before: nil
            )
        )
        XCTAssertEqual(store.task(withID: task.id)?.columnID, DefaultColumns.todoID)

        XCTAssertFalse(
            TaskDropHandler.handle(
                [TaskDragPayload(taskID: task.id)],
                store: store, to: DefaultColumns.backlogID, before: task.id
            )
        )
        XCTAssertFalse(TaskDropHandler.handle([], store: store, to: DefaultColumns.backlogID, before: nil))
    }

    /// 构造不等宽/不等距的列几何（中心与半宽均为任意值），验证算法只依赖实时几何。
    private func makeAnchors(
        centers: [BoardColumn.ID: CGFloat],
        halfWidths: [BoardColumn.ID: CGFloat]? = nil
    ) -> [DirectGripPlanner.ColumnAnchor] {
        centers.map { columnID, center in
            let halfWidth = halfWidths?[columnID] ?? 140
            return DirectGripPlanner.ColumnAnchor(
                columnID: columnID,
                frame: CGRect(x: center - halfWidth, y: 0, width: halfWidth * 2, height: 600)
            )
        }
    }

    func testDirectGripPlannerMapsByRealColumnCentersAndClamps() {
        let ids = [BoardTask.ID(), BoardTask.ID()]
        let taskID = ids[0]
        let anchors = makeAnchors(centers: [
            DefaultColumns.backlogID: 100,
            DefaultColumns.todoID: 420,
            DefaultColumns.inProgressID: 780,
            DefaultColumns.doneID: 1300
        ])

        func plan(width: CGFloat) -> DirectGripPlanner.Plan? {
            DirectGripPlanner.plan(
                taskID: taskID,
                sourceColumnID: DefaultColumns.todoID,
                orderedIDs: ids,
                translation: CGSize(width: width, height: 0),
                columnAnchors: anchors
            )
        }

        XCTAssertEqual(plan(width: 360)?.columnID, DefaultColumns.inProgressID)
        XCTAssertEqual(plan(width: 880)?.columnID, DefaultColumns.doneID)
        XCTAssertEqual(plan(width: 5_000)?.columnID, DefaultColumns.doneID, "右侧越界夹取末列")
        XCTAssertEqual(plan(width: -320)?.columnID, DefaultColumns.backlogID)
        XCTAssertEqual(plan(width: -5_000)?.columnID, DefaultColumns.backlogID, "左侧越界夹取首列")
        XCTAssertNil(plan(width: 40), "仍在源列范围内：不跨列")
    }

    func testDirectGripPlannerSupportsCustomColumnsAndVerticalFallback() {
        let testing = BoardColumn(name: "测试中", symbol: "testtube.2", colorName: "teal", sortOrder: 4)
        let three = [BoardTask.ID(), BoardTask.ID(), BoardTask.ID()]
        let middle = three[1]
        let anchors = makeAnchors(centers: [
            DefaultColumns.backlogID: 100,
            DefaultColumns.todoID: 420,
            DefaultColumns.inProgressID: 780,
            testing.id: 1200,
            DefaultColumns.doneID: 1600
        ])

        // 自定义列同样可作为跨列目标。
        let cross = DirectGripPlanner.plan(
            taskID: middle, sourceColumnID: DefaultColumns.todoID, orderedIDs: three,
            translation: CGSize(width: 780, height: 0), columnAnchors: anchors
        )
        XCTAssertEqual(cross?.columnID, testing.id)

        // 低水平位移回退为同列上移一位。
        let up = DirectGripPlanner.plan(
            taskID: middle, sourceColumnID: DefaultColumns.todoID, orderedIDs: three,
            translation: CGSize(width: 30, height: -80), columnAnchors: anchors
        )
        XCTAssertEqual(up, DirectGripPlanner.Plan(columnID: DefaultColumns.todoID, before: three[0]))

        // 首行上移 / 位移过小 / 空 anchors：无操作。
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: three[0], sourceColumnID: DefaultColumns.todoID, orderedIDs: three,
            translation: CGSize(width: 0, height: -60), columnAnchors: anchors
        ))
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: three[0], sourceColumnID: DefaultColumns.todoID, orderedIDs: three,
            translation: CGSize(width: 8, height: 12), columnAnchors: anchors
        ))
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: three[0], sourceColumnID: DefaultColumns.todoID, orderedIDs: three,
            translation: CGSize(width: 300, height: 0), columnAnchors: []
        ))
    }
}

// MARK: - 测试辅助

/// 测试内编码快照（与 StoreSnapshot 同构；StoreSnapshot 为私有）。
private struct StoreSnapshotEncodable: Encodable {
    let schemaVersion = 2
    let projects: [Project]
    let columns: [BoardColumn]
    let tasks: [BoardTask]
}

private func orderedColumnNames(of columns: [BoardColumn]) -> [String] {
    columns.sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
}

private extension Array where Element == BoardColumn {
    func minByOrder() -> BoardColumn? {
        min { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
        }
    }
}
