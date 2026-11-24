# Opt-in photo backup and resumable uploads

Status: gated engineering preview, 24 November 2026. Both flags default off.
Native transport has simulator/emulator evidence; physical acceptance, signing
and store review remain release gates. This is one-way backup into a private
vault, not two-way photo-library sync.

## Platform behavior

| Preview capability | iOS / Android app | Website / installed PWA |
| --- | --- | --- |
| Manually choose photos/videos | Yes | Yes |
| Retry without repeating confirmed multipart parts | Yes | Original tab and selected files must remain available |
| Recover owned staged files after relaunch | Yes, after authenticating the same account | No persistent binary queue; reload/close loses local state |
| OS-managed transfer | Current native file part, subject to OS scheduling | No closed-tab guarantee |
| Choose device albums / allowed Photos scope | Yes, explicit permission and consent | No native Photos-library access |
| Discover new selected media | While open, on library changes and on return | Manual selection only |
| Periodic library scanning while terminated | Not implemented | Not implemented |

Only one multipart part is submitted to the native service at a time. Dart
requests subsequent signed URLs and finalizes the upload; suspension can defer
these steps until the app returns. Reopening safely replays unconfirmed parts
and checks missed processing results. An entire queue is not guaranteed to
finish while closed. Byte transfer is not a ready item until API finalization
and worker processing succeed.

Apple cancels background sessions after explicit user force-quit, and background
uploads must use files. Android execution is subject to OS/vendor scheduling.
Browser Background Fetch is experimental, has limited availability and addresses
downloads; Background Sync cannot guarantee long file transfers. Installing a
PWA does not grant native Photos access. See the platform sources below.

## User choices

1. In Profile, choose **Choose backup albums**. Merely opening Profile does not
   request Photos access. Backup starts off, separately for each device/account.
2. The OS asks for access. Full access exposes device albums. Limited access
   exposes **Photos you allow**, restricted to the permitted subset; iOS does
   not expose user album names in this mode. To change that subset, use the
   phone's Photos permissions, then review choices in Mynube.
3. Turn on **Automatic backup** and save choices. At least one accessible scope
   is required, with up to 20 albums. Limited/full permission changes never
   silently expand the saved selection.
4. **Include existing photos and videos** defaults off. Off excludes capture
   times before backup was first enabled. On deliberately includes older items,
   subject to quota. The cutoff persists across disable/enable actions; imported
   media with unusual device dates can fall on either side of that cutoff.
5. **Include videos** defaults on; **Wi-Fi only** defaults on. Turning Wi-Fi only
   off permits mobile data. These apply to automatic backup; manually selected
   uploads follow the user's explicit upload action.
6. Turn backup off at any time: discovery stops and pending automatic transfers
   pause. Ready vault copies remain. A new login/account switch requires consent
   review again. A valid restored session can resume its saved consent on return.

Device albums are sources, **not** Mynube Collections; no collections or shares
are created automatically. Phone deletion, album deselection and disabling
backup never delete vault copies. Vault deletion never deletes phone originals.
Queued copies were authorized at discovery time: album changes affect future
discovery, while turning backup off pauses pending automatic work. Explicit
resume/cancel remains available in the upload queue.

## Architecture and privacy

`PhotoLibrary` owns permission/enumeration/connectivity; `DeviceBackupProvider`
owns consent/discovery. Manual and automatic sources use the same owned
`MediaUploadProvider`, `UploadJournal` and `PartTransfer` ports. No administrative
MinIO access or second upload pipeline is introduced.

- Native sources are copied in bounded chunks to private Application Support
  storage: **1 GiB / 100 pending files** across accounts, **512 MiB per file**.
  Disk-full/copy failures prevent a new upload. Phone originals are never removed.
- iOS staging is excluded from device backups and protected until first unlock
  after boot. Android uses the existing application backup exclusion. This is
  OS storage protection, not end-to-end encryption of server media.
- Atomic checkpoints contain owner/source identity, stable random upload ID,
  filename/type/size, remote upload ID and confirmed part ETags. No password,
  API bearer token or signed URL is written to this journal. The native transfer
  library necessarily retains short-lived signed URLs while executing tasks;
  never log/export its records. Auth remains in existing secure storage.
- Recovery is scoped to the authenticated owner. Stale native tasks are cancelled
  before recovery; unconfirmed parts can safely replay. Sign-out/account switch
  cancels continuation and clears that owner's pending sources. Generation/owner
  checks reject late source exports and HTTP callbacks.
- Completion receipts are per account/device and written only after readiness.
  They survive clearing pending uploads, contain no media bytes and are bounded
  to 100,000 entries / 32 MiB; full history fails closed.
- Source identity is asset ID plus modification time. Overlapping albums
  deduplicate that version, not arbitrary equal-content files. Edits can create
  new copies. Reinstallation, cleared data or another device can copy an item
  again. A backed-up version is not re-uploaded automatically after vault deletion
  on this installation.
- Corrupt committed checkpoints block discovery and preserve staged sources for
  diagnosis. Uncommitted interrupted staging copies never sent to the API can
  be cleaned. Dismiss/cancel touches only the corresponding private source copy.

Discovery handles 50 items/page, up to five selected albums and five new queued
items/pass, with a 30-second foreground interval and rotating album order.
Automatic retries stop after three failures until explicit retry. Manual pauses
stay paused. Transient failures/expired signed URLs preserve owned progress;
fresh URLs come from the authenticated API. Existing server reservation expiry
and cleanup still apply: old expired sessions may require cancelling and choosing
the source again. Resume does not extend reservations indefinitely.

## API compatibility and rollout

`POST /api/v1/media/upload/init` accepts optional `client_upload_id` (UUID).
Old clients can omit it. The same active owner and matching ID/name/type/size
reuse an existing reservation. Different metadata conflicts; foreign sessions
cannot be reused. Completed IDs cannot acquire another reservation. Normal quota
locking, permissions, signature validation, scanning and completion idempotency
remain authoritative. No SQL migration, grants, credentials or storage changes
are required.

Both build flags default `false`:

```text
--dart-define=ENABLE_RESUMABLE_UPLOADS=true
--dart-define=ENABLE_DEVICE_BACKUP=true
```

Native backup requires both flags and a live authenticated native build. Sample
mode never reads Photos. Web resumability is tab-lifetime only. Deploy this
backend before distributing a flagged client. An old backend's random-ID response
is rejected and aborted instead of claiming safe recovery. Flags require a new
client build; no production feature was enabled here. Follow [mobile acceptance](mobile-acceptance.md)
before wider rollout. Default builds retain foreground uploads.

Pinned compatible packages: `background_downloader 9.5.9`, `photo_manager 3.12.0`,
`path_provider 2.1.5`, `connectivity_plus 7.0.0`. Flutter stays at 3.35.4 / Dart 3.9;
the minimum Dart constraint now matches that toolchain. Newer downloader versions
require a newer SDK; review CI/native compatibility before upgrading.

## Deliberate limits before store release

- No OS periodic library scanner, autonomous full-queue orchestration or guarantee
  after force-quit/force-stop. Reopen the app to finish.
- Live Photos are skipped automatically. Preserving both paired resources needs
  a separate design; flattening is not advertised as a complete backup.
- OS exports may require iCloud download and may have privacy-redacted metadata.
  No location permission is requested just for backup. Export is bounded to 60
  seconds; unsupported/unavailable sources need attention.
- Two-way edits/deletion, album mirroring, cross-device content deduplication
  and storage sales are outside this slice.
- Photos permission/reselection, HEIC/MOV, locked screen, network changes, OS
  termination, cleanup and account transitions still need physical acceptance.
- Android broad photo/video permissions require Play declaration/review for the
  persistent backup use case. iOS disclosures, signing and TestFlight remain open.

## Validation

Use normal Flutter analysis/tests/builds and the [isolated Docker stack](../tests/integration/README.md),
never production URLs. E2E includes a synthetic multipart PNG: replay init, retain
the first ETag, transfer the remaining part, retry completion, check readiness
and exact download bytes, then delete only that isolated fixture.

`flutter_app/test/preview/backup_preview.dart` is a separate sample-only UI entry
with fake albums, no Photos access, credentials or real uploads. Never ship it
as the actual application.

`integration_test/native_transfer_test.dart` requires the explicit define
`NATIVE_UPLOAD_TEST_ACK=isolated-synthetic-target` and private
`NATIVE_UPLOAD_TEST_URL`. Use a dedicated receiver accepting only six synthetic
bytes and returning ETags. This validates native file ranges and journal recovery
over HTTPS, not auth, Photos, suspension or physical hardware. Never point it at
production. Remove temporary receivers/tunnels and keep capability URLs private.

## Platform sources

- Apple: [background URLSession / force-quit](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background%28withidentifier%3A%29),
  [file-based transfers](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background),
  [limited Photos](https://developer.apple.com/documentation/PhotoKit/delivering-an-enhanced-privacy-experience-in-your-photos-app).
- Android: [partial media access](https://developer.android.com/about/versions/14/changes/partial-photo-video-access),
  [background transfer options](https://developer.android.com/develop/background-work/background-tasks/data-transfer-options).
- Google Play: [photo/video permission requirements](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en).
- Web: [Background Fetch](https://developer.mozilla.org/en-US/docs/Web/API/Background_Fetch_API),
  [Background Sync](https://developer.mozilla.org/en-US/docs/Web/API/Background_Synchronization_API),
  [directory picker compatibility](https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker).
