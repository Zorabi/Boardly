import XCTest
@testable import Boardly

@MainActor
final class BoardlySettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "BoardlySettingsTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    func testDefaultsAreReadableAndUseful() {
        let settings = BoardlySettings(defaults: makeDefaults())

        XCTAssertEqual(settings.fontSizePreset, .standard)
        XCTAssertEqual(settings.fontScale, 1.0, accuracy: 0.001)
        XCTAssertTrue(settings.showTaskNotes)
        XCTAssertTrue(settings.showTaskMetadata)
        XCTAssertEqual(settings.cardDensity, .standard)
        XCTAssertTrue(settings.periodicSnapshotsEnabled)
        XCTAssertEqual(settings.backupDailyRetention, .oneMonth)
        XCTAssertEqual(settings.backupMonthlyRetention, .oneYear)
        XCTAssertEqual(settings.backupConfiguration, .default)
    }

    func testChangesPersistAndPresetUpdatesScale() {
        let defaults = makeDefaults()
        let settings = BoardlySettings(defaults: defaults)

        settings.fontSizePreset = .large
        settings.showTaskNotes = false
        settings.showTaskMetadata = false
        settings.cardDensity = .compact
        settings.periodicSnapshotsEnabled = false
        settings.backupDailyRetention = .oneWeek
        settings.backupMonthlyRetention = .threeMonths

        let reloaded = BoardlySettings(defaults: defaults)
        XCTAssertEqual(reloaded.fontSizePreset, .large)
        XCTAssertEqual(reloaded.fontScale, 1.15, accuracy: 0.001)
        XCTAssertFalse(reloaded.showTaskNotes)
        XCTAssertFalse(reloaded.showTaskMetadata)
        XCTAssertEqual(reloaded.cardDensity, .compact)
        XCTAssertFalse(reloaded.periodicSnapshotsEnabled)
        XCTAssertEqual(reloaded.backupDailyRetention, .oneWeek)
        XCTAssertEqual(reloaded.backupMonthlyRetention, .threeMonths)

        settings.fontScale = 1.07
        let smoothScale = BoardlySettings(defaults: defaults)
        XCTAssertEqual(smoothScale.fontScale, 1.07, accuracy: 0.001)
    }

    func testResetRestoresDefaults() {
        let settings = BoardlySettings(defaults: makeDefaults())
        settings.fontScale = 1.3
        settings.showTaskNotes = false
        settings.showTaskMetadata = false
        settings.cardDensity = .spacious
        settings.periodicSnapshotsEnabled = false
        settings.backupDailyRetention = .oneYear
        settings.backupMonthlyRetention = .none

        settings.resetToDefaults()

        XCTAssertEqual(settings.fontScale, 1.0, accuracy: 0.001)
        XCTAssertTrue(settings.showTaskNotes)
        XCTAssertTrue(settings.showTaskMetadata)
        XCTAssertEqual(settings.cardDensity, .standard)
        XCTAssertTrue(settings.periodicSnapshotsEnabled)
        XCTAssertEqual(settings.backupDailyRetention, .oneMonth)
        XCTAssertEqual(settings.backupMonthlyRetention, .oneYear)
    }

    func testInvalidStoredBackupRetentionUsesSafeDefaults() {
        let defaults = makeDefaults()
        defaults.set(-1, forKey: "boardly.settings.backupDailyRetention")
        defaults.set(999, forKey: "boardly.settings.backupMonthlyRetention")

        let settings = BoardlySettings(defaults: defaults)

        XCTAssertEqual(settings.backupDailyRetention, .oneMonth)
        XCTAssertEqual(settings.backupMonthlyRetention, .oneYear)
        XCTAssertEqual(
            BackupConfiguration(
                isPeriodicSnapshotsEnabled: true,
                dailyRetentionDays: -5,
                monthlyRetentionMonths: -5
            ).dailyRetentionDays,
            1
        )
    }
}
