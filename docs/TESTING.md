# Testing

iInteract ships on **iPhone, iPad, and Mac Catalyst** (and a separate
watchOS extension). The `iInteractTests` target compiles against the
shared iOS code, so the same Swift unit tests can run on each
destination. `iInteractUITests` is iOS-only.

## Running locally

**Inner loop (fast — single destination, what most edits need):**

```bash
./scripts/test-matrix.sh fast       # iPhone simulator only
```

This is the iPhone simulator destination the project's default
`xcodebuild test` already uses; running it explicitly via the script
keeps the destination pin in one place.

**Full matrix (catches platform drift):**

```bash
./scripts/test-matrix.sh            # iPhone + iPad + Mac Catalyst
```

~3× slower than `fast`. Run before pushing anything that touches
UIKit, layout, or platform-conditional code. CI runs this on every
push.

**Single destination:**

```bash
./scripts/test-matrix.sh iphone
./scripts/test-matrix.sh ipad
./scripts/test-matrix.sh catalyst
```

## What's covered

| Platform | Coverage |
|---|---|
| iPhone simulator | Unit tests + UI tests |
| iPad simulator | Same unit tests as iPhone (UI tests too, but layouts not validated) |
| Mac Catalyst | **Build-only.** No tests run. The unit test code is platform-portable Swift exercised by the iPhone + iPad runs; Catalyst-specific issues (UIKit-vs-AppKit drift, deployment-target floors, entitlement mismatches) all show up at build/link time, not test-runtime. Catalyst test runs would also need a dev team for `iInteractUITests` and CloudKit entitlements that survive ad-hoc signing — fragile setup for duplicate coverage. |
| watchOS | **Not covered.** `iInteractWatch` has no test target. |

The unit tests target shared logic (`PanelStore`, `PINGate`,
`PushQueue`, `CloudKitAssetStore`, the various coordinators) that
compiles identically on every iOS variant — so iPad and Mac Catalyst
runs catch conditional-compilation drift, deployment-target floor
issues, and any sneaky `#if` branches. They do *not* exercise iPad
popover layouts, Mac Catalyst-specific UI paths, or anything in the
watch extension.

## When to add a watch test target

Manual smoke testing on a watch simulator is the right
cost-benefit-ratio today — the watch code is a thin shell over
`events.plist` and `Event` model parsing. Add an `iInteractWatchTests`
target when:

- The watch sync logic in `WatchSync` and `iInteractWatch/InterfaceController`
  grows beyond simple panel-order display.
- A watch-side bug ships and slips past manual testing.
- You start sharing model code between iOS and watchOS that needs
  per-platform regression coverage.

Until one of those is true, a separate watch test bundle is
infrastructure overhead without payoff.

## Updating destinations

If Xcode's installed simulators change, update the `*_DEST` constants
at the top of `scripts/test-matrix.sh`. List currently installed
destinations with:

```bash
xcodebuild -showdestinations -scheme iInteract
```
