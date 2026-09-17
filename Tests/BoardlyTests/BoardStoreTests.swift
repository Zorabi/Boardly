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

    /// 缺 isDone 的自定义列必须原样保留（不退回默认列）；isDone 缺省 false；
    /// 无任何完成列时追加独立“已完成”列满足不变量，不把现有列改成完成语义。
    func testCustomColumnMissingIsDoneIsPreserved() throws {
        let firstID = "eeeeeeee-0000-0000-0000-000000000001"
        let secondID = "eeeeeeee-0000-0000-0000-000000000002"
        let json = """
        {
          "schemaVersion": 2,
          "projects": [],
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

        XCTAssertEqual(
            snapshot.columns.map(\.name),
            ["测试中", "验证中", "已完成"],
            "缺 isDone 的自定义列不得退回默认列，且追加独立完成列"
        )
        XCTAssertEqual(snapshot.columns.first?.isDone, false, "现有自定义列保持未完成语义")
        XCTAssertEqual(snapshot.columns.first?.sortOrder, 0, "现有列顺序不变")
        XCTAssertEqual(snapshot.columns.last?.id, DefaultColumns.doneID, "追加的完成列使用已知默认 doneID")
        XCTAssertEqual(snapshot.columns.last?.isDone, true)
        XCTAssertEqual(snapshot.tasks.first?.columnID, UUID(uuidString: secondID), "任务保持原列（未完成语义）")
        XCTAssertEqual(snapshot.schemaVersion, 2)
    }

    /// 无完成列但快照里已有 DefaultColumns.doneID（如手工关闭过）：恢复该已知默认列，
    /// 不追加新列、不改写其他自定义列。
    func testNoDoneColumnRestoresKnownDefaultDoneColumn() throws {
        let custom = "eeeeeeee-0000-0000-0000-000000000003"
        let json = """
        {
          "schemaVersion": 2,
          "projects": [],
          "columns": [
            {"id": "\(custom)", "name": "自定义", "symbol": "bolt", "colorName": "amber", "sortOrder": 0},
            {"id": "\(DefaultColumns.doneID.uuidString)", "name": "已完成", "symbol": "checkmark.circle.fill", "colorName": "green", "sortOrder": 1, "isDone": false}
          ],
          "tasks": []
        }
        """
        let snapshot = try BoardStore.decodeSnapshot(Data(json.utf8))

        XCTAssertEqual(snapshot.columns.count, 2, "恢复已知默认完成列，不追加新列")
        XCTAssertEqual(
            snapshot.columns.first(where: { $0.id == DefaultColumns.doneID })?.isDone,
            true,
            "已知默认 doneID 列恢复完成语义"
        )
        XCTAssertEqual(
            snapshot.columns.first(where: { $0.name == "自定义" })?.isDone,
            false,
            "自定义列语义不变"
        )
    }

    /// 非可选字段的显式 null 必须抛错（不得当作缺失降级）：columnID/isDone/schemaVersion。
    /// columnID:null 会被静默重分类到 legacyStatus/todoID、isDone:null 降级 false、
    /// schemaVersion:null 降级 v1——三种情况都必须进入恢复路径而非静默改数据。
    func testExplicitNullsOnNonOptionalFieldsThrow() throws {
        // BoardTask.columnID: null（即使同时带有合法旧 status）。
        let nullColumnID = #"{"id": "aaaaaaaa-0000-0000-0000-0000000000b1", "title": "T", "columnID": null, "status": "todo"}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(BoardTask.self, from: Data(nullColumnID.utf8)),
            "columnID 显式 null 不得回退旧 status 静默重分类"
        )

        // BoardColumn.isDone: null。
        let nullIsDone = """
        {"schemaVersion": 2, "projects": [], "tasks": [],
         "columns": [{"id": "cccccccc-0000-0000-0000-00000000000c", "name": "A", "symbol": "circle", "colorName": "blue", "sortOrder": 0, "isDone": null}]}
        """
        XCTAssertThrowsError(
            try BoardStore.decodeSnapshot(Data(nullIsDone.utf8)),
            "isDone 显式 null 不得降级为 false"
        )

        // schemaVersion: null。
        let nullVersion = """
        {"schemaVersion": null, "projects": [], "tasks": []}
        """
        XCTAssertThrowsError(
            try BoardStore.decodeSnapshot(Data(nullVersion.utf8)),
            "schemaVersion 显式 null 不得降级为 v1"
        )
    }

    /// columnID 与旧 status 同时缺失：数据不完整，必须抛错，
    /// 不得静默把 v2 缺列任务归入待办列。
    func testTaskWithoutColumnIDAndStatusThrows() {
        let bothMissing = #"{"id": "aaaaaaaa-0000-0000-0000-0000000000b2", "title": "无列任务"}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(BoardTask.self, from: Data(bothMissing.utf8)),
            "columnID 与 status 均缺失不得静默落入待办列"
        )
    }

    /// load 区分“文件不存在”与“存在但读取失败”：
    /// 前者返回绑定路径的 preview 种子（可正常持久化）；
    /// 后者返回不绑定路径的安全内存 store，后续写入绝不覆盖不可读的原文件。
    func testLoadDistinguishesMissingFileFromUnreadableFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 路径一：文件不存在 → preview 种子 + 绑定路径，修改会正常落盘。
        let missingURL = dir.appendingPathComponent("board.json")
        let seededStore = BoardStore.load(persistenceURL: missingURL)
        XCTAssertFalse(seededStore.tasks.isEmpty, "首启应加载示例种子")
        seededStore.addTask(title: "首启任务", notes: "", columnID: DefaultColumns.todoID, priority: .medium, projectID: nil, dueDate: nil)
        seededStore.flushPersistence()
        XCTAssertTrue(FileManager.default.fileExists(atPath: missingURL.path), "绑定路径的 store 修改后应落盘")

        // 路径二：文件存在但不可读（chmod 000）→ 安全内存 store，修改不落盘。
        let unreadableURL = dir.appendingPathComponent("board2.json")
        let validJSON = #"{"schemaVersion": 2, "projects": [], "columns": [{"id": "cccccccc-0000-0000-0000-00000000000e", "name": "A", "symbol": "circle", "colorName": "blue", "sortOrder": 0, "isDone": true}], "tasks": []}"#
        let originalData = Data(validJSON.utf8)
        try originalData.write(to: unreadableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadableURL.path) }

        let safeStore = BoardStore.load(persistenceURL: unreadableURL)
        XCTAssertTrue(safeStore.tasks.isEmpty, "读取失败的安全 store 不得以示例任务冒充")
        XCTAssertNotNil(safeStore.persistenceError, "仅内存模式必须明确暴露保存不可用状态")
        safeStore.addTask(title: "不应落盘", notes: "", columnID: DefaultColumns.todoID, priority: .medium, projectID: nil, dueDate: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadableURL.path)
        XCTAssertEqual(try Data(contentsOf: unreadableURL), originalData, "不可读原文件不得被覆盖")
    }

    /// v2 快照缺 projects/columns/tasks 任一必需键：必须抛错，不得降级空集合后覆盖原数据。
    func testV2SnapshotRequiresAllCollectionKeys() {
        let columns = "[{\"id\": \"cccccccc-0000-0000-0000-00000000000a\", \"name\": \"A\", \"symbol\": \"circle\", \"colorName\": \"blue\", \"sortOrder\": 0}]"
        let tasks = "[{\"id\": \"dddddddd-0000-0000-0000-00000000000b\", \"title\": \"T\", \"columnID\": \"cccccccc-0000-0000-0000-00000000000a\", \"sortOrder\": 0}]"

        XCTAssertThrowsError(
            try BoardStore.decodeSnapshot(Data("{\"schemaVersion\": 2, \"columns\": \(columns), \"tasks\": \(tasks)}".utf8)),
            "v2 缺 projects 必须抛错"
        )
        XCTAssertThrowsError(
            try BoardStore.decodeSnapshot(Data("{\"schemaVersion\": 2, \"projects\": [], \"tasks\": \(tasks)}".utf8)),
            "v2 缺 columns 必须抛错"
        )
        XCTAssertThrowsError(
            try BoardStore.decodeSnapshot(Data("{\"schemaVersion\": 2, \"projects\": [], \"columns\": \(columns)}".utf8)),
            "v2 缺 tasks 必须抛错"
        )
    }

    /// BoardTask 字段级严格解码：字段存在但类型/取值畸形必须抛错；
    /// 仅字段缺失（或可选字段合法 null）才使用旧版默认。
    func testTaskFieldMalformedValuesThrow() throws {
        let base = #"{"id": "aaaaaaaa-0000-0000-0000-0000000000aa", "title": "T""#

        // 每个可容忍默认字段的畸形取值：全部抛错。
        for malformed in [
            #", "notes": 42}"#,
            #", "columnID": 123}"#,
            #", "priority": "urgent"}"#,
            #", "projectID": "not-a-uuid"}"#,
            #", "dueDate": "yesterday"}"#,
            #", "tags": "not-an-array"}"#,
            #", "tags": [42]}"#,
            #", "sortOrder": "zero"}"#
        ] {
            XCTAssertThrowsError(
                try JSONDecoder().decode(BoardTask.self, from: Data((base + malformed).utf8)),
                "字段存在但畸形必须抛错：\(malformed)"
            )
        }

        // 缺字段 → 旧版默认；可选字段合法 null → nil。
        let minimal = try JSONDecoder().decode(
            BoardTask.self,
            from: Data(#"{"id": "aaaaaaaa-0000-0000-0000-0000000000ab", "title": "最小任务", "status": "todo"}"#.utf8)
        )
        XCTAssertEqual(minimal.notes, "")
        XCTAssertEqual(minimal.columnID, DefaultColumns.todoID)
        XCTAssertEqual(minimal.priority, .medium)
        XCTAssertNil(minimal.projectID)
        XCTAssertNil(minimal.dueDate)
        XCTAssertEqual(minimal.tags, [])
        XCTAssertEqual(minimal.sortOrder, 0)

        let nulls = try JSONDecoder().decode(
            BoardTask.self,
            from: Data(#"{"id": "aaaaaaaa-0000-0000-0000-0000000000ac", "title": "空值任务", "columnID": "eeeeeeee-0000-0000-0000-00000000000d", "projectID": null, "dueDate": null}"#.utf8)
        )
        XCTAssertNil(nulls.projectID)
        XCTAssertNil(nulls.dueDate)
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

    /// 备份写入失败（目录不可写）时必须走安全失败路径：返回不绑定原文件的内存 store，
    /// 后续修改绝不落盘覆盖原 board.json。覆盖畸形数据与 v1 迁移两条路径。
    func testBackupWriteFailureNeverOverwritesOriginalFile() throws {
        // 路径一：畸形数据 + 备份失败。
        let corruptDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let corruptURL = corruptDir.appendingPathComponent("board.json")
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        let corruptData = Data("{ broken json".utf8)
        try corruptData.write(to: corruptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: corruptDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: corruptDir.path)
            try? FileManager.default.removeItem(at: corruptDir)
        }

        let cleanStore = BoardStore.load(persistenceURL: corruptURL)
        XCTAssertTrue(cleanStore.tasks.isEmpty)
        XCTAssertNotNil(cleanStore.persistenceError, "备份失败后不得误报所有更改已保存")
        cleanStore.addTask(title: "不应落盘", notes: "", columnID: DefaultColumns.todoID, priority: .medium, projectID: nil, dueDate: nil)
        XCTAssertEqual(try Data(contentsOf: corruptURL), corruptData, "内存 store 的修改不得写回未备份的原文件")
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(at: corruptDir, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("board.json.") && $0.lastPathComponent.hasSuffix(".backup") }
                .isEmpty,
            "备份失败时不应留下任何备份文件"
        )

        // 路径二：合法 v1 数据 + 迁移备份失败：数据可用但仅存内存，原文件保持 v1 字节。
        let legacyDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyURL = legacyDir.appendingPathComponent("board.json")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyData = Data(
            #"{"projects": [], "tasks": [{"id": "aaaaaaaa-0000-0000-0000-0000000000ff", "title": "旧任务", "status": "todo", "sortOrder": 0}]}"#.utf8
        )
        try legacyData.write(to: legacyURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: legacyDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: legacyDir.path)
            try? FileManager.default.removeItem(at: legacyDir)
        }

        let memoryStore = BoardStore.load(persistenceURL: legacyURL)
        XCTAssertEqual(memoryStore.tasks.first?.title, "旧任务", "解码成功的数据应加载进内存 store")
        XCTAssertEqual(memoryStore.tasks.first?.columnID, DefaultColumns.todoID)
        XCTAssertNotNil(memoryStore.persistenceError, "迁移备份失败后不得误报所有更改已保存")
        memoryStore.addColumn(name: "也不应落盘", symbol: "circle", colorName: "blue")
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData, "备份失败的迁移不得让后续写入覆盖原 v1 文件")
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
        store.selectedTaskID = first.id

        XCTAssertTrue(store.deleteColumn(id: source.id, migratingTasksTo: target.id))
        XCTAssertNil(store.column(withID: source.id))
        XCTAssertNil(store.selectedTaskID, "被删列中的任务迁移后不得继续高亮目标列")
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

    /// Inspector 显式保存时，字段修改与跨列移动必须原子完成；目标列尾追加，
    /// 源列与目标列排序连续，不能留下重复 sortOrder。
    func testInspectorSaveAcrossColumnsPreservesOrderingAndDetails() {
        let sourceTask0 = BoardTask(title: "S0", columnID: DefaultColumns.todoID, sortOrder: 0)
        let sourceTask1 = BoardTask(title: "S1", columnID: DefaultColumns.todoID, sortOrder: 1)
        let targetTask = BoardTask(title: "T0", columnID: DefaultColumns.backlogID, sortOrder: 1)
        let moverID = sourceTask1.id
        let store = BoardStore(tasks: [sourceTask0, sourceTask1, targetTask])

        var draft = sourceTask1
        draft.title = "已更新"
        draft.notes = "显式保存"
        draft.columnID = DefaultColumns.backlogID
        store.saveTask(draft)

        XCTAssertEqual(store.tasks(in: DefaultColumns.backlogID).map(\.id), [targetTask.id, moverID], "改列后追加到目标列末尾")
        XCTAssertEqual(store.tasks(in: DefaultColumns.todoID).map(\.id), [sourceTask0.id])
        XCTAssertEqual(store.task(withID: moverID)?.title, "已更新")
        XCTAssertEqual(store.task(withID: moverID)?.notes, "显式保存")
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

    func testAddTaskRevalidatesColumnAndNormalizesMissingProject() throws {
        let store = BoardStore()

        XCTAssertNil(store.addTask(
            title: "失效列",
            notes: "",
            columnID: UUID(),
            priority: .medium,
            projectID: nil,
            dueDate: nil
        ))
        XCTAssertTrue(store.tasks.isEmpty, "列在表单提交前被删除时不得静默创建或关闭后丢失输入")

        let taskID = try XCTUnwrap(store.addTask(
            title: "项目已删除",
            notes: "",
            columnID: DefaultColumns.todoID,
            priority: .medium,
            projectID: UUID(),
            dueDate: nil
        ))
        XCTAssertNil(store.task(withID: taskID)?.projectID, "失效项目引用必须归一为未分类")
    }

    func testSnapshotDanglingProjectReferenceIsNormalizedToInbox() throws {
        let json = #"{"schemaVersion":2,"projects":[],"columns":[{"id":"5F1F9E4A-2E1B-4B6D-9A71-0C1D2E3F4002","name":"待办","symbol":"circle","colorName":"blue","sortOrder":0,"isDone":false}],"tasks":[{"id":"aaaaaaaa-0000-0000-0000-000000000011","title":"悬空项目","columnID":"5F1F9E4A-2E1B-4B6D-9A71-0C1D2E3F4002","projectID":"bbbbbbbb-0000-0000-0000-000000000011","sortOrder":0}]}"#

        let snapshot = try BoardStore.decodeSnapshot(Data(json.utf8))

        XCTAssertNil(snapshot.tasks.first?.projectID)
    }

    func testTaskQuerySearchesAllFieldsAndInvalidatesAfterUpdate() {
        let task = BoardTask(
            title: "标题",
            notes: "背景说明",
            columnID: DefaultColumns.todoID,
            tags: ["标签"]
        )
        let store = BoardStore(tasks: [task])

        XCTAssertEqual(store.tasks(in: DefaultColumns.todoID, matching: "背景").map(\.id), [task.id])
        XCTAssertEqual(store.tasks(in: DefaultColumns.todoID, matching: "标签").map(\.id), [task.id])

        var moved = task
        moved.title = "更新后的标题"
        moved.columnID = DefaultColumns.backlogID
        store.updateTask(moved)

        XCTAssertTrue(store.tasks(in: DefaultColumns.todoID).isEmpty)
        XCTAssertEqual(store.tasks(in: DefaultColumns.backlogID).map(\.title), ["更新后的标题"])
    }

    // MARK: - 异步持久化

    func testFlushPersistenceWritesLatestDebouncedSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("board.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let task = BoardTask(title: "初始标题", columnID: DefaultColumns.todoID)
        let store = BoardStore(tasks: [task], persistenceURL: fileURL)
        XCTAssertEqual(store.persistenceSuccessRevision, 0, "尚未写盘时不应显示保存成功反馈")
        var updated = task
        updated.title = "终止前的最新标题"
        store.updateTask(updated) // 高频编辑走延迟后台持久化。
        store.flushPersistence()

        let snapshot = try BoardStore.decodeSnapshot(Data(contentsOf: fileURL))
        XCTAssertEqual(snapshot.tasks.first?.title, "终止前的最新标题")
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(store.persistenceSuccessRevision, 1, "成功反馈只应由真实落盘完成触发")
    }

    func testDebouncedPersistenceEventuallyWritesLatestSnapshotWithoutFlush() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("board.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let task = BoardTask(title: "初始标题", columnID: DefaultColumns.todoID)
        let store = BoardStore(tasks: [task], persistenceURL: fileURL)
        var updated = task
        updated.title = "第一次输入"
        store.updateTask(updated)
        updated.title = "最终输入"
        store.updateTask(updated)

        XCTAssertTrue(store.isPersistencePending)
        let deadline = Date.now.addingTimeInterval(2)
        while store.isPersistencePending, Date.now < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(store.isPersistencePending, "延迟写入必须在合理时间内完成")
        XCTAssertNil(store.persistenceError)
        XCTAssertEqual(store.persistenceSuccessRevision, 1)
        let snapshot = try BoardStore.decodeSnapshot(Data(contentsOf: fileURL))
        XCTAssertEqual(snapshot.tasks.first?.title, "最终输入")
    }

    func testFlushPersistencePublishesWriteFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let nonDirectory = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: nonDirectory)
        let store = BoardStore(persistenceURL: nonDirectory.appendingPathComponent("board.json"))
        store.addTask(title: "不能写入", notes: "", columnID: DefaultColumns.todoID, priority: .medium, projectID: nil, dueDate: nil)
        store.flushPersistence()

        XCTAssertNotNil(store.persistenceError, "后台/flush 写盘失败必须保留可观察状态")
        XCTAssertEqual(store.persistenceSuccessRevision, 0, "写盘失败不得触发保存成功反馈")
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

    // MARK: - 新增列位置插入

    /// addColumn(before:) 指定位置插入：最前、某列之前、末尾；顺序持久化为连续 sortOrder。
    func testAddColumnInsertsAtRequestedPosition() throws {
        let store = BoardStore(columns: DefaultColumns.makeDefaults())

        // 最前（首列之前）。
        _ = try XCTUnwrap(
            store.addColumn(name: "最前", symbol: "bolt", colorName: "teal", before: DefaultColumns.backlogID)
        )
        XCTAssertEqual(
            store.orderedColumns.map(\.name),
            ["最前", "Backlog", "待办", "进行中", "已完成"]
        )

        // 指定列之后 = 下一列之前（“待办”之后 = “进行中”之前）。
        _ = try XCTUnwrap(
            store.addColumn(name: "中间", symbol: "clock", colorName: "amber", before: DefaultColumns.inProgressID)
        )
        XCTAssertEqual(
            store.orderedColumns.map(\.name),
            ["最前", "Backlog", "待办", "中间", "进行中", "已完成"]
        )

        // 末尾（before 为 nil）。
        _ = try XCTUnwrap(store.addColumn(name: "末尾", symbol: "tray", colorName: "coral", before: nil))
        XCTAssertEqual(
            store.orderedColumns.map(\.name).last, "末尾"
        )

        // 插入后 sortOrder 连续且与展示顺序一致（持久化结构稳定）。
        XCTAssertEqual(store.orderedColumns.map(\.sortOrder), Array(0..<store.orderedColumns.count))

        // 未知目标列：安全回退为追加末尾，不抛错。
        let fallbackID = try XCTUnwrap(store.addColumn(name: "兜底", symbol: "circle", colorName: "blue", before: UUID()))
        XCTAssertEqual(store.orderedColumns.last?.id, fallbackID)
    }

    /// 新增列默认位置：首个完成列之前；无完成列时追加末尾（NewColumnSheet 的默认值依据）。
    func testAddColumnDefaultPlacementBeforeFirstDoneColumn() throws {
        let store = BoardStore(columns: DefaultColumns.makeDefaults())

        // 默认（首完成列之前）：与 NewColumnSheet.defaultPlacement 一致地计算 before。
        let defaultBefore = store.firstDoneColumn?.id
        XCTAssertEqual(defaultBefore, DefaultColumns.doneID, "默认目标是首个完成列")
        _ = try XCTUnwrap(store.addColumn(name: "测试中", symbol: "testtube.2", colorName: "teal", before: defaultBefore))
        XCTAssertEqual(
            store.orderedColumns.map(\.name),
            ["Backlog", "待办", "进行中", "测试中", "已完成"],
            "默认插在首个完成列之前"
        )

        // 无完成列：firstDoneColumn 为 nil → before nil → 追加末尾。
        let a = BoardColumn(name: "A", symbol: "circle", colorName: "blue", sortOrder: 0)
        let b = BoardColumn(name: "B", symbol: "clock", colorName: "amber", sortOrder: 1)
        let noDoneStore = BoardStore(columns: [a, b])
        XCTAssertNil(noDoneStore.firstDoneColumn)
        let appendedID = try XCTUnwrap(
            noDoneStore.addColumn(name: "末尾列", symbol: "bolt", colorName: "teal", before: noDoneStore.firstDoneColumn?.id)
        )
        XCTAssertEqual(noDoneStore.orderedColumns.last?.id, appendedID, "无完成列时默认追加到末尾")
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
        self.min { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
        }
    }
}
