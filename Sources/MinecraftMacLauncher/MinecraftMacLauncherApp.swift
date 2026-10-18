import SwiftUI
import AppKit
import LauncherCore

@main
struct MinecraftMacLauncherApp: App {
    @StateObject private var model = AppModel()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        WindowGroup("Minecraft on Mac") { LauncherView().environmentObject(model).frame(minWidth: 900, minHeight: 650).task { await model.load(); NSApplication.shared.activate(ignoringOtherApps: true); if ProcessInfo.processInfo.arguments.contains("--smoke-launch-current") { await model.play() }; if ProcessInfo.processInfo.arguments.contains("--setup") { await model.installAndPlay() }; if ProcessInfo.processInfo.arguments.contains("--setup-bedrock") { await model.installAndPlay(game: .bedrock) }; if ProcessInfo.processInfo.arguments.contains("--repair-current"), let current = model.current { await model.repair(current); if model.error == nil { await model.play() } } } }
        Settings { ScrollView { SettingsView().environmentObject(model).padding(24) }.frame(width: 640, height: 650) }
    }
}
enum Page: String, CaseIterable, Identifiable {
    case dungeons = "Dungeons II", bedrock = "Bedrock Edition", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self { case .dungeons: "shield.lefthalf.filled"; case .bedrock: "cube.fill"; case .settings: "gearshape" }
    }
}
struct LauncherView: View {
    @EnvironmentObject var model: AppModel
    @State private var page: Page? = ProcessInfo.processInfo.arguments.contains("--setup-bedrock") ? .bedrock : .dungeons
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
            List(selection: $page) {
                Section("Games") { row(.dungeons); row(.bedrock) }
                Section { row(.settings) }
            }.listStyle(.sidebar)
            HStack(spacing: 10) {
                Image(nsImage: LauncherArtwork.image("launcher-mac")).resizable().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Minecraft on Mac").font(.system(size: 12, weight: .semibold))
                    Text("Unofficial launcher").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            // Keep the split column's size independent of the scroll content's
            // minimum size. Expanding maintenance controls must not feed new
            // constraints back into NSSplitView during its constraint update.
            LauncherDetailViewport {
                VStack(spacing: 0) {
                    ScrollViewReader { scroll in
                        ScrollView {
                            Group {
                                switch page ?? .dungeons {
                                case .dungeons: GameView(game: .dungeons2, onNavigate: { scroll.scrollTo("game-top", anchor: .top) })
                                case .bedrock: GameView(game: .bedrock, onNavigate: { scroll.scrollTo("game-top", anchor: .top) })
                                case .settings: SettingsView().padding(30)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).id("game-top")
                        }
                        .onChange(of: page) { _, _ in scroll.scrollTo("game-top", anchor: .top) }
                    }
                    if let progress = model.progress {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.phase).font(.headline)
                            if let fraction = progress.fraction { ProgressView(value: fraction) } else { ProgressView().controlSize(.small) }
                            if progress.total > 0 { Text(progress.phase.contains("Downloading") || ["Preparing game files", "Verifying encrypted package"].contains(progress.phase) ? "\(ByteCountFormatter.string(fromByteCount: progress.completed, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file))" : "\(progress.completed) / \(progress.total) files").font(.caption).foregroundStyle(.secondary) }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                    }
                    if !model.message.isEmpty { Text(model.message).font(.callout).foregroundStyle(.secondary).padding().frame(maxWidth: .infinity, alignment: .leading) }
                }.background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onChange(of: page, initial: true) { _, value in
            if value == .bedrock { model.selectedGame = .bedrock }
            else if value == .dungeons { model.selectedGame = .dungeons2 }
            if value != .settings { model.offerTestedUpdate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await model.refresh() } }
        .sheet(item: $model.testedUpdate) { update in
            TestedReleaseUpdateView(update: update).environmentObject(model)
        }
        .alert("Operation could not finish", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }), presenting: model.error) { error in
            Button("OK") { model.error = nil }
            Button("Report on GitHub…") { model.open(ProjectSupport.issueURL(errorCode: error.code)) }
            Button("Copy Details") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(error.errorDescription ?? "", forType: .string) }
        } message: { error in Text((error.errorDescription ?? "") + "\n\nIf this keeps happening, please report it on GitHub.") }
    }
    func row(_ page: Page) -> some View {
        HStack(spacing: 12) {
            if page == .settings {
                Image(systemName: page.symbol).frame(width: 28)
            } else {
                Image(nsImage: LauncherArtwork.image(page == .bedrock ? "bedrock" : "dungeons", extension: "jpg"))
                    .resizable().scaledToFill().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text(page.rawValue).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }.padding(.vertical, 6).tag(page)
    }
}
/// A split column fills the available viewport, regardless of expanded content.
struct LauncherDetailViewport<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { viewport in
            content.frame(width: viewport.size.width, height: viewport.size.height)
        }
    }
}

enum LauncherArtwork {
    static func image(_ name: String, extension ext: String = "png") -> NSImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources/Artwork"),
              let image = NSImage(contentsOf: url) else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return image
    }
    static let accent = Color(red: 0.32, green: 0.68, blue: 0.25)
}

enum GameSection: Equatable { case overview, versions, advanced }

struct GameView: View {
    let game: GameDefinition
    @EnvironmentObject var model: AppModel
    private let onNavigate: () -> Void
    @State private var section: GameSection
    init(game: GameDefinition, initialSection: GameSection = .overview, onNavigate: @escaping () -> Void = {}) {
        self.game = game
        self.onNavigate = onNavigate
        _section = State(initialValue: initialSection)
    }
    private var installations: [Installation] { model.database.installations.filter { $0.game == game } }
    var body: some View {
        Group {
            switch section {
            case .overview: overview
            case .versions:
                VStack(alignment: .leading, spacing: 24) {
                    sectionHeader("Versions & Downloads")
                    VersionsView(game: game, onNavigate: onNavigate)
                }.padding(28)
            case .advanced:
                VStack(alignment: .leading, spacing: 24) {
                    sectionHeader("Advanced")
                    maintenance
                }.padding(28)
            }
        }.id(game).onChange(of: section) { _, _ in onNavigate() }
    }
    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { section = .overview } label: {
                Label("Back to \(game == .bedrock ? "Bedrock Edition" : "Dungeons II")", systemImage: "chevron.left")
            }.buttonStyle(.borderless).accessibilityIdentifier("game.back")
            VStack(alignment: .leading, spacing: 5) {
                Text(game == .bedrock ? "BEDROCK EDITION" : "DUNGEONS II").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                Text(title).font(.title.bold())
            }
        }
    }
    private var maintenance: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Maintenance").font(.title3.bold())
            if let install = model.current(for: game) {
                HStack {
                    Button("Verify Files") { Task { await model.verify(install) } }.disabled(model.busy || model.running)
                    Button("Repair") { Task { await model.repair(install) } }.disabled(!install.managed || model.busy || model.running)
                    Button("Open Folder") { model.open(install.path) }
                }.buttonStyle(.bordered)
                LabeledContent("Environment", value: install.bottle)
                LabeledContent("Storage", value: ByteCountFormatter.string(fromByteCount: install.storageBytes ?? install.diskBytes, countStyle: .file))
                Text(install.path.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Button("Open Versions & Downloads") { section = .versions }
            }.disabled(model.busy || model.running)
            AccountView(game: game)
            GameImportOptionsView(game: game)
            if game == .bedrock {
                Text("Bedrock 1.26.5203.0 · CrossOver 26.3.x · D3DMetal").font(.caption).foregroundStyle(.secondary)
                Text("Back up worlds before changing versions. Choosing an older game version does not restore world data.").font(.callout).foregroundStyle(.secondary)
                BedrockStorageView()
            }
            Text("File verification checks the installation and runtime. Gameplay, saves and multiplayer require separate live testing.").font(.caption).foregroundStyle(.secondary)
            Link("Microsoft GDK license", destination: URL(string: "https://github.com/microsoft/GDK/blob/main/LICENSE.md")!)
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                Image(nsImage: LauncherArtwork.image(game == .bedrock ? "bedrock" : "dungeons", extension: "jpg"))
                    .resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height, alignment: .top).clipped()
                    .overlay {
                        ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MINECRAFT ON MAC").font(.system(size: 11, weight: .bold)).tracking(3).foregroundStyle(.white.opacity(0.8))
                            Text(game == .bedrock ? "Minecraft" : "Minecraft Dungeons II")
                                .font(.system(size: game == .bedrock ? 44 : 34, weight: .heavy)).foregroundStyle(.white)
                            Text(game == .bedrock ? "BEDROCK EDITION" : "WINDOWS EDITION")
                                .font(.system(size: 12, weight: .semibold)).tracking(2).foregroundStyle(.white.opacity(0.85))
                        }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
            }.aspectRatio(2.2, contentMode: .fit).accessibilityLabel(game.name)
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 20) {
                    if !installations.isEmpty {
                        Button { section = .versions } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SELECT VERSION").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    Text(model.current(for: game)?.version ?? "Choose a version").font(.title3.weight(.semibold)).monospacedDigit()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                                Text("Manage versions & updates").font(.caption).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("versions.toggle")
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(model.current(for: game).map { $0.state != .ready ? "Verification needed" : $0.usesUntestedVersion ? "Not tested · may work" : "Ready to play" } ?? "Choose a version").font(.callout.weight(.medium))
                            Text(model.accounts[game]?.gamertag ?? "Microsoft account").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Install \(game == .bedrock ? "Bedrock Edition" : "Dungeons II")").font(.title3.bold())
                            Text("Sign in to download your game and set up CrossOver automatically.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    Button { Task {
                        if model.current(for: game) != nil { await model.play(game: game) }
                        else { section = .versions }
                    } } label: {
                        Label(model.runningGames.contains(game) ? "Game running" : model.current(for: game) != nil ? "Play" : installations.isEmpty ? "Install a Version" : "Select Version", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .bold)).frame(minWidth: 125).padding(.vertical, 9)
                    }.buttonStyle(.borderedProminent).tint(LauncherArtwork.accent)
                        .disabled(model.busy || model.running)
                    if model.runningGames.contains(game) {
                        Button { Task { await model.quitGame(game) } } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                                .frame(width: 22, height: 22).padding(.vertical, 9)
                        }.buttonStyle(.borderedProminent).tint(.red)
                            .disabled(model.quittingGame != nil)
                            .help("Force quit this game. Unsaved progress will be lost.")
                            .accessibilityLabel("Force quit \(game.name)")
                    }
                }
                if installations.isEmpty {
                    Label("Requires licensed CrossOver, game ownership and 35 GB of free space.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Button { section = .versions } label: {
                        Label("Versions & Downloads", systemImage: "square.stack.3d.up")
                    }.buttonStyle(.borderless)
                    Text("\(installations.count) installed").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { section = .advanced } label: {
                        Label("Advanced", systemImage: "gearshape")
                    }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                Text("Unofficial launcher · Not affiliated with Mojang or Microsoft").font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(28)
        }.id(game)
    }
}
struct BedrockStorageView: View {
    private let game: GameDefinition = .bedrock
    @EnvironmentObject var model: AppModel
    @State private var pendingEnvironment: String?
    @State private var pendingStaging: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Bedrock storage and environment") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Open Bedrock Data") { model.open(LibraryStore.defaultRoot.appendingPathComponent("Games/bedrock")) }
                    ForEach(model.database.retainedEnvironmentsByGameId[game.rawValue] ?? [], id: \.self) { name in
                        Text("Saved Bedrock environment: \(name)").font(.callout)
                        Text("Kept for your worlds; reused on the next Bedrock installation.").font(.caption).foregroundStyle(.secondary)
                        Button("Delete Bedrock Environment and Worlds…", role: .destructive) { pendingEnvironment = name }.disabled(model.busy || model.running)
                    }
                    ForEach(model.staging.filter { $0.hasPrefix("bedrock/") }, id: \.self) { name in
                        HStack { Text("Interrupted Bedrock installation"); Spacer(); Button("Delete Temporary Files…") { pendingStaging = name }.disabled(model.busy || model.running) }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog("Permanently delete this Bedrock environment and all its worlds?", isPresented: Binding(get: { pendingEnvironment != nil }, set: { if !$0 { pendingEnvironment = nil } }), titleVisibility: .visible) {
            if let name = pendingEnvironment { Button("Delete Bedrock Environment and Worlds", role: .destructive) { pendingEnvironment = nil; Task { await model.perform { try await model.store?.removeRetainedEnvironment(name) } } } }
        } message: { Text("Deletes only this retained, launcher-owned Bedrock environment. Other game environments and the Microsoft Keychain login are preserved.") }
        .confirmationDialog("Delete interrupted Bedrock installation?", isPresented: Binding(get: { pendingStaging != nil }, set: { if !$0 { pendingStaging = nil } }), titleVisibility: .visible) {
            if let name = pendingStaging { Button("Delete Temporary Files", role: .destructive) { Task { await model.perform { try await model.store?.removeStaging(name) } }; pendingStaging = nil } }
        }
    }
}
struct BottlePicker: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("CrossOver bottle", selection: $model.selectedBottle) {
            if model.bottles.isEmpty { Text("No bottles detected").tag("") }
            ForEach(model.bottles, id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 440)
    }
}
struct VersionsView: View {
    let game: GameDefinition
    @EnvironmentObject var model: AppModel
    @State private var pendingRemoval: Installation?
    @State private var removeEnvironment = false
    @State private var cloneConfirmation: Installation?
    private var installationsAreEmpty: Bool { !model.database.installations.contains { $0.game == game } }
    @State private var tab: VersionTab
    private let onNavigate: () -> Void
    enum VersionTab: String, CaseIterable { case installed = "Installed", downloads = "Install a Version" }
    init(game: GameDefinition, initialTab: VersionTab = .installed, onNavigate: @escaping () -> Void = {}) {
        self.game = game
        self.onNavigate = onNavigate
        _tab = State(initialValue: initialTab)
    }
    private var installationIDs: Set<UUID> { Set(model.database.installations.filter { $0.game == game }.map(\.id)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Versions workspace", selection: $tab) {
                ForEach(VersionTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().tint(LauncherArtwork.accent).accessibilityIdentifier("versions.workspace")
            switch tab {
            case .installed:
                installedVersions
            case .downloads:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install a version").font(.title3.bold())
                    Text("Choose the tested release, or check Microsoft for a newer version to try.").font(.callout).foregroundStyle(.secondary)
                }
                LatestTestedReleaseView(game: game)
                Divider()
                VersionAvailabilityView(game: game)
            }
        }
        .onAppear { if installationsAreEmpty { tab = .downloads } }
        .onChange(of: tab) { _, _ in onNavigate() }
        .onChange(of: installationIDs) { old, new in
            if !new.subtracting(old).isEmpty { tab = .installed }
        }
        .sheet(item: $pendingRemoval) { install in
            VStack(alignment: .leading, spacing: 16) {
                Text(install.managed ? "Delete Version \(install.version)?" : "Unregister local installation?").font(.title2.bold())
                Text(install.managed ? "Deletes the complete version folder, including game files, downloaded component cache and installation metadata." : "Removes this entry from the launcher. Your original game files and environment are preserved.")
                if install.id == model.database.currentByGameId[install.gameId] { Text("This is the current installation. Start Game will be unavailable until you select or install another copy.").foregroundStyle(.secondary) }
                if install.managed && install.isOfficialManaged {
                    let shared = model.database.installations.contains { $0.id != install.id && $0.bottle == install.bottle }
                    Toggle("Also delete this game's environment and all its saves", isOn: $removeEnvironment).disabled(shared)
                    Text(shared ? "Another version uses this environment, so it must be kept." : "Off by default. Enabling this permanently removes the owned CrossOver environment and its saved games. Microsoft Keychain login is preserved.").font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Cancel") { pendingRemoval = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(install.managed ? "Delete Version" : "Unregister", role: .destructive) {
                        let deleteEnvironment = removeEnvironment
                        pendingRemoval = nil
                        Task { await model.remove(install, removeEnvironment: deleteEnvironment) }
                    }.disabled(model.busy || model.running)
                }
            }.padding(24).frame(width: 520)
        }
        .confirmationDialog("Create a managed snapshot?", isPresented: Binding(get: { cloneConfirmation != nil }, set: { if !$0 { cloneConfirmation = nil } }), titleVisibility: .visible) {
            if let install = cloneConfirmation { Button("Clone and Verify") { Task { await model.clone(install) }; cloneConfirmation = nil } }
        } message: { Text("Copies this local installation using APFS copy-on-write and hashes all game files. This can take several minutes. Current selection stays available.") }

    }
    private var installedVersions: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Installed versions").font(.title3.bold())
                    Text("Select a version for Play, then start it here.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let current = model.current(for: game) {
                    Button { Task { await model.play(game: game) } } label: {
                        Label("Play \(current.version)", systemImage: "play.fill")
                    }.buttonStyle(.borderedProminent).tint(LauncherArtwork.accent)
                        .disabled(current.state != .ready || model.busy || model.running)
                }
            }
            if installationsAreEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No versions installed yet.").foregroundStyle(.secondary)
                    Button("Install a Version") { tab = .downloads }.buttonStyle(.borderedProminent).tint(LauncherArtwork.accent)
                }
            }
            ForEach(VersionAvailability.sorted(model.database.installations, game: game)) { install in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(install.version).font(.headline).monospacedDigit()
                                if install.usesUntestedVersion {
                                    Label("Not tested · may work", systemImage: "flask").font(.caption).foregroundStyle(.secondary)
                                } else if install.version == game.baseline {
                                    Text("Latest tested").font(.caption).foregroundStyle(.secondary)
                                }
                                if install.id == model.database.currentByGameId[install.gameId] {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LauncherArtwork.accent).accessibilityLabel("Selected for Play")
                                }
                            }
                            Text("\(install.displayKind) · \(ByteCountFormatter.string(fromByteCount: install.storageBytes ?? install.diskBytes, countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                            if install.state != .ready {
                                Label("Verification needed", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(install.id == model.current(for: game)?.id ? "Selected" : "Select for Play") { Task { await model.select(install) } }
                            .disabled(install.id == model.database.currentByGameId[install.gameId] || install.state != .ready || model.busy || model.running)
                        Menu {
                            Button("Show in Finder") { NSWorkspace.shared.open(install.managed ? install.path.deletingLastPathComponent() : install.path) }
                            Button("Verify Files") { Task { await model.verify(install) } }
                            Button("Create Snapshot…") { cloneConfirmation = install }
                            Divider()
                            Button(install.managed ? "Delete Version…" : "Unregister…", role: .destructive) { removeEnvironment = false; pendingRemoval = install }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().help("Manage version \(install.version)")
                        .disabled(model.busy || model.running)
                    }
                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(install.managed ? "Removing this version keeps your saves unless you explicitly choose to delete its environment." : "External installation. Unregistering keeps the original files.")
                            Text(install.path.path).font(.caption.monospaced()).textSelection(.enabled)
                            LabeledContent("Environment", value: install.bottle)
                            if model.developerMode { Text(install.compatibilityProfile).font(.caption.monospaced()) }
                        }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
                Divider()
            }
        }
    }

}
struct GameImportOptionsView: View {
    let game: GameDefinition
    @EnvironmentObject var model: AppModel
    @State private var clearCurrent = false
    var body: some View {
        DisclosureGroup("Import & selection options") {
            VStack(alignment: .leading, spacing: 12) {
                if game == .dungeons2 {
                    BottlePicker()
                    Button("Register Existing Installation…") { model.chooseInstallation() }.disabled(model.busy || model.selectedBottle.isEmpty || model.running)
                }
                if let current = model.current(for: game) {
                    if game == .dungeons2 {
                        Button("Change Bottle") { Task { await model.perform { try await model.store?.changeBottle(current.id, bottle: model.selectedBottle) } } }.disabled(model.busy || model.running)
                    }
                    Button("Clear Current Selection…") { clearCurrent = true }.disabled(model.busy || model.running)
                }
            }.padding(.top, 12)
        }
        .confirmationDialog("Clear current selection?", isPresented: $clearCurrent, titleVisibility: .visible) {
            Button("Clear Selection") { Task { await model.perform { try await model.store?.clearSelection(game: game) } } }
        } message: { Text("Select an installed version in Versions & Downloads to enable Play again.") }
    }
}
struct DownloadsView: View {
    var body: some View {
        ContentUnavailableView { Label("Downloads", systemImage: "arrow.down.circle") } description: {
            Text("Open Versions & Downloads → Install a Version on the game page to choose a download.")
        }
    }
}
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var cacheConfirmation = false
    @State private var pendingStaging: String?
    @State private var pendingEnvironment: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.largeTitle.bold())
            GroupBox("CrossOver") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.crossOver == nil ? "CrossOver not detected" : "CrossOver detected").font(.headline)
                    BottlePicker()
                    if let crossover = model.crossOver {
                        Button("Open Selected Bottle") { if let url = try? crossover.bottleURL(model.selectedBottle) { model.open(url) } }
                    }
                    Link("Download CrossOver from CodeWeavers", destination: URL(string: "https://www.codeweavers.com/crossover")!)
                    Text("The launcher creates its own game environment automatically. The bottle picker is only needed for external installations.").font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Storage") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Open Launcher Data") { model.open(LibraryStore.defaultRoot) }
                    Button("Clear Download Cache…") { cacheConfirmation = true }.disabled(model.busy || model.running)
                    ForEach(model.database.retainedEnvironments ?? [], id: \.self) { name in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Saved game environment (no installed version)").font(.callout)
                            Text("Kept for your saves; reused on the next installation.").font(.caption).foregroundStyle(.secondary)
                            Button("Delete Environment and Saves…", role: .destructive) { pendingEnvironment = name }.disabled(model.busy || model.running)
                        }
                    }
                    ForEach(model.staging.filter { !$0.hasPrefix("bedrock/") }, id: \.self) { name in
                        HStack { Text("Interrupted snapshot").font(.callout); Spacer(); Button("Delete Temporary Files…") { pendingStaging = name }.disabled(model.busy || model.running) }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            DisclosureGroup("Advanced") {
                DiagnosticsView().padding(.vertical, 12)
            }
            Toggle("Developer Mode", isOn: $model.developerMode)
            GroupBox("Dependencies") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(DependencyManager.inspect(developerMode: model.developerMode)) { dependency in
                        HStack { Image(systemName: dependency.available ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(dependency.available ? .green : .secondary); Text(dependency.name); Spacer(); Text(dependency.requiredForPlay ? "Play" : "Development").font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(8)
            }
            Text("No telemetry. Credentials are never included in diagnostics. Native Microsoft credentials use a separate macOS Keychain namespace. The reference game retains its existing login.").font(.caption).foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Link("Report a problem on GitHub ↗", destination: ProjectSupport.issueURL())
                Text("Built with assistance from AI. AI tools also assisted the reverse engineering and compatibility research behind this project.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

        }
        .confirmationDialog("Permanently delete this environment and all its saves?", isPresented: Binding(get: { pendingEnvironment != nil }, set: { if !$0 { pendingEnvironment = nil } }), titleVisibility: .visible) {
            if let name = pendingEnvironment { Button("Delete Environment and Saves", role: .destructive) { pendingEnvironment = nil; Task { await model.perform { try await model.store?.removeRetainedEnvironment(name) } } } }
        } message: { Text("Deletes only this retained, launcher-owned CrossOver environment. Microsoft Keychain login and other game environments are preserved.") }
        .confirmationDialog("Clear download cache?", isPresented: $cacheConfirmation, titleVisibility: .visible) {
            Button("Clear Cache", role: .destructive) { Task { await model.perform { try await model.store?.clearCache(); try await model.diagnostics?.record(.cacheCleared) } } }
        } message: { Text("Installed versions and saved games are preserved.") }
        .confirmationDialog("Delete interrupted snapshot?", isPresented: Binding(get: { pendingStaging != nil }, set: { if !$0 { pendingStaging = nil } }), titleVisibility: .visible) {
            if let name = pendingStaging { Button("Delete Temporary Files", role: .destructive) { Task { await model.perform { try await model.store?.removeStaging(name) } }; pendingStaging = nil } }
        }
    }
}
struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Diagnostics").font(.largeTitle.bold())
            Text("Reports contain fixed event codes, timestamps and process exit status. Raw game output is discarded because it can contain authentication secrets.").foregroundStyle(.secondary)
            Button("Export Diagnostic Report…") { model.exportDiagnostics() }
            GroupBox("Validation scope") {
                Text("The bundled compatibility profile pins the known game build and DLL hashes. Live menu, gameplay, save persistence and multiplayer must be confirmed separately. Native ABI probes are maintained in the developer test suite.").padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.developerMode {
                Button("Open Launcher Data") { model.open(LibraryStore.defaultRoot) }
                if let current = model.current {
                    ForEach(current.hashes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading) { Text(key).font(.caption.bold()); Text(value).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
            }
        }
    }
}

struct AccountView: View {
    var game: GameDefinition = .dungeons2
    @EnvironmentObject var model: AppModel
    @State private var signOut = false
    var body: some View {
        GroupBox("Microsoft package account") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Account", value: model.accounts[game]?.gamertag ?? (model.accounts[game]?.signedIn == true ? "Connected" : "Not checked"))
                LabeledContent("Content license", value: model.accounts[game]?.entitlement == "verified" ? "Verified by Microsoft" : "Not verified")
                LabeledContent("Available package", value: model.accounts[game]?.availableVersion ?? "Not checked")
                HStack {
                    Button("Sign In") { Task { await model.accountOperation(.login, game: game) } }
                    Button("Check Ownership / Updates") { Task { await model.accountOperation(.check, game: game) } }
                    Button("Sign Out…") { signOut = true }
                }.disabled(model.busy || model.running)
                Text("Managed installations use this same Microsoft login through the macOS Keychain bridge. External reference installations retain their existing account.").font(.caption).foregroundStyle(.secondary)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Sign out of the native package account?", isPresented: $signOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await model.accountOperation(.logout, game: game) } }
        } message: { Text("Removes only this launcher's Microsoft Keychain entries. The working game's current login stays intact. Sign in again to switch the native package account.") }
    }
}
