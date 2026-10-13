# SiTV-ATV

Native Apple TV (tvOS) version of SiTV.

## Project goals

SiTV-ATV is intentionally small and focused on live IPTV playback on Apple TV.

### In scope
- M3U playlist loading and parsing
- Channel groups and channel list
- Favorites
- Playlist cache
- tvOS-native navigation and Siri Remote focus handling
- Multi-source fallback per channel
- AVPlayer for native Apple playback paths
- VLCKit fallback for formats/codecs AVPlayer cannot handle
- MPEG-DASH/MPD support
- ClearKey/CENC DRM support for authorized streams
- FairPlay support when a provider exposes an authorized Apple/FPS path

### Explicitly out of scope
- EPG / XMLTV
- QR-code input
- Xtream UI/features
- Movies / Series catalog
- TMDB / Trakt integrations
- Recording
- Multiview

## Architecture direction

```text
M3U / Playlist
      |
      v
Channel + [StreamSource]
      |
      v
PlayerRouter
  |       |        |
  |       |        +--> DASH/ClearKey engine
  |       +-----------> VLCKit fallback
  +-------------------> AVPlayer

If a source fails, SiTV-ATV tries the next source for that channel.
```

## Source-of-truth rules

- Android SiTV remains the behavior/reference source for playlist parsing and multi-source semantics.
- SiTV-ATV is a separate native tvOS codebase.
- Do not copy AGPL code into this repository.
- Prefer permissive dependencies (MIT/BSD/Apache) and system frameworks.
- LGPL dependencies may be used only with their license obligations respected.
- DRM support is for authorized streams/keys/licenses only.

## Implemented foundation

- Native tvOS SwiftUI app shell and five playlist source slots
- M3U parser parity for SiTV stream metadata, headers and multi-source channels
- Playlist cache and source persistence
- PlayerRouter with source/engine fallback
- AVPlayer native playback path
- VLCKit fallback for supported non-DRM streams
- DASH/MPD parsing, segment planning and live manifest refresh
- CMAF/CENC inspection and authorized ClearKey sample decryption
- DASH audio/video sample-buffer rendering and period-rollover re-prepare
- Channel groups, channel grid and persistent Favorites
- HTTP/HTTPS IPTV compatibility matching Android SiTV behavior
- GitHub Actions tvOS build/test with durable failure logs

## Current validation state

Automated tvOS build/tests are passing on the active development line. Real-device validation is still required for representative HLS, VLC fallback and authorized DASH/ClearKey live streams, plus Siri Remote focus/navigation behavior.

## Project documents

- `AGENTS.md` — mandatory repository/CI operating rules.
- `docs/PROJECT-STATE.md` — current verified checkpoint and next work.
- `docs/DEVICE-SMOKE-TEST.md` — real Apple TV validation checklist.
- `docs/GITHUB-ACTIONS-LOGGING-POLICY.md` — durable CI-log procedure.
- `docs/THIRD-PARTY-NOTICES.md` — pinned dependency licenses and release gates.
