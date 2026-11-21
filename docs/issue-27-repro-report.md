# Issue 27 reproduction report (simulator, 2026-11-20)

Issue: https://github.com/michaelmoskie/Downtify-IOS-Client/issues/27

Setup: iPhone 18 Pro simulator (iOS 27.0), installed app 0.1.2 (8), signed in to the real Downtify server
(HTTPS, remote host). All the code cited below is the same on `origin/main` (a042f7b).
Screenshots are in `docs/issue-27-evidence/`.

## Summary

| Symptom | Reproduced? | Where the bug is |
|---|---|---|
| 1. Adding a song adds another version of a song already in the library | **Yes** | Client: catalog rows never show "In Library" for songs the user already owns. Server: no duplicate check by default. |
| 2. Adding an album adds the artist's whole catalog | **No** (tested two album entry points) | Every client album path checked sends only one album URL or that album's tracks. The server album endpoint expands only that album. |

## Symptom 1: duplicate versions (reproduced)

### Steps
1. Search tab → Songs → "Karma Police".
2. The results show **In your library: Karma Police · Radiohead** (one row), and below it, under
   **Catalog songs**, several Radiohead versions (OK Computer OKNOTOK 1997 2017, OK Computer, …). Each one shows
   the green **+ (Add to Library)** button (`01-karma-police-before.png`).
3. Tap **+** on the OKNOTOK row. No warning appears, and the request is sent.
4. About 30 s later, **In your library** shows **two** "Karma Police · Radiohead" rows (`02-karma-police-after.png`).
   Library → Albums → Recently added now has a new album, "OK Computer OKNOTOK 1997 2…" (`04-recently-added-after.png`).

The same thing happens wherever catalog songs are listed. For example, the Downloads screen's "Find music to add" list
showed two separate "Airbag · Radiohead" rows, each with its own +, even though Airbag is already in the library from
OK Computer (`06-two-airbag-rows.png`).

### Root cause

1. **The client never marks a catalog row as already in the library.** In `Downtify/Domain/LibraryMembership.swift`,
   `track(for:)` returns a track only when `song.source == "library"`:
   ```swift
   func track(for song: CatalogSong) -> LibraryTrack? {
       guard song.source == "library", let file = song.file, ...
   ```
   `LibraryHomeView.libraryTrack(forCatalogSong:)` (and through it `catalogLibraryState`) depends on this, so a
   YouTube Music, Deezer or Spotify row counts as "in library" only after this app session has added it
   (`completedFilename(forActionKey:)`). A song the user already owns always shows +, on Search, Discover and the
   Downloads screen.
2. **Each catalog row is a separate version, and nothing de-duplicates them.** Search returns one row per
   release (original album, remaster/OKNOTOK, live, compilations). `ServerDownloadPresentationModel.request(song:)`
   keys its state by `song.id`, so adding one version does not mark the others as added.
3. **The server accepts the request and keeps both files.** `overwrite_existing_files` is on by default, and the
   duplicate check compares only the Spotify ID or the output filename. A different album tag produces a different
   filename, so the second version is saved as a new file (see "Duplicates" in `docs/issue-27-findings.md`).

Album-level state works differently. `isAlbumFullyInLibrary` matches on album title and artist, which is why
"OK Computer" showed ✓ while its individual songs showed +. That mismatch makes the bug easy to hit.

## Symptom 2: album adds whole catalog (not reproduced)

### What was tested
- **Search → Albums → "The Bends" → +.** One `POST /api/download/album` request. Afterwards Recently added showed
  only *The Bends* (plus the OKNOTOK album from the symptom 1 test). No other Radiohead albums appeared
  (`03-album-add-no-confirmation.png`, `04-recently-added-after.png`).
- **Library → Artists → Radiohead → Find more albums → Pablo Honey** (the `ArtistCatalogAlbumView` that feeds
  "Add Missing Songs to Library"). It lists exactly the album's 12 tracks, You through Blow Out
  (`05-artist-album-pablo-honey-scoped.png`). I did not tap the batch button, to avoid adding 12 more files.

### Code check (all entry points on main)
`requestAlbum` is called from 4 places: Search album row, Discover album row, "Albums in this link", and the
Downloads album row. All of them pass a single YouTube Music `MPREb_`/`OLAK5uy_` URL; `isYouTubeMusicAlbumURL`
enforces this. `requestBatch` is called from 2 places: the Downloads multi-select and the artist-album
"Add Missing Songs". Both send only the rows shown on screen. On the server, `_songs_for_album_download` rejects
any URL that is not an album and expands only one `get_album` track list. Nothing found loops over an artist's
albums.

### Still unexplained
- I tested Radiohead only. I did not test an artist with a very large catalog, or Deezer-only albums, which have no
  + button.
- The report may come from an older build. The installed build is 0.1.2 (8). Ask the reporter for the build, the
  exact screen and the artist.
- A likely explanation: users who don't see "In Library" on songs they already own (symptom 1) and add album after
  album would see the artist's catalog pile up as duplicates.

## UX gaps from the issue's expected behavior (confirmed)
- The album + sends at once: there is no confirmation and no track count (`03-album-add-no-confirmation.png`).
- The album request is one blocking POST (up to 600 s) with a spinner. There is no progress per track.

## Suggested fixes
1. Client: compute library membership for catalog rows. Match by catalog ID when the library has it; otherwise
   use a normalized artist + title key, the same `song_key` rule `/api/library/lookup` uses. Show
   "In Library" or an "Add another version?" confirmation instead of a bare +.
2. Client: group catalog versions of the same song (normalized artist + title) and mark all of them once one is
   in the library or queued.
3. Client: show the track count and ask for confirmation before an album add above a threshold, as the issue
   requests.
4. Server (separate issue): skip or report `already_in_library` by catalog ID regardless of
   `overwrite_existing_files`, and extend `/api/library/lookup` to match by ID (see `docs/issue-27-findings.md`).

## Side effects of this run (on the real server)
- Server: the user's self-hosted Downtify server (HTTPS, address redacted), signed in as an admin.
- Added and left in place on purpose: *The Bends* (full album) and a second *Karma Police*
  (album "OK Computer OKNOTOK 1997 2017", the only track in that album).
- I tried to remove them with Move to trash, and the server answered "Music trash is disabled or unavailable."
  Trash has no UI switch. It turns on only through the server environment variable `DOWNTIFY_TRASH=true`
  (or `DOWNTIFY_TRASH_CONFIG`) followed by a restart (`trash_from_env` in the server's `downtify/library_trash.py`).
  As things stand, a duplicate added by this bug can't be removed from the app.
