import XCTest
@testable import LauncherCore

final class TestedReleaseUpdateTests: XCTestCase {
    private func install(_ version: String, game: GameDefinition = .dungeons2, state: InstallState = .ready) -> Installation {
        Installation(game: game, version: version, path: URL(fileURLWithPath: "/fixture/Game"), bottle: "Fixture", managed: true, state: state)
    }
    func testNewCatalogPromotesExistingTrialAndKeepsOldProfile() throws {
        XCTAssertEqual(GameDefinition.dungeons2.baseline, "1.1.2.0")
        var trial = install("1.1.2.0")
        trial.experimental = true
        XCTAssertFalse(trial.usesUntestedVersion)
        let profile = try CompatibilityProfile.forInstallation(trial)
        XCTAssertEqual(profile.id, "dungeons2-managed-1.1.2-r1")
        XCTAssertEqual(profile.hashes[GameDefinition.dungeons2.executable], "4dd569de727f267f1198dc90c7eea27440f12f174b55ed0a0d8be6e8e475b69d")
        let old = try CompatibilityProfile.forInstallation(install("1.1.1.0"))
        XCTAssertEqual(old.version, "1.1.1.0")
        XCTAssertEqual(old.hashes[GameDefinition.dungeons2.executable], "4d8de2e84a8a0c7a753d36082ca059388161e4e75fbd45164dd300da14adcb12")
        XCTAssertEqual(Set(profile.hashes.keys), Set(old.hashes.keys))
        for (name, hash) in old.hashes where name != GameDefinition.dungeons2.executable { XCTAssertEqual(profile.hashes[name], hash) }
    }
    func testOfferDownloadsOrReusesReadyCopyButNeverDowngrades() throws {
        let old = install("1.1.1.0"), latest = install("1.1.2.0")
        XCTAssertNotNil(TestedReleaseUpdate(game: .dungeons2, installations: [old], selected: old))
        XCTAssertNil(TestedReleaseUpdate(game: .dungeons2, installations: [old], selected: old)?.installedID)
        XCTAssertEqual(TestedReleaseUpdate(game: .dungeons2, installations: [old, latest], selected: old)?.installedID, latest.id)
        XCTAssertNil(TestedReleaseUpdate(game: .dungeons2, installations: [install("1.1.2.0", state: .failed)], selected: old)?.installedID)
        for version in ["1.1.2.0", "1.1.3.0"] { XCTAssertNil(TestedReleaseUpdate(game: .dungeons2, installations: [], selected: install(version))) }
        XCTAssertNil(TestedReleaseUpdate(game: .bedrock, installations: [old], selected: old))
        XCTAssertNil(TestedReleaseUpdate(game: .dungeons2, installations: [], selected: nil))
    }
}
