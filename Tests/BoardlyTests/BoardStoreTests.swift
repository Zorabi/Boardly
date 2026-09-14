import XCTest
@testable import Boardly

@MainActor
final class BoardStoreTests: XCTestCase {
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
