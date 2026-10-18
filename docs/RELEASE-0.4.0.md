Minecraft on Mac 0.4.0 brings tested **Dungeons II 1.1.2.0**, clearer version management for both games, and verified downloads for newer releases.

## What's new

- **Dungeons II 1.1.2.0 is Latest tested.** Its exact Microsoft package revision and SHA-256 are pinned, with a separate compatibility profile. The user successfully installed and gameplay-tested it. Existing 1.1.2.0 trial copies are recognized without downloading again; existing 1.1.1.0 copies remain usable.
- **Update prompt:** when an older version is selected, the new launcher offers Download & Select, reuses an already installed tested copy, or lets you choose Later. The selection changes only after verification succeeds. Nothing downloads in the background.
- **Versions & Downloads for Dungeons and Bedrock:** separate Installed / Install a Version tabs, clear latest-tested and latest-Microsoft versions, installed detection, update checks, and Select for Play. Advanced is a separate page.
- **Try newer versions:** “Not tested · may work” downloads install in separate owned environments and preserve the current selection. A successful download does not itself mark a version tested.
- **Newer-package download fix:** legacy Microsoft asset hosting no longer causes SECURE_DOWNLOAD_UNAVAILABLE. Unknown packages are authenticated using Microsoft's retail RSA-PSS/SHA256 signature and the complete signed hash tree before parsing/decryption. HTTPS certificate verification remains enabled; account/license traffic stays on HTTPS.
- **Advanced crash mitigation (#1):** isolates the SwiftUI detail viewport from split-view size feedback and removes animated control insertion. Regression-tested locally; the exact macOS 27.2 crash is not claimed reproduced or confirmed resolved on that OS.
- **Support and transparency:** error dialogs link to GitHub issue reporting, offer safe code details, and Settings includes the requested AI-assisted development/reverse-engineering disclosure.

## Download and install

Download **Minecraft-on-Mac-0.4.0-preview-arm64.dmg**, open it, and drag the app to Applications. The app ZIP is an alternative. For an update, quit games/the launcher and replace the app only; keep the library and CrossOver environments.

No developer tools, existing game folder, manual DLL setup or copied bottle are required. **CrossOver remains a separately installed and licensed prerequisite**, alongside an entitled Microsoft account. Apple silicon, macOS 14+, internet and 35 GB free during installation are required. Bedrock requires CrossOver 26.3.x / D3DMetal. Intel and CrossOver Beta are unsupported.

This is an **ad-hoc signed, unnotarized preview**. macOS may require Open Anyway in Privacy & Security on first launch. An independent second-Mac installation has not yet been verified. See [the first-run guide](https://github.com/rafaelreverberi/Minecraft-on-Mac/blob/v0.4.0/docs/INSTALL.md).

## Validation and boundaries

- 58 Swift/core/layout tests completed with no failures; 2 existing opt-in live tests skipped. 13 native-helper tests passed, including signature/header/tree/content tampering and source-policy rejection. 2 credential-bridge tests and 4 Python integrity tests passed.
- Full encrypted Dungeons 1.1.2.0 (9,805,545,472 bytes) and Bedrock 1.26.5203.0 (2,069,975,040 bytes) passed live retail-signature and complete hash-tree/content verification. The user subsequently installed and successfully gameplay-tested Dungeons 1.1.2.0.
- Hosted UI previews cover both games, versions, settings and the tested-update dialog. Strict app signatures, helper/resource digests and delivered Bedrock provenance are checked during packaging.
- Independent second-Mac, exact macOS 27.2 crash behavior, multiplayer, and cross-environment save migration are separate unverified boundaries.

Assets include the DMG, app ZIP, corresponding source ZIP and SHA256SUMS-0.4.0.txt. Game data, Microsoft SDK binaries, credentials, CrossOver and saves are not redistributed. Unofficial; not affiliated with Mojang, Microsoft or CodeWeavers.
