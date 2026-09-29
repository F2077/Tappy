# Tappy

<p align="center">
  <img src="Assets/AppIcon-rounded.png" width="128" alt="Tappy app icon">
</p>

A baby-safe macOS app: click the mouse or bang the keyboard and cute
things pop up with sounds. Tappy is a generic engine — all content
(animals today; vehicles, sea creatures, professions, … tomorrow) comes
from **resource packs**, so new themes ship as data, not code.
See `docs/resource-packs.md` (中文) for the pack format.

> On the App Store the app is called **Pat-a-Pet** (敲敲小世界): pat is
> the gentle tap — on a pet, on a child's head — and a nod to
> pat-a-cake, the oldest parent-baby clapping game there is. The name
> "Tappy" was already taken, and this one tells the story better
> anyway. The repo and binary keep the name Tappy.

## Run

```sh
make run        # patches deps (CLT workaround), then swift run
```

Note: SwiftDraw uses Xcode-only macros (`#Preview`, `@Entry`) that the
plain Command Line Tools toolchain cannot compile; `make` runs
`Scripts/patch-deps.sh` to strip them from the SwiftPM checkout
first. Re-run it after `swift package update`.

Or build a double-clickable app bundle:

```sh
make app        # produces build/Tappy.app
open build/Tappy.app

make dmg        # produces build/Tappy.dmg (app + both theme packs)
```

## Controls

- **Click empty background** — an entity pops up where you clicked
- **Any key** — an entity pops up at a random spot
- **Scroll wheel / trackpad swipe** — spawns at the cursor; harder flick,
  bigger one
- **Click an entity** — it bounces, spins, and replays its sound and name
- **6+ entities on screen** — parade mode (max 8 marchers); choreography
  (lanes / graze, speed, heights) is pack-defined per scene
- **Theme** (settings, shown with 2+ packs) — one theme at a time:
  spawning and the scene list follow the active pack
- **Hold Esc 1.5s** — quit · **Hold S 2s** — switch scene ·
  **Hold P 2s** — parent settings

## Content: resource packs

Scenes, entities, artwork, sounds, localized names and
parade choreography live in `.tappypack` bundles (a directory or a zip
archive with one `pack.json`). Loaded at runtime from the app bundle and
`~/Library/Application Support/Tappy/Packs/`; user packs override
built-in entries by id. Two packs ship built in: `Default` (ten Twemoji
animals, two hand-coded scenes) and `Vehicles` (ten Twemoji vehicles,
two data-driven scenes) — pick one at a time in settings. The DMG also
loosely includes both packs as `.tappypack` zip archives to drop into
`~/Library/Application Support/Tappy/Packs/`.

## Sounds

Lookup order per entity: parent-provided file in
`~/Library/Application Support/Tappy/Sounds/<entity-id>.wav` (or a
catch-all `default.<ext>`) → pack sound → macOS system sound. The
default pack mixes real CC0 recordings and synthesized cute tones
(`Scripts/synth-sounds.swift`, see the pack's `sounds/NOTICE.txt`).
Speech synthesis (saying the name) is off by default.

While running, the app is full screen with the Dock and menu bar hidden,
⌘Tab switching disabled, and all menu shortcuts (including ⌘Q) swallowed,
so a toddler cannot leave the app by accident.

## Layout

- `Sources/TappyCore/` — testable core: `ResourcePack` (pack manifest,
  `PackCatalog` loading), `GameState` (observable state, spawn rate
  limiting, parade), `EntityArt` (SVG rasterizing via SwiftDraw, SF
  Symbol fallback), `SoundPlayer` / `Speaker`, `SettingsStore`
  (persisted settings), `InputCatcherView` (event monitor)
- `Sources/Tappy/` — the app: `TappyApp` (entry, kiosk setup),
  `PlayfieldView` / `EntityView` / `SceneView` (rendering, animation,
  generic pack-driven scene renderer), `SettingsView`
- `Sources/TappyChecks/` — assertion-based checks (no Xcode required)
- `docs/resource-packs.md` — pack authoring guide (中文)

## Test

```sh
make test       # swift run TappyChecks
make smoke      # end-to-end: launches the app windowed and fires real
                # synthetic events (click/key/scroll) into it
make bench      # micro-benchmarks for the hot paths
```

The machine only needs Command Line Tools; no Xcode or XCTest required.
The smoke run is windowed, muted, and self-exits in ~10 s; its CGEvent
injector needs a one-time Accessibility trust for the calling terminal.

## Credits

- Pack artwork: [Twemoji](https://github.com/jdecked/twemoji),
  CC-BY 4.0 (see each pack's `NOTICE.txt`)
- Sound effects: synthesized in-repo (`Scripts/synth-*.swift`) plus a few
  CC0 recordings from OpenGameArt.org (credits in each pack's
  `sounds/NOTICE.txt`)
- App icon: AI-generated for this project (see `NOTICE`)
- SVG rendering: [SwiftDraw](https://github.com/swhitty/SwiftDraw), Zlib

## License

Code is [MIT](LICENSE). Third-party assets keep their own licenses —
see [NOTICE](NOTICE) for the full list. The same attribution appears in
the app's settings panel and ships inside the app bundle, so the CC-BY
obligation travels with the binary.
