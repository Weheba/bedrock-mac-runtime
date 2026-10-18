import Foundation

/// Compares Microsoft's package with every ready installation for one game.
public struct VersionAvailability: Sendable {
    public enum State: Sendable { case unchecked, installed, downloadable, untested, tooOld }
    public let state: State
    public let version: String?
    public let installedID: UUID?
    public let isNewerThanSelected: Bool

    public init(game: GameDefinition, availableVersion: String?, revision: String?, installations: [Installation], selected: Installation?) {
        version = availableVersion
        isNewerThanSelected = availableVersion.flatMap { try? PackageVersion($0) }.map { available in
            selected.flatMap { try? PackageVersion($0.version) }.map { $0 < available } ?? false
        } ?? false
        guard let availableVersion, (try? PackageVersion(availableVersion)) != nil else {
            state = .unchecked; installedID = nil; return
        }
        let matching = installations.filter {
            $0.game == game && $0.state == .ready && $0.version == availableVersion &&
            (revision == nil || $0.packageRevision == nil || $0.packageRevision == revision)
        }.sorted { lhs, rhs in
            if (lhs.id == selected?.id) != (rhs.id == selected?.id) { return lhs.id == selected?.id }
            return lhs.installedAt > rhs.installedAt
        }.first
        installedID = matching?.id
        if matching != nil { state = .installed }
        else if (try? game.validateVersion(availableVersion)) != nil { state = .downloadable }
        else if (try? game.validateInstallVersion(availableVersion, allowUntested: true)) != nil { state = .untested }
        else { state = .tooOld }
    }

    public static func sorted(_ installations: [Installation], game: GameDefinition) -> [Installation] {
        installations.filter { $0.game == game }.sorted {
            if let lhs = try? PackageVersion($0.version), let rhs = try? PackageVersion($1.version), lhs != rhs { return lhs > rhs }
            if $0.installedAt != $1.installedAt { return $0.installedAt > $1.installedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

/// The bundled tested catalog can offer an upgrade without a network request.
public struct TestedReleaseUpdate: Identifiable, Sendable {
    public var id: String { game.rawValue + ":" + game.baseline }
    public let game: GameDefinition
    public let installedID: UUID?
    public init?(game: GameDefinition, installations: [Installation], selected: Installation?) {
        guard let selected, selected.game == game,
              let version = try? PackageVersion(selected.version),
              let latest = try? PackageVersion(game.baseline), version < latest else { return nil }
        self.game = game
        installedID = VersionAvailability.sorted(installations, game: game).first {
            $0.version == game.baseline && $0.state == .ready
        }?.id
    }
}
