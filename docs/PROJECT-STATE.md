# SiTV-ATV — PROJECT STATE

Updated: 2026-10-13

## Active development line

- Current feature branch: `dev/favorites`
- Base playback branch: `dev/dash-engine`
- `dev/favorites` includes the current DASH engine line plus Favorites, coordinator fallback tests, HTTP/ATS parity work and final tvOS brand assets.
- `main` remains protected from experimental development work unless explicitly requested.

## Verified automated checkpoint

Latest verified repository-wide CI checkpoint at this update:

- Workflow run: `#185`
- Run ID: `38364127384`
- Branch: `dev/favorites`
- Commit: `4df8c5151a921068d4246acbbd9e993219cb888c`
- Result: tvOS `build-test` SUCCESS
- Simulator test suite: SUCCESS
- Unsigned generic tvOS device build: SUCCESS
- Unsigned device artifact: `sitv-atv-unsigned-38364127384-1`
- Artifact ID: `11796550605`
- Artifact size: 23,006,837 bytes
- Artifact expiry: 2026-10-27
- Durable build log artifact: `tvos-build-test-log-38364127384-1`
- Durable build log artifact ID: `11796790288`
- Final tvOS asset catalog compiled successfully into the device `.app`; bundle inspection confirms `Assets.car`, `CFBundleIcons -> App Icon`, three-layer home/App Store icon stacks, Top Shelf and Top Shelf Wide assets.

Additional verified checkpoints:

- Workflow run `#184` passed simulator tests, unsigned generic tvOS device build and `.app` artifact packaging before final branding assets were added.
- Workflow run `#183` passed the unsigned generic tvOS device build before app-bundle artifact packaging was added.
- Workflow run `#180` passed the dedicated `PlayerCoordinator` fallback tests covering same-source engine fallback, source 1 → source 2 fallback, stop-before-switch and unsupported routing.

The unsigned `.app` artifact is a CI/device-build checkpoint, not a signed installable App Store/TestFlight package. Real Apple TV installation still requires normal Apple code signing.

Durable CI logging is enabled; failed-run diagnosis must follow `AGENTS.md` and `docs/GITHUB-ACTIONS-LOGGING-POLICY.md`.

Do not assume this remains the latest run. Before every CI diagnosis, refresh workflow runs repository-wide with no branch filter and follow `AGENTS.md`.

## Implemented

### Playlist / data

- Five configurable playlist source slots.
- Active-source persistence and source fallback semantics.
- M3U parsing with SiTV Android-compatible metadata handling.
- Multiple stream sources per channel.
- Source headers, manifest type, DRM metadata and license metadata parsing.
- Playlist cache and cache invalidation when source URL changes.
- HTTP and HTTPS playlist/stream compatibility retained to match Android SiTV cleartext behavior; ATS configuration is explicit in the tvOS project.

### Player routing

- `PlayerRouter` chooses an engine per stream source.
- Channel source fallback is preserved by `PlayerCoordinator`.
- Same-source engine fallback and cross-source fallback are covered by unit tests.
- AVPlayer is used for native-compatible playback paths.
- VLCKit is available as non-DRM fallback where supported.
- Widevine/FairPlay are not falsely advertised as supported.
- Playback failures expose useful localized messages instead of raw enum descriptions.

### DASH / ClearKey

Authorized-stream path only.

- DASH/MPD parser.
- BaseURL and SegmentTemplate/SegmentTimeline handling.
- Representation/segment planning.
- CMAF parsing via permissively licensed `swift-cmaf-kit`.
- CENC inspection and ClearKey material validation.
- Clear sample decryption pipeline.
- CoreMedia audio/video format factories.
- `CMSampleBuffer` construction with sample timing and sync/non-sync metadata.
- Synchronized audio/video sample-buffer renderer.
- DASH ClearKey player engine and playback controller.
- Live manifest refresh.
- Period rollover planning and engine re-prepare.
- tvOS display-layer surface integrated into `PlayerView`.

### tvOS UI

- Channel groups and channel grid.
- Source settings UI.
- Full-screen playback UI with engine/source overlay.
- Persistent Favorites store.
- `Yêu thích` virtual group in the sidebar.
- Per-channel star toggle.
- Favorites state restored at bootstrap.
- Final SiTV tvOS branding assets ported from the existing Android SiTV vector artwork.
- Three-layer parallax AppIcon, App Store icon, Top Shelf and Top Shelf Wide assets are compiled into `Assets.car`.

### CI / agent rules

- tvOS XcodeGen build/test workflow.
- Durable `xcodebuild` log artifact uploaded with `if: always()`.
- Unsigned generic tvOS device build is compiled on every CI run.
- Unsigned `.app` bundle is packaged and uploaded as a dedicated CI artifact on successful device builds.
- Docs-only changes under `README.md`, `AGENTS.md` and `docs/**` do not create unnecessary CI runs.
- `AGENTS.md` is mandatory before diagnosis or writes.
- Raw job log may be attempted once only; artifact fallback is mandatory if raw log is unusable.
- Latest workflow run must always be discovered repo-wide before CI diagnosis.

### Dependency / release hygiene

- `swift-cmaf-kit` `0.1.2` is recorded as Apache-2.0.
- VLCKit pinned revision is recorded as LGPL-2.1 and requires a distribution-compliance review before TestFlight/App Store/public binary distribution.
- See `docs/THIRD-PARTY-NOTICES.md`.

## Remaining validation / next work

Priority order:

1. Real Apple TV smoke test of a normal HLS channel through AVPlayer.
2. Real Apple TV smoke test of a non-DRM stream that requires VLCKit fallback.
3. Real Apple TV smoke test of an authorized DASH/MPD + ClearKey channel.
4. Verify long-running live DASH behavior across manifest refresh and period rollover.
5. Verify source fallback by intentionally failing source 1 and confirming source 2 is selected.
6. Verify a legitimate HTTP playlist/stream on-device to confirm ATS parity in the real app bundle.
7. Verify Siri Remote focus movement, return-from-player focus behavior and Favorites star interaction on-device.
8. Review and satisfy VLCKit LGPL distribution obligations before public/TestFlight distribution.
9. Only after device evidence, fix device-specific playback/focus issues with minimal patches.

Detailed device procedure: `docs/DEVICE-SMOKE-TEST.md`.

## Scope locks

- No EPG/XMLTV.
- No QR input.
- No Xtream UI/features.
- No Movies/Series catalog.
- No TMDB/Trakt.
- No recording.
- No multiview.
- DRM work is limited to authorized keys/licenses and lawful playback compatibility.
- Do not copy AGPL/GPL implementation code into this project.
