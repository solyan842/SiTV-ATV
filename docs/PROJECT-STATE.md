# SiTV-ATV — PROJECT STATE

Updated: 2026-10-13

## Active development line

- Current feature branch: `dev/favorites`
- Base playback branch: `dev/dash-engine`
- `dev/favorites` is based on the latest DASH engine line and must not lose those playback changes.
- `main` remains protected from experimental development work unless explicitly requested.

## Verified automated checkpoint

Latest verified feature checkpoint before this document update:

- Workflow run: `#174`
- Branch: `dev/favorites`
- Commit: `7d7acfb26a3c066aee662affbca557c5c9f17941`
- Result: tvOS `build-test` SUCCESS
- Durable CI logging is enabled; failed-run diagnosis must follow `AGENTS.md` and `docs/GITHUB-ACTIONS-LOGGING-POLICY.md`.

Do not assume this remains the latest run. Before every CI diagnosis, refresh workflow runs repository-wide with no branch filter and follow `AGENTS.md`.

## Implemented

### Playlist / data

- Five configurable playlist source slots.
- Active-source persistence and source fallback semantics.
- M3U parsing with SiTV Android-compatible metadata handling.
- Multiple stream sources per channel.
- Source headers, manifest type, DRM metadata and license metadata parsing.
- Playlist cache and cache invalidation when source URL changes.

### Player routing

- `PlayerRouter` chooses an engine per stream source.
- Channel source fallback is preserved by `PlayerCoordinator`.
- AVPlayer is used for native-compatible playback paths.
- VLCKit is available as non-DRM fallback where supported.
- Widevine/FairPlay are not falsely advertised as supported.

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
- Full-screen playback UI.
- Persistent Favorites store.
- `Yêu thích` virtual group in the sidebar.
- Per-channel star toggle.
- Favorites state restored at bootstrap.

### CI / agent rules

- tvOS XcodeGen build/test workflow.
- Durable `xcodebuild` log artifact uploaded with `if: always()`.
- `AGENTS.md` is mandatory before diagnosis or writes.
- Raw job log may be attempted once only; artifact fallback is mandatory if raw log is unusable.
- Latest workflow run must always be discovered repo-wide before CI diagnosis.

## Remaining validation / next work

Priority order:

1. Real Apple TV smoke test of a normal HLS channel through AVPlayer.
2. Real Apple TV smoke test of a non-DRM stream that requires VLCKit fallback.
3. Real Apple TV smoke test of an authorized DASH/MPD + ClearKey channel.
4. Verify long-running live DASH behavior across manifest refresh and period rollover.
5. Verify source fallback by intentionally failing source 1 and confirming source 2 is selected.
6. Verify Siri Remote focus movement, return-from-player focus behavior and Favorites star interaction on-device.
7. Only after device evidence, fix device-specific playback/focus issues with minimal patches.

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
