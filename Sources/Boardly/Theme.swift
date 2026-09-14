import SwiftUI

enum BoardlyTheme {
    static let accent = Color(red: 117 / 255, green: 103 / 255, blue: 248 / 255)
    static let canvas = Color(red: 17 / 255, green: 17 / 255, blue: 20 / 255)
    static let sidebar = Color(red: 23 / 255, green: 23 / 255, blue: 27 / 255)
    static let column = Color(red: 15 / 255, green: 15 / 255, blue: 18 / 255)
    static let card = Color(red: 31 / 255, green: 31 / 255, blue: 36 / 255)
    static let cardHover = Color(red: 39 / 255, green: 39 / 255, blue: 45 / 255)
    static let selectedCard = accent.opacity(0.11)
    static let border = Color.white.opacity(0.08)
    static let selectedBorder = accent.opacity(0.9)

    static func projectColor(named name: String) -> Color {
        switch name {
        case "blue": .blue
        case "purple": .purple
        case "green": .green
        case "orange": .orange
        default: accent
        }
    }

    static func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .backlog: .secondary
        case .todo: .orange
        case .inProgress: .blue
        case .done: .green
        }
    }
}
