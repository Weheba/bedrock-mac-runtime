import SwiftUI
import LauncherCore

struct VersionAvailabilityView: View {
    let game: GameDefinition
    @EnvironmentObject var model: AppModel
    private var availability: VersionAvailability { model.versionAvailability(for: game) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Latest from Microsoft").font(.headline)
                    Text(availability.version ?? "Check for the latest version").font(.title3.weight(.semibold)).monospacedDigit()
                    if let checked = model.versionCheckedAt[game] {
                        Text("Checked \(checked.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Check for a newer version to try.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button { Task { await model.checkUpdates(game: game) } } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }.disabled(model.busy || model.running).accessibilityIdentifier("versions.checkUpdates")
            }
            switch availability.state {
            case .unchecked:
                Text("Checking only refreshes version information. You choose what to download.").font(.callout).foregroundStyle(.secondary)
            case .installed:
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("This version is installed", systemImage: "checkmark.circle.fill").foregroundStyle(LauncherArtwork.accent)
                        if availability.version != game.baseline {
                            Label("Not tested · may work", systemImage: "flask").foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let id = availability.installedID, id != model.current(for: game)?.id {
                        Text("Choose it under Installed").font(.caption).foregroundStyle(.secondary)
                    }
                }.font(.callout)
            case .downloadable:
                Label("Install the tested release above", systemImage: "arrow.down.circle")
                    .font(.callout).foregroundStyle(.secondary)
            case .untested:
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Not tested · may work", systemImage: "flask").font(.callout.weight(.medium))
                        Text("Installs separately. Choose it under Installed when you want to try it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Install Untested Version") {
                        if let version = availability.version {
                            Task { await model.installAndPlay(game: game, launch: false, untestedVersion: version) }
                        }
                    }.buttonStyle(.bordered).disabled(model.busy || model.running)
                        .accessibilityIdentifier("versions.downloadUntested")
                }
            case .tooOld:
                Text("This package is older than the latest tested version. Choose the tested download above.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if game == .bedrock {
                Text("Back up worlds before switching versions. Older versions do not restore older world data.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct LatestTestedReleaseView: View {
    let game: GameDefinition
    @EnvironmentObject var model: AppModel
    private var installed: Installation? {
        VersionAvailability.sorted(model.database.installations, game: game).first { $0.version == game.baseline && $0.state == .ready && !$0.usesUntestedVersion }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Latest tested version").font(.headline)
                    HStack(spacing: 10) {
                        Text(game.baseline).font(.title3.weight(.semibold)).monospacedDigit()
                        Label(installed == nil ? "Tested" : "Tested · installed", systemImage: "checkmark.seal.fill")
                            .font(.caption).foregroundStyle(LauncherArtwork.accent)
                    }
                }
                Spacer(minLength: 0)
                Button(installed == nil ? "Install \(game.baseline)" : "Reinstall \(game.baseline)") {
                    Task { await model.installAndPlay(game: game, launch: false, selectForPlay: false) }
                }.buttonStyle(.borderedProminent).tint(LauncherArtwork.accent)
                    .disabled(model.busy || model.running).accessibilityIdentifier("versions.downloadTested")
            }
            Text("Recommended. Installs this exact tested release. Your current Play selection stays unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct TestedReleaseUpdateView: View {
    let update: TestedReleaseUpdate
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("A new tested version is ready", systemImage: "checkmark.seal.fill")
                .font(.title2.weight(.semibold)).foregroundStyle(LauncherArtwork.accent)
            Text("\(update.game.name) \(update.game.baseline)").font(.title3.weight(.semibold))
            Text(update.installedID == nil ? "Would you like to download the latest tested version and select it for Play?" : "The latest tested version is already installed. Would you like to select it for Play?")
            Text("Your installed versions are kept. The Play selection changes only after verification succeeds.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Later") { model.testedUpdate = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(update.installedID == nil ? "Download & Select" : "Select for Play") {
                    Task { await model.acceptTestedUpdate(update) }
                }.buttonStyle(.borderedProminent).tint(LauncherArtwork.accent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 480)
    }
}
