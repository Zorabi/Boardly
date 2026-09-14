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

    func testTaskDragPayloadRoundTripsTaskIDThroughProvider() async throws {
        let task = BoardTask(title: "Drag me", status: .todo)
        let provider = TaskDragPayload.makeProvider(taskID: task.id)

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(BoardlyTheme.taskDragType.identifier))

        let decoded = try await TaskDragPayload.decodeTaskID(from: provider)
        XCTAssertEqual(decoded, task.id)
    }

    func testTaskDragPayloadRejectsNonUUIDData() async throws {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: BoardlyTheme.taskDragType.identifier,
            visibility: .all
        ) { completion in
            completion("not-a-uuid".data(using: .utf8), nil)
            return nil
        }

        let decoded = try await TaskDragPayload.decodeTaskID(from: provider)
        XCTAssertNil(decoded)
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
