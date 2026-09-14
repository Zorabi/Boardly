import Foundation

enum TaskStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case backlog
    case todo
    case inProgress
    case done

    var id: Self { self }

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "待办"
        case .inProgress: "进行中"
        case .done: "已完成"
        }
    }

    var systemImage: String {
        switch self {
        case .backlog: "tray"
        case .todo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
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

struct BoardTask: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var status: TaskStatus
    var priority: TaskPriority
    var projectID: UUID?
    var dueDate: Date?
    var tags: [String]
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        projectID: UUID? = nil,
        dueDate: Date? = nil,
        tags: [String] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.projectID = projectID
        self.dueDate = dueDate
        self.tags = tags
        self.sortOrder = sortOrder
    }
}

enum SidebarScope: Hashable, Sendable {
    case inbox
    case today
    case all
    case project(UUID)

    var title: String {
        switch self {
        case .inbox: "收件箱"
        case .today: "今天"
        case .all: "所有任务"
        case .project: "项目"
        }
    }
}
