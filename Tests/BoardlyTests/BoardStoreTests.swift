import XCTest
@testable import Boardly

@MainActor
final class BoardStoreTests: XCTestCase {
    func testTaskDragTypeIsDeclaredWithoutForceUnwrap() {
        // 回归守卫：拖放类型必须以非可选方式声明；如果声明方式退化回
        // UTType(_:)! 且返回 nil，模块初始化会直接崩溃并使本测试无法运行。
        XCTAssertEqual(BoardlyTheme.taskDragType.identifier, "com.boardly.task")
        XCTAssertFalse(BoardlyTheme.taskDragType.identifier.isEmpty)
    }

    func testTaskDragPayloadCodableRoundTrip() throws {
        // Transferable 的 CodableRepresentation 依赖稳定 JSON 编解码。
        let payload = TaskDragPayload(taskID: BoardTask.ID())
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(TaskDragPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(
            String(data: try JSONEncoder().encode(TaskDragPayload(taskID: payload.taskID)), encoding: .utf8),
            #"{"taskID":"\#(payload.taskID.uuidString)"}"#
        )
    }

    /// 构造不等宽/不等距的列几何（中心与半宽均为任意值），验证算法只依赖实时几何。
    private func makeAnchors(
        centers: [TaskStatus: CGFloat],
        halfWidths: [TaskStatus: CGFloat]? = nil
    ) -> [DirectGripPlanner.ColumnAnchor] {
        TaskStatus.allCases.map { status in
            let center = centers[status] ?? 0
            let halfWidth = halfWidths?[status] ?? 140
            return DirectGripPlanner.ColumnAnchor(
                status: status,
                frame: CGRect(x: center - halfWidth, y: 0, width: halfWidth * 2, height: 600)
            )
        }
    }

    func testDirectGripPlannerCrossesColumnsUsingRealColumnCenters() {
        let ids = [BoardTask.ID(), BoardTask.ID()]
        let taskID = ids[0]
        // 不等距中心：backlog 100、todo 420、inProgress 780、done 1300。
        let anchors = makeAnchors(centers: [.backlog: 100, .todo: 420, .inProgress: 780, .done: 1300])

        func plan(width: CGFloat) -> DirectGripPlanner.Plan? {
            DirectGripPlanner.plan(
                taskID: taskID, source: .todo, orderedIDs: ids,
                translation: CGSize(width: width, height: 0),
                columnAnchors: anchors
            )
        }

        // 跨 1 列：落在 inProgress 实际范围内。
        XCTAssertEqual(plan(width: 360), DirectGripPlanner.Plan(status: .inProgress, before: nil))
        // 跨 2 列：落在 done 实际范围内。
        XCTAssertEqual(plan(width: 880), DirectGripPlanner.Plan(status: .done, before: nil))
        // 跨 3 列越界：夹取到最后一列。
        XCTAssertEqual(plan(width: 5_000), DirectGripPlanner.Plan(status: .done, before: nil))
        // 向左跨列与越界夹取到首列。
        XCTAssertEqual(plan(width: -320), DirectGripPlanner.Plan(status: .backlog, before: nil))
        XCTAssertEqual(plan(width: -5_000), DirectGripPlanner.Plan(status: .backlog, before: nil))
        // 落在源列自身范围内（如间隙之外的轻微位移仍属于 todo）→ 不跨列。
        XCTAssertNil(plan(width: 40))
    }

    func testDirectGripPlannerAdaptsToUnequalWidthsAndScaledWindows() {
        let ids = [BoardTask.ID(), BoardTask.ID()]
        let taskID = ids[0]
        // 不等宽列：backlog [0,200)、todo [220,400)、inProgress [430,690)、done [700,1240)。
        let anchors = makeAnchors(
            centers: [.backlog: 100, .todo: 310, .inProgress: 560, .done: 970],
            halfWidths: [.backlog: 100, .todo: 90, .inProgress: 130, .done: 270]
        )

        // targetX=640 在 inProgress [430,690) 内，即使距 done 中心也不越界。
        XCTAssertEqual(
            DirectGripPlanner.plan(
                taskID: taskID, source: .todo, orderedIDs: ids,
                translation: CGSize(width: 330, height: 0), columnAnchors: anchors
            ),
            DirectGripPlanner.Plan(status: .inProgress, before: nil)
        )
        // targetX=700（done 左边界，todo 中心 310 + 390）进入 done。
        XCTAssertEqual(
            DirectGripPlanner.plan(
                taskID: taskID, source: .todo, orderedIDs: ids,
                translation: CGSize(width: 390, height: 0), columnAnchors: anchors
            ),
            DirectGripPlanner.Plan(status: .done, before: nil)
        )

        // 窗口缩放 1.5×：中心与位移同比放大后映射结果不变。
        let scaled = makeAnchors(
            centers: [.backlog: 150, .todo: 465, .inProgress: 840, .done: 1455],
            halfWidths: [.backlog: 150, .todo: 135, .inProgress: 195, .done: 405]
        )
        XCTAssertEqual(
            DirectGripPlanner.plan(
                taskID: taskID, source: .todo, orderedIDs: ids,
                translation: CGSize(width: 495, height: 0), columnAnchors: scaled
            ),
            DirectGripPlanner.Plan(status: .inProgress, before: nil)
        )
    }

    func testDirectGripPlannerLowDisplacementFallsBackToVertical() {
        let three = [BoardTask.ID(), BoardTask.ID(), BoardTask.ID()]
        let middle = three[1]
        let anchors = makeAnchors(centers: [.backlog: 100, .todo: 420, .inProgress: 780, .done: 1300])

        // 水平位移落在源列范围内、向上 → 插入到上一张之前。
        let up = DirectGripPlanner.plan(
            taskID: middle, source: .todo, orderedIDs: three,
            translation: CGSize(width: 30, height: -80),
            columnAnchors: anchors
        )
        XCTAssertEqual(up, DirectGripPlanner.Plan(status: .todo, before: three[0]))

        // 向下 → 3 张卡中第 2 张下移一位等于追加列尾。
        let down = DirectGripPlanner.plan(
            taskID: middle, source: .todo, orderedIDs: three,
            translation: CGSize(width: 0, height: 80),
            columnAnchors: anchors
        )
        XCTAssertEqual(down, DirectGripPlanner.Plan(status: .todo, before: nil))

        // 4 张卡中第 2 张下移一位 = 插入到第 4 张之前。
        let four = [BoardTask.ID(), BoardTask.ID(), BoardTask.ID(), BoardTask.ID()]
        let downFour = DirectGripPlanner.plan(
            taskID: four[1], source: .inProgress, orderedIDs: four,
            translation: CGSize(width: 0, height: 60),
            columnAnchors: anchors
        )
        XCTAssertEqual(downFour, DirectGripPlanner.Plan(status: .inProgress, before: four[3]))
    }

    func testDirectGripPlannerVerticalBoundariesAndNoOps() {
        let ids = [BoardTask.ID(), BoardTask.ID()]
        let anchors = makeAnchors(centers: [.backlog: 100, .todo: 420, .inProgress: 780, .done: 1300])

        // 首行上移、尾行下移、位移过小：均不产生移动。
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: ids[0], source: .todo, orderedIDs: ids,
            translation: CGSize(width: 0, height: -60), columnAnchors: anchors
        ))
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: ids[1], source: .todo, orderedIDs: ids,
            translation: CGSize(width: 0, height: 60), columnAnchors: anchors
        ))
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: ids[0], source: .todo, orderedIDs: ids,
            translation: CGSize(width: 8, height: 12), columnAnchors: anchors
        ))
        // 未知任务 ID（含空列情形）与缺失列几何均不产生移动。
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: BoardTask.ID(), source: .todo, orderedIDs: [],
            translation: CGSize(width: 300, height: 0), columnAnchors: anchors
        ))
        XCTAssertNil(DirectGripPlanner.plan(
            taskID: ids[0], source: .todo, orderedIDs: ids,
            translation: CGSize(width: 300, height: 0), columnAnchors: []
        ))
    }

    func testDirectGripPlanAppliesToStoreWithCorrectBeforeSemantics() {
        let first = BoardTask(title: "First", status: .todo, sortOrder: 0)
        let second = BoardTask(title: "Second", status: .todo, sortOrder: 1)
        let backlogTask = BoardTask(title: "Backlog item", status: .backlog, sortOrder: 0)
        let store = BoardStore(tasks: [first, second, backlogTask])
        let orderedIDs = store.tasks(in: .backlog).map(\.id)
        let anchors = makeAnchors(centers: [.backlog: 100, .todo: 420, .inProgress: 780, .done: 1300])

        // 跨列计划（追加空/目标列语义）→ 应用后顺序正确。
        let cross = DirectGripPlanner.plan(
            taskID: backlogTask.id, source: .backlog, orderedIDs: orderedIDs,
            translation: CGSize(width: 320, height: 0), columnAnchors: anchors
        )
        XCTAssertEqual(cross, DirectGripPlanner.Plan(status: .todo, before: nil))
        store.moveTask(id: backlogTask.id, to: cross!.status, before: cross!.before)
        XCTAssertEqual(store.tasks(in: .todo).map(\.id), [first.id, second.id, backlogTask.id])

        // 垂直计划（上移一位）→ 应用后插到上一张之前。
        let vertical = DirectGripPlanner.plan(
            taskID: backlogTask.id, source: .todo,
            orderedIDs: store.tasks(in: .todo).map(\.id),
            translation: CGSize(width: 0, height: -80),
            columnAnchors: anchors
        )
        XCTAssertEqual(vertical, DirectGripPlanner.Plan(status: .todo, before: second.id))
        store.moveTask(id: backlogTask.id, to: vertical!.status, before: vertical!.before)
        XCTAssertEqual(store.tasks(in: .todo).map(\.id), [first.id, backlogTask.id, second.id])
    }

    func testDropActionMovesTaskBeforeDestinationCard() {
        let first = BoardTask(title: "First", status: .todo, sortOrder: 0)
        let second = BoardTask(title: "Second", status: .todo, sortOrder: 1)
        let backlogTask = BoardTask(title: "Backlog item", status: .backlog, sortOrder: 0)
        let store = BoardStore(tasks: [first, second, backlogTask])

        // 模拟卡片落点的 dropDestination action：拖 Backlog 卡到待办首卡上方。
        let accepted = TaskDropHandler.handle(
            [TaskDragPayload(taskID: backlogTask.id)],
            store: store,
            to: .todo,
            before: first.id
        )

        XCTAssertTrue(accepted)
        XCTAssertEqual(store.tasks(in: .todo).map(\.id), [backlogTask.id, first.id, second.id])
        XCTAssertTrue(store.tasks(in: .backlog).isEmpty)
    }

    func testDropActionAppendsToColumnEndAndRejectsSelfDrop() {
        let task = BoardTask(title: "Solo", status: .backlog, sortOrder: 0)
        let store = BoardStore(tasks: [task])

        // 模拟列级落点（空列或列尾）：before 为 nil，追加到列尾。
        XCTAssertTrue(
            TaskDropHandler.handle([TaskDragPayload(taskID: task.id)], store: store, to: .todo, before: nil)
        )
        XCTAssertEqual(store.task(withID: task.id)?.status, .todo)
        XCTAssertEqual(store.task(withID: task.id)?.sortOrder, 0)

        // 拖到自身卡片上：拒绝且不产生任何移动。
        XCTAssertFalse(
            TaskDropHandler.handle([TaskDragPayload(taskID: task.id)], store: store, to: .backlog, before: task.id)
        )
        XCTAssertEqual(store.task(withID: task.id)?.status, .todo)

        // 空载荷同样拒绝。
        XCTAssertFalse(TaskDropHandler.handle([], store: store, to: .backlog, before: nil))
    }

    func testMoveTaskChangesStatusAndAppendsToDestination() {
        let first = BoardTask(title: "First", status: .todo, sortOrder: 0)
        let second = BoardTask(title: "Second", status: .done, sortOrder: 4)
        let store = BoardStore(tasks: [first, second])

        store.moveTask(id: first.id, to: .done)

        XCTAssertEqual(store.task(withID: first.id)?.status, .done)
        XCTAssertEqual(store.task(withID: first.id)?.sortOrder, 1)
    }

    func testMoveTaskReordersBeforeDestinationInSameColumn() {
        let first = BoardTask(title: "First", status: .todo, sortOrder: 0)
        let second = BoardTask(title: "Second", status: .todo, sortOrder: 1)
        let third = BoardTask(title: "Third", status: .todo, sortOrder: 2)
        let store = BoardStore(tasks: [first, second, third])

        store.moveTask(id: third.id, to: .todo, before: first.id)

        XCTAssertEqual(store.tasks(in: .todo).map(\.id), [third.id, first.id, second.id])
    }

    func testInboxScopeOnlyShowsUnassignedTasks() {
        let project = Project(name: "Project", symbol: "folder", colorName: "blue")
        let inbox = BoardTask(title: "Inbox", status: .todo)
        let assigned = BoardTask(title: "Assigned", status: .todo, projectID: project.id)
        let store = BoardStore(projects: [project], tasks: [inbox, assigned])
        store.selectedScope = .inbox

        XCTAssertEqual(store.tasks(in: .todo).map(\.id), [inbox.id])
    }

    func testSearchMatchesNotesAndTags() {
        let tagged = BoardTask(title: "One", notes: "Accessibility review", status: .backlog, tags: ["VoiceOver"])
        let other = BoardTask(title: "Two", notes: "Visual polish", status: .backlog)
        let store = BoardStore(tasks: [tagged, other])

        XCTAssertEqual(store.tasks(in: .backlog, matching: "voiceover").map(\.id), [tagged.id])
        XCTAssertEqual(store.tasks(in: .backlog, matching: "accessibility").map(\.id), [tagged.id])
    }

    func testBlankTitleIsNotAdded() {
        let store = BoardStore()

        store.addTask(
            title: "   ",
            notes: "Ignored",
            status: .todo,
            priority: .medium,
            projectID: nil,
            dueDate: nil
        )

        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testMoveTaskToEmptyColumnAppendsToDestination() {
        let first = BoardTask(title: "First", status: .todo, sortOrder: 0)
        let second = BoardTask(title: "Second", status: .todo, sortOrder: 1)
        let store = BoardStore(tasks: [first, second])

        // 拖放到空列（如 Backlog）：moveTask 无 before，应追加到列尾。
        store.moveTask(id: second.id, to: .backlog)

        XCTAssertEqual(store.task(withID: second.id)?.status, .backlog)
        XCTAssertEqual(store.task(withID: second.id)?.sortOrder, 0)
        // 源列在移出后重新归一化，剩余顺序保持稳定。
        XCTAssertEqual(store.tasks(in: .todo).map(\.id), [first.id])
        XCTAssertEqual(store.task(withID: first.id)?.sortOrder, 0)
    }

    func testMoveTaskBeforeDestinationInDifferentColumn() {
        let mover = BoardTask(title: "Mover", status: .todo, sortOrder: 0)
        let doneFirst = BoardTask(title: "Done First", status: .done, sortOrder: 0)
        let doneSecond = BoardTask(title: "Done Second", status: .done, sortOrder: 1)
        let store = BoardStore(tasks: [mover, doneFirst, doneSecond])

        // 跨列拖放到“Done Second”卡片上方：应插入到它之前。
        store.moveTask(id: mover.id, to: .done, before: doneSecond.id)

        XCTAssertEqual(store.tasks(in: .done).map(\.id), [doneFirst.id, mover.id, doneSecond.id])
        XCTAssertTrue(store.tasks(in: .todo).isEmpty)
    }

    func testMoveTaskAppendAfterLastKeepsColumnStable() {
        let first = BoardTask(title: "First", status: .inProgress, sortOrder: 3)
        let second = BoardTask(title: "Second", status: .inProgress, sortOrder: 7)
        let store = BoardStore(tasks: [first, second])

        // 列级落点（列尾）对已经是最后一张的卡片不应改变顺序。
        store.moveTask(id: second.id, to: .inProgress)

        XCTAssertEqual(store.tasks(in: .inProgress).map(\.id), [first.id, second.id])
        XCTAssertEqual(store.tasks(in: .inProgress).map(\.sortOrder), [0, 1])
    }

    func testMoveTaskBackAndForthBetweenColumnsPreservesOtherTasks() {
        let first = BoardTask(title: "First", status: .todo, sortOrder: 0)
        let second = BoardTask(title: "Second", status: .todo, sortOrder: 1)
        let traveler = BoardTask(title: "Traveler", status: .todo, sortOrder: 2)
        let store = BoardStore(tasks: [first, second, traveler])

        store.moveTask(id: traveler.id, to: .backlog)
        store.moveTask(id: traveler.id, to: .todo, before: first.id)

        XCTAssertEqual(store.tasks(in: .todo).map(\.id), [traveler.id, first.id, second.id])
        XCTAssertEqual(store.tasks(in: .todo).map(\.sortOrder), [0, 1, 2])
        XCTAssertTrue(store.tasks(in: .backlog).isEmpty)
    }

    func testTaskCountExcludesCompletedTasks() {
        let project = Project(name: "Project", symbol: "folder", colorName: "blue")
        let active = BoardTask(title: "Active", status: .todo, projectID: project.id)
        let completed = BoardTask(title: "Completed", status: .done, projectID: project.id)
        let store = BoardStore(projects: [project], tasks: [active, completed])

        XCTAssertEqual(store.taskCount(in: project.id), 1)
    }

    func testProjectLifecycleAndTaskRecovery() {
        let store = BoardStore()
        let projectID = try! XCTUnwrap(store.addProject(name: "  新项目  ", symbol: "folder", colorName: "violet"))
        XCTAssertEqual(store.project(withID: projectID)?.name, "新项目")
        XCTAssertEqual(store.selectedScope, .project(projectID))

        store.addTask(
            title: "Project task",
            notes: "",
            status: .todo,
            priority: .medium,
            projectID: projectID,
            dueDate: nil
        )

        var project = try! XCTUnwrap(store.project(withID: projectID))
        project.name = "重命名项目"
        store.updateProject(project)
        XCTAssertEqual(store.project(withID: projectID)?.name, "重命名项目")

        store.deleteProject(id: projectID)
        XCTAssertNil(store.project(withID: projectID))
        XCTAssertNil(store.tasks.first?.projectID)
        XCTAssertEqual(store.selectedScope, .all)
    }
}
