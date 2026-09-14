import SwiftUI
import UniformTypeIdentifiers

// MARK: - 设计令牌

enum BoardlyTheme {
    /// 应用内拖放任务卡片使用的唯一传输类型；onDrag 与 onDrop 必须同时使用它。
    /// 使用 exportedAs（非可选、自带声明），避免 UTType(_:) 在无类型声明的
    /// SwiftPM 可执行环境中返回 nil 导致启动崩溃。
    static let taskDragType = UTType(exportedAs: "com.boardly.task")

    static let accent = Color(red: 117 / 255, green: 103 / 255, blue: 248 / 255)
    static let accentPressed = Color(red: 104 / 255, green: 91 / 255, blue: 226 / 255)
    static let canvas = Color(red: 17 / 255, green: 17 / 255, blue: 20 / 255)
    static let sidebar = Color(red: 23 / 255, green: 23 / 255, blue: 27 / 255)
    static let column = Color(red: 21 / 255, green: 21 / 255, blue: 25 / 255)
    static let card = Color(red: 32 / 255, green: 32 / 255, blue: 37 / 255)
    static let cardHover = Color(red: 39 / 255, green: 39 / 255, blue: 45 / 255)
    static let field = Color(red: 27 / 255, green: 27 / 255, blue: 32 / 255)
    static let section = Color(red: 26 / 255, green: 26 / 255, blue: 31 / 255)
    static let selectedCard = accent.opacity(0.11)
    static let border = Color.white.opacity(0.08)
    static let strongBorder = Color.white.opacity(0.13)
    static let selectedBorder = accent
    static let danger = Color(red: 255 / 255, green: 102 / 255, blue: 95 / 255)

    static let cornerRadiusCard: CGFloat = 9
    static let cornerRadiusField: CGFloat = 8
    static let cornerRadiusSection: CGFloat = 12
    static let cornerRadiusColumn: CGFloat = 12

    // MARK: 项目颜色

    struct ProjectColorOption: Identifiable {
        let name: String
        let title: String
        let color: Color
        var id: String { name }
    }

    static let projectColorOptions: [ProjectColorOption] = [
        ProjectColorOption(name: "violet", title: "紫罗兰", color: Color(red: 117 / 255, green: 103 / 255, blue: 248 / 255)),
        ProjectColorOption(name: "blue", title: "蓝", color: Color(red: 96 / 255, green: 138 / 255, blue: 214 / 255)),
        ProjectColorOption(name: "teal", title: "青", color: Color(red: 79 / 255, green: 179 / 255, blue: 169 / 255)),
        ProjectColorOption(name: "green", title: "绿", color: Color(red: 98 / 255, green: 179 / 255, blue: 118 / 255)),
        ProjectColorOption(name: "amber", title: "琥珀", color: Color(red: 214 / 255, green: 163 / 255, blue: 85 / 255)),
        ProjectColorOption(name: "coral", title: "珊瑚", color: Color(red: 224 / 255, green: 120 / 255, blue: 86 / 255)),
        ProjectColorOption(name: "pink", title: "粉", color: Color(red: 214 / 255, green: 120 / 255, blue: 168 / 255)),
        ProjectColorOption(name: "purple", title: "深紫", color: Color(red: 155 / 255, green: 127 / 255, blue: 212 / 255))
    ]

    static let projectSymbolOptions = [
        "folder", "sparkles", "house", "book.closed", "briefcase",
        "flag", "heart", "graduationcap", "airplane", "cart", "wrench", "moon"
    ]

    static func projectColor(named name: String) -> Color {
        projectColorOptions.first(where: { $0.name == name })?.color ?? accent
    }

    static func projectColorTitle(named name: String) -> String {
        projectColorOptions.first(where: { $0.name == name })?.title ?? "紫罗兰"
    }

    // MARK: 状态颜色（状态永远同时有图标，不单靠颜色区分）

    static func statusColor(_ status: TaskStatus) -> Color {
        switch status {
        case .backlog: Color(white: 0.62)
        case .todo: Color(red: 96 / 255, green: 138 / 255, blue: 214 / 255)
        case .inProgress: Color(red: 214 / 255, green: 163 / 255, blue: 85 / 255)
        case .done: Color(red: 98 / 255, green: 179 / 255, blue: 118 / 255)
        }
    }
}

// MARK: - 按钮样式

/// 主操作按钮：强调色填充，每个界面只保留一个。
struct BoardlyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled ? BoardlyTheme.accent : BoardlyTheme.accent.opacity(0.35))
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// 次要按钮：低调表面 + 细边框。
struct BoardlySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isEnabled ? BoardlyTheme.border : BoardlyTheme.border.opacity(0.5))
            }
    }
}

/// 紧凑图标按钮：列头与卡片内部的小型操作入口。
struct BoardlyIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Color.secondary : Color(white: 0.35))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// 破坏性操作按钮：仅用于删除等不可恢复入口。
struct BoardlyDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .foregroundStyle(isEnabled ? BoardlyTheme.danger : BoardlyTheme.danger.opacity(0.4))
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BoardlyTheme.danger.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(BoardlyTheme.danger.opacity(isEnabled ? 0.35 : 0.15))
            }
    }
}

// MARK: - 表单组件

/// 表单分区：标题 + 深色圆角表面，替代系统 Form 的统一外观。
struct BoardlyFormSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusSection, style: .continuous)
                    .fill(BoardlyTheme.section)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusSection, style: .continuous)
                    .strokeBorder(BoardlyTheme.border)
            }
        }
    }
}

/// 表单行：左侧字段名 + 右侧控件，保证所有表单的标签对齐一致。
struct BoardlyFormRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 文本输入框统一样式：深色表面 + 细边框。
struct BoardlyTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous)
                    .fill(BoardlyTheme.field)
            )
            .overlay {
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous)
                    .strokeBorder(BoardlyTheme.border)
            }
    }
}

/// 多行文本编辑器：与 BoardlyTextFieldStyle 相同的表面。
struct BoardlyTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 110
    var prompt: String?

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous)
                    .fill(BoardlyTheme.field)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty, let prompt {
                    Text(prompt)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous)
                    .strokeBorder(BoardlyTheme.border)
            }
            .accessibilityLabel(prompt.map { "\($0)输入框" } ?? "多行文本输入框")
    }
}

/// Sheet 弹窗的统一标题栏。
struct BoardlySheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}
