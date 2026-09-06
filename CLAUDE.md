# Claude instructions

Follow `AGENTS.md` for repository workflow, authority order, and proof rules.

## Design system (mandatory for all UI work)

- All UI work must follow `docs/design/design-system.md` (source of truth) and
  use `DesignSystem/Theme.swift` (`JellytoneTheme`, the `jt*` `Color`/`Font`
  extensions, and the Jellytone button/toggle/chip styles and glass modifiers).
- Haptics use `DesignSystem/Haptics.swift` (`JellytoneHaptics`) only — see
  design-system.md §8. Prefer shared controls / intentional action entry points;
  do not haptic ordinary navigation-row presses.
- No raw hex or RGB colour values in views — semantic colours live in
  `App/Assets.xcassets` (light/dark variants) and are exposed only through
  `Color.jt*`.
- No system-default fonts in views (`.headline`, `.caption`, bare `.font(...)`
  sizes) — use the `Font.jt*` type scale.
- No magic-number spacing or corner radii in views — use
  `JellytoneTheme.Space` / `JellytoneTheme.Radius` values only.
- The HTML mockups in `docs/design/` are the visual reference; `design-system.md`
  wins if they disagree.
- Sole UI system: `DesignSystem/Theme.swift` (+ `Haptics.swift`). Do not
  reintroduce a parallel design layer or raw styling outside `jt*` tokens.
