# Changelog

Historical record of Downtify iOS releases (version 0.1.2), newest first. Each build lists the user-facing notes shipped to TestFlight (from `release-notes/`), followed by the notable changes behind them. Issue numbers refer to the project issue tracker.

Builds 0.1.2-7 and earlier predate the curated release notes; their entries are reconstructed from git history.
## 0.1.2 (11) — 2026-11-21

Release notes:
- Now Playing has clear Like, Up Next and Add to Playlist buttons
- Tap the artist or album in Now Playing to open the full artist or album page, including catalog music you don't own yet
- Album artwork now shows on the lock screen and in Control Center
- Catalog artists in Search show their photos
- More of the app is translated in every supported language

Changes:
- Open artist and album pages from Now Playing (#43)
- Make Like, Up Next and Add to Playlist discoverable in Now Playing (#57)
- Show album artwork on the lock screen and in Control Center (#44)
- Show artwork in Catalog Artists search results (#47)
- Localize string-literal ternaries outside Now Playing and add a guard against new ones (ported from #59)
- Localize Now Playing navigation hints flagged by the ternary guard

## 0.1.2 (10) — 2026-11-20

Release notes:
- Songs you already own now show as In Library, and adding them again no longer creates duplicate versions
- The currently playing song is highlighted in song and album lists
- The network debug overlay is now translated in every supported language

Changes:
- Show owned songs as In Library and stop adding duplicate versions (#27)
- Highlight the currently playing song in song and album lists, with a UI regression test (#46)
- Fix localization parity for the network debug overlay
- Add a debug-only harness for repeatable simulator tests (#48)
- Add Add to Library request capture and server trace to issue 27 findings (docs)

## 0.1.2 (9) — 2026-11-17

Release notes:
- Add to Library and Add to Device now clearly distinguish server downloads from offline copies on your phone
- See storage usage and clear app data while keeping your sign-in
- Playback can recover from temporary stream failures and keep the current song's quality when the network changes
- The network debug overlay shows queue and cache readiness and can be resized and moved
- Network diagnostics and the concurrent request limit are now in Settings

Changes:
- Add to Library / Add to Device wording and actions across catalog search, Discover, artist albums, podcasts, Downloads and library menus; localized (#25)
- Show In Library on library-matched catalog rows and on albums already fully in the library, including track-count lookup for owned-looking albums; rows update after Add to Library (#25)
- Offer Add to Device on catalog rows that are in the library (#25)
- Add a Storage section in More with storage usage by category and Clear App Cache and Saved Data, keeping the login (#26)
- Improve playback recovery and network diagnostics; keep bounded skipping for unplayable catalog tracks
- Translate the playback quality setting

## 0.1.2 (8) — 2026-11-16

Release notes:
- Dismiss the keyboard in Search and Finder by tapping outside the field, pressing Done, or scrolling
- Playback on slow or unstable connections now builds a short startup buffer sized to your measured server speed
- Background preloading no longer crowds out album artwork and playback requests: concurrent requests default to 4 and can be changed in More > Diagnostics
- Network debug overlay now shows the effective audio delivery rate
- Likes and playlist favorites made while offline are queued and sent when the connection returns, with pending status in More
- Playlist editing: duplicate-aware add and remove controls, conflict recovery, and localized feedback

Changes:
- Dismiss keyboard from search fields (#17)
- Adapt playback buffering to server throughput
- Add curated release notes and bump build number

## 0.1.2 (7) — 2026-11-13 (TestFlight)

- Finish playlist editing integration (#14)
- Prepare TestFlight 0.1.2 build 7

## 0.1.2 (6) — 2026-11-12

- Prioritize playback and improve album browsing (#11)
- Resolve YouTube Music catalog results by song ID (#10)
- Buffer/Queue (#9)
- Preload the current song and five upcoming songs for offline playback (#8)
- Add TestFlight beta installation instructions (#7)
- Keep final list actions clear of the playback dock (#6)
- Make the About page public (#5)
- Integrate catalog discovery, library search and playlist editing (#4)

## Initial — 2026-11-06

- Initial clean repository snapshot
- Correct About screen license information
- Update About page project links (#1)
