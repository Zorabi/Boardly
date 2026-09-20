import Foundation

/// 仅影响应用自动管理的快照；迁移、恢复和用户自行保留的文件始终不参与清理。
struct BackupConfiguration: Equatable, Sendable {
    /// 防止长时间没有新快照时失去最后可恢复版本的不可下调安全底线。
    static let minimumLatestSnapshots = 3
    static let defaultDailyRetentionDays = 30
    static let defaultMonthlyRetentionMonths = 12

    /// 仅控制普通保存时的每日快照；删除前的安全快照始终启用。
    var isPeriodicSnapshotsEnabled: Bool
    var dailyRetentionDays: Int
    var monthlyRetentionMonths: Int

    init(
        isPeriodicSnapshotsEnabled: Bool = true,
        dailyRetentionDays: Int = Self.defaultDailyRetentionDays,
        monthlyRetentionMonths: Int = Self.defaultMonthlyRetentionMonths
    ) {
        self.isPeriodicSnapshotsEnabled = isPeriodicSnapshotsEnabled
        self.dailyRetentionDays = max(1, dailyRetentionDays)
        self.monthlyRetentionMonths = max(0, monthlyRetentionMonths)
    }

    static let `default` = BackupConfiguration()
}
