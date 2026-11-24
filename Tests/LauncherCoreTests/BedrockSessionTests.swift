import XCTest
import Foundation
import Darwin
import CoreGraphics
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

    func window(pid: Int32 = 7, layer: Int = 0, width: CGFloat, height: CGFloat, onScreen: Bool, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: pid), kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowBounds as String: CGRect(x: 0, y: 0, width: width, height: height).dictionaryRepresentation,
         kCGWindowIsOnscreen as String: NSNumber(value: onScreen), kCGWindowAlpha as String: NSNumber(value: alpha)]
    }

    func testGameWindowDetection() {
        let pids: Set<Int32> = [7]
        XCTAssertTrue(BedrockSession.isGameWindow(window(width: 854, height: 480, onScreen: true), pids: pids))
        XCTAssertTrue(BedrockSession.isGameWindow(window(layer: 25, width: 1728, height: 1117, onScreen: true), pids: pids), "fullscreen above layer 0")
        XCTAssertTrue(BedrockSession.isGameWindow(window(layer: 25, width: 1728, height: 1117, onScreen: false), pids: pids), "fullscreen on another Space")
        XCTAssertTrue(BedrockSession.isGameWindow(window(width: 854, height: 480, onScreen: false), pids: pids), "minimized or hidden game window")
        XCTAssertTrue(BedrockSession.isGameWindow(window(width: 400, height: 300, onScreen: true), pids: pids), "small window the player resized")
        XCTAssertFalse(BedrockSession.isGameWindow(window(width: 500, height: 500, onScreen: false), pids: pids), "hidden placeholder")
        XCTAssertFalse(BedrockSession.isGameWindow(window(width: 500, height: 500, onScreen: true, alpha: 0), pids: pids), "transparent placeholder")
        XCTAssertFalse(BedrockSession.isGameWindow(window(width: 1, height: 1, onScreen: true), pids: pids))
        XCTAssertFalse(BedrockSession.isGameWindow(window(layer: -1, width: 854, height: 480, onScreen: true), pids: pids))
        XCTAssertFalse(BedrockSession.isGameWindow(window(pid: 8, width: 854, height: 480, onScreen: true), pids: pids))
    }

    func testNoWindowWhileTheGameHasNotStarted() {
        let install = Installation(game: .bedrock, version: "1.26.5203.0", path: URL(fileURLWithPath: "/fixture/NotStarted"), bottle: "MinecraftMac-bedrock-fixture", managed: true)
        XCTAssertFalse(BedrockSession.hasGameWindow(install, crossOver: cx))
    }
}

final class SessionFlag: @unchecked Sendable {
    private let lock = NSLock(); private var value = 0
    var count: Int { lock.withLock { value } }
    var isSet: Bool { count > 0 }
    func set() { lock.withLock { value += 1 } }
}

final class GameProcessExclusionTests: XCTestCase {
    func testCleanupStopsAsSoonAsAGameIsRunning() async {
        let game = SessionFlag(), passes = SessionFlag()
        let processes = GameProcess(gameRunning: { game.isSet })
        await processes.endIdle { mayContinue in
            for _ in 0..<20 {
                guard await mayContinue() else { return }
                passes.set()
                if passes.count == 3 { game.set() }
            }
        }
        XCTAssertEqual(passes.count, 3)
    }

    func testCleanupDoesNotStartWhileGameRunsOrLaunchIsInFlight() async throws {
        let ran = SessionFlag()
        let running = GameProcess(gameRunning: { true })
        await running.endIdle { _ in ran.set() }
        let launching = GameProcess(gameRunning: { false })
        try await launching.reserve()
        await launching.endIdle { _ in ran.set() }
        XCTAssertFalse(ran.isSet)
        await launching.release()
        await launching.endIdle { _ in ran.set() }
        XCTAssertTrue(ran.isSet)
    }

    func testSecondLaunchIsRejectedWhileOneIsInFlight() async throws {
        let processes = GameProcess(gameRunning: { false })
        try await processes.reserve()
        do { try await processes.reserve(); XCTFail("second launch admitted") } catch let error as LauncherError {
            XCTAssertEqual(error.code, "GAME_ALREADY_RUNNING")
        }
    }

    func testLaunchWaitsForCleanupToFinish() async throws {
        let processes = GameProcess(gameRunning: { false })
        let finished = SessionFlag(), reserved = SessionFlag()
        let (release, gate) = AsyncStream<Void>.makeStream()
        let cleanup = Task { await processes.endIdle { _ in for await _ in release {}; finished.set() } }
        try await Task.sleep(for: .milliseconds(50))
        let launch = Task { try await processes.reserve(); XCTAssertTrue(finished.isSet); reserved.set() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(reserved.isSet)
        gate.finish()
        try await launch.value
        await cleanup.value
        XCTAssertTrue(reserved.isSet)
    }

    func testConcurrentCleanupsRunOnce() async throws {
        let processes = GameProcess(gameRunning: { false })
        let runs = SessionFlag()
        let (release, gate) = AsyncStream<Void>.makeStream()
        let first = Task { await processes.endIdle { _ in runs.set(); for await _ in release {} } }
        try await Task.sleep(for: .milliseconds(50))
        let second = Task { await processes.endIdle { _ in runs.set() } }
        try await Task.sleep(for: .milliseconds(50))
        gate.finish()
        await first.value; await second.value
        XCTAssertEqual(runs.count, 1)
    }
}
