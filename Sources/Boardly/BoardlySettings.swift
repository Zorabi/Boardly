import Combine
import Foundation
import SwiftUI

/// 看板显示与备份策略：只保存设备级偏好，不写入 board.json，避免把显示习惯
/// 和保留周期混入任务数据。设置通过 UserDefaults 持久化，修改后立即反映到当前窗口。
@MainActor
final class BoardlySettings: ObservableObject {
    private static let minimumFontScale = 0.85
    private static let maximumFontScale = 1.35

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

    enum BackupDailyRetention: Int, CaseIterable, Identifiable, Sendable {
        case oneWeek = 7
        case oneMonth = 30
        case threeMonths = 90
        case oneYear = 365

        var id: Self { self }

        var title: String {
            switch self {
            case .oneWeek: "7 天"
            case .oneMonth: "30 天"
            case .threeMonths: "90 天"
            case .oneYear: "1 年"
            }
        }
    }

    enum BackupMonthlyRetention: Int, CaseIterable, Identifiable, Sendable {
        case none = 0
        case threeMonths = 3
        case oneYear = 12
        case twoYears = 24

        var id: Self { self }

        var title: String {
            switch self {
            case .none: "不保留"
            case .threeMonths: "3 个月"
            case .oneYear: "12 个月"
            case .twoYears: "24 个月"
            }
        }
    }

    private enum Key {
        static let fontScale = "boardly.settings.fontScale"
        static let showTaskNotes = "boardly.settings.showTaskNotes"
        static let showTaskMetadata = "boardly.settings.showTaskMetadata"
        static let cardDensity = "boardly.settings.cardDensity"
        static let periodicSnapshotsEnabled = "boardly.settings.periodicSnapshotsEnabled"
        static let backupDailyRetention = "boardly.settings.backupDailyRetention"
        static let backupMonthlyRetention = "boardly.settings.backupMonthlyRetention"
    }

    private let defaults: UserDefaults

    @Published var fontScale: Double {
        didSet {
            let bounded = min(max(fontScale, Self.minimumFontScale), Self.maximumFontScale)
            if bounded != fontScale {
                fontScale = bounded
                return
            }
            defaults.set(fontScale, forKey: Key.fontScale)
        }
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

    /// 控制普通保存时的每日快照；删除前安全快照不受此项影响。
    @Published var periodicSnapshotsEnabled: Bool {
        didSet { defaults.set(periodicSnapshotsEnabled, forKey: Key.periodicSnapshotsEnabled) }
    }

    @Published var backupDailyRetention: BackupDailyRetention {
        didSet { defaults.set(backupDailyRetention.rawValue, forKey: Key.backupDailyRetention) }
    }

    @Published var backupMonthlyRetention: BackupMonthlyRetention {
        didSet { defaults.set(backupMonthlyRetention.rawValue, forKey: Key.backupMonthlyRetention) }
    }

    /// 只补充新域中缺失的应用设置，保留旧域和用户已有的新设置。
    static func migrateLegacyPreferences(
        to defaults: UserDefaults,
        legacyPreferences: [String: Any]
    ) {
        for (key, value) in legacyPreferences
        where key.hasPrefix("boardly.settings.") && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    init(defaults: UserDefaults = .standard) {
        if defaults === UserDefaults.standard, Bundle.main.bundleIdentifier == "dongx.boardly" {
            Self.migrateLegacyPreferences(
                to: defaults,
                legacyPreferences: defaults.persistentDomain(forName: "dev.boardly.app") ?? [:]
            )
        }
        self.defaults = defaults

        let savedScale = defaults.object(forKey: Key.fontScale) as? Double ?? FontSizePreset.standard.scale
        self.fontScale = min(max(savedScale, Self.minimumFontScale), Self.maximumFontScale)
        self.showTaskNotes = defaults.object(forKey: Key.showTaskNotes) as? Bool ?? true
        self.showTaskMetadata = defaults.object(forKey: Key.showTaskMetadata) as? Bool ?? true
        self.cardDensity = CardDensity(
            rawValue: defaults.string(forKey: Key.cardDensity) ?? ""
        ) ?? .standard
        self.periodicSnapshotsEnabled = defaults.object(forKey: Key.periodicSnapshotsEnabled) as? Bool ?? true
        self.backupDailyRetention = BackupDailyRetention(
            rawValue: defaults.object(forKey: Key.backupDailyRetention) as? Int ?? BackupConfiguration.defaultDailyRetentionDays
        ) ?? .oneMonth
        self.backupMonthlyRetention = BackupMonthlyRetention(
            rawValue: defaults.object(forKey: Key.backupMonthlyRetention) as? Int ?? BackupConfiguration.defaultMonthlyRetentionMonths
        ) ?? .oneYear
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

    var backupConfiguration: BackupConfiguration {
        BackupConfiguration(
            isPeriodicSnapshotsEnabled: periodicSnapshotsEnabled,
            dailyRetentionDays: backupDailyRetention.rawValue,
            monthlyRetentionMonths: backupMonthlyRetention.rawValue
        )
    }

    func resetToDefaults() {
        fontScale = FontSizePreset.standard.scale
        showTaskNotes = true
        showTaskMetadata = true
        cardDensity = .standard
        periodicSnapshotsEnabled = true
        backupDailyRetention = .oneMonth
        backupMonthlyRetention = .oneYear
    }
}
