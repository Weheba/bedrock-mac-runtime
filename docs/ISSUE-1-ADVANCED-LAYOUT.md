# Issue 1: Advanced layout crash

Source: https://github.com/rafaelreverberi/Minecraft-on-Mac/issues/1,
including both `.ips` files in its attached `Archive.zip` (inspected 2026-10-18).
Do not commit the raw reports, which contain machine-specific information.

## Evidence and diagnosis

Both reports identify launcher 0.3.1 on macOS 27.2, build `26B5091g`,
and an uncaught Objective-C exception ending in SIGABRT on the main thread.
Both exception backtraces reach
`-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]`.

The Dungeons report reaches that frame through
`NSHostingView.SizeConstraints.update(from:)`,
`SplitViewChildController.hostingView(_:didUpdateMinSize:maxSize:)`, and
`AppKitPlatformViewHost.enqueueLayoutInvalidation()` during constraint updates.
The Bedrock report instead includes `HostingScrollView.updateContext(_:)`,
`ScrollViewHelper.updateGraphState(isPreferred:)`, and hit testing during the
display cycle. Neither exception backtrace identifies a game/runtime operation.
The reports do not provide an exception reason sufficient to prove the precise
internal AppKit assertion.

The likely trigger is content-dependent size propagation from the scrolling
detail column into NavigationSplitView while Advanced inserts AppKit-backed
controls under an animated move/opacity transition. This is a diagnosis from
the stacks and code, not a confirmed reproduction of the 27.2 abort.

## Change

`LauncherDetailViewport` uses the available geometry to size the detail content,
so expanded content does not change the split column's minimum/ideal size.
Advanced and Versions now insert their controls without a layout animation.
Both games use this shared presentation; their maintenance actions, game launch,
authentication, files, and runtime configuration are unchanged.

## Verification

- Local host: macOS 27.0.1 (`26A434`), not the reporter's OS.
- Release configuration and local app packaging succeeded using
  `scripts/package_app.py --reuse-compatibility --reuse-native-helper` with the
  existing installed helper. The packager verified the retained runtime/helper
  digests, delivered Bedrock provenance, and the ad-hoc app signature. Output:
  `build/Minecraft on Mac.app`. The installed app was not replaced.
- `swift test`: core suite plus a hosted SwiftUI/AppKit layout regression test.
  The layout fixture changes between collapsed and expanded controls in the
  same NSHostingView, includes a long selectable path, and checks two viewport
  sizes. It does not load AppModel, access accounts, or start games.
- Negative control: temporarily bypassing the viewport made the layout test fail.
  The fixture's fitting size changed from 58 x 16 collapsed to 4055 x 445 expanded;
  with the viewport it stays 10 x 10 in both states. This demonstrates the size
  feedback being removed, not the original crash itself.
- The native UI automation could read the existing launcher but clicking and
  screenshots failed with `native pipe closed` / timeout. No successful manual
  click-through or 27.2 crash reproduction is claimed.

Before declaring the issue resolved on 27.2, open/close Advanced and Versions
repeatedly for both games, separately and together. Scroll to the bottom, resize
the window, change games, and hide/show the sidebar. Check the installed and
uninstalled states and the maintenance/account buttons' availability. No game
launch, sign-in, repair, or deletion is needed for this UI check.
