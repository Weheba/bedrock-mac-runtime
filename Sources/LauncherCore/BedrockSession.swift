import Foundation
import Darwin
import CoreGraphics

/// Wine session lifetime for launcher-owned Bedrock environments only.
public enum BedrockSession {
    static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static func leftovers(in bottle: URL, snapshot: [GameProcessIdentity], crossOver: CrossOver, workingDirectory: (Int32) -> String?) -> [GameProcessIdentity] {
        let root = bottle.resolvingSymlinksInPath().path + "/"
        return snapshot.filter { process in
            guard process.uid == getuid(), GameTermination.belongsToRuntime(process, crossOver: crossOver),
                  let cwd = workingDirectory(process.pid) else { return false }
            return (URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path + "/").hasPrefix(root)
        }
    }

    static func ownedBottle(_ install: Installation, crossOver: CrossOver) -> URL? {
        guard install.game == .bedrock, let bottle = try? crossOver.bottleURL(install.bottle),
              (try? ManagedInstaller.validateOwner(bottle: bottle, name: install.bottle, game: .bedrock)) != nil else { return nil }
        return bottle
    }

    /// Wine keys its server directory on the prefix's device and inode.
    static func serverDirectory(for bottle: URL) -> String? {
        var info = stat()
        guard stat(bottle.path, &info) == 0 else { return nil }
        return "/private/tmp/.wine-\(getuid())/server-\(String(UInt64(UInt32(bitPattern: info.st_dev)), radix: 16))-\(String(info.st_ino, radix: 16))"
    }

    static func servers(for bottle: URL, snapshot: [GameProcessIdentity], crossOver: CrossOver, workingDirectory: (Int32) -> String?) -> [GameProcessIdentity] {
        guard let directory = serverDirectory(for: bottle) else { return [] }
        let app = URL(fileURLWithPath: crossOver.wine.path.components(separatedBy: "/Contents/")[0]).resolvingSymlinksInPath().path + "/Contents/"
        return snapshot.filter { process in
            let binary = URL(fileURLWithPath: process.executable).resolvingSymlinksInPath()
            guard process.uid == getuid(), binary.path.hasPrefix(app), binary.lastPathComponent.lowercased().contains("wineserver"),
                  let cwd = workingDirectory(process.pid) else { return false }
            return URL(fileURLWithPath: cwd).resolvingSymlinksInPath().path == URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
        }
    }

    /// Stops the environment's wineserver and every Wine process still inside it.
    /// Stops early once `mayContinue` reports a game starting or running.
    static func end(_ install: Installation, crossOver: CrossOver, while mayContinue: @Sendable () async -> Bool) async {
        guard await mayContinue(), let bottle = ownedBottle(install, crossOver: crossOver), let processes = try? GameTermination.snapshot() else { return }
        if !servers(for: bottle, snapshot: processes, crossOver: crossOver, workingDirectory: workingDirectory).isEmpty {
            let wineserver = crossOver.wine.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("bin/wineserver")
            await Task.detached {
                let p = Process(); p.executableURL = crossOver.wine
                p.arguments = ["--bottle", install.bottle, "--ux-app", wineserver.path, "-k"]
                p.environment = CrossOver.environment(for: .bedrock)
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return }
                let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timer)
                defer { timer.cancel() }; p.waitUntilExit()
            }.value
        }
        for _ in 0..<20 {
            guard await mayContinue(), let processes = try? GameTermination.snapshot() else { return }
            let remaining = leftovers(in: bottle, snapshot: processes, crossOver: crossOver, workingDirectory: workingDirectory) +
                servers(for: bottle, snapshot: processes, crossOver: crossOver, workingDirectory: workingDirectory)
            if remaining.isEmpty { return }
            for process in remaining {
                guard let live = GameTermination.identity(process.pid), process.sameProcess(as: live) else { continue }
                _ = kill(process.pid, SIGKILL)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func endIdle(_ installations: [Installation], crossOver: CrossOver, while mayContinue: @Sendable () async -> Bool) async {
        var seen = Set<String>()
        for install in installations where install.game == .bedrock && seen.insert(install.bottle).inserted {
            await end(install, crossOver: crossOver, while: mayContinue)
        }
    }

    /// While the game has no window, Wine keeps only a hidden placeholder of about 500x500.
    /// Fullscreen, minimized and other-Space windows are off screen or above layer 0 but keep the game's size.
    static let minimumHiddenWindowArea: CGFloat = 640 * 480

    static func isGameWindow(_ window: [String: Any], pids: Set<Int32>) -> Bool {
        guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(pid),
              let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue, layer >= 0,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds), rect.width >= 64, rect.height >= 64 else { return false }
        let onScreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        if onScreen && alpha > 0 { return true }
        return rect.width * rect.height >= minimumHiddenWindowArea
    }

    /// True when a process of this installation owns a game window, shown or not.
    public static func hasGameWindow(_ install: Installation, crossOver: CrossOver) -> Bool {
        guard let processes = try? GameTermination.snapshot() else { return true }
        let pids = Set(processes.filter { GameTermination.matches($0, installation: install, crossOver: crossOver) }.map(\.pid))
        guard !pids.isEmpty else { return true }
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        return windows.contains { isGameWindow($0, pids: pids) }
    }
}
