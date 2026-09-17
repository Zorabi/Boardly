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
    }

    func testChangesPersistAndPresetUpdatesScale() {
        let defaults = makeDefaults()
        let settings = BoardlySettings(defaults: defaults)

        settings.fontSizePreset = .large
        settings.showTaskNotes = false
        settings.showTaskMetadata = false
        settings.cardDensity = .compact

        let reloaded = BoardlySettings(defaults: defaults)
        XCTAssertEqual(reloaded.fontSizePreset, .large)
        XCTAssertEqual(reloaded.fontScale, 1.15, accuracy: 0.001)
        XCTAssertFalse(reloaded.showTaskNotes)
        XCTAssertFalse(reloaded.showTaskMetadata)
        XCTAssertEqual(reloaded.cardDensity, .compact)

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

        settings.resetToDefaults()

        XCTAssertEqual(settings.fontScale, 1.0, accuracy: 0.001)
        XCTAssertTrue(settings.showTaskNotes)
        XCTAssertTrue(settings.showTaskMetadata)
        XCTAssertEqual(settings.cardDensity, .standard)
    }
}
