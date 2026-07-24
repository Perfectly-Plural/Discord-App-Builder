import Foundation

struct PersistedApplicationSettings: Codable, Equatable {
    var appearance: AppAppearance = .system
    var recentProjectPaths: [String] = []
}

final class ApplicationSettingsStore {
    static let directoryName = "Discord App Builder"
    static let fileName = "settings.json"
    static let legacyRecentProjectsKey = "DiscordAppBuilder.recentProjectPaths"

    let fileURL: URL
    private(set) var values: PersistedApplicationSettings

    init(
        applicationSupportDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        let supportDirectory = applicationSupportDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let settingsDirectory = supportDirectory.appending(
            path: Self.directoryName,
            directoryHint: .isDirectory
        )
        fileURL = settingsDirectory.appending(path: Self.fileName)

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersistedApplicationSettings.self, from: data) {
            values = decoded
        } else {
            values = PersistedApplicationSettings(
                appearance: userDefaults.string(forKey: AppAppearance.storageKey)
                    .flatMap(AppAppearance.init(rawValue:)) ?? .system,
                recentProjectPaths: userDefaults.stringArray(
                    forKey: Self.legacyRecentProjectsKey
                ) ?? []
            )
            try? fileManager.createDirectory(
                at: settingsDirectory,
                withIntermediateDirectories: true
            )
            try? persist()
        }
    }

    var appearance: AppAppearance {
        values.appearance
    }

    var recentProjectPaths: [String] {
        values.recentProjectPaths
    }

    func setAppearance(_ appearance: AppAppearance) {
        guard values.appearance != appearance else { return }
        values.appearance = appearance
        try? persist()
    }

    func setRecentProjectPaths(_ paths: [String]) {
        guard values.recentProjectPaths != paths else { return }
        values.recentProjectPaths = paths
        try? persist()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(values).write(to: fileURL, options: .atomic)
    }
}
