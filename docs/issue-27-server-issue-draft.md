Title: Prevent duplicate versions of songs already in the library (catalog ID and song_key guard, per-track album progress)

Source checkout: Downtify server at commit df3da344. Line numbers below refer to that commit.

## Context

Client issue: https://github.com/michaelmoskie/Downtify-IOS-Client/issues/27

Adding a song can add a second version of a song the library already has. The iOS client now hides
"Add to Library" for songs whose artist+title key is already owned, but the server should also guard against
duplicates, because other clients and direct API calls reach the same endpoints.

Current behavior summary:
- Duplicate checks run only when `overwrite_existing_files` is off (api.py:4465, downloader.py:1065). It defaults to on (api.py:747, downloader.py:433), so repeat requests re-download and overwrite.
- When it is off, the check matches only Spotify IDs (track_index.py:26, 324) or the rendered filename (downloader.py:771, 833). YouTube and Deezer IDs are not checked.
- `/api/library/lookup` matches only `song_key` (library_catalog.py:696, 867). It does not match catalog IDs, and it does not echo the request index or ID per result.

## Requested changes

### 1. Duplicate guard on song and batch requests (independent of overwrite)

Current: `POST /api/download/url` (api.py:4712) builds one song (`_song_from_download_request`, api.py:4070) and registers one job (`_register_job`, api.py:4150). `POST /api/download/batch` (api.py:5916) registers one job per row via `_submit_playlist_batch` (api.py:5865) and `_process_batch` (api.py:4934). None of these check the library before queuing when overwrite is on.

Proposed, applied to both endpoints and each batch row:
- (a) Exact catalog-ID match: `song_id`, `youtube_id`, Spotify ID or Deezer ID matches a library track. Treat as already in library.
- (b) Version match: the row has the same `song_key` as an existing library track, even if the catalog ID differs (for example a different release or live version). Treat as already in library. Live, Explicit and Clean stay distinct in `song_key`. Remaster and feat tags do not change it.
- Rule (a) alone would not stop the reported bug, because different versions of one song have different video or catalog IDs. Use `song_key` for both lookup (item 2) and this guard, so the two rules agree.
- Response status: `already_in_library`.
- The match skips the download and returns the existing file's filename with status `already_in_library`, regardless of `overwrite_existing_files`.
- Proposed: an explicit request flag, for example `allow_duplicate: true`, forces a new copy. The app already has an "Add another copy of existing tracks" toggle, which would map to this flag.

### 2. `/api/library/lookup` matches by catalog ID, then by song_key

Current: match on `song_key` only (library_catalog.py:867, key at 696). Returns one row per distinct key, not per input song (library_catalog.py:881 caps input at `LOOKUP_SONG_MAX`, line 112). No index or echo.

Proposed:
- Match catalog IDs first, then fall back to `song_key`, using the same rule as item 1.
- Echo the request index and, if given, the request ID for each result, for example `{matches: [{input_index, id, row}]}`.

### 3. Album add: per-track job IDs and resolved album info

Current: `POST /api/download/album` (api.py:6090) validates the URL in `_songs_for_album_download` (api.py:6074). It downloads the album's track list (`album_tracks_from_browse_id`, providers.py:2748) and returns `{song_id: filename}` after all tracks finish, so the client waits on one blocking request.

Proposed:
- Do not add a new endpoint. The album endpoint queues one job per track and returns right away with the job IDs.
- Response also includes the resolved album title and track count, so the client can check scope before downloads finish.
- The client reads progress from the existing queue endpoint (`GET /api/queue`, api.py:8581).

### 4. Trash toggle (secondary)

Current: `DOWNTIFY_TRASH=true` or `DOWNTIFY_TRASH_CONFIG` must be set in the server environment, then the server restarts (`trash_from_env`, library_trash.py:1065, env read at 1077-1080). The app cannot turn this on, so a duplicate added by this bug cannot be removed from the app.

Proposed: an admin-only field in the existing server settings API (the `overwrite_existing_files` field is already settable there, api.py:9098-9100). The environment variable stays as the default and override.

## Acceptance criteria

1. With `overwrite_existing_files` on, requesting a song whose `youtube_id` is already in the library returns `already_in_library` and queues no download.
2. The same request with `allow_duplicate: true` queues a download and does not return `already_in_library`.
3. Requesting a different video of a song whose `song_key` is already in the library (for example a remaster) returns `already_in_library`.
4. A live version of an owned song is not blocked by `song_key` (it has a different key).
5. A batch with one duplicate row and one new row queues only the new row and reports the duplicate with its existing filename.
6. `POST /api/library/lookup` with a catalog ID that is in the library returns a match with the request's `input_index`, even if the `song_key` differs.
7. `POST /api/download/album` returns without waiting for the tracks to finish, with one job ID per track, the resolved album title, and the track count.
8. `GET /api/queue` shows the per-track jobs for that album as they progress.
9. The trash setting can be changed by an admin through the settings API without a server restart, and a non-admin cannot change it.

## Open questions for the maintainer

- Q1: Block versions by `song_key` as well as by catalog ID (proposed), or only by catalog ID? The `song_key` rule blocks different versions that share artist and title, and may block legitimate separate releases.
- Q5: Admin-only settings field (proposed), or environment-variable only? A settings field makes trash available to the app, but changes who can enable it.
