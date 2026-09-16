# Jellytone — iOS Design System Spec
Music client for Jellyfin. Reference for SwiftUI implementation (Theme.swift + component library). All values below are exact, taken from the approved HTML prototype.

---
## 1. Colour Palette

Colours are defined in OKLCH in the source and converted to sRGB hex below. If your tooling supports OKLCH natively, prefer the OKLCH values (more perceptually uniform across the dark/light pair); otherwise use hex.

### Dark mode (default; Now Playing is ALWAYS dark, even in light mode)
| Token | OKLCH | Hex | Usage |
|---|---|---|---|
| `background` | oklch(15% 0.006 40) | `#0D0A09` | Screen background |
| `surface` | oklch(24% 0.012 40) | `#241D1B` | Flat cards (storage card, etc.) |
| `text-primary` | oklch(97% 0.004 40) | `#F8F4F3` | Titles, primary labels |
| `text-secondary` | oklch(65% 0.01 40) | `#958D8B` | Subtitles, artist names under titles |
| `text-tertiary` | oklch(55% 0.01 40) | `#77706D` | Captions, durations, eyebrow labels |
| `border` (hairline) | oklch(30% 0.01 40) | `#322C2A` | Row dividers, card outlines |
| `track-off` | oklch(35% 0.01 40) | `#3F3937` | Toggle switch OFF background |

### Light mode
| Token | OKLCH | Hex | Usage |
|---|---|---|---|
| `background` | oklch(97% 0.006 90) | `#F7F5F1` | Screen background (warm off-white, not pure white) |
| `surface` | oklch(91% 0.008 90) | `#E3E1DB` | Flat cards |
| `text-primary` | oklch(22% 0.01 40) | `#1F1917` | Titles |
| `text-secondary` | oklch(42% 0.012 40) | `#534B48` | Subtitles |
| `text-tertiary` | oklch(56% 0.01 40) | `#7A7370` | Captions |
| `border` | oklch(84% 0.008 40) | `#CFC9C7` | Dividers |
| `track-off` | oklch(80% 0.008 40) | `#C3BCBA` | Toggle OFF background |

### Accent (identical in both modes — the ONLY accent colour in the app)
| Token | OKLCH | Hex |
|---|---|---|
| `accent` (coral) | oklch(70% 0.19 29) | `#FE6555` |

Used for: play/active state highlights, toggle ON state, selected tab icon+label, selected pill/chip, links ("Sign Out", "Remove", "Clear Cache", "Save Queue as Playlist"), progress bars, favourite/heart fill, now-playing lyric word highlight, repeat-mode "1" badge.

**Rule: exactly one accent hue in the whole app.** Never introduce a second brand colour (no blue links, no green success states). Warnings/destructive actions reuse the same coral rather than red — "Sign Out" and "Remove" use accent, not a separate error colour.

### Artwork placeholder gradients (album/artist art system)
Every album/artist/playlist gets a generated 135° gradient placeholder (real artwork replaces this 1:1 in production):
```
linear-gradient(135deg, oklch(42% 0.13 <hue>), oklch(20% 0.13 <hue+30>))
```
A rotating hue wheel is used across the catalogue: **29, 260, 145, 200, 330, 55, 190, 15, 280, 100** (degrees). Each album/artist is deterministically assigned one hue so repeat visits look consistent. In production this gradient is the *loading/missing-art* state, not a permanent design element.

### Glass/chrome surfaces (translucent, used over both light and dark backgrounds — always rendered dark-tinted since chrome sits above artwork or blurred content)
| Surface | Fill | Blur | Border | Notes |
|---|---|---|---|---|
| Tab bar | `rgba(120,120,128,0.20)` | 24px blur, 180% saturation | 0.5px `rgba(255,255,255,0.15)` top only | + inset top highlight `rgba(255,255,255,0.12)` |
| Mini player | `rgba(120,120,128,0.28)` | 24px blur, 180% saturation | 0.5px `rgba(255,255,255,0.15)` all sides | + drop shadow `0 2px 6px rgba(0,0,0,0.35)` + inset highlight |
| Settings grouped rows / Downloads toggle row | `rgba(120,120,128,0.20)` | 16px blur, 180% saturation | 0.5px `rgba(255,255,255,0.10)` | flat, no shadow |
| Circular nav buttons (back, more) | `rgba(120,120,128,0.28)` | 16px blur, 180% saturation | 0.5px `rgba(255,255,255,0.15)` | + inset `1px 1px 1px rgba(255,255,255,0.15)` |
| Pill buttons over artwork (Shuffle, heart, download on detail headers) | `rgba(255,255,255,0.14)` | 16px blur, 180% saturation | 0.5px `rgba(255,255,255,0.25)` | + inset `1px 1px 1px rgba(255,255,255,0.2)` |
| Library filter pills (unselected) | `rgba(120,120,128,0.22)` | 16px blur, 180% saturation | 0.5px `rgba(255,255,255,0.10)` | selected state switches to solid accent |

**In SwiftUI**: `.background(.ultraThinMaterial)` tinted, or a custom `Color(white:1,opacity:X).background(.regularMaterial)` layered under a 0.5pt hairline stroke — do not fake blur with a flat translucent colour alone; the blur+saturation boost is core to the look.

---
## 2. Typography

Font: **system font** (San Francisco) throughout — `-apple-system` / SF Pro / system-ui. No custom typefaces. All weights via SF's variable weight axis.

| Role | Size | Weight | Letter-spacing | Line-height | Example |
|---|---|---|---|---|---|
| Large Title | 38px | Bold (800/Heavy) | -1.2px | 0.95 | "For You", "Library", "Settings" screen titles |
| Onboarding Hero | 32px | Bold (800) | -0.5px | 1.15 | "Your music, on your terms." |
| Detail Title | 23–25px | Bold (800) | none | 1.1 | Album/artist/playlist name on detail header |
| Section Header | 22px | Bold (800) | -0.4px | 1.0 | "Recently Added", "Favourite Artists" |
| Hero Card Title | 18–19px | Bold (800) | none | 1.15–1.2 | Continue Listening card, Made-For-You hero |
| Subsection Header | 17–18px | Bold (800) | -0.3px | 1.0 | "Popular", "About", search result group headers |
| Now-Playing Track Title | 21px | Bold (800) | none | 1.2 | Full-screen player track name |
| Row Title (emphasis) | 14.5–15px | Semibold (600–700) | none | 1.2 | Track/album/playlist row titles, list rows |
| Body / Secondary | 13.5–15px | Regular–Medium (500) | none | 1.5 | Onboarding subtext, artist bio, descriptions |
| Row Subtitle | 12–12.5px | Regular–Medium (500–600) | none | 1.2 | Artist name under track, "N songs" |
| Caption / Meta | 11.5–12.5px | Semibold (600–700) | none | 1.2 | Durations, timestamps, quality tag |
| Eyebrow (uppercase label) | 11–12px | Bold (700) | +1.5px | 1.2 | "GOOD MORNING · MONDAY", "OFFLINE & READY" |

Minimum text size anywhere in the app is 10px (tab bar label) — never go smaller.

---
## 3. Spacing & Radius Scale

### Spacing (base unit 2px; primary scale is 4/6/8/10/12/14/16/18/20/22/24/30/32/56)
- **20px** — standard horizontal screen margin (every screen's content padding)
- **56px** top / **32px** bottom — screen vertical padding (56 clears the status bar/nav; content starts under it)
- **8–10px** — gap between icon and label, small inline gaps
- **12–14px** — gap between grid cells, row internal gaps (art→text)
- **16–18px** — gap between horizontal-scroll cards, section-internal spacing
- **24–30px** — spacing between major sections
- Use only values from this scale; don't invent odd spacings like 15px or 25px.

### Corner radius
| Radius | Usage |
|---|---|
| 8px | small track-row artwork (42×42) |
| 9–10px | mini-player artwork, home-screen row art |
| 12px | search-result album art, grid list icons |
| 12–14px | settings/downloads grouped cards, genre tiles |
| 14px | library grid album covers |
| 16px | mini player card, onboarding input card, connect button, made-for-you tiles |
| 18–20px | large hero cards (Continue Listening, Recently Added hero, album detail artwork) |
| 50% | avatar/artist circles, all circular icon buttons |
| 100px (pill) | filter chips, capsule buttons (Play/Shuffle), toggle switch tracks |

**Never** use radii outside this set (no 6px, no 24px) — keep the scale disciplined.

---
## 4. Component Patterns

### 4.1 Cards (album / hero / grid tile)
- Fill: gradient placeholder (§1) or real artwork, no border, no shadow on grid tiles.
- Hero cards (Continue Listening, Recently Added hero) get a **bottom-anchored scrim**: `linear-gradient(to top, rgba(0,0,0,0.68–0.75), transparent 55–60%)` so white title text sits legibly at the bottom-left.
- Grid album covers: 1:1 aspect ratio, 14px radius, 8px gap below to title.
- Small horizontal-scroll cards (112×112 to 130×130) get a subtle drop shadow `0 6px 14px rgba(0,0,0,0.3)` since they float on the plain background (not on a scrim).
- Text under a card: title 12.5–13.5px/700, subtitle 11.5–12px/500 in `text-secondary`, both single-line truncated with ellipsis.

### 4.2 Buttons
- **Primary capsule (Play)**: pill radius 100px, padding 12px 22px, 14.5px/700 label, 12px play-triangle icon + 8px gap. On dark artwork headers: solid white fill, black text/icon. In flat/dark contexts (playlist header): solid accent fill (`#FE6555`), white text.
- **Secondary capsule (Shuffle)**: same padding/radius, translucent glass fill (`rgba(255,255,255,0.14)` + blur, see §1) with white text/icon over artwork; accent-tinted glass (`accent @ 16% opacity` fill, accent text) in flat contexts.
- **Icon-only circular buttons** (heart, download, back, more, nav): 44×44 (detail headers) or 34×34 (nav bars), 50% radius, glass fill per §1, centered icon.
- **Press feedback**: every tappable element scales to **0.88–0.94** on press (`transform: scale()`) with a **0.12s ease** transition. This is the only pressed-state treatment — no colour change, no shadow change.
- **Disabled state**: reduce opacity to ~0.4, remove pointer/press-scale interaction. (Not present in current build but this is the rule to extend consistently.)

### 4.3 List / Track Rows
- Layout: `[artwork 42×42, radius 8] – 12px gap – [title (14.5px/600) + subtitle (12px, text-secondary)] – flex – [duration, 12px, text-tertiary]`.
- Vertical padding 9–11px, full-width **1px hairline** bottom border in `border` token (omit on last row of a group).
- Playing-state row (inside an album's track list, if a track is the active one): index/number swaps to accent colour and title text stays default colour — do NOT recolor the whole row, only the index glyph, to keep it subtle. (Track number column is 22px wide, centered.)
- Grouped settings-style rows (Account, Playback, etc.): same row shape but label left / value right (`text-secondary`), inside one glass card (§1) with 13px/16px padding, no artwork.

### 4.4 Mini Player
> **Superseded (product decision, 2026-07):** the mini player and tab bar now
> use the native iOS 26 system chrome, matching Apple Music: `TabView` with a
> `.search`-role tab, `.tabBarMinimizeBehavior(.onScrollDown)`, and the mini
> player as `tabViewBottomAccessory` ("Not Playing" when idle; artwork thumb +
> title + play/pause + skip, skip dropped in the inline placement). The system
> draws the glass capsule and the collapse/expand morph. The custom spec below
> applies only to the pre-iOS 26 fallback.
- Full-width card, 8px inset from screen edges, 6px bottom inset, 16px corner radius.
- Structure top→bottom: 2px progress bar (track `rgba(255,255,255,0.15)`, fill accent) → row: 38×38 artwork (radius 9) + 10px gap + title (14px/700) & artist (11.5px, white @ 65% opacity) + 34×34 play/pause circle + 34×34 skip circle.
- Fill/blur/border/shadow: see §1 "Mini player" row.
- Tapping the row (not the buttons) opens Now Playing; play/pause and skip stop propagation.

### 4.5 Now Playing (full screen, always dark regardless of theme)
- Background: `radial-gradient(circle at 50% 0%, oklch(38% 0.1 <hue>), oklch(12% 0.01 <hue>) 70%)` — a moody wash tinted from the current track's hue, not a flat black.
- Header row: 34×34 glass chevron-down (close) — centered album-name eyebrow (11px/700, uppercase, 0.5px tracking, white 60% opacity) — 34×34 glass "more" button.
- Artwork: 290×290, 20px radius, `0 30px 60px rgba(0,0,0,0.5)` shadow — swaps for a lyrics view (word-by-word) when toggled. Optional **vinyl mode** (footer disc toggle): circular LP with groove ring + centre label art; rotates while playing (~12s/rev), freezes on pause, static under Reduce Motion. Preference persists (`nowPlayingShowsVinylDisc`).
- **Lyrics mode**: lines center-stacked, inactive lines at 0.55 opacity / scale 1.0, active line 1.0 opacity / scale 1.04. Within the active line: sung words → white; current word → accent colour + scale(1.08); unsung words → white @ 40% opacity. Transition 0.25–0.3s on colour/transform.
- Track title 21px/800 white, artist 14.5px white @ 65%, heart icon top-right of that block (21×21, scale-on-press to 0.8).
- Scrub bar: 4px track (white @ 25%), white fill, 12px round thumb with a small drop shadow, expands to `scaleY(1.8)` on press. Time labels 11.5px, white @ 55%, elapsed left / remaining (as `-M:SS`) right.
- Transport row: shuffle (20px icon) — prev (26px) — **play/pause 68×68 solid white circle, black glyph** — next (26px) — repeat (20px, coral "1" badge super-scripted when repeat-one). All icons default to white @ 85% opacity, switch to accent when the mode is active (shuffle on, repeat on).
- Footer row: quality tag (e.g. "FLAC · 24-bit", 11.5px white @ 50%) — vinyl disc icon toggle (accent when LP mode) — "Lyrics" text toggle (12px/700, accent when open) — queue icon (opens Queue sheet).

### 4.6 Queue sheet
- Full-screen sheet, standard `background` fill (not glass), 20px side padding.
- Header: "Playback Queue" 19px/800 + "Done" accent text button.
- "Now Playing" section: single row in an **accent-tinted glass card** (`accent @ 16%` fill, `accent @ 30%` border, 12px radius) with an equalizer glyph on the right.
- "Up Next" section: plain track rows (drag handle dots · artwork 38×38 · title/artist · circular ✕ remove button in `border`-tinted circle). "Clear" text action top-right of this section header.
- Footer: full-width "Save Queue as Playlist" pill in the standard settings-glass style, accent text.

### 4.7 Navigation
- **Tab bar**: 5 items (Home, Library, Search, Downloads, Settings), glass fill per §1, 24px icon + 10px/600 label, 3px gap between icon/label. Active tab = accent colour (icon+label); inactive = white @ 55% opacity (dark) / text-tertiary (light). Padding `8px 4px 22px` (bottom padding clears the home indicator). *(Superseded 2026-07: native iOS 26 tab bar is used instead — see §4.4 note; accent tint still applies.)*
- **Section headers** (list pages): 22px/800 title, no divider below (hairline rule removed by product decision, 2026-07). No numbering, no icon — text only.
- **Library filter pills**: horizontal scroll row of capsules (Albums/Artists/Songs/Playlists/Genres), unselected = glass per §1, selected = solid accent fill + white text.
- **Detail header**: sticky 34×34 glass back-chevron over a top gradient scrim (fades to transparent), floats over the hero artwork/colour band beneath.

---
## 5. Iconography

- Style: **thin monoline stroke icons**, no fills except where the glyph is inherently solid (play triangle, pause bars, skip triangles — these read as filled shapes by design, not stroke).
- Stroke width: **1.7–2px** at 20–26px icon sizes. Rounded line caps/joins throughout.
- Colour: white (dark contexts) or `text-secondary`/`text-tertiary` (settings icons on light/dark screens), swapping to accent only to indicate an active/selected state (shuffle on, repeat on, selected tab, filled heart).
- No icon ever carries a background chip/badge of its own colour — active state is communicated by the icon's own colour change, not a container.
- Favourite/heart icon: outline stroke always; fill switches from `none` to accent when favourited (never switches to red).

## 6. Imagery / Artwork Treatment

- All artwork (album covers, artist photos, playlist collages) is edge-to-edge, no inner padding, no rounded-corner "frame" beyond the container radius itself.
- Missing/loading artwork uses the generated gradient system (§1) — never a grey placeholder box or a broken-image icon.
- Any text laid over artwork requires a scrim (linear gradient to transparent) sized to guarantee 4.5:1 contrast for the smallest overlaid text.
- Playlist collages: 2×2 grid of 4 track/album artworks, 2px gaps, clipped to the playlist artwork's outer radius.

---
## 7. Do / Don't

**Do**
- Keep exactly one accent colour (`#FE6555`) for every interactive/active/highlight purpose across the whole app.
- Use the glass/blur treatment (§1) for every piece of chrome that floats over content: tab bar, mini player, sheets' nav buttons, pills over artwork.
- Use scale-on-press (0.85–0.94) as the *only* pressed-state affordance for tappable rows/buttons.
- Keep section headers plain text at 22px/800 — no hairline rule (removed by product decision, 2026-07), no numbering, no icons, no colour tinting.
- Respect the radius scale in §3 exactly; don't introduce new corner radii per-component.
- Keep Now Playing dark always, independent of the user's light/dark setting.

**Don't**
- Don't add a second accent colour (no blue links, no green "success", no red "destructive" — reuse coral, or in the worst case a neutral grey, for destructive actions).
- Don't render chrome as flat opaque colour — always blur+saturate translucent surfaces per §1; a flat rgba fill without backdrop-filter reads as "wrong" immediately.
- Don't add drop shadows to grid/list content that sits directly on the background (only hero cards, small horizontal-scroll cards, floating chrome, and the Now Playing artwork get shadows — see §4.1/4.5).
- Don't add borders around album art or avatars — the artwork edge IS the shape.
- Don't use hover states (this is a touch app — only rest and pressed/active states exist).
- Don't add numbered eyebrow labels, icons, or hairline rules to section headers (previously used, both have been removed — keep it plain text only).
- Don't drop below the minimum type sizes in §2 (10px absolute floor, and only for the tab bar label).

---
## 8. Haptics

Purposeful, short, interruptible — matching `PRODUCT_PLAN.md` and `AGENTS.md`.
Implementation: `DesignSystem/Haptics.swift` (`JellytoneHaptics`).

| Cue | Where |
| --- | --- |
| **Light impact** | Transport (skip / shuffle / repeat), play-from-library rows, secondary capsules, download start, queue jump, lyrics / vinyl toggles |
| **Medium impact** | Primary play/pause, favouriting on |
| **Soft impact** | Unfavourite, nav chrome, expand/collapse Now Playing |
| **Selection** | Alphabet index scrub, Now Playing seek ticks, toggles, chips, appearance picker |
| **Success** | Successful server connect |
| **Warning** | Remove download, clear cache, sign out, clear up-next |
| **Error** | Failed connect |

**Do not** fire haptics on ordinary navigation-row presses (Library category, album grid, search result push). System haptic settings are respected automatically; do not gate on Reduce Motion.