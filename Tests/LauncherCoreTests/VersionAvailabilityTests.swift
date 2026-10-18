import XCTest
@testable import LauncherCore

final class VersionAvailabilityTests: XCTestCase {
    private func installation(_ game: GameDefinition = .bedrock, version: String? = nil, state: InstallState = .ready, revision: String? = nil) -> Installation {
        var result = Installation(game: game, version: version ?? game.baseline, path: URL(fileURLWithPath: "/fixture"), bottle: "fixture", managed: true, state: state)
        result.packageRevision = revision
        return result
    }
    func testLatestInstalledInUnselectedCopyIsRecognized() {
        let selected = installation(version: "1.26.5000.0")
        let latest = installation()
        let result = VersionAvailability(game: .bedrock, availableVersion: GameDefinition.bedrock.baseline, revision: nil, installations: [selected, latest], selected: selected)
        XCTAssertEqual(result.state, .installed)
        XCTAssertEqual(result.installedID, latest.id)
        XCTAssertTrue(result.isNewerThanSelected)
    }
    func testUnverifiedLatestIsOfferedAsUntested() {
        let result = VersionAvailability(game: .bedrock, availableVersion: "1.27.0.0", revision: nil, installations: [], selected: installation())
        XCTAssertEqual(result.state, .untested)
        XCTAssertEqual(result.version, "1.27.0.0")
        XCTAssertTrue(result.isNewerThanSelected)
    }
    func testFailedAndOtherGameCopiesDoNotCountAsInstalled() {
        let result = VersionAvailability(game: .bedrock, availableVersion: GameDefinition.bedrock.baseline, revision: nil,
                                         installations: [installation(state: .failed), installation(.dungeons2, version: GameDefinition.bedrock.baseline)], selected: nil)
        XCTAssertEqual(result.state, .downloadable)
        XCTAssertNil(result.installedID)
    }
    func testPackageRevisionDifferenceAllowsDownloadAndUnknownRevisionDoesNotClaimUpdate() {
        for (local, expected) in [("old", VersionAvailability.State.downloadable), ("new", .installed), (nil, .installed)] {
            let result = VersionAvailability(game: .bedrock, availableVersion: GameDefinition.bedrock.baseline, revision: "new", installations: [installation(revision: local)], selected: nil)
            XCTAssertEqual(result.state, expected)
        }
    }
    func testMissingVersionIsUncheckedAndOrderingIsNumericAndPerGame() {
        XCTAssertEqual(VersionAvailability(game: .bedrock, availableVersion: nil, revision: nil, installations: [], selected: nil).state, .unchecked)
        let versions = VersionAvailability.sorted([installation(version: "1.9.0.0"), installation(version: "1.10.0.0"), installation(.dungeons2)], game: .bedrock)
        XCTAssertEqual(versions.map(\.version), ["1.10.0.0", "1.9.0.0"])
    }
    func testIssueDraftContainsOnlyCodeAndNoUntrustedErrorDetails() throws {
        let url = ProjectSupport.issueURL(errorCode: "NETWORK_UNAVAILABLE")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/rafaelreverberi/Minecraft-on-Mac/issues/new")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(query.first(where: { $0.name == "body" })?.value?.contains("Error code: NETWORK_UNAVAILABLE") == true)
        for unsafe in ["/Users/private/account", "token=secret", "CODE\nsecret", String(repeating: "A", count: 100)] {
            XCTAssertFalse(ProjectSupport.issueURL(errorCode: unsafe).absoluteString.contains("secret"))
            XCTAssertFalse(ProjectSupport.issueURL(errorCode: unsafe).absoluteString.contains("Error%20code"))
        }
    }
}
