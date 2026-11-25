# Runtime themes

In Settings → Appearance, choose **Original** or **Redesign** from the Theme picker. Both are bundled JSON files in `themes/`. To make your own, export the selected theme to Files, edit its JSON, and import it. The imported theme appears in the picker and remains available when you switch between themes. Importing another file replaces the saved imported theme. Changes take effect immediately and remain selected after restarting. Theme files contain presentation settings only and do not contain account information.

The original fields are required; the component style and extra color fields are optional and default to the standard interface for compatibility with earlier theme files. Colors are six hexadecimal RGB digits without `#`; iOS selects the light or dark value according to Appearance. OLED retains its black background and dark surface. The example below uses the green and dark surfaces of the redesign:

```json
{
  "version": 1,
  "name": "Redesign",
  "accentLight": "14833B",
  "accentDark": "1ED760",
  "backgroundLight": "FFFFFF",
  "backgroundDark": "121212",
  "surfaceLight": "F3F3F3",
  "surfaceDark": "1E1E1E",
  "cardCornerRadius": 8,
  "cardPadding": 16,
  "rowSpacing": 12,
  "albumGridMinimum": 142,
  "homeSections": [
    "recent",
    "new",
    "favorites"
  ],
  "shelfLayout": "carousel",
  "navigationStyle": "drawer",
  "headerStyle": "profile",
  "recentStyle": "tiles",
  "playerStyle": "compact",
  "componentStyles": {
    "home": "redesign",
    "library": "redesign",
    "search": "redesign",
    "collection": "redesign",
    "downloads": "redesign",
    "player": "redesign",
    "settings": "redesign",
    "connection": "redesign",
    "discover": "redesign",
    "podcasts": "redesign",
    "queue": "redesign"
  },
  "elevatedLight": "E8E8E8",
  "elevatedDark": "2A2A2A",
  "brandLight": "1DB954",
  "brandDark": "1DB954",
  "onBrandLight": "000000",
  "onBrandDark": "000000",
  "fontDesign": "system",
  "browseColors": {
    "For You": "203562",
    "Charts": "E33600",
    "Finder": "27866F",
    "Similar": "8863A8",
    "Podcasts": "006450",
    "Downloads": "B65B00"
  }
}
```

`cardCornerRadius` accepts 0–40 points, `cardPadding` and `rowSpacing` 4–32, and `albumGridMinimum` 100–240. `homeSections` must contain each of `recent`, `new`, and `favorites` once, in the desired order. `shelfLayout` is `grid`, `list`, or `carousel` (horizontal shelves; accessibility text sizes use the list). `navigationStyle` is `system` or `drawer`: drawer themes show Home, Search, and Your Library in a custom bar and put the other destinations in the profile menu. `headerStyle` is `system` or `profile` (inline header). `recentStyle` is `shelf` or `tiles`; the tile style falls back to a shelf at accessibility text sizes. `playerStyle` is `standard` or `compact`. `componentStyles` can independently select `standard` or `redesign` for `home`, `library`, `search`, `collection`, `downloads`, `player`, `settings`, `connection`, `discover`, `podcasts`, and `queue`. `elevatedLight`/`elevatedDark`, `brandLight`/`brandDark`, and `onBrandLight`/`onBrandDark` provide the raised surface, filled control, and control foreground colors. Set each light/dark pair together. `surfaceStyle` can be `system` to use iOS grouped surfaces (as the Original theme does), or `custom` to use the supplied surface colors. `browseColors` optionally sets six-digit RGB colors for individual Search tiles. `fontDesign` is `system`, `rounded`, `serif`, or `monospaced`. `equalizerAccentLight`/`equalizerAccentDark` (curve, its fill, and the selected preset), `equalizerHandleLight`/`equalizerHandleDark` (band handles), and `equalizerGridLight`/`equalizerGridDark` (dB scale, guide lines, band labels, and the curve while the equalizer is off) optionally color the Equalizer; set each pair together. When omitted, they use `accent`, `brand`, and the system secondary text color. The Equalizer card uses the theme surface, `cardCornerRadius`, and `cardPadding`; the on/off switch uses `brand`, the value shown while dragging uses `elevated`, and text follows `fontDesign`. Invalid or unsupported files are rejected and leave the current theme intact.

The theme controls shared palette colors, cards, media-row spacing, the library grid, and home shelf order and presentation. The redesign components include a profile menu, navigation bar, quick-access tiles, a combined library list, collection artwork and controls, and a compact player. Collection and player backgrounds use a subdued color sampled from locally loaded cover artwork when available; otherwise they use the theme’s elevated color. The redesign library remembers its grid/list choice separately from the default theme. The theme does not implement the redesign branch’s playback features or every screen-specific layout. Some native controls retain their system styling.
