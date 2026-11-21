# Issue 27 findings

## Client requests

What the iOS client sends for each Add to Library entry point. Captured by
`DowntifyTests/Issue27CaptureTests.swift` with a recording fake transport (each test prints an
`ISSUE27-CAPTURE` line with method, path, query and body). Fixtures are hand-built to match the shapes in
existing tests, not captured from a live server.

| Entry point | Request | Identifier sent | Over-fetch risk | Evidence |
|---|---|---|---|---|
| Search song row, YouTube Music | `POST /api/download/url?url=<watch URL>`, body = the full row JSON | `https://music.youtube.com/watch?v=<id>`, plus `youtube_id` in the body | Low. One video ID. | `testSearchSongRow_YouTubeMusic_...`; `ServerDownloadQueue.swift:78` |
| Search song row, Deezer | same endpoint, `url=https://www.deezer.com/track/<id>`; body has `song_id`, `deezer_album_id`, `deezer_artist_id`, no `youtube_id` | Deezer track URL | Medium. The server must pick a YouTube match by title/artist/duration, so it can choose original, live, remaster or explicit/clean. The client sends nothing that pins a version. | `testSearchSongRow_Deezer_...` |
| Search song row, Spotify | same endpoint, `url=https://open.spotify.com/track/<id>`; no `youtube_id` | Spotify track URL | Same as Deezer. | `testSearchSongRow_Spotify_...` |
| Search song row, text-search pseudo row | same endpoint, `url=downtify-search:<id>`, body has `download_by_metadata:true`, name, artists | Title and artist (no real URL) | High. This is a pure title/artist query, so the server can match several versions. | `testSearchSongRow_TextSearchPseudoURL_...` |
| Discover song row (charts, similar, finder) | identical to the search song row (same `serverDownloads.request(song:)`) | Same as the row's source | Same as the matching source above. Chart titles often carry "(Remastered)" or "(Deluxe)", and these go through verbatim. | `testDiscoverSongRow_...`; `LibraryHomeView.swift:1473` and `:1506` |
| Search album row (YouTube Music album only) | `POST /api/download/album?url=<album URL>`, no body | YouTube Music `/browse/MPREb_...` or `playlist?list=OLAK5uy_...` URL | Medium. The client names an album URL only, and the server expands it. Which tracks it downloads depends entirely on the server's album handler. The client's `expected` list is used only to score the reply. | `testSearchAlbumRow_...`; `ServerDownloadQueue.swift:99`; `CatalogSearchView.swift:448-463` |
| "Albums in this link" | same request as the search album row; `expected` is the link's whole track list when the link resolves to exactly one album | Same album URL | Same as the search album row. | `testAlbumsInThisLink_...`; `CatalogSearchView.swift:415-421` |
| Downloads screen, album action | same request, `expected` omitted | Same album URL | Same as the search album row. | `testDownloadsScreenAlbumAction_...`; `DownloadsView.swift:237-246` |
| Deezer / Spotify album rows | No request. The button is only shown for YouTube Music album URLs, and `requestAlbum` rejects anything else. | n/a | None from the client. | `testDeezerAndSpotifyAlbumURLsNeverReachTheAlbumEndpoint` |
| Artist album "Add Missing Songs to Library" | `POST /api/download/batch`, body `{songs:[<full rows>], generate_m3u:false}`; no playlist, album or artist field | Each track's own row (Deezer/Spotify/YouTube URL) | Per-track risk as above. Not an artist-catalog dump: the list is only the opened album's tracks. | `testArtistAlbumAddMissing_batchContainsOnlyTheOpenedAlbumsTracks`; `LibraryHomeView.swift:1093-1175` |

### Artist album batch: what goes in the list

`ArtistCatalogAlbumsView` (`LibraryHomeView.swift:~1005`) lists albums with
`searchAlbums(query: <artist name>, limit: 50)`, keeping rows whose `artist` equals the artist name.
Opening one album (`ArtistCatalogAlbumView`) loads `songs` from `finderAlbum(id: <that album's Deezer ID>)` or,
without a Deezer ID, `resolve(url: <that album's URL>)`. "Add Missing Songs to Library" then calls
`requestBatch(songs: songs.filter(canRequest))`. So the client batch holds the opened album's tracks and nothing from
the artist's other albums, as the 2-album fixture in the test shows. If the server's `/api/finder/album` or
`/api/url/resolve` returns more than the album's tracks, the client forwards all of it unfiltered.

### Open points for the server side

- Songs: for Deezer, Spotify and text-search rows the client sends a provider URL or metadata, never a YouTube ID. Version
  selection (original, live, remaster, explicit/clean) happens server-side.
- Albums: the client sends only an album URL. Any "adds the whole artist" behavior would come from the server's album
  handler (for example treating a browse or playlist URL as an artist or search query), or from the album-lookup endpoints
  returning extra tracks.
- Client-side gap: the 4 song entry points and the batch send the whole row without de-duplicating songs that share
  title and artist. The batch de-duplicates action keys only by `songID`/`youtubeID`/`url`, so two rows for different
  versions of the same song both go out.

## Server trace (read-only, local checkout of Server/downtify at 3ab33ee; the deployed test server may differ)

### Issue 27 server trace (read-only; local checkout of /Users/moskie/Documents/DownDev/Server/downtify)

All paths relative to `downtify/`. Line numbers are from the local checkout and may differ from the deployed server.

## Song requests (`POST /api/download/url`)

- Entry: `api.py:4669 download_endpoint`. It calls `_song_from_download_request` (api.py:4028), registers exactly ONE job via `_register_job` (api.py:4108, called at ~4700) and runs exactly ONE `_run_download` (api.py:4303). There is no loop or fan-out; one call can never create more than one job/download. Return value is a single filename.
- `_song_from_download_request` (api.py:4028-4056):
  - body `download_by_metadata: true` -> body used as-is, `_match_by_metadata` set (YouTube search by title/artist, i.e. a *fuzzy* pick).
  - body `source` in `{'text_search','deezer'}` (api.py:4025) -> body used as-is, URL ignored.
  - otherwise `_song_for_download(url)` (api.py:4059-4100), then `_merge_client_track_hints` (api.py:3956) copies track_number, release_date, explicit, album_artist, and any body `youtube_id` / `soundcloud_url` (api.py:4010-4022, marks `youtube_id_override`, i.e. "download exactly that video").
- Per input form (`_song_for_download`, api.py:4059):
  - YouTube watch URL -> `parse_youtube_url` kind `track` -> `providers.song_from_video_id` (single video; `watch?v=..&list=..` stays a track, providers.py:1286 docstring). One exact version.
  - Spotify track URL -> `spotify.track_from_id` (metadata only, no video id). The audio is then chosen at download time by `Downloader._resolve_source` -> `providers.find_match` (downloader.py:547, 605-611; providers.py:1379) = text search on title/artist/duration (+ album-tracklist fallback, providers.py:2800ish). This is a *single guess*: can land on the wrong version (live/remaster/clean), but only ONE version per request. `find_match` has variant filters (live/karaoke etc. only match if the wanted title says so, providers.py:1882-1918, 3092). BUT if the body carries `youtube_id`, it overrides the search (api.py:4017-4022; downloader.py:563-607).
  - Deezer track URL -> `deezer.track_from_id` (api.py:4081), same search-by-metadata behaviour as Spotify. Body with `source=='deezer'` skips URL resolution entirely.
  - Album URL (`/browse/MPREb_`, `list=OLAK5uy_`) -> kind `album` -> HTTP 400 "Only single YouTube video URLs are supported here" (api.py:4070). Not expanded.
  - Artist/channel URL (`/channel/UC..`, `.com/@handle`) -> kind `artist` -> HTTP 400 (same branch). Playlist URL (`/browse/VL..`, bare `list=`) -> kind `playlist` -> HTTP 400.
  - SoundCloud URL -> single track. Anything else -> 400 "Unsupported URL" (api.py:4100). A plain search string is not accepted (it is a URL param run through the parsers).
- Note on queue key: `_register_job` keys by `song['song_id'] or song['url'] or id(song)` (api.py:4118ish). Two different versions with different `song_id` get two separate jobs/files; the same `song_id` twice joins the existing job while it is queued/downloading and restarts a finished one (api.py:4108 docstring).

## Batch (`POST /api/download/batch`)

- `api.py:5874`: takes `payload['songs']`, `_submit_playlist_batch` (api.py:5823) registers one job per dict in `songs` (non-dicts skipped), then `_process_batch` (api.py:4892) downloads exactly those songs via `_run_download`. No expansion: `song.url` is NOT re-resolved here (rows are used as given; Spotify/YTM enrichment only happens later inside the downloader for sparse rows, downloader.py:1065-1070).
- `playlist_url` is only parsed with `parse_playlist_url` + `fetch_playlist` (api.py:4905-4925) to get the playlist *name* (folder / M3U / Spotify track-count bookkeeping). The fetched `tracks` are never enqueued. If an album-ish URL were passed as `playlist_url`, it would at most rename the target folder. `playlist_name`/`cover_url` are used directly (api.py:5893-5896).
- So: batch downloads exactly the given payloads, one version each (resolved per row as in "Song requests": `youtube_id` in the row is used if present, else fuzzy match).

## Album (`POST /api/download/album`)

- `api.py:6048` -> `_songs_for_album_download` (api.py:6032): requires `parse_youtube_url(url)` kind == `album`, else 400. `parse_youtube_url` (providers.py:1286-1318) returns `album` only for `/browse/(MPREb_...)` (providers.py:1270) or `list=(OLAK5uy_...)` (providers.py:1271). A `/channel/UC` or `@handle` URL returns `artist` (providers.py:1272-1273, 1309-1312) and is rejected with 400. Note the album regexes are checked FIRST and unanchored (`search`), so only a URL that literally contains an `MPREb_` browse path or `list=OLAK5uy_` is treated as album.
- `providers.album_tracks_from_browse_id` (providers.py:2748): for `OLAK5uy_` ids resolves one browse id via `get_album_browse_id`; then `_cached_album_tracks_and_count` (providers.py:2468) = `ytmusicapi.get_album(browse_id)['tracks']` only. It reads just `data['tracks']`; it does NOT read `related`, "more from artist" or other shelves of the album response. Output = that album's tracks, one dict each (`_album_track_song`), skipping rows with no videoId. Cached by browse id (`_album_track_cache`).
- `download_album_endpoint` downloads exactly that list (api.py:6100-6125), returns `{song_id: filename}`.
- Conclusion: the server endpoint cannot return an artist's whole catalog. The only way to get a whole artist would be the client sending an artist's id/URL as album URL (rejected with 400) or the client enqueueing many albums / looping over `artist_albums_from_channel_id` results itself.

## Artist discography (reachable?)

- `providers.artist_albums_from_channel_id` (providers.py:894) is used by `GET /api/song/url` (`_resolve_url`, api.py:3647-3651) and `_collection_details` (api.py:3770-3782, artist -> `{'kind':'artist','tracks':[],'albums':[...]}`) and by monitor.py:1583. These are search/link-resolution (GET) and the monitor, not download endpoints. None of `/api/download/url`, `/batch`, `/album` call it. It returns lightweight album summaries ("no tracklists", providers.py:900-906), never tracks.
- Implication: if the app, after resolving an artist, gets many album summaries and then posts each album / all their tracks (or posts every track of `albums`), the whole catalog comes from the client's loop, not a server expansion. Also: if the client ever calls `/api/download/album` once per album row of an artist result (rather than only the tapped one), that yields the full catalog.

## Duplicates

- Default settings: `overwrite_existing_files: True` (api.py:713; downloader.py:431). `_finish_with_existing` (api.py:4417-4423) and `Downloader._download_impl` (downloader.py:1041) only skip when that setting is OFF. With the default, a repeat request re-downloads and overwrites the same filename; no "already in library" response.
- When overwrite is OFF, skipping is by (a) Spotify track id in `TrackIndex` (`normalize_spotify_track_id`, track_index.py:26; `resolve_existing_download`, track_index.py:324-349) - only for 22-char Spotify ids in `song_id`/`url`; YouTube/Deezer `youtube_id`/`song_id` are NOT checked; or (b) rendered output filename (`existing_filename_for`, downloader.py:767; `find_existing_download`, downloader.py:829 scans the whole library for the same artist/title (+album per template) stem, case-insensitive). No content hash, no `youtube_id` comparison.
- Consequence: the same song requested twice = same filename = overwrite (default) or skip (setting off). Two *versions* (e.g. "Song", "Song - Live", "Song (Remastered 2011)", explicit/clean from different video ids) render different names (title differs; `{album}` often too) -> kept as separate files, so the library really can hold several versions. Duplicate uploads of the same title/artist/album collide on filename (one file), but with different album/version tags they become distinct files.
- The client is the one creating multiple requests for one "song" if the search results list several versions; the server treats each distinct payload as a distinct song.

## Library lookup (`POST /api/library/lookup`)

- `api.py:7008 library_lookup` -> `library_catalog.lookup_library_songs` (library_catalog.py:867). Body `{songs:[...]}`, max 200 (`LOOKUP_SONG_MAX`, library_catalog.py:112).
- Matches ONLY on `song_key(artist, title)` (library_catalog.py:696): `artist` = `artist` or `artists[0]` (first before `,`/`;`/` & `), title = `title` or `name`; both folded, "(feat ..)", "(...remaster...)", " - ... remaster" tails and non-alnum stripped. Result `artist|title`. No song_id/youtube_id/Spotify/Deezer id matching; live/explicit/clean tags are NOT stripped, only feat/remaster, so Live stays distinct but Remaster == original.
- Response: a JSON list of library listing rows (same shape as `GET /tracks`, `listing_for_request`; includes at least `file`, `title`, `artist`, `album` ...), one row per distinct matched key (first hit; `found_keys` de-dupes), NOT one row per input song and not echoing the input index/ids. The client must re-derive the key to correlate. Non-admins are limited to their own files (`allowed_entry_keys`).
- Could support catalog-ID matching only with a server change (index `song_id`/`youtube_id`/`spotify id` from track index or tags and echo the request id).

## Verdict per symptom

1. Multiple versions of one song added: **POSSIBLE, mostly client/catalog-side; server cannot add several from one request.**
   - One `/api/download/url` call = one job = one file (api.py:4669-4730; no fan-out). One batch row = one job (api.py:5833-5843).
   - Server contributes: (a) Spotify/Deezer URLs resolve by fuzzy search, so it can pick one wrong version (live/remaster/clean) (downloader.py:605-611, providers.py:1379) unless the body carries `youtube_id` (api.py:4017); (b) nothing stops different versions co-existing: dedup is only by Spotify id or rendered filename, and is off by default (api.py:713, 4423); `/api/library/lookup` matches only artist|title, not versions.
   - Several versions most plausibly come from the search results listing several versions as separate rows, or from the client sending many rows / repeated taps.
2. Album adds whole artist catalog: **NO (server cannot cause it from `/api/download/album`)**.
   - `/api/download/album` accepts only `MPREb_`/`OLAK5uy_` URLs (api.py:6032-6040), artist/channel/handle URLs get 400, and tracks come from one `get_album` tracklist (providers.py:2748-2790, 2468-2490). Batch never expands (api.py:5823-5873, 4892). Artist discography (`artist_albums_from_channel_id`, providers.py:894) is only reached via GET resolve (`/api/song/url`, api.py:3647, 3781) and returns album summaries, no tracks.
   - Remaining server-side possibility: an `OLAK5uy_` playlist id that `get_album_browse_id` maps to a wrong/other release is unlikely and would still be one album. More likely client: looping over every album summary or sending all artist songs.

## Server changes that would help

- Make duplicate handling ID-aware: on `/api/download/url` and batch rows, skip/return "already in library" by `song_id`/`youtube_id`/spotify/deezer id (index these in `TrackIndex`), independent of `overwrite_existing_files`; return a status (`skipped_existing`) the client can show.
- Extend `/api/library/lookup` to match on catalog IDs (`song_id`, `youtube_id`, spotify/deezer ids) first, fall back to `artist|title`; echo the request index/id per row (or return `{matches:[{input_index, row}]}`) and consider treating live/explicit/clean as distinct in `song_key`.
- Let the download response / job payload carry the chosen `youtube_id` and matched title so the client can show which version was picked, and prefer the row's `youtube_id` for Spotify/Deezer URLs (always pass it through, not only as retry override).
- Optional: a `strict_album` flag or an explicit `album_id` check in `/api/download/album` plus returning the resolved album title/track count in the response, so the client can verify it got one album.
- Optional: reject (400) rows in batch whose `url` is a non-track URL instead of silently using them.
