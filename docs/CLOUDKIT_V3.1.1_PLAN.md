# v3.1.1 — CloudKit Push-Only — Implementation Plan

Status: planned. Depends on completion of v3.1.0 (`AssetStore` protocol
extraction, commit `05e6b32`).
See `docs/CLOUDKIT_MIGRATION.md` for the higher-level design.

## Manual setup (you do; ~30 min)

1. **Apple Developer portal** → Identifiers → CloudKit Containers →
   **+ New**. Container ID: `iCloud.com.ijaz.iinteract` (matches
   the existing KVS entitlement pattern of `iCloud.<bundle id>`).
2. **Xcode** → iInteract target → Signing & Capabilities → **+
   Capability** → iCloud → check **CloudKit** → add the new container.
   Auto-edits `iInteract.entitlements`:

   ```xml
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array>
       <string>iCloud.com.ijaz.iinteract</string>
   </array>
   <key>com.apple.developer.icloud-services</key>
   <array>
       <string>CloudKit</string>
   </array>
   ```
3. **CloudKit Dashboard** (icloud.developer.apple.com) → select the
   container → Development environment → Schema → define the record
   types in the next section. (Production deploy comes later, before
   the App Store release.)

## Schema (CloudKit Dashboard)

### Record type: `UserPanel`

| Field | Type | Indexed | Notes |
|---|---|---|---|
| `panelID` | String | queryable, sortable | Same as `Panel.id.uuidString`. Used as `recordName` (deterministic, idempotent retries). |
| `title` | String | queryable | Plain text, free-form. |
| `colorRGBA` | Bytes | — | 4 little-endian Float32s = 16 bytes. Same encoding as the existing JSON Codable. |

That's it. Order + isHidden + the layout cursor stay in **KVS** for
v3.1.1 — no need to duplicate, KVS is already syncing them.

### Record type: `Interaction`

| Field | Type | Indexed | Notes |
|---|---|---|---|
| `interactionID` | String | queryable | UUID string, used as `recordName`. |
| `panelRef` | Reference (`UserPanel`, cascade delete) | queryable | Cascade so deleting the parent purges children. |
| `displayName` | String | — | Same as `Interaction.displayName`. |
| `order` | Int64 | sortable | Within parent panel, 0-indexed. |
| `imageAsset` | Asset | — | `.jpg`, nullable. |
| `audioBoyAsset` | Asset | — | `.boy.m4a`, nullable. |
| `audioGirlAsset` | Asset | — | `.girl.m4a`, nullable. |

Recommended Dashboard indexes:
- `UserPanel.recordName` — queryable
- `Interaction.recordName` — queryable
- `Interaction.panelRef` — queryable, sortable (so a future
  "fetch all interactions for panel X ordered by `order`" query is
  cheap when v3.1.2 pull lands)

## `AssetStore` protocol — one method to add

The current protocol is read/write/delete-centric. CloudKit needs to
know when a caller wrote to a URL it didn't go through `write()` for
(AVAudioRecorder records directly to `url(for:id:)`).

```swift
protocol AssetStore {
    // ... existing methods ...

    /// Called after a caller wrote to a URL returned by `url(for:id:)`
    /// without going through `write(_:kind:id:)` — typically
    /// AVAudioRecorder finishing a recording. Local-FS implementations
    /// no-op; CloudKit-backed implementations enqueue an upload.
    func didExternallyWrite(_ kind: AssetKind, id: UUID)
}
```

`InteractionEditorViewController` currently calls AVAudioRecorder
against `store.assetURL(for: workingID, kind: voice.assetKind)`. After
the recording-stop handler runs, add a call to a PanelStore convenience
that delegates to `assetStore.didExternallyWrite`. One line of new code
at the call site.

## `CloudKitAssetStore` — push-only

Local-first, CloudKit as background mirror. Single class,
~150–200 lines.

```swift
final class CloudKitAssetStore: AssetStore {
    private let cache: LocalFSAssetStore       // local-first; same rootDirectory contract
    private let database: CloudKitDatabase     // protocol, see below
    private let pushQueue: PushQueue

    var rootDirectory: URL { cache.rootDirectory }

    init(parentDirectory: URL,
         database: CloudKitDatabase = LiveCloudKitDatabase(),
         pushQueueURL: URL? = nil) {
        self.cache = LocalFSAssetStore(parentDirectory: parentDirectory)
        self.database = database
        self.pushQueue = PushQueue(persistedAt:
            pushQueueURL ?? parentDirectory.appendingPathComponent("CloudKitPushQueue.json"))
    }

    // Reads + existence checks: pure passthrough to local cache.
    func url(for kind: AssetKind, id: UUID) -> URL { cache.url(for: kind, id: id) }
    func exists(_ kind: AssetKind, id: UUID) -> Bool { cache.exists(kind, id: id) }

    func write(_ data: Data, kind: AssetKind, id: UUID) throws {
        try cache.write(data, kind: kind, id: id)
        pushQueue.enqueue(.uploadAsset(kind: kind, id: id))
    }

    func didExternallyWrite(_ kind: AssetKind, id: UUID) {
        pushQueue.enqueue(.uploadAsset(kind: kind, id: id))
    }

    func delete(_ kind: AssetKind, id: UUID) {
        cache.delete(kind, id: id)
        pushQueue.enqueue(.deleteAsset(kind: kind, id: id))
    }

    func deleteAll(id: UUID) {
        cache.deleteAll(id: id)
        pushQueue.enqueue(.deleteInteraction(id: id))
    }

    func deleteEverything() {
        cache.deleteEverything()
        // For v3.1.1 (push-only), wiping local does NOT touch CloudKit.
        // Settings.bundle "Clear All My Data" is documented as a local
        // wipe; iCloud copy is preserved so the user can re-pull from
        // a different device. Consider a separate "Clear iCloud copy
        // too" toggle in v3.1.3 if users ask for it.
    }
}
```

### `CloudKitDatabase` injection seam

```swift
protocol CloudKitDatabase {
    func save(_ record: CKRecord) async throws
    func delete(recordID: CKRecord.ID) async throws
    func modifyRecords(saving: [CKRecord],
                       deleting: [CKRecord.ID]) async throws
}

struct LiveCloudKitDatabase: CloudKitDatabase {
    let database = CKContainer(identifier: "iCloud.com.ijaz.iinteract")
        .privateCloudDatabase
    // Wrap CKModifyRecordsOperation in async/await wrappers.
}

final class MockCloudKitDatabase: CloudKitDatabase {
    var savedRecords: [CKRecord] = []
    var deletedRecordIDs: [CKRecord.ID] = []
    var nextError: Error? = nil
    // ... etc
}
```

## `PushQueue` — persistence + retry state machine

A new type, ~100 lines. Single source of truth for "what needs to be
pushed."

```swift
enum PushOperation: Codable {
    case savePanel(id: UUID)
    case deletePanel(id: UUID)
    case saveInteraction(id: UUID, parentID: UUID)
    case deleteInteraction(id: UUID)
    case uploadAsset(kind: AssetKind, id: UUID)
    case deleteAsset(kind: AssetKind, id: UUID)
}

struct PushEntry: Codable {
    let id: UUID                        // entry id, for dedupe + removal
    let op: PushOperation
    let createdAt: Date
    var retryCount: Int
    var nextEligibleAt: Date            // for backoff
}

final class PushQueue {
    private let persistedAt: URL
    private(set) var entries: [PushEntry]

    func enqueue(_ op: PushOperation) {
        // Dedupe: a pending uploadAsset for the same (kind, id)
        // supersedes earlier ones (only the latest file content
        // matters). A deleteInteraction supersedes pending uploads
        // for that interaction. Save to disk after every mutation.
    }

    func nextDue(now: Date) -> PushEntry? { ... }
    func markSuccess(_ entry: PushEntry) { /* remove + save */ }
    func markFailure(_ entry: PushEntry, retryable: Bool, now: Date) {
        if !retryable { /* drop, log */ return }
        // Exponential backoff: 30s, 2m, 8m, 30m, 2h, max 12h.
        // After 10 attempts: drop + log + surface user alert.
    }
}
```

**Persistence**: JSON file at
`Application Support/PanelStore/CloudKitPushQueue.json`. Atomic writes.
Read on init.

**Drainer**: a `Task` started at app launch (in
`AppDelegate.didFinishLaunching` or equivalent). Loop:

```swift
while true {
    guard pushQueue.entries.contains(where: { $0.nextEligibleAt <= Date() }) else {
        try await Task.sleep(...)  // wait for nearest eligibility
        continue
    }
    guard let entry = pushQueue.nextDue(now: Date()) else { continue }
    do {
        try await execute(entry)  // build CKRecord + database.save
        pushQueue.markSuccess(entry)
    } catch let error as CKError where error.isRetryable {
        pushQueue.markFailure(entry, retryable: true, now: Date())
    } catch {
        pushQueue.markFailure(entry, retryable: false, now: Date())
    }
}
```

**Retryable CKError codes**: `networkUnavailable`, `networkFailure`,
`requestRateLimited`, `serviceUnavailable`, `zoneBusy`,
`notAuthenticated` (only if iCloud account becomes available later).

**Non-retryable** (drop): `unknownItem`, `quotaExceeded`,
`serverRejectedRequest`, `permissionFailure`, schema-related errors.

## Wiring into `PanelStore.shared`

Production wiring becomes:

```swift
extension PanelStore {
    static let shared = {
        let dir = ...  // Application Support / PanelStore
        let useCloudKit = FileManager.default.ubiquityIdentityToken != nil
        let assetStore: AssetStore = useCloudKit
            ? CloudKitAssetStore(parentDirectory: dir)
            : LocalFSAssetStore(parentDirectory: dir)
        return PanelStore(directory: dir,
                          keyValueStore: NSUbiquitousKeyValueStore.default,
                          iCloudAvailability: { FileManager.default.ubiquityIdentityToken != nil },
                          assetStore: assetStore)
    }()
}
```

Plus a record-level mirror in `PanelStore.savePanel(_:)` /
`deletePanel(id:)` — those need to enqueue `savePanel` / `deletePanel`
push operations too (not just the asset operations the AssetStore
handles). Easiest: add a `panelChanged` notification observer in
`CloudKitAssetStore` (or a sibling `CloudKitRecordMirror`) that
receives `PanelStore.didChangeNotification` and diffs to figure out
what records to push. Cleanest if the record-push logic lives next to
the asset-push logic in `CloudKitAssetStore` for v3.1.1; can split
later.

## Build a `CKRecord` from a Panel/Interaction

```swift
extension Panel {
    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "UserPanel", recordID: recordID)
        record["panelID"] = id.uuidString
        record["title"] = title
        record["colorRGBA"] = colorRGBABytes()
        return record
    }
}

extension Interaction {
    func toCKRecord(parentPanelID: UUID,
                    order: Int,
                    assetURLs: (image: URL?, boy: URL?, girl: URL?),
                    in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "Interaction", recordID: recordID)
        record["interactionID"] = id.uuidString
        let parentRecordID = CKRecord.ID(recordName: parentPanelID.uuidString, zoneID: zoneID)
        record["panelRef"] = CKRecord.Reference(recordID: parentRecordID, action: .deleteSelf)
        record["displayName"] = displayName
        record["order"] = Int64(order)
        if let url = assetURLs.image  { record["imageAsset"]     = CKAsset(fileURL: url) }
        if let url = assetURLs.boy    { record["audioBoyAsset"]  = CKAsset(fileURL: url) }
        if let url = assetURLs.girl   { record["audioGirlAsset"] = CKAsset(fileURL: url) }
        return record
    }
}
```

## Tests for v3.1.1

### Unit tests (no real CloudKit)

`CloudKitAssetStoreTests`:
- `write` enqueues `uploadAsset`.
- `delete` enqueues `deleteAsset`.
- `didExternallyWrite` enqueues `uploadAsset`.
- `deleteEverything` does NOT enqueue (local-only wipe contract).
- Local cache reads work without ever calling the database.

`PushQueueTests`:
- Persistence: enqueue → reload from disk → entries match.
- Dedupe: two `uploadAsset(.picture, id: X)` collapse to one.
- Supersession: `deleteInteraction(id: X)` removes pending
  `uploadAsset(_, id: X)`.
- Backoff: failed entry's `nextEligibleAt` advances; succeeds removes
  from queue.
- Retry cap: 10th failure drops the entry.

`CloudKitDatabaseAdapterTests` (the wrapper around CKDatabase):
- Hard to unit-test without real CKDatabase, but we can test the error
  mapping (retryable vs. non-retryable) by feeding canned `CKError`
  instances into a thin `classify(error:) -> RetryDecision` helper.

### Integration test (optional, opt-in via env var)

`CloudKitIntegrationTests` — single-device round-trip:
- Real iCloud account on the test simulator/device.
- Save a custom panel + interaction with audio.
- Wait for push queue to drain.
- Fetch via `CKDatabase` directly (bypassing our store) and assert
  the record exists with the right field values + asset bytes.
- Skipped by default; opt in via
  `RUN_CLOUDKIT_INTEGRATION_TESTS=1` so CI doesn't need iCloud
  credentials.

## Implementation order — 4 sub-commits

Per the workflow rule about splitting larger steps into 2–3 sub-commits
with pause points:

### v3.1.1a — Push queue + plumbing (no CloudKit network calls yet)

- `PushOperation` enum + `PushEntry` struct + `PushQueue` class with
  persistence + dedupe + supersession + backoff math.
- `CloudKitDatabase` protocol with a `MockCloudKitDatabase`
  implementation.
- Add `didExternallyWrite` to `AssetStore` protocol (`LocalFSAssetStore`
  no-ops).
- Tests: `PushQueueTests` (~15 tests), `MockCloudKitDatabaseTests`.
- No production wiring yet; no entitlement change yet. Pure plumbing.

### v3.1.1b — `CloudKitAssetStore` + record encoding

- `CloudKitAssetStore` class.
- `Panel.toCKRecord` / `Interaction.toCKRecord` extensions.
- Error-classification helper.
- Tests: `CloudKitAssetStoreTests` using `MockCloudKitDatabase` to
  assert correct CKRecords get saved.
- Still not wired into production.

### v3.1.1c — Production wiring + entitlement + record mirror

- Update `iInteract.entitlements` (after you've added the capability
  in Xcode).
- `PanelStore.shared` selects `CloudKitAssetStore` when
  `ubiquityIdentityToken != nil`.
- Observer/mirror that listens for `PanelStore.didChangeNotification`
  and enqueues panel/interaction record-level pushes (not just asset
  pushes).
- AppDelegate kicks off the push drainer task.
- `InteractionEditorViewController` calls `didExternallyWrite` after
  AVAudioRecorder finishes.
- Manual smoke test on your test device.

### v3.1.1d — Optional: opt-in integration test + Dashboard schema deploy notes

- `CloudKitIntegrationTests` skipped-by-default scaffolding.
- A `docs/CLOUDKIT_DEPLOY_CHECKLIST.md` for the Dashboard
  schema-promotion step before App Store submission.

## Estimated effort

| Sub-commit | Days |
|---|---|
| v3.1.1a — Push queue + mocks | 1.5 |
| v3.1.1b — CloudKitAssetStore + record encoding | 1.5 |
| v3.1.1c — Production wiring + record mirror | 1 |
| v3.1.1d — Integration test + deploy doc | 0.5 |
| **Total focused work** | **~4.5 days** |

Plus 30–60 min of your manual portal/Xcode setup before v3.1.1c can
be merged.

## Risks specific to v3.1.1

1. **Schema deploy timing.** The Development schema you build in
   Dashboard during v3.1.1c is *not* what production users hit.
   Before App Store submission, you must "Deploy Schema to Production"
   via Dashboard. If you forget, prod users get errors on every save.
   Add a checkbox to your release checklist.
2. **`notAuthenticated` is annoyingly retryable.** Per CKError docs
   it's transient (user could sign in later). But it can also indicate
   a permanent state for some users. The push queue's "max 10 retries"
   cap handles this — eventually entries drop, and the user sees a
   one-time alert "Sign into iCloud to back up your custom panels."
3. **Push queue file corruption.** If JSON gets malformed, init throws
   and the queue is silently empty. Fallback: on parse failure, rename
   the bad file to `CloudKitPushQueue.bad-<timestamp>.json` and start
   fresh. Logs the corruption for debugging.
4. **AVAudioRecorder writes are async.** The `didExternallyWrite` call
   needs to happen in the recorder's stop completion handler, not when
   the user taps "Stop." If we enqueue too early, the file might not
   be fully flushed and CKAsset upload will get a partial file.
