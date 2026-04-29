# CloudKit Migration — v3.1 / v4 Sketch

Status: design sketch, not yet implemented.
Branch: planned for `cloudkit` off current bug-fix line.

## Why CloudKit (not iCloud Drive)

The app currently uses `NSUbiquitousKeyValueStore` (KVS) for cross-device
sync, which has a **1 MB total quota per app**. That's plenty for
metadata (titles, colors, hashes) but a single voice recording is
~50–200 KB and a panel image can be hundreds of KB. So media was
deliberately scoped out of sync at v3.0 and stored locally in
Application Support.

The user-visible cost: a parent who records 30 minutes of custom voice
on the iPhone gets none of it on a second iPad signed into the same
Apple ID. New device = re-record everything. For our user base
(parents customizing for kids with special needs), that effort is
significant and the multi-device scenario is real (home iPad + school
iPad, device upgrades).

**iCloud Drive container** would be ~20 lines but exposes files in
the user's Files app — a parent or kid can browse / move / delete
`recording_panel3.mp3` and break the app.

**CloudKit private database** is invisible to the user, properly
sandboxed (~1 GB free per user, scales with iCloud subscription),
schema-aware, and the right primitive for any future feature like
"share a panel set with a therapist."

## Scope — what moves vs. what stays

CloudKit is for the heavy stuff. KVS keeps doing what it does well.

| Data | Storage | Why |
|---|---|---|
| Built-in panels | Bundled (unchanged) | Read-only, no sync needed |
| Mode | KVS (unchanged) | Tiny, KVS already works |
| PIN hash + question + answer hash | KVS (unchanged) | Tiny, security-sensitive, keep boring |
| Layout (visible/hidden + order) | KVS (unchanged) | Tiny, frequent writes, KVS handles well |
| Custom user panels (titles, colors) | CloudKit | Per-user, multi-device |
| Interactions (linked to user panels) | CloudKit | Per-user, multi-device |
| **Audio MP3s** | CloudKit (`CKAsset`) | The actual fix |
| **Pictures** | CloudKit (`CKAsset`) | The actual fix |

The migration is therefore **narrower than "replace KVS with
CloudKit"** — KVS stays. Only custom panels + their interactions +
binary assets move.

## Schema

**Private database**, single zone (`iInteractZone`).

### `UserPanel` record
- `panelID`: String (UUID, indexed) — same as `Panel.id`
- `title`: String
- `colorRGBA`: Bytes — encoded the same way the JSON Codable does today
- `createdAt`, `modifiedAt`: Date (CloudKit fills `modifiedAt`
  automatically via change tags)

### `Interaction` record
- `interactionID`: String (UUID, indexed)
- `panelRef`: `CKRecord.Reference` → `UserPanel` (cascade delete)
- `displayName`: String
- `audioAsset`: `CKAsset` (nullable until recorded)
- `imageAsset`: `CKAsset` (nullable until set)
- `order`: Int64 (within parent panel)

That's it. ~2 record types, ~10 fields. No deeper hierarchy needed.

## Architecture — local-first, CloudKit as mirror

**Critical design decision**: don't make `PanelStore` async. Keep its
current synchronous API. Add a `CloudKitMirror` actor alongside that
listens for local changes and pushes/pulls in the background.

```
PanelStore (sync) ←—local source of truth—→ Application Support files
        ↓ NSNotification on every write
CloudKitMirror (async actor)
        ↓ pushes records / pulls remote changes
CloudKit private DB
```

**Why this shape**: zero refactor of existing call sites. `PanelStore`
reads/writes are immediate as today. Sync is eventually-consistent
(matching what users expect from iCloud anyway).

### `CloudKitMirror` responsibilities

1. **Push queue.** On `PanelStore.didChangeNotification`, diff what
   changed, enqueue `CKModifyRecordsOperation`. Retries on transient
   errors (`networkUnavailable`, `requestRateLimited`).
2. **Pull on launch + push notification.** `CKDatabaseSubscription`
   fires `CKQueryNotification` → fetch
   `CKFetchRecordZoneChangesOperation` with persisted change token →
   apply remote records to local store.
3. **Conflict resolution.** CloudKit's default last-writer-wins via
   record change tags is fine for this data model (rare concurrent
   edits; if Mom and Dad both rename a panel, last one sticks).
4. **Tombstones for delete.** Trash purge on device A must propagate.
   Use CloudKit's native delete (CKRecordID-only
   `CKModifyRecordsOperation` with `recordIDsToDelete`). Local store
   applies on pull.
5. **Asset caching.** On pull, download CKAssets to local Application
   Support so reads are instant. Existing playback path doesn't
   change.

## First-launch KVS cleanup (no migration code)

Production users (v2.1.0) have no custom panels to bring over.
Test/dev devices that already ran a v3.x build do have local panels —
those are handled by the user wiping the app or running "Clear All My
Data on Resume," not by migration logic.

```swift
// One-time on first v3.1 launch: detect orphan KVS entries that
// reference custom panels CloudKit doesn't have, and wipe them so
// the local store doesn't show ghost rows pointing at nothing.
if defaults.bool(forKey: "cloudkit_first_launch_v1") == false {
    if cloudKitMirror.fetchAllUserPanelIDs().isEmpty
        && !store.userPanels().isEmpty {
        // KVS has panel refs from a pre-CloudKit build; CloudKit is empty.
        // Clear local user-panel state so we don't render stale rows.
        store.clearUserPanelsAndLayout()
    }
    defaults.set(true, forKey: "cloudkit_first_launch_v1")
}
```

~5 lines of real logic. Idempotent. No partial-failure surface.

## Settings.bundle additions

One toggle:

- **Sync custom panels via iCloud** (`icloud_sync_enabled`, default
  `true`). When off, `CloudKitMirror` pauses (no pushes, no pulls).
  Local edits continue working. Re-enabling resumes from the
  persisted change token.
- Footer text: *"When off, your custom panels and recordings stay on
  this device only. Data already in iCloud is preserved — turning
  sync back on resumes where it left off."*

## Testing strategy

- New `AssetStore` protocol (mirrors existing `KeyValueStorage`
  pattern). Production = `CloudKitAssetStore`. Tests =
  `MemoryAssetStore` (no network, no schema).
- **Unit tests**: `CloudKitMirror` push/pull state machine — fed
  simulated `CKDatabase` responses, asserts correct ops emitted,
  retries on right errors.
- **Integration test**: real iCloud account, single-device round-trip
  (`save panel → wait for push → fetch via second store instance →
  assert match`). Slow, optional, not in normal CI.

## Operational checklist

1. Add `com.apple.developer.icloud-container-identifiers` to
   entitlements (`iCloud.com.ijaz.iInteract`).
2. Provision the container in Apple Developer portal + enable iCloud
   capability in Xcode.
3. Build schema in CloudKit Dashboard (Development environment).
4. **Before App Store submission**: deploy schema to Production
   environment via Dashboard. Forgetting this = prod users hit
   unschemaed records.
5. Add a launch-time `iCloudAvailability()` check — if signed out,
   fall back to local-only and surface a one-time alert: *"Sign into
   iCloud to sync your custom panels across devices."*

## Effort estimate

| Chunk | Days |
|---|---|
| Schema design + container provisioning + Dashboard setup | 1 |
| `AssetStore` protocol + `CloudKitAssetStore` skeleton | 1 |
| `CKRecord` encode/decode for Panel + Interaction | 1 |
| `CKAsset` upload/download for audio + image | 1 |
| `CloudKitMirror` push state machine | 2 |
| `CloudKitMirror` pull + change tokens + subscription | 2 |
| Conflict resolution + delete propagation | 1 |
| First-launch KVS cleanup guard | 0.25 |
| Settings.bundle toggle + reconciler hook | 0.5 |
| Tests (unit + integration scaffolding) | 1.5 |
| **Total focused work** | **~11.25 days** |

Plus ~1 week of buffer for iCloud-not-available edge cases, App Store
review feedback, and schema iteration during testing.

## Suggested split into shippable steps

Each is 2–4 days, each is independently shippable, each de-risks the
next.

### v3.1.0 — `AssetStore` protocol refactor

Pure code reorganization, no CloudKit yet.

- Extract local-FS asset reading/writing into an `AssetStore`
  protocol.
- Implement `LocalFSAssetStore` with current behavior.
- `PanelStore` depends on the protocol; production wires
  `LocalFSAssetStore`, tests wire a `MemoryAssetStore`.
- Includes the first-launch KVS cleanup guard so it's already in
  place when CloudKit lands.

Ships safely. No behavior change.

### v3.1.1 — `CloudKitAssetStore` + push only

One-way upload, local stays source of truth.

- Add CloudKit entitlement + container provisioning.
- Implement `CloudKitAssetStore` for record + asset *push only*.
- Existing users start backing up; no pull, no conflict surface.
- Failure modes are simple: push retries, never blocks local writes.

### v3.1.2 — Pull + subscription

Multi-device sync goes live. The risk-bearing release.

- `CKFetchRecordZoneChangesOperation` with persisted change token.
- `CKDatabaseSubscription` for push notifications on remote changes.
- Conflict resolution + delete propagation.
- Asset caching to local Application Support.

### v3.1.3 — Settings.bundle opt-out toggle

- `icloud_sync_enabled` toggle.
- Reconciler hook to pause/resume `CloudKitMirror`.
- Footer text explaining what "off" means.

## Test-phone setup before installing v3.1.0

Pick one:
- Delete + reinstall iInteract on the test phone.
- iOS Settings → iInteract → toggle **Clear All My Data on Resume**,
  return to app, confirm.
- Do nothing — the first-launch cleanup will detect the orphan KVS
  refs and clear them automatically. (This is the path real test
  users would hit, so it's also good QA coverage.)

## Risks

- **App Store review**: must handle iCloud-unavailable gracefully
  (already partially done via existing `iCloudAvailability` check in
  `PanelStore.swift:60`).
- **Schema evolution**: any future schema change requires Dashboard
  deployment. Field additions are easy; removals are not.
- **Quota**: ~1 GB free per user, scales with iCloud subscription.
  Audio at ~50 KB/recording = ~20K recordings before any quota issue.
  Images at ~500 KB = ~2K images. Safe for this app's scale.
- **Schema deployment timing**: must deploy to Production *before*
  the App Store release ships, otherwise prod users hit unschemaed
  records. Coordinate carefully.
