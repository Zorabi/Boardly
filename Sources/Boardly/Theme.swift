import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 设计令牌

enum BoardlyTheme {
    static let boardCoordinateSpace = "BoardlyBoardCoordinateSpace"
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
    /// 标题栏/工具栏语义表面：介于侧栏与字段之间，与深色色板同族。
    static let toolbar = Color(red: 24 / 255, green: 24 / 255, blue: 29 / 255)
    static let selectedCard = accent.opacity(0.11)
    static let border = Color.white.opacity(0.08)
    static let strongBorder = Color.white.opacity(0.13)
    static let selectedBorder = accent
    static let danger = Color(red: 255 / 255, green: 102 / 255, blue: 95 / 255)

    // 优先级令牌：高优先级使用珊瑚红表达紧迫，中优先级使用琥珀色，
    // 低优先级退回安静的石墨灰，避免与品牌紫和项目蓝混淆。
    static let priorityHigh = danger
    static let priorityMedium = Color(red: 214 / 255, green: 163 / 255, blue: 85 / 255)
    static let priorityLow = Color(white: 0.62)

    static let cornerRadiusCard: CGFloat = 9
    static let cornerRadiusField: CGFloat = 8
    static let cornerRadiusSection: CGFloat = 12
    static let cornerRadiusColumn: CGFloat = 12

#if canImport(AppKit)
    /// 标题栏/工具栏的 AppKit 对应令牌：用于窗口级 chrome（titlebar 透明 +
    /// 窗口背景），确保 SwiftUI 工具栏与窗口标题栏颜色一致。
    static let toolbarNSColor = NSColor(red: 24 / 255, green: 24 / 255, blue: 29 / 255, alpha: 1)
#endif

    // MARK: 项目颜色

    struct ProjectColorOption: Identifiable {
        let name: String
        let title: String
        let color: Color
        var id: String { name }
    }

    static let projectColorOptions: [ProjectColorOption] = [
        ProjectColorOption(name: "graphite", title: "石墨", color: Color(white: 0.62)),
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

    /// 自定义列可用的 SF Symbol 候选。
    static let columnSymbolOptions = [
        "square.grid.2x2", "tray", "circle", "clock", "checkmark.circle.fill",
        "wrench.and.screwdriver", "testtube.2", "eyeglasses", "shippingbox",
        "questionmark.circle", "bolt", "flag"
    ]

    static func projectColor(named name: String) -> Color {
        projectColorOptions.first(where: { $0.name == name })?.color ?? accent
    }

    static func projectColorTitle(named name: String) -> String {
        projectColorOptions.first(where: { $0.name == name })?.title ?? "紫罗兰"
    }

    static func priorityColor(for priority: TaskPriority) -> Color {
        switch priority {
        case .low: priorityLow
        case .medium: priorityMedium
        case .high: priorityHigh
        }
    }
}

// MARK: - 字体缩放

/// 字体设置使用连续比例，而不是只在几个 Dynamic Type 档位之间跳转。
/// 控件仍保留系统 Dynamic Type 环境，正文则通过这个令牌获得真实的字号变化。
private struct BoardlyFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var boardlyFontScale: CGFloat {
        get { self[BoardlyFontScaleKey.self] }
        set { self[BoardlyFontScaleKey.self] = newValue }
    }
}

enum BoardlyTextStyle {
    case caption
    case subheadline
    case body
    case headline
    case title3

    var baseSize: CGFloat {
        switch self {
        case .caption: 12
        case .subheadline: 13
        case .body: 14
        case .headline: 17
        case .title3: 20
        }
    }
}

private struct BoardlyFontModifier: ViewModifier {
    @Environment(\.boardlyFontScale) private var scale
    let style: BoardlyTextStyle
    let weight: Font.Weight
    let monospacedDigits: Bool

    func body(content: Content) -> some View {
        var font = Font.system(size: style.baseSize * scale, weight: weight)
        if monospacedDigits {
            font = font.monospacedDigit()
        }
        return content.font(font)
    }
}

private struct BoardlySystemFontModifier: ViewModifier {
    @Environment(\.boardlyFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}

extension View {
    func boardlyFont(
        _ style: BoardlyTextStyle,
        weight: Font.Weight = .regular,
        monospacedDigits: Bool = false
    ) -> some View {
        modifier(
            BoardlyFontModifier(
                style: style,
                weight: weight,
                monospacedDigits: monospacedDigits
            )
        )
    }

    func boardlySystemFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(BoardlySystemFontModifier(size: size, weight: weight))
    }
}

// MARK: - 按钮样式

/// 主操作按钮：强调色填充，每个界面只保留一个。
struct BoardlyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .boardlyFont(.subheadline, weight: .medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled ? BoardlyTheme.accent : BoardlyTheme.accent.opacity(0.35))
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .focusEffectDisabled()
    }
}

/// 次要按钮：低调表面 + 细边框。
struct BoardlySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .boardlyFont(.subheadline, weight: .medium)
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
            .focusEffectDisabled()
    }
}

/// 紧凑图标按钮：列头与卡片内部的小型操作入口。
struct BoardlyIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var size: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .boardlySystemFont(size: 12, weight: .medium)
            .foregroundStyle(isEnabled ? Color.secondary : Color(white: 0.35))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .focusEffectDisabled()
    }
}

/// 破坏性操作按钮：仅用于删除等不可恢复入口。
struct BoardlyDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .boardlyFont(.subheadline, weight: .medium)
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
            .focusEffectDisabled()
    }
}

/// 无系统焦点外框的轻量按钮：保留键盘焦点语义，但避免点击后留下高亮边框。
/// 适用于颜色色板、侧栏次要入口和看板空状态等自定义命中区域。
struct BoardlyPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .focusEffectDisabled()
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
                .boardlyFont(.caption, weight: .semibold)
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
    let alignment: VerticalAlignment
    let labelTopPadding: CGFloat
    let control: Control

    init(
        label: String,
        alignment: VerticalAlignment = .firstTextBaseline,
        labelTopPadding: CGFloat = 0,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.alignment = alignment
        self.labelTopPadding = labelTopPadding
        self.control = control()
    }

    var body: some View {
        HStack(alignment: alignment) {
            Text(label)
                .boardlyFont(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
                .padding(.top, labelTopPadding)
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
    var height: CGFloat = 110
    var prompt: String?

    var body: some View {
        TextEditor(text: $text)
            .boardlyFont(.body)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.automatic)
            .frame(height: height)
            .boardlyScrollers()
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: BoardlyTheme.cornerRadiusField, style: .continuous)
                    .fill(BoardlyTheme.field)
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty, let prompt {
                    Text(prompt)
                        .boardlyFont(.body)
                        .foregroundStyle(.tertiary)
                        // 匹配 TextEditor 的外边距与 NSTextView 文本容器内边距，
                        // 让占位文字和实际输入使用同一基线。
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
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
                .boardlyFont(.title3, weight: .semibold)
            Text(subtitle)
                .boardlyFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }
}

// MARK: - 统一滚动条主题

private final class BoardlyScroller: NSScroller {
    private let trackColor = NSColor(calibratedWhite: 1, alpha: 0.06)
    private let knobColor = NSColor(calibratedRed: 117 / 255, green: 103 / 255, blue: 248 / 255, alpha: 0.82)

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        guard scrollerStyle == .legacy else { return }
        trackColor.setFill()
        NSBezierPath(roundedRect: slotRect.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4).fill()
    }

    override func drawKnob() {
        guard isEnabled else { return }
        let knobRect = rect(for: .knob).insetBy(dx: 2, dy: 2)
        guard !knobRect.isEmpty else { return }
        knobColor.setFill()
        NSBezierPath(roundedRect: knobRect, xRadius: 4, yRadius: 4).fill()
    }
}

/// 全应用滚动容器主题：定位最近的宿主 NSScrollView 及其嵌套容器，
/// 把普通横/纵 scroller 切到 overlay 样式并使用主题色。
/// TextEditor 同样使用主题滑块，但保留 AppKit 的自动隐藏行为，
/// 避免无溢出时出现禁用的满高滑块。
private struct BoardlyScrollerThemer: NSViewRepresentable {
    final class Coordinator {
        var didTheme = false
        var isSchedulingAttempt = false
        var attemptCount = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Inspector 的 ScrollView 可能在 representable 创建后才挂入窗口，
        // 因此在短时间内重试几次，确保不会错过宿主 NSScrollView。
        scheduleTheme(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // updateNSView 会随 SwiftUI 重绘调用；未找到宿主时复用同一组有限重试，
        // 找到后不再参与滚动或输入期间的更新。
        scheduleTheme(for: nsView, coordinator: context.coordinator)
    }

    private func scheduleTheme(for view: NSView, coordinator: Coordinator) {
        guard !coordinator.didTheme, !coordinator.isSchedulingAttempt else { return }

        coordinator.isSchedulingAttempt = true
        let attempt = coordinator.attemptCount + 1
        coordinator.attemptCount = attempt

        // 0.02 秒足以跨过 SwiftUI/AppKit 的挂载边界；最多等待约 0.25 秒，
        // 避免无宿主时产生永久定时任务。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak view, weak coordinator] in
            guard let view, let coordinator else { return }
            coordinator.isSchedulingAttempt = false
            guard !coordinator.didTheme else { return }

            if let scrollView = Self.enclosingScrollViewOf(view) {
                Self.theme(scrollViewAndDescendantsOf: scrollView)
                coordinator.didTheme = true

                // SwiftUI 可能在第一次布局后替换原生 scroller；再校验一次，
                // 仍只发生在挂载阶段，不影响正常滚动性能。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak view] in
                    guard let view else { return }
                    guard let scrollView = Self.enclosingScrollViewOf(view) else { return }
                    Self.theme(scrollViewAndDescendantsOf: scrollView)
                }
            } else if attempt < 12 {
                self.scheduleTheme(for: view, coordinator: coordinator)
            }
        }
    }

    private static func theme(scrollViewAndDescendantsOf scrollView: NSScrollView) {
        let scrollViews = [scrollView] + descendantScrollViews(of: scrollView)
        for scrollView in scrollViews {
            theme(scrollView: scrollView)
        }
    }

    private static func theme(scrollView: NSScrollView) {
        let isTextEditor = scrollView.documentView is NSTextView
        if isTextEditor {
            scrollView.autohidesScrollers = true
        }

        // 统一使用不占内容空间的 overlay；TextEditor 在自身挂载主题器，
        // 避免依赖父级扫描导致系统灰色滑块漏网。
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        let darkAppearance = NSAppearance(named: .vibrantDark)

        if scrollView.hasVerticalScroller, !(scrollView.verticalScroller is BoardlyScroller) {
            let scroller = BoardlyScroller(frame: scrollView.verticalScroller?.frame ?? .zero)
            scroller.appearance = darkAppearance
            scrollView.verticalScroller = scroller
        }
        if scrollView.hasHorizontalScroller, !(scrollView.horizontalScroller is BoardlyScroller) {
            let scroller = BoardlyScroller(frame: scrollView.horizontalScroller?.frame ?? .zero)
            scroller.appearance = darkAppearance
            scrollView.horizontalScroller = scroller
        }
    }

    private static func descendantScrollViews(of view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { child in
            var matches: [NSScrollView] = []
            if let scrollView = child as? NSScrollView {
                matches.append(scrollView)
            }
            matches.append(contentsOf: descendantScrollViews(of: child))
            return matches
        }
    }

    private static func enclosingScrollViewOf(_ view: NSView) -> NSScrollView? {
        var current: NSView? = view.superview
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }
            current = candidate.superview
        }
        return nil
    }
}

extension View {
    /// 统一 Boardly 深色主题滚动条（overlay 样式 + accent 滑块着色）。
    /// 应用于 ScrollView/Form 内容的 background，不影响布局与命中测试。
    func boardlyScrollers() -> some View {
        background(BoardlyScrollerThemer())
    }
}
