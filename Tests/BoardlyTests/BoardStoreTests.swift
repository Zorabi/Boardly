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
