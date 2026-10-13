# SiTV-ATV — THIRD-PARTY DEPENDENCIES

This document records the licenses of dependencies currently pinned by `project.yml`. It is a project-maintenance checklist, not legal advice.

## swift-cmaf-kit

- Repository: `atelier-socle/swift-cmaf-kit`
- Pinned version: `0.1.2`
- Products used: `CMAFKit`, `CMAFKitDRM`
- License at the pinned version: Apache License 2.0
- Copyright notice in the pinned license: Copyright 2026 Atelier Socle SAS

Distribution notes:
- preserve the Apache-2.0 license and applicable attribution/copyright notices;
- if the upstream distribution contains a required NOTICE file, preserve the applicable NOTICE contents as required by Apache-2.0.

## VLCKit

- Repository: `videolan/vlckit`
- Pinned revision: `2e0868f5ed40fe59cd92f377645fdcc260c6e759`
- Product used: `VLCKit`
- Swift package form at the pinned revision: binary target / framework package
- License file at the pinned revision: GNU Lesser General Public License 2.1 (LGPL-2.1)

Distribution gate:
- do not treat LGPL as equivalent to MIT/Apache permissive licensing;
- before App Store/TestFlight/public binary distribution, verify that the chosen VLCKit binary/linking/distribution method satisfies the applicable LGPL requirements, including notices, license copy, source/relinking obligations where applicable, and any constraints imposed by the distribution channel;
- if those obligations cannot be satisfied cleanly, replace or isolate the VLC fallback before public distribution rather than silently shipping a non-compliant binary.

## Apple system frameworks

The project also uses Apple platform frameworks such as AVFoundation, AVKit, CoreMedia, SwiftUI and UIKit. These are platform SDK/system dependencies and are not vendored into this repository as third-party source packages.

## Maintenance rule

Whenever a dependency version/revision changes:

1. re-check the license at the exact new tag/revision;
2. update this document;
3. verify any new NOTICE/attribution requirements;
4. re-evaluate App Store distribution implications before release.
