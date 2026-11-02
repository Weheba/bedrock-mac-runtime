# Changelog

## 0.4.1 — 2026-11-02

- Fix Microsoft sign-in, ownership checks and Play failing with MICROSOFT_SERVICE_FAILED after Microsoft's late-October change to the Xbox token exchange.
- Refresh the stored device token before it expires instead of reusing it indefinitely.
- Install newer Bedrock versions such as 1.26.6005, whose game executable is stored unencrypted.
- No repeated keychain password prompts after updating the app; the launcher asks for one Microsoft sign-in instead.
- Paste and other edit shortcuts work in the Microsoft sign-in window.
- Account and install errors now end with a short step code for reports.

## 0.4.0 — 2026-10-18

- Promote user-tested Dungeons II 1.1.2.0 to the latest tested, pinned release while retaining the 1.1.1.0 profile.
- Offer tested game upgrades when the new launcher opens, with reuse of installed copies and an explicit Later option.
- Reorganize version selection/downloads for both Dungeons and Bedrock; separate Advanced maintenance.
- Support explicitly requested untested versions in separate owned environments.
- Verify Microsoft retail signatures and complete signed hash trees for unknown packages; fix legacy-CDN download rejection.
- Mitigate Advanced split-view layout crashes and add hosted layout coverage (exact macOS 27.2 confirmation pending).
- Add GitHub error-report links, safe error codes and AI-assisted development disclosure.
- Ship Apple silicon app ZIP and drag-to-Applications DMG, source and checksums. See [full release notes](docs/RELEASE-0.4.0.md).

## 0.3.1 — 2026-10-02

Restore Bedrock WinRT registrations after CrossOver updates to fix startup status 99. Add an API regression probe and verified helper reuse. [Release notes](docs/RELEASE-0.3.1.md).

## 0.3.0 — 2026-10-02

Native per-game launcher redesign, artwork, guarded game termination and packaged runtime provenance. [Release notes](docs/RELEASE-0.3.0.md).

## 0.2.1 — 2026-10-02

Managed Dungeons installation, native account/download helper and reversible version lifecycle.
