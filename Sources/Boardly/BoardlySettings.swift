import Combine
import Foundation
import SwiftUI

/// 看板显示设置：只保存 UI 偏好，不写入 board.json，避免把设备显示习惯
/// 与任务数据混在一起。设置通过 UserDefaults 持久化，修改后立即反映到当前窗口。
@MainActor
final class BoardlySettings: ObservableObject {
    enum FontSizePreset: String, CaseIterable, Identifiable, Sendable {
        case small
        case standard
        case large
        case extraLarge

        var id: Self { self }

        var title: String {
            switch self {
            case .small: "小"
            case .standard: "标准"
            case .large: "大"
            case .extraLarge: "特大"
            }
        }

        var scale: Double {
            switch self {
            case .small: 0.9
            case .standard: 1.0
            case .large: 1.15
            case .extraLarge: 1.3
            }
        }
    }

    enum CardDensity: String, CaseIterable, Identifiable, Sendable {
        case compact
        case standard
        case spacious

        var id: Self { self }

        var title: String {
            switch self {
            case .compact: "紧凑"
            case .standard: "标准"
            case .spacious: "宽松"
            }
        }

        var taskSpacing: CGFloat {
            switch self {
            case .compact: 5
            case .standard: 8
            case .spacious: 12
            }
        }

        var cardContentSpacing: CGFloat {
            switch self {
            case .compact: 6
            case .standard: 8
            case .spacious: 10
            }
        }

        var cardPadding: CGFloat {
            switch self {
            case .compact: 10
            case .standard: 12
            case .spacious: 14
            }
        }
    }

    private enum Key {
        static let fontScale = "boardly.settings.fontScale"
        static let showTaskNotes = "boardly.settings.showTaskNotes"
        static let showTaskMetadata = "boardly.settings.showTaskMetadata"
        static let cardDensity = "boardly.settings.cardDensity"
    }

    private let defaults: UserDefaults

    @Published var fontScale: Double {
        didSet { defaults.set(fontScale, forKey: Key.fontScale) }
    }

    @Published var showTaskNotes: Bool {
        didSet { defaults.set(showTaskNotes, forKey: Key.showTaskNotes) }
    }

    @Published var showTaskMetadata: Bool {
        didSet { defaults.set(showTaskMetadata, forKey: Key.showTaskMetadata) }
    }

    @Published var cardDensity: CardDensity {
        didSet { defaults.set(cardDensity.rawValue, forKey: Key.cardDensity) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedScale = defaults.object(forKey: Key.fontScale) as? Double ?? FontSizePreset.standard.scale
        self.fontScale = min(max(savedScale, 0.85), 1.35)
        self.showTaskNotes = defaults.object(forKey: Key.showTaskNotes) as? Bool ?? true
        self.showTaskMetadata = defaults.object(forKey: Key.showTaskMetadata) as? Bool ?? true
        self.cardDensity = CardDensity(
            rawValue: defaults.string(forKey: Key.cardDensity) ?? ""
        ) ?? .standard
    }

    var fontSizePreset: FontSizePreset {
        get {
            FontSizePreset.allCases.min {
                abs($0.scale - fontScale) < abs($1.scale - fontScale)
            } ?? .standard
        }
        set { fontScale = newValue.scale }
    }

    /// 将自定义比例映射到 SwiftUI 的动态字体档位，使系统控件和自定义文本
    /// 一起放大，而不是只放大任务卡片标题。
    var dynamicTypeSize: DynamicTypeSize {
        switch fontScale {
        case ..<0.95: .small
        case ..<1.08: .large
        case ..<1.2: .xLarge
        default: .xxLarge
        }
    }

    func resetToDefaults() {
        fontScale = FontSizePreset.standard.scale
        showTaskNotes = true
        showTaskMetadata = true
        cardDensity = .standard
    }
}
