import Foundation
import Testing
@testable import DiscordAppBuilder

struct ApplicationSettingsStoreTests {
    @Test func storesAndMigratesApplicationSettingsInApplicationSupport() throws {
        let supportDirectory = FileManager.default.temporaryDirectory.appending(
            path: "DiscordAppBuilderSettings-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let suiteName = "DiscordAppBuilderSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            try? FileManager.default.removeItem(at: supportDirectory)
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(AppAppearance.dark.rawValue, forKey: AppAppearance.storageKey)
        defaults.set(
            ["/tmp/First Bot", "/tmp/Second Bot"],
            forKey: ApplicationSettingsStore.legacyRecentProjectsKey
        )

        let migrated = ApplicationSettingsStore(
            applicationSupportDirectory: supportDirectory,
            userDefaults: defaults
        )
        #expect(migrated.appearance == .dark)
        #expect(migrated.recentProjectPaths == ["/tmp/First Bot", "/tmp/Second Bot"])
        #expect(
            migrated.fileURL == supportDirectory
                .appending(path: ApplicationSettingsStore.directoryName)
                .appending(path: ApplicationSettingsStore.fileName)
        )
        #expect(FileManager.default.fileExists(atPath: migrated.fileURL.path))

        migrated.setAppearance(.light)
        migrated.setRecentProjectPaths(["/tmp/Updated Bot"])
        defaults.removePersistentDomain(forName: suiteName)

        let reloaded = ApplicationSettingsStore(
            applicationSupportDirectory: supportDirectory,
            userDefaults: defaults
        )
        #expect(reloaded.appearance == .light)
        #expect(reloaded.recentProjectPaths == ["/tmp/Updated Bot"])
    }
}
