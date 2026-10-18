import AppKit
import SwiftUI
import XCTest
import LauncherCore
@testable import MinecraftMacLauncher

final class VersionManagementLayoutTests: XCTestCase {
    @MainActor
    func testVersionPanelsAndSettingsRenderWithoutLibraryAccess() throws {
        let model = AppModel(store: nil, diagnostics: nil)
        for game in GameDefinition.allCases {
            let current = Installation(game: game, version: game.baseline, path: URL(fileURLWithPath: "/fixture/game"), bottle: "Fixture", managed: true, state: .ready)
            model.database.installations.append(current)
            model.database.currentByGameId[game.rawValue] = current.id
        }
        for (name, game, version) in [("bedrock-installed", GameDefinition.bedrock, GameDefinition.bedrock.baseline),
                                       ("bedrock-newer", .bedrock, "1.27.0.0"),
                                       ("dungeons-installed", .dungeons2, GameDefinition.dungeons2.baseline),
                                       ("dungeons-newer", .dungeons2, "1.1.3.0")] {
            let data = try JSONSerialization.data(withJSONObject: ["schema": 1, "status": "ok", "signedIn": true, "entitlement": "verified", "availableVersion": version])
            model.accounts[game] = try AccountStatus.decode(data)
            model.versionCheckedAt[game] = Date(timeIntervalSince1970: 1_792_320_000)
            try render(name, view: VersionsView(game: game, initialTab: .downloads).environmentObject(model), size: NSSize(width: 650, height: 680))
        }
        for game in GameDefinition.allCases {
            try render("\(game.rawValue)-versions-page", view: GameView(game: game, initialSection: .versions).environmentObject(model), size: NSSize(width: 650, height: 850), padding: 0)
            try render("\(game.rawValue)-advanced-page", view: GameView(game: game, initialSection: .advanced).environmentObject(model), size: NSSize(width: 650, height: 1100), padding: 0)
        }
        try render("game-bedrock", view: GameView(game: .bedrock).environmentObject(model), size: NSSize(width: 650, height: 720))
        var trial = Installation(version: "1.1.3.0", path: URL(fileURLWithPath: "/fixture/trial"), bottle: "Separate Trial", managed: true, state: .ready)
        trial.experimental = true
        model.database.installations.append(trial)
        model.database.currentByGameId[trial.gameId] = trial.id
        XCTAssertEqual(model.versionAvailability(for: .dungeons2).state, .installed)
        try render("dungeons-trial-installed", view: VersionsView(game: .dungeons2).environmentObject(model), size: NSSize(width: 650, height: 800))
        model.database.installations = []
        model.database.currentByGameId = [:]
        let available = try JSONSerialization.data(withJSONObject: ["schema": 1, "status": "ok", "signedIn": true, "entitlement": "verified", "availableVersion": GameDefinition.bedrock.baseline])
        model.accounts[.bedrock] = try AccountStatus.decode(available)
        XCTAssertEqual(model.versionAvailability(for: .bedrock).state, .downloadable)
        try render("bedrock-download", view: VersionsView(game: .bedrock, initialTab: .downloads).environmentObject(model), size: NSSize(width: 650, height: 680))
        model.accounts = [:]
        try render("bedrock-unchecked", view: VersionsView(game: .bedrock, initialTab: .downloads).environmentObject(model), size: NSSize(width: 650, height: 680))
        try render("settings", view: SettingsView().environmentObject(model), size: NSSize(width: 650, height: 1100))
        XCTAssertNil(model.store)
        XCTAssertNil(model.diagnostics)
    }

    @MainActor
    func testTestedUpdateIsOfferedOncePerSessionAndRenders() throws {
        let model = AppModel(store: nil, diagnostics: nil)
        let old = Installation(version: "1.1.1.0", path: URL(fileURLWithPath: "/fixture/old"), bottle: "Old", managed: true, state: .ready)
        model.database.installations = [old]
        model.database.currentByGameId[old.gameId] = old.id
        model.running = true
        model.offerTestedUpdate()
        XCTAssertNil(model.testedUpdate)
        model.running = false
        model.offerTestedUpdate()
        let update = try XCTUnwrap(model.testedUpdate)
        XCTAssertEqual(update.game, .dungeons2)
        try render("tested-update", view: TestedReleaseUpdateView(update: update).environmentObject(model), size: NSSize(width: 600, height: 400), padding: 0)
        model.testedUpdate = nil
        model.offerTestedUpdate()
        XCTAssertNil(model.testedUpdate)
    }

    @MainActor
    private func render(_ name: String, view: some View, size: NSSize, padding: CGFloat = 28) throws {
        let host = NSHostingView(rootView: view.padding(padding).frame(width: size.width, height: size.height, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize, size)
        if let directory = ProcessInfo.processInfo.environment["MML_UI_PREVIEW_DIR"] {
            let destination = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: destination.appendingPathComponent(name + ".png"))
        }
    }
}
