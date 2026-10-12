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

## Initial implementation order

1. Project skeleton + models
2. M3U parser parity with SiTV Android
3. Playlist repository/cache
4. PlayerRouter contract
5. AVPlayer engine
6. VLCKit fallback
7. DASH/MPD parser path
8. ClearKey/CENC smoke test
9. tvOS channel UI and Siri Remote behavior
10. Integration and device testing

## Status

Bootstrap phase.
