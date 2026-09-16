import Foundation

/// 旧版固定状态的遗留枚举：仅用于解码历史 board.json（status 字段），
/// 新代码一律使用 BoardColumn / columnID。
enum TaskStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case backlog
    case todo
    case inProgress
    case done

    var id: Self { self }
}

/// 看板列：用户可新增、重命名、排序、删除；标识为稳定 UUID。
struct BoardColumn: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String
    var colorName: String
    var sortOrder: Int
    /// 完成语义列（默认“已完成”列为 true）：侧栏计数、卡片置灰等以此判断。
    var isDone: Bool

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        colorName: String,
        sortOrder: Int,
        isDone: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.isDone = isDone
    }
}

/// 默认四列使用固定 UUID，保证旧快照（按 status 存储）迁移与
/// 跨设备写入都能映射到同一批列，不产生漂移。
enum DefaultColumns {
    static let backlogID = UUID(uuidString: "5F1F9E4A-2E1B-4B6D-9A71-0C1D2E3F4001")!
    static let todoID = UUID(uuidString: "5F1F9E4A-2E1B-4B6D-9A71-0C1D2E3F4002")!
    static let inProgressID = UUID(uuidString: "5F1F9E4A-2E1B-4B6D-9A71-0C1D2E3F4003")!
    static let doneID = UUID(uuidString: "5F1F9E4A-2E1B-4B6D-9A71-0C1D2E3F4004")!

    static func makeDefaults() -> [BoardColumn] {
        [
            BoardColumn(id: backlogID, name: "Backlog", symbol: "tray", colorName: "graphite", sortOrder: 0),
            BoardColumn(id: todoID, name: "待办", symbol: "circle", colorName: "blue", sortOrder: 1),
            BoardColumn(id: inProgressID, name: "进行中", symbol: "clock", colorName: "amber", sortOrder: 2),
            BoardColumn(id: doneID, name: "已完成", symbol: "checkmark.circle.fill", colorName: "green", sortOrder: 3, isDone: true)
        ]
    }

    /// 旧 status → 默认列 ID 的确定性映射（迁移用）。
    static func columnID(for status: TaskStatus) -> UUID {
        switch status {
        case .backlog: backlogID
        case .todo: todoID
        case .inProgress: inProgressID
        case .done: doneID
        }
    }
}

enum TaskPriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: Self { self }

    var title: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    var systemImage: String {
        switch self {
        case .low: "arrow.down"
        case .medium: "minus"
        case .high: "arrow.up"
        }
    }
}

struct Project: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String
    var colorName: String

    init(id: UUID = UUID(), name: String, symbol: String, colorName: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
    }
}

/// 任务引用稳定列 ID（BoardColumn.id）。自定义 Codable 兼容旧快照：
/// 缺少 columnID 时读取旧 status 字段并映射到默认列，保证既有任务不丢失。
struct BoardTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var columnID: UUID
    var priority: TaskPriority
    var projectID: UUID?
    var dueDate: Date?
    var tags: [String]
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        columnID: UUID,
        priority: TaskPriority = .medium,
        projectID: UUID? = nil,
        dueDate: Date? = nil,
        tags: [String] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.columnID = columnID
        self.priority = priority
        self.projectID = projectID
        self.dueDate = dueDate
        self.tags = tags
        self.sortOrder = sortOrder
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, columnID, priority, projectID, dueDate, tags, sortOrder
        /// 旧版字段名，仅用于解码历史数据。
        case legacyStatus = "status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        if let decoded = try? container.decode(UUID.self, forKey: .columnID) {
            columnID = decoded
        } else if let legacy = try? container.decode(TaskStatus.self, forKey: .legacyStatus) {
            columnID = DefaultColumns.columnID(for: legacy)
        } else {
            columnID = DefaultColumns.todoID
        }
        priority = (try? container.decode(TaskPriority.self, forKey: .priority)) ?? .medium
        projectID = try? container.decode(UUID.self, forKey: .projectID)
        dueDate = try? container.decode(Date.self, forKey: .dueDate)
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        sortOrder = (try? container.decode(Int.self, forKey: .sortOrder)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(columnID, forKey: .columnID)
        try container.encode(priority, forKey: .priority)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(tags, forKey: .tags)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

enum SidebarScope: Hashable, Sendable {
    case inbox
    case today
    case all
    case project(UUID)

    var title: String {
        switch self {
        case .inbox: "未分类"
        case .today: "今天"
        case .all: "所有任务"
        case .project: "项目"
        }
    }
}
