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
    /// Callers must ensure no managed game is running.
    public static func end(_ install: Installation, crossOver: CrossOver) async {
        guard let bottle = ownedBottle(install, crossOver: crossOver), let processes = try? GameTermination.snapshot() else { return }
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
            guard let processes = try? GameTermination.snapshot() else { return }
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

    public static func endIdle(_ installations: [Installation], crossOver: CrossOver) async {
        guard !CrossOver.gameRunning() else { return }
        var seen = Set<String>()
        for install in installations where install.game == .bedrock && seen.insert(install.bottle).inserted {
            await end(install, crossOver: crossOver)
        }
    }

    /// True when a process of this installation shows a normal window on screen.
    public static func hasVisibleWindow(_ install: Installation, crossOver: CrossOver) -> Bool {
        guard let processes = try? GameTermination.snapshot() else { return true }
        let pids = Set(processes.filter { GameTermination.matches($0, installation: install, crossOver: crossOver) }.map(\.pid))
        guard !pids.isEmpty else { return true }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return true }
        return windows.contains { window in
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pids.contains(pid) else { return false }
            return (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }
    }
}
