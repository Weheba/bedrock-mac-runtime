import XCTest
import Foundation
import Darwin
@testable import LauncherCore

final class BedrockSessionTests: XCTestCase {
    let cx = CrossOver(wine: URL(fileURLWithPath: "/fixture/CrossOver.app/Contents/wine"), bottlesRoot: URL(fileURLWithPath: "/fixture/bottles"))
    func record(_ pid: Int32, path: String = "/fixture/CrossOver.app/Contents/wine") -> GameProcessIdentity {
        .init(pid: pid, parent: 1, uid: getuid(), startedSeconds: 1, startedMicroseconds: 1, executable: path, command: "")
    }

    func testLeftoversAreRuntimeProcessesInsideTheBottleOnly() {
        let bottle = URL(fileURLWithPath: "/fixture/bottles/MinecraftMac-bedrock-A")
        let cwd: [Int32: String] = [
            1: "/fixture/bottles/MinecraftMac-bedrock-A/drive_c/windows",
            2: "/fixture/bottles/MinecraftMac-bedrock-AB/drive_c/windows",
            3: "/fixture/bottles/MinecraftMac-bedrock-A/drive_c/windows",
            4: "/fixture/bottles/MinecraftMac-bedrock-A",
            5: "/fixture/bottles/MinecraftMac-bedrock-A/drive_c",
        ]
        let snapshot = [record(1), record(2), record(3, path: "/bin/sleep"), record(4, path: "/fixture/CrossOver.app/Contents/wineserver"), record(5), record(6)]
        let found = BedrockSession.leftovers(in: bottle, snapshot: snapshot, crossOver: cx) { cwd[$0] }
        XCTAssertEqual(found.map(\.pid), [1, 5])
    }

    func testServerDirectoryMatchesWineNaming() throws {
        let bottle = FileManager.default.temporaryDirectory.appendingPathComponent("Session-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: bottle, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bottle) }
        var info = stat()
        XCTAssertEqual(stat(bottle.path, &info), 0)
        let expected = "/private/tmp/.wine-\(getuid())/server-\(String(UInt64(UInt32(bitPattern: info.st_dev)), radix: 16))-\(String(info.st_ino, radix: 16))"
        XCTAssertEqual(BedrockSession.serverDirectory(for: bottle), expected)
        let server = record(9, path: "/fixture/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineserver")
        let other = record(10, path: "/fixture/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wineserver")
        let found = BedrockSession.servers(for: bottle, snapshot: [server, other, record(11)], crossOver: cx) { [9: expected, 10: expected + "0", 11: expected][$0] }
        XCTAssertEqual(found.map(\.pid), [9])
    }

    func testOnlyOwnedBedrockEnvironmentsAreEnded() {
        let dungeons = Installation(game: .dungeons2, version: "1.1.2.0", path: URL(fileURLWithPath: "/fixture/Game"), bottle: "Dungeons2Xbox", managed: false)
        let missing = Installation(game: .bedrock, version: "1.26.5203.0", path: URL(fileURLWithPath: "/fixture/Game"), bottle: "MinecraftMac-bedrock-missing", managed: true)
        XCTAssertNil(BedrockSession.ownedBottle(dungeons, crossOver: cx))
        XCTAssertNil(BedrockSession.ownedBottle(missing, crossOver: cx))
    }
}
