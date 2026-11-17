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
