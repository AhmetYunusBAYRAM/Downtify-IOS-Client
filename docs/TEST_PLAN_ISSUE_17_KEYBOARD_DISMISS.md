# Test plan: dismiss keyboard from search fields (issue 17)

Environment: iPhone 17 simulator, iOS 27.0, branch `codex/prioritize-playback-downloads`, signed in to a dev/staging server. Hardware keyboard disconnected (Simulator > I/O > Keyboard > Connect Hardware Keyboard off) so the software keyboard shows.

| # | Steps | Expected |
|---|-------|----------|
| 1 | Search tab, tap empty search field | Keyboard appears, "Done" button shown above it |
| 2 | Tap empty-state area / blank space outside the field | Keyboard dismisses |
| 3 | Refocus field, tap keyboard "Done" | Keyboard dismisses |
| 4 | Refocus field, drag the page down/up | Keyboard dismisses interactively |
| 5 | Refocus field, type a query, tap the category picker (Artists) | Picker changes; page still responds (keyboard dismissal acceptable) |
| 6 | With results shown, tap a result row / play button | Row action fires (not swallowed by the background tap) |
| 7 | Finder (Discover tab > Finder): tap field, then tap outside | Keyboard dismisses |
| 8 | Finder: tap field, tap "Done" | Keyboard dismisses |
| 9 | Finder: type text, tap xmark clear button | Query clears; button works |
| 10 | Finder: tap field, switch section (For You) | Page responds, no stuck keyboard |

Pass = all rows match expected.

## Results (2026-11-16, iPhone 17 simulator, iOS 27.0, final build)

| # | Result | Notes |
|---|--------|-------|
| 1 | Pass | Keyboard shown via Simulator "on-screen keyboard" setting |
| 2 | Pass | After fix: taps on text areas and blank space below content now dismiss (first implementation only covered the view background and failed on text and below-content taps; fixed by a tap handler on the shared scroll container in `LibraryHomeView.browsePage`) |
| 3 | Pass | "Done" button appears bottom-right with the hardware-keyboard-style layout; dismisses |
| 4 | Pass | Slow drag dismisses; a fast short swipe did not (content is shorter than the screen) |
| 5 | Pass | Category picker responds while keyboard focused |
| 6 | Pass | Artist row navigation works with keyboard focused; song play/download buttons not exercised (download would hit the server) |
| 7 | Pass | Finder: tap on hero text and blank area dismiss |
| 8 | Not separately run | Same "Done" control as row 3 |
| 9 | Pass | xmark clears query and dismisses |
| 10 | Pass | Switching to For You with keyboard focused works |

Not covered: physical device, software-keyboard "Done" placement above the QuickType bar (not visible in simulator screenshots), VoiceOver.
