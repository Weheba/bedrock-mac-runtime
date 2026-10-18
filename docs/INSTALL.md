# Install on another Mac

The release app contains the native launcher, account/download helper, compatibility
runtime and offline probes. No Xcode, Homebrew, Python, Rust, Terminal setup,
pre-existing game folder or copied CrossOver bottle is needed.

## Requirements

- Apple silicon Mac (M1 or newer), macOS 14 or newer. Intel is not supported.
- Separately installed, opened and licensed [CrossOver](https://www.codeweavers.com/crossover).
  Use the normal CrossOver.app in Applications or ~/Applications. Bedrock requires
  CrossOver 26.3.x and uses D3DMetal; CrossOver Beta is not supported.
- A Microsoft account with a valid license for the Windows game, internet access,
  and at least 35 GB free during installation.

## First launch

1. Download the arm64 DMG from [GitHub Releases](https://github.com/rafaelreverberi/Minecraft-on-Mac/releases/tag/v0.4.0).
2. Open the DMG and drag Minecraft on Mac.app to Applications. Eject the disk image.
   Alternatively, extract the app ZIP and move the app to Applications.
3. Open the app. This preview is ad-hoc signed, not Developer ID signed or notarized.
   If macOS blocks it, use System Settings → Privacy & Security → Open Anyway for
   this downloaded app, then confirm Open. Do not disable Gatekeeper globally.
4. Choose Dungeons II or Bedrock Edition and Install & Play. Complete Microsoft
   sign-in in Microsoft's window; approve macOS Keychain access for the bundled
   helper if requested. No account, game license or CrossOver license is bundled.
5. The launcher verifies ownership, downloads the official package and required
   Microsoft components, verifies integrity, extracts persistent game files,
   prepares its own CrossOver environment, then runs readiness checks.

Versions & Downloads → Install a Version always offers the latest tested build:
Dungeons II 1.1.2.0 or Bedrock 1.26.5203.0. Newer builds can be tried separately as
“Not tested · may work”. Downloads started from this page keep the current Play
selection; choose Select for Play under Installed when ready.

## Updating this launcher

Quit the launcher and games, replace only Minecraft on Mac.app with the new
release, then reopen it. Keep your library and CrossOver environments. If an older
game version is selected, the launcher offers Download & Select, or Select for
Play when the tested version is already installed. Later postpones the offer.
Existing Dungeons 1.1.2.0 trial installations are recognized as tested automatically.

## Storage and support

The DMG/ZIP in Downloads can be deleted after copying the app. Game installations
are under ~/Library/Application Support/Minecraft on Mac; owned environments and
saves are under CrossOver's Bottles folder. Delete games using Versions, not by
manually deleting arbitrary CrossOver folders. Saves are kept by default; separate
experimental environments keep separate saves. Back up worlds before switching.

For errors, use Report on GitHub in the error dialog or
[open an issue](https://github.com/rafaelreverberi/Minecraft-on-Mac/issues/new).
Do not post tokens, credentials, account identifiers or unreviewed raw logs.

Independent second-Mac acceptance remains to be confirmed. Dungeons gameplay was
reported working by the user on the development setup; this is not a guarantee
for every OS/CrossOver combination. The macOS 27.2 Advanced crash mitigation has
layout regression coverage, but the exact reporter OS was not available locally.
