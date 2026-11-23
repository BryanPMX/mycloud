# Mobile acceptance and iOS-first release

Status: engineering work in progress. Neither physical platform has completed
acceptance. An emulator, compilation or sample-data UI test is not a substitute
for real-device evidence. iOS distributes first; Android remains a required
validation target.

## Targets and prerequisites

- iOS: owner's iPhone 16 Pro Max, reported iOS 27.0.1. Confirm from device
  discovery before recording acceptance. Apple individual development membership
  reported available; account entitlement, signing and provisioning remain to
  verify. Installed Xcode and iPhoneOS SDK: 27.1.
- Android: Android Studio AVD `Medium_Phone_API_36.1` available. No physical
  Android device was connected during discovery; obtain one for hardware sign-off.
- Use the same reviewed commit and production configuration with sample mode
  disabled. Use synthetic media and designated test accounts. Keep credentials,
  session tokens, private media and signed URLs out of logs, Git and screenshots.
- Builds must use appropriate distribution signing before TestFlight/Play
  upload. The current Android debug-signing fallback is for smoke builds, not
  proof of store readiness. Do not change or publish signing credentials.

## Transfer behavior required before release

The existing uploader runs in Dart memory. Native background transfers and a
persistent, account-owned queue are **not implemented** by the picker safety fix.
No automatic background photo-backup claim is accepted.

Implement selected-file background uploads before approving the release:

1. Stage selected files in app-private storage, exclude staged media from device
   cloud backups, bound disk use and clean it after success/cancellation. Picker
   temporary paths cannot be assumed valid across process restarts.
2. Persist account ID, upload/media IDs, source identity, part size and completed
   part ETags atomically. Do not persist account passwords or log bearer/signed
   URLs. Secure-store auth separately. Restore only after verifying the same
   authenticated account; discard/cancel another account's pending transfers.
3. Transfer files through iOS background URLSession and Android's supported
   background transfer facilities. Keep the existing multipart, quota and private
   object authorization boundaries; do not proxy large files through the API or
   weaken request limits just to enable backgrounding.
4. Refresh expired part URLs, reconcile uncertain completion, avoid duplicate
   media/reservations, retry transient failures with bounds and preserve explicit
   cancellation. Recover completion events missed while Dart was suspended.
5. Reconcile uploaded parts and finalize the application upload before calling it
   complete; background byte transfer alone does not start worker processing.
6. Distinguish system suspension/termination from explicit force-quit/force-stop.
   After an explicit force-quit, resume safely on the next launch rather than
   promising that the OS will keep transferring or relaunch the app.

Apple requires file-based background uploads and documents cancellation after
user force-quit: [URLSession background configuration](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background%28withidentifier%3A%29)
and [background transfers](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background).
Android transfer mechanisms must follow its current [data transfer guidance](https://developer.android.com/develop/background-work/background-tasks/data-transfer-options).

## Acceptance matrix

Record PASS/FAIL/BLOCKED per physical device, exact OS version, build number,
commit, date and test case. Emulator results occupy a separate column. Any
failure remains open until fixed and rerun. No secrets or real photo names in
results.

| Case | iPhone hardware | Android emulator | Android hardware |
| --- | --- | --- | --- |
| Install, cold launch, sign in/out, invitation links | Pending | Pending | Pending |
| Session restoration, offline launch, refresh expiry/revocation | Pending | Pending | Pending |
| Picker cancellation, limited/denied Photos access, re-selection | Pending | Pending | Pending |
| Synthetic PNG/JPEG, device HEIC, short MOV/MP4 upload and playback | Pending | Pending | Pending |
| Multi-file batch, original download/save, SHA-256 where practical | Pending | Pending | Pending |
| Background, locked screen, return to foreground, missed processing events | Pending | Pending | Pending |
| Network loss, Wi-Fi/cellular switch, expired signed URL, retry | Pending | Pending | Pending |
| OS termination, manual force-quit, relaunch, no duplicates | Pending | Pending | Pending |
| Sign out/account switch with queued/in-flight work; no cross-account transfer | Pending | Pending | Pending |
| Size/quota rejection, cancellation, staging-file cleanup | Pending | Pending | Pending |
| Trash/restore and permanent deletion of only synthetic assets | Pending | Pending | Pending |
| Family sharing and outsider denial with two test identities | Pending | Pending | Pending |
| VoiceOver/TalkBack, large text, rotation, keyboard/safe areas | Pending | Pending | Pending |

Do not use broad production reset/seed E2E helpers. Production writes require
specific disposable fixtures, bounded processing waits and no infrastructure
changes. A destructive-test confirmation must identify the exact synthetic
asset; never empty a mixed trash list.

## Distribution gates

1. Close native transfer implementation and the device matrix above.
2. Close the outstanding SSD acceptance deletion/log/storage verification and
   independent backup/recovery checks; keep originals elsewhere meanwhile.
3. Verify release signing and build an iOS distribution archive with sample mode
   disabled. Verify permissions, icons, privacy declarations, native link routing,
   export-compliance answers and app metadata against the shipped build.
4. Distribute a reviewed TestFlight build, gather feedback on both account roles
   and repeat the matrix for fixes. Do not label unsigned builds or sample UI
   tests as TestFlight/device acceptance.
5. Submit publicly only after acceptance and owner authorization. Android store
   distribution comes later; Android hardware acceptance is not waived.

## Initial engineering evidence — 23 November 2026

- Device discovery found no connected physical iPhone or Android phone.
- Native picker cancellation now returns without reopening a second picker.
  Permission/native errors propagate; only unsupported mixed selection falls
  back to a single selection.
- Lost picker data has no reliable owner or purpose. It now requires explicit
  reselection instead of automatically uploading to the current vault or avatar.
  Delayed recovery/picker results cannot update another account's state.
- Eight new automated regressions cover picker cancellation/fallback/denial,
  lost-media handling, account changes and picker state isolation. These are
  mocked unit tests, not native OS plugin or hardware acceptance.
- Flutter analysis and all 62 tests passed. A fresh unsigned production iOS
  release build passed with sample mode disabled (Xcode/iPhoneOS SDK 27.1).
- Both existing sample admin/member integration flows passed on the Android
  API 36.1 emulator and iPhone 17 Pro Max simulator running iOS 26.2. These
  exercise the native app's sample UI, not production networking or hardware
  Photos/background behavior. An Android device-discovery warning occurred when
  the completed Android test emulator was stopped during iOS target discovery;
  the selected iOS simulator build and both tests nevertheless passed.
