<p align="center"><img width="80" src="https://github.com/user-attachments/assets/628d4334-7326-446e-9f2a-4d3ab4fc95c3" alt="Downtify logo"></p>
<h1 align="center">Downtify for iOS</h1>
<p align="center">
  <a href="#install-the-beta-with-testflight">Install</a> •
  <a href="#features">Features</a> •
  <a href="#downtify-server">Downtify Server</a> •
  <a href="#build-and-test-on-a-mac">Build &amp; Test</a> •
  <a href="#project-documents">Documentation</a>
</p>

<p align="center">Your self-hosted Downtify library on iPhone and iPad.<br>Browse, discover and listen wherever you go.</p>

## Overview

Downtify for iOS is a SwiftUI app for connecting to your own Downtify server. Browse and play your library, discover music in the server catalog and keep tracks on your device for offline listening. The app requires iOS or iPadOS 17 or later and a reachable compatible server for server-backed features.

## Features

| | |
| --- | --- |
| **Library** | Connect to your server, sync your library and browse your music on iPhone or iPad. |
| **Playback** | Listen with a persistent library and catalog queue, queue editing, shuffle, repeat, and background and lock-screen controls. |
| **Search and discover** | Search your synced library and the server catalog; explore Finder, personalized suggestions, charts and similar tracks. |
| **Downloads** | Submit catalog tracks to the server download queue or save available tracks to your device for offline listening. Server jobs and device downloads are shown separately. |

## Screenshots

<p>
  <img src="screenshots/app-store/01-home.png" alt="Downtify home screen" width="24%">
  <img src="screenshots/app-store/02-album.png" alt="Album view" width="24%">
  <img src="screenshots/app-store/03-now-playing.png" alt="Now Playing screen" width="24%">
  <img src="screenshots/app-store/04-queue.png" alt="Play queue" width="24%">
</p>

## Install the beta with TestFlight

To try Downtify on an iPhone or iPad running iOS or iPadOS 17 or later:

1. Install Apple's free [TestFlight app](https://apps.apple.com/app/testflight/id899247664) on your device.
2. On that device, open the [Downtify public beta invitation](https://testflight.apple.com/join/Uej1Yta5).
3. In TestFlight, tap **Accept**, then **Install**. If you have already joined, tap **Update** or **Open** instead.
4. Open Downtify and connect to a reachable Downtify server instance to use the server-backed features.

TestFlight shows whether a compatible beta build is available for your device. See [Apple's TestFlight instructions](https://testflight.apple.com/) for more help with installing and updating beta apps.

## Build and test on a Mac

Open `Downtify.xcodeproj` with the installed Xcode version. Install an iOS simulator runtime in Xcode Settings, choose the shared **Downtify** scheme and an iPhone or iPad simulator, then use **Product → Run** and **Product → Test**. Simulator builds do not need a development team.

For command-line validation, use an available simulator UDID from the listing.

```sh
xcrun simctl list devices available
xcodebuild -project Downtify.xcodeproj -scheme Downtify -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' -derivedDataPath /tmp/DowntifyDerived clean build-for-testing
xcodebuild -project Downtify.xcodeproj -scheme Downtify -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' -derivedDataPath /tmp/DowntifyDerived test-without-building
```

## Simulator checklist

Run the test suite above for deterministic playback, persistence, network-contract, and presentation behavior. Then use **Product → Run** to review the complete user flow:

- Connect to a reachable server, sign in, refresh the library, and start a track.
- Open Now Playing; verify play/pause, seek, previous/next, shuffle, and all three repeat modes.
- Open Play Queue; verify the current item and upcoming items, select an upcoming item, remove an item (including one duplicate track occurrence), and reorder upcoming entries.
- Confirm queue edits and the selected occurrence survive relaunch, and confirm lock-screen controls/metadata while audio plays.
- Try sign out and reconnect, including the permission and error states relevant to the server.
- Search both the synced library and server catalog; try a supported URL resolve, Finder browse, Discover collections, charts and Similar.
- Request a server download from a catalog result and confirm it appears in the server queue. Compare this with a device offline download, which is stored on the phone and available offline.
- In library-only mode, confirm catalog actions that require external providers are unavailable and local catalog search remains usable.

Manual server-backed playback, catalog discovery, server download queue updates, persistence across an app relaunch, and lock-screen behavior require a reachable server and device/simulator interaction; automated fixture tests alone do not verify these end-to-end steps. See [the parity audit](docs/WEBUI_PARITY_AUDIT.md) and [execution handoff](docs/EXECUTION_HANDOFF.md) for current implementation and verification status.

## Downtify Server

[Downtify](https://github.com/henriquesebastiao/downtify) is the original self-hosted server project by [Henrique Sebastião](https://github.com/henriquesebastiao). It downloads and organizes music, provides a web interface and exposes the API used by this app. Set up your own server and connect the app to an address reachable from your device.

Repository: **[henriquesebastiao/downtify](https://github.com/henriquesebastiao/downtify)**

Getting started: **[Downtify installation guide](https://downtify.henriquesebastiao.com/getting-started/installation/)**

## License

This project is licensed under the [GNU General Public License version 3](LICENSE), matching the Android reference app.

## About page release notes

If `release-notes/<version>-<build>.json` exists (for example `0.1.2-8.json`), its bullets are packaged as the About page list; add one for every release so builds from `main` are not empty. Otherwise Xcode generates the About page bullet list at build time from commit subjects on the current branch since its merge base with `origin/main` (falling back to local `main`). The generated `ReleaseNotes.json` is packaged into the app. Keep commit subjects user facing when building a release branch; a build from `main` itself has no branch changes to list.

## Boundaries and platform decisions

- **App** owns composition. The SwiftUI App holds a single container across scenes. Add concrete adapters at this boundary as their features land and pass feature dependencies through initializers. Presentation owns scene and main-actor UI state. Future playback and transfer coordinators should be process-scoped, with their mutable state isolated from views.
- **Presentation** receives domain values and feature protocols as those are introduced. **Network/V1** owns wire names and decoding. Transport and DTO-to-domain mapping belong at the network and repository boundaries. Add **Domain**, **Data** and **Playback** groups when they have concrete responsibilities.
- Use system SQLite through `SQLite3` for the synced library and durable operations. Keep the connection behind an isolated store. Apply ordered schema migrations in transactions and test upgrades from supported versions. A failed migration should preserve the database and surface a recovery state. Only explicitly rebuildable data can be discarded and resynced.
- Put durable data and offline media in Application Support, separate from purgeable stream and artwork caches. Exclude redownloadable media and database state from backup while preserving durable user-created state. Use complete-until-first-user-authentication file protection where background access after unlock is required and complete protection for foreground-only sensitive files. Protect database sidecars alongside the database. Store the device token in Keychain with after-first-unlock, this-device-only accessibility if background authentication is required.
- Use the SwiftUI scene lifecycle for foreground refresh and state persistence as those features land. Add background modes and any delegate callbacks with the playback and transfer implementations that require them.

## Project documents

- [Porting plan](docs/PORTING_PLAN.md)
- [Simulator automation (debug harness)](docs/SIMULATOR_AUTOMATION.md)
- [Android parity audit](docs/ANDROID_PARITY_AUDIT.md)
- [Search, Finder and Discover parity audit](docs/WEBUI_PARITY_AUDIT.md)
- [Agent handoffs](agents/README.md)
