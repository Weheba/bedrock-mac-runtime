import XCTest
@testable import LauncherCore

final class ExperimentalVersionTests: XCTestCase {
    func testRejectedInstallDoesNotTouchExistingSelectionOrCreateStaging() async throws {
        let temporary = FileManager.default.temporaryDirectory.path
        let root = URL(fileURLWithPath: temporary.hasPrefix("/var/") ? "/private" + temporary : temporary).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let working = Installation(version: "1.1.1.0", path: root.appendingPathComponent("Working"), bottle: "Working", managed: false, state: .ready)
        var database = LibraryDatabase()
        database.installations = [working]; database.currentByGameId[working.gameId] = working.id
        try FileSafety.write(database, to: root.appendingPathComponent("library.json"))
        let crossOver = CrossOver(wine: root.appendingPathComponent("wine"), bottlesRoot: root.appendingPathComponent("Bottles"))
        let store = try LibraryStore(root: root, crossOver: crossOver, runtimeTests: false, isGameRunning: { false })
        do {
            _ = try await store.install(game: .dungeons2, version: "1.1.3.0", experimental: false)
            XCTFail("An untested install without opt-in was accepted")
        } catch { XCTAssertEqual((error as? LauncherError)?.code, "COMPATIBILITY_UNVERIFIED") }
        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.currentByGameId[working.gameId], working.id)
        XCTAssertEqual(snapshot.installations, [working])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: GameDefinition.dungeons2.versionRoot(in: root).path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: crossOver.bottlesRoot.path))
    }
    func testNewBuildRequiresExplicitOptInAndOldOrMalformedBuildsAreRejected() throws {
        for (game, version) in [(GameDefinition.dungeons2, "1.1.3.0"), (.bedrock, "1.27.0.0")] {
            XCTAssertThrowsError(try game.validateInstallVersion(version, allowUntested: false))
            try game.validateInstallVersion(version, allowUntested: true)
            try game.validateInstallVersion(game.baseline, allowUntested: false)
            for invalid in ["0.0.0.0", "../new", "1.2.3", "1.2.3.65536", "1.+2.3.4"] {
                XCTAssertThrowsError(try game.validateInstallVersion(invalid, allowUntested: true))
            }
        }
    }
    func testExperimentalProfileDoesNotPinOldGameExecutableOrOriginalGameDLL() throws {
        let tested = try CompatibilityProfile.managed(for: .dungeons2)
        let experimental = try CompatibilityProfile.forVersion(game: .dungeons2, version: "1.1.3.0", experimental: true)
        XCTAssertEqual(experimental.version, "1.1.3.0")
        XCTAssertTrue(experimental.id.contains("experimental"))
        XCTAssertNil(experimental.hashes[GameDefinition.dungeons2.executable])
        XCTAssertNil(experimental.hashes["Dungeons/Binaries/WinGDK/libHttpClient.GDK.dll"])
        XCTAssertEqual(experimental.hashes["Dungeons/Binaries/WinGDK/XCurl.dll"], tested.hashes["Dungeons/Binaries/WinGDK/XCurl.dll"])
        XCTAssertEqual(experimental.hashes["Dungeons/Binaries/WinGDK/xgameruntime.dll"], tested.hashes["Dungeons/Binaries/WinGDK/xgameruntime.dll"])
        XCTAssertEqual(try CompatibilityProfile.managed(for: .dungeons2).hashes, tested.hashes)
    }
    func testBedrockTrialRetainsEveryBundledCompatibilityHash() throws {
        let tested = try CompatibilityProfile.managed(for: .bedrock)
        let trial = try CompatibilityProfile.forVersion(game: .bedrock, version: "1.27.0.0", experimental: true)
        XCTAssertEqual(trial.hashes, tested.hashes)
        XCTAssertEqual(tested.version, GameDefinition.bedrock.baseline)
    }
    func testExperimentalMarkerRoundTripsWithoutBreakingLegacyReceipts() throws {
        var install = Installation(version: "1.1.3.0", path: URL(fileURLWithPath: "/fixture/Game"), bottle: "Fixture", managed: true, compatibilityProfile: "dungeons2-managed-experimental")
        install.experimental = true
        let trial = try JSONDecoder().decode(Installation.self, from: JSONEncoder().encode(install))
        XCTAssertTrue(trial.usesUntestedVersion)
        XCTAssertEqual(try CompatibilityProfile.forInstallation(trial).version, "1.1.3.0")
        install.experimental = nil
        let legacy = try JSONDecoder().decode(Installation.self, from: JSONEncoder().encode(install))
        XCTAssertFalse(legacy.usesUntestedVersion)
        XCTAssertThrowsError(try CompatibilityProfile.forInstallation(legacy))
    }
}
