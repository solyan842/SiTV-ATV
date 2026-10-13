# SiTV-ATV — APPLE TV DEVICE SMOKE TEST

Use this checklist only after the active dev branch has a green tvOS CI run. Device evidence wins over simulator assumptions.

## 1. Build and install

1. Open the generated Xcode project after running `xcodegen generate`.
2. Select the real Apple TV as destination.
3. Select the signing team for bundle ID `com.solyan.sitvatv`.
4. Build and run SiTV on the Apple TV.
5. Confirm the app opens without a crash and the source settings screen can be reached.

Record:
- Apple TV model / tvOS version.
- Commit SHA installed.
- Whether launch succeeds.

## 2. Playlist input and HTTP parity

Test one HTTPS M3U URL and, if available, one legitimate HTTP M3U URL.

Expected:
- Both playlists load when reachable.
- Channel groups populate.
- No ATS / insecure-load error is shown for the HTTP source.

If HTTP fails, record the exact visible error and URL scheme only. Do not paste credentials, tokens or DRM keys.

## 3. Native HLS / AVPlayer

Choose a plain non-DRM HLS channel with no custom HTTP headers.

Expected:
- Playback opens full screen.
- Overlay shows `avPlayer · nguồn 1` (or the actual source index).
- Audio and video both start.
- Exit returns cleanly to the channel list.

Observe:
- startup delay;
- stalls;
- audio/video sync;
- whether focus returns to a sensible location after exiting.

## 4. VLCKit fallback

Use a lawful non-DRM stream that AVPlayer intentionally does not claim, for example a source requiring `Referer` / `User-Agent`, or another format already known to need VLC.

Expected:
- Coordinator skips/rejects the unsuitable AVPlayer attempt.
- Playback succeeds through VLC when VLCKit supports the stream.
- Overlay shows `vlc · nguồn N`.

Do not use this test to infer that VLCKit supports DRM.

## 5. Authorized DASH + ClearKey

Use only a stream and ClearKey material that you are authorized to use.

Playlist metadata should identify the source as DASH/MPD + ClearKey using the formats already supported by the SiTV M3U parser.

Expected:
- Router selects `dashClearKey`.
- MPD loads and the protected track KID matches the supplied authorized key material.
- Audio and video render through the synchronized sample-buffer pipeline.
- Overlay shows `dashClearKey · nguồn N`.

Do not paste DRM keys, session tokens or license secrets into bug reports.

## 6. Long-running live DASH

For an authorized live DASH/ClearKey channel, keep playback running for at least 10–15 minutes or long enough to cross several manifest refreshes.

Expected:
- playback remains alive through MPD refresh;
- no duplicate audio/video after refresh;
- no accumulating A/V drift;
- period rollover re-prepares cleanly when the live MPD changes Period.

Record the approximate playback time if a failure occurs.

## 7. Source fallback

Create or use a test channel with:
- source 1 intentionally unreachable or unsupported;
- source 2 valid and playable.

Expected:
- source 1 fails without closing the player flow;
- coordinator tries source 2;
- playback starts from source 2;
- overlay shows `nguồn 2`.

Also verify engine fallback on one source when applicable, for example AVPlayer failure followed by VLC success.

## 8. Favorites

1. Add several channels with the star button.
2. Open the `Yêu thích` group.
3. Remove one favorite while the group is selected.
4. Quit and relaunch SiTV.

Expected:
- favorite state updates immediately;
- removing the last favorite produces the dedicated empty state;
- favorites persist across relaunch;
- favorite state is not lost when switching playlist source.

## 9. Siri Remote / focus

Verify with the physical Siri Remote:
- group sidebar navigation;
- channel grid navigation;
- star button focus and activation;
- settings button;
- opening a channel;
- Menu/Back/Exit from player;
- focus after returning from player;
- no focus trap between the channel card and favorite star button.

## 10. Failure report format

For any failure, capture only:

- installed commit SHA;
- Apple TV model and tvOS version;
- channel name;
- visible engine/source overlay, e.g. `vlc · nguồn 2`;
- what action triggered the issue;
- exact visible error text;
- whether retrying the same channel changes the result;
- approximate time into playback for live-stream failures.

Never include passwords, authorization headers, DRM keys, license secrets or private tokens.

## Pass gate

Device smoke is considered complete only when these minimum paths have evidence:

- normal HLS through AVPlayer;
- one real VLC fallback path;
- one authorized DASH/ClearKey path;
- source 1 → source 2 fallback;
- Favorites persistence;
- Siri Remote navigation / player exit;
- legitimate HTTP playlist or stream compatibility when the source actually uses HTTP.
