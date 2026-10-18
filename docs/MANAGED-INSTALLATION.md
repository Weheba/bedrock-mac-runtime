# Managed installation

The packaged Apple Silicon app includes its native account/download helper, the open-source Windows runtime and XCurl proxy, and offline ABI probes. No Homebrew, Python, Rust, MinGW or Xcode is needed on the destination Mac. Microsoft game files and SDK DLLs are downloaded directly from their publishers and never redistributed in the app.

CrossOver is still a separate licensed prerequisite. Install CrossOver in Applications (or ~/Applications), open it once and activate the user's license. Settings links to CodeWeavers. The launcher never clones the reference bottle, its credentials or its saved games.

“Sign In, Install & Play” opens native Microsoft sign-in when needed, verifies a real content license, chooses the latest tested package through its fixed version and revision, downloads the full encrypted package, verifies its revision-pinned SHA-256 and service-provided size, decrypts every required file locally, and verifies the recorded output. The extractor rejects absolute paths, traversal, duplicate case-insensitive paths, oversized packages and unexpected content IDs. It never invokes xodus run or keeps a mounted streaming overlay.

A transaction lives under Games/dungeons2/Versions/.staging-UUID. Microsoft components use pinned official SDK/NuGet archives and individual SHA-256s. Visual C++ is installed from Microsoft's pinned original redistributable. The native parsers handle ZIP/MSI/CAB, with no external extraction tools. Our bundled runtime/proxy have their own exact compatibility profile. For tested releases, the shipping executable and original libHttpClient must match the previously working game. For an explicitly requested untested trial, those game-owned files are checked against the downloaded package inventory instead; the bundled compatibility components retain their exact pinned hashes.

A dedicated Windows 11 CrossOver bottle carries an owner UUID receipt. Existing user bottles cannot be overwritten. Subsequent managed reinstalls share the owned environment across compatibility revisions. Local saves are stored below the bottle’s LOCALAPPDATA/Minecraft on Mac/Dungeons2/<authenticated XUID>/savedata, outside version folders. A launcher update repairs its own pinned compatibility components before Play when their digests change; game data is checked before repair. The launcher installs prerequisites and runs the Windows ABI, 61-export XCurl and seven-export runtime load checks before atomically committing the version. Downloads from Versions & Downloads keep the previous selection and return to Installed; command-line setup can still select and launch the installed copy. Errors preserve the previous current version; interrupted staging is shown in Storage for receipt-driven cleanup. Bottle/saves are preserved by version and staging cleanup.

Managed game authentication uses the same native account through an ephemeral localhost credential bridge. ChaCha20-Poly1305 protects bounded request/reply messages, binds direction and request nonces, and the broker rejects repeated nonces and nonallowlisted keys. Its random 256-bit key is passed through anonymous stdin and the game process environment only. No HTTP listener, command-line token, credential JSON/RON file, credential copy, or persisted authentication log is created. The broker exits when its parent pipe closes or the launch completes. Native and old Windows Xodus serialization is unchanged for the four allowed token entries.

Update checks consult the real service. Newer versions are marked “Not tested · may work” and can be explicitly downloaded to try in a separate environment. Trials preserve the current selection. Neither a successful download nor ABI verification promotes a trial to the latest tested release. Compatibility repair updates only pinned components in an owned environment after verifying game data. Full game-data damage requires a fresh download; the prior registered copy remains available. Downloads are bounded by size/read timeout; interruptions currently restart from a new staging transaction rather than resume encrypted ranges.

Distribution is an ad-hoc signed, unnotarized preview. Developer ID signing/notarization and a fully independent second-Mac login/download/gameplay/save test remain separate acceptance gates. See ACCEPTANCE.md for observed results.

The live package service uses a composite version (`1.1.1.0.package-GUID`); numeric build and package revision are recorded separately, so same-build Store revisions are detectable. The real service does not provide FileHash for this container. The builder captures its full SHA-256 in a developer-only bootstrap, requiring the unchanged reference header/hash-table prefix and verification of all data pages. The released helper has that tested revision pin built in. An explicit untested trial without an authenticated SHA-256 verifies the Microsoft retail RSA-PSS/SHA256 header signature with an independently recovered public key, binds the content ID and version to authenticated metadata, then verifies the signed hash-tree root, every intermediate node and every stored content page before parsing or extraction. Unsupported layouts or any mismatch are rejected. See [public anchor provenance](../NativeHelper/src/trust/README.md).

Microsoft's legacy assets1/2.xboxlive.com endpoint serves these already encrypted public containers over HTTP and has no valid HTTPS certificate for the supplied hostname. Only this credential-free, query-free legacy game payload can use HTTP, and only with the fixed package SHA-256 or mandatory Microsoft signature plus full signed hash-tree verification. Authentication, licensing and SDK downloads require validated HTTPS; certificate verification is never disabled. The bootstrap verifies the pinned reference prefix and all stored data-page hashes, following the [original XVD integrity implementation](https://github.com/emoose/xvdtool/blob/master/LibXboxOne/XVD/XVDFile.cs). No account token, cookie or license key is sent to the public asset host.

Version deletion removes its full transaction folder, including component cache. Current can be removed after confirmation and its selection is cleared. A rename to receipt-backed staging separates database commit from physical cleanup, with interrupted pre-commit removal restored on library open. Saves/environment are retained and reused by default; explicit deletion of the final unshared owned environment includes its saves. External copies only unregister. Microsoft login is separate.

## Bedrock and game isolation

The same transaction protocol also routes gameId bedrock / Store 9NBLGGH2JHXJ.
Its tested executable baseline is 1.26.5203.0, with a dedicated CrossOver 26.3.x
Windows 11 D3DMetal profile and WinRT/GameInput probes. Current versions and
retained environments are scoped by game. Protected files are extracted with
full decryption into SSD files; the encrypted package is never a Play dependency.
See [Bedrock details and acceptance limits](BEDROCK.md).

## Latest tested release and trials

The fixed tested catalog currently identifies Dungeons II 1.1.2.0 and Bedrock
1.26.5203.0, including their exact Microsoft package revision UUIDs and SHA-256s.
A tested download uses `GetSpecificBasePackage` rather than substituting whatever
`GetBasePackage` returns today. This request shape is documented by the
[original endpoint investigation](https://gist.github.com/rtm516/725fa1e38aafd2600976113ccc45a496).
Actual continued package hosting and account licensing remain under Microsoft's
control; an unavailable tested package produces an explicit error, never a
silent download of a different version. This is a version-specific official
Microsoft download, not a redistributed game archive.

An untested request binds the version shown when clicked and rechecks the returned
version before extraction. If Microsoft has changed the latest package, it asks
for a new update check. The experimental marker is persisted in the installation
receipt and preserved by snapshots, file verification, repair and launch. Trials
use a new owned CrossOver environment; a tested download does not reuse a retained
trial environment. Their saves are separate as a result. Users can switch back to
the tested installation explicitly in Versions.

Offline acceptance covers Swift version policy, compatible component hashes,
receipt migration, per-game UI rendering, Rust request routing and the fixed
revision/pin contract. Observed live acquisition checks are recorded in [download verification](DOWNLOAD-VERIFICATION.md).
Gameplay on a new release and Microsoft's continued availability of each old
package remain separate live acceptance checks.

## Dungeons 1.1.2.0 promotion (2026-10-18)

The user confirmed that the downloaded 1.1.2.0 release ran successfully after
in-game testing. The package had already passed independent retail signature and
full hash-tree/content verification (see DOWNLOAD-VERIFICATION.md). The tested
catalog now pins revision `ce1e7dbd-8b08-4b46-83c8-dfede30bd3f4` and SHA256
`5af8ccaf853f8db4c86a1f041701af54a0f1a08d224ddcd5273fdf07202f3b98`.
The new profile binds the shipping executable SHA256
`4dd569de727f267f1198dc90c7eea27440f12f174b55ed0a0d8be6e8e475b69d`
and retains every existing runtime/component hash. The old 1.1.1.0 profile remains
available for existing installations and rollback.

The original experimental receipt field is retained as installation history;
tested status comes from the bundled catalog. Previously installed 1.1.2.0 copies
use the new strict tested profile on verification/Play, without a redownload or
changes to their environment/saves. Future uncatalogued builds remain untested.

At startup or when visiting a game, the new launcher offers a newer tested
version once per game per session when the selected version is older. It reuses
an already ready installed copy or downloads the exact tested revision. Selection
changes only after verification succeeds. Later defers until the next session;
there is no background download, downgrade, deletion or automatic game launch.
This records user-reported gameplay success, not independent second-Mac,
multiplayer, or cross-environment save-migration acceptance.
