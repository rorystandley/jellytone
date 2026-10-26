# Handoff: Jellytone iOS Music App

## Overview
Jellytone is an iOS music client for a personal Jellyfin server. This package covers the full app: onboarding/connect, Home ("For You"), Library (albums/artists/songs/playlists/genres), Search, Downloads, Settings, Album/Artist/Playlist detail, Now Playing (full-screen player with lyrics), and the Playback Queue sheet. The look is one coral accent, frosted translucent chrome over a warm neutral palette, plain-text section headers with hairline rules, and generated hue-gradient artwork when the server has none.

## About the Design Files
The `.dc.html` files are HTML prototypes of look, layout, and behaviour. Do not paste them into the app. Rebuild the screens in SwiftUI, inside the existing `jellyfin-ios-audio-player` codebase, using its established architecture (`Features/`, `Domain/`, `DesignSystem/`). Do not ship a web view.

`Jellytone.dc.html` is the full interactive prototype (open it in a browser to click through every flow). `Design Reference Mockup.dc.html` is a still 390×844 reference for the Home screen (dark and light) and the Now Playing screen. Use it for exact pixel comparison. `ios-frame.jsx` and `support.js` are prototype-runtime scaffolding only, not implementation guidance.

## Fidelity
Colours, typography, spacing, radii, and interaction timings below and in `design-system.md` are the spec. Match them.

## Design Tokens & SwiftUI Theme
The token list (palette, type scale, spacing/radius scale, component patterns, iconography, do/don't rules) is in `design-system.md`. That file wins.

**`DesignSystem/Theme.swift`** (`JellytoneTheme`, `jt*` colours/fonts, button/toggle/chip styles, glass modifiers) is the sole SwiftUI translation of that spec. Pair with `DesignSystem/Haptics.swift` for tactile cues. No hex codes or magic numbers should be needed outside these files when implementing the screens below.

## Screens / Views

### 1. Onboarding / Connect
- Purpose: enter Jellyfin server URL, username, password; connect.
- Layout: single column, 28px side padding, 74px top / 40px bottom. App mark (64×64, 20px radius, accent fill) → hero headline (32px/800) → subcopy (15px, secondary) → grouped input card (16px radius, 3 stacked fields, 1px dividers) → primary capsule "Connect" button (spinner while connecting) → Keychain reassurance caption with lock icon.
- States: idle → connecting (spinner in button, ~900ms) → connected (routes to Home).

### 2. Home ("For You")
- Layout: scroll view, 56px top / 32px bottom padding, 20px side margins on text, edge-to-edge on horizontal carousels.
- Header row: eyebrow ("Good Morning · Monday") + 38px large title "For You", + circular avatar button (top-right) opening Settings.
- "Continue Listening" hero (conditional on active track): 220px full-bleed artwork card, bottom scrim, title/artist bottom-left, 54px play/pause circle bottom-right.
- Sections (each: plain 22px/800 header + hairline rule, no icons/numbering): Recently Added (one 170px hero card + horizontal-scroll row of 112×112 cards), Favourite Artists (circular avatars, horizontal scroll), Made For You (2-col asymmetric grid, 140px tall tiles), Genres & Moods (wrapping chip row), Rediscover (horizontal-scroll 130×130 cards at 0.85 opacity + one-line description under its header).

### 3. Library
- Filter pills (Albums/Artists/Songs/Playlists/Genres) scroll sideways. The selected pill is a solid accent capsule. The others are glass.
- Content switches per filter: 2-col album grid (1:1 art, 14px radius) / 3-col circular artist grid / flat track list (42×42 art rows) / playlist list (60×60 art rows) / 2-col genre colour tiles.

### 4. Search
- Search field: glass pill input with leading magnifier icon.
- Empty state: "Browse Categories" genre grid. Results state: grouped Artists (circular scroll) / Albums (square scroll) / Songs (flat list) sections, each with its own subsection header + rule.

### 5. Downloads
- "Storage" section: flat card with used/total label + progress bar. Wi-Fi-only toggle row (glass card). "Downloaded Albums" section: rows with 56×56 art, name, track count + size, accent "Remove" action.

### 6. Settings
- Grouped rows in glass cards (Account: server/user/Sign Out; Playback: streaming/download quality + Gapless + Volume Normalisation toggles; Appearance: Dark/Light/Auto 3-way segmented control; Data & Storage: cellular toggle row + Clear Cache; Device: CarPlay/AirPlay info rows). Section titles are plain text. Do not put numbers back on them.

### 7. Album / Artist / Playlist Detail
- Sticky glass back-chevron over a scrim at the top.
- Album: full-bleed gradient header (hue-tinted), 200×200 artwork, title/artist/meta, Play (solid white)/Shuffle (glass)/heart/download action row, track list (grouped by disc if >1), "More by [artist]" horizontal scroll.
- Artist: circular photo header, Play + heart + download actions, "Popular" ranked list, "Albums" horizontal scroll, "About" bio with 3-line clamp + Read More toggle.
- Playlist: 2×2 artwork collage header on flat dark surface, Play (solid accent)/Shuffle (accent-tinted glass), flat track list.

### 8. Now Playing (always dark, independent of app theme)
- Full-screen, hue-tinted radial-gradient background derived from current track.
- Header: glass chevron-down (close), album name eyebrow, glass "more".
- Artwork (290×290, 20px radius, heavy drop shadow) toggles to word-by-word lyrics view (center-stacked lines, active line scaled 1.04 + full opacity, current word coral + scale 1.08, sung words white, unsung 40% white).
- Title/artist + heart. Scrub bar (4px, white fill, 12px thumb, expands on press) + elapsed/remaining labels. Transport row: shuffle / prev / 68px solid-white play-pause / next / repeat (with "1" badge for repeat-one). Footer: Lyrics toggle / quality tag / queue button.

### 9. Playback Queue (sheet)
- Header ("Playback Queue" + accent "Done"). "Now Playing" row in accent-tinted glass card with equalizer glyph. "Up Next" list (drag handles, art, title/artist, ✕ remove) + "Clear" action. Footer: "Save Queue as Playlist" glass button.

### 10. Mini Player & Tab Bar (persistent chrome)
- Mini player: floating glass card above the tab bar, 2px accent progress bar, 38×38 art, title/artist, play/pause + skip circles. Tapping the row opens Now Playing.
- Tab bar: 5 items (Home/Library/Search/Downloads/Settings), glass chrome, accent = selected icon+label, 55%-opacity white = unselected.

## Interactions and behaviour
- **Press feedback**: every tappable element scales to 0.85–0.94 on press, 0.12s ease-out. This is the *only* pressed-state affordance app-wide (see `JellytoneTheme.Motion.press`).
- **Toggles**: spring-overshoot thumb slide, ~0.28s, accent when on, `trackOff` grey when off.
- **Theme switch** (Settings → Appearance): Dark/Light/Auto, cross-fades colours; Now Playing screen ignores this and stays dark.
- **Lyrics**: word highlight advances on a fixed per-line timer tied to playback position; colour and scale transitions ~0.25s.
- **Navigation**: tab bar switches top-level screens and clears any open detail; detail screens push over the current tab as a full-screen overlay with a sticky back chevron; Now Playing and Queue are separate full-screen overlays (z-index above tab content).
- **Playback**: play/pause, next/prev, shuffle (reshuffles queue), repeat (off → all → one cycle), scrub-bar seek by tap position, queue reordering via remove/jump.

## State Management
Suggested state (see `Jellytone.dc.html`'s logic class for the reference shape, to be reimplemented against the real `Domain`/`Playback` layers already in the codebase):
- Session: server URL, connecting flag, connected/onboarding screen state.
- Navigation: active tab, active detail (type + id), Now Playing open, Queue open, lyrics open.
- Playback: queue array, current index, elapsed time, isPlaying, shuffle flag, repeat mode.
- Library-derived: favourite album/artist/track ids, downloaded album ids.
- Settings: Wi-Fi-only, gapless, volume normalisation, theme (dark/light/auto), bio-expanded (per artist).

## Assets
There is no real artwork in the prototype. Albums, artists, and playlists use a generated gradient (see `design-system.md` §1 and `JellytoneTheme.placeholderGradient(hue:)`) keyed off a fixed hue wheel, until a Jellyfin image URL is available. Replace with real Jellyfin artwork URLs 1:1 in production. The gradient is the loading/missing-art state, not a permanent visual element. Icons in the prototype are inline monoline SVGs. Recreate them with SF Symbols where a reasonable match exists, otherwise custom vector icons at the same stroke weight (1.7–2px).

## Files
`Jellytone.dc.html` is the clickable prototype (all screens, real click-through). `Design Reference Mockup.dc.html` is the still Home and Now Playing reference (Home dark, Home light, Now Playing) at 390×844. `design-system.md` is the token and component spec. That file is the canonical reference. `JellytoneTheme.swift` is the SwiftUI theme translation (colours, fonts, spacing/radius, ButtonStyle/ToggleStyle/ViewModifier helpers). `ios-frame.jsx` and `support.js` only run the prototype. They are not implementation-relevant.
