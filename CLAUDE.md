# CLAUDE.md

> Starter instructions for a new Godot 4 project. The pipeline comes first: Godot, git, headless tests, CI, and a web build that runs on a phone and a PC. Game content comes later.
> **Fill in the `TODO` sections (Pillars, Milestones) before Milestone 1.** Milestone 0 needs nothing from you except the GitHub settings in "One-time setup".

## Goal
A Godot 4 (GDScript) prototype of **TODO: one-line pitch**.

Milestone 0 was **Hello Cow** (a tappable 48x48 cow) to prove the pipeline. Milestone 1 turned it into a landscape 480x270 game: a cat (Fern) walking around a meadow, with the cow as the first NPC. Milestone 2 made it talk: three cats with branching conversations whose choices set flags that change later lines. Milestone 3 makes it a place: a living, generated meadow, a small pixel-scale dialogue box, nightfall after the conversations, and sound.

## Pillars
TODO: 3-5 short statements every feature is checked against. If a feature doesn't serve a pillar or the current milestone question, don't build it.

1. TODO
2. TODO
3. TODO

## Milestones
Each milestone has one **question** it is meant to answer. Build the smallest thing that answers it.

- **Milestone 0: Hello Cow (pipeline).** "Can we change the game, push, and see the change on a phone and a PC within minutes, with tests guarding it?" Done when everything in "Milestone 0 checklist" below holds.
- **Milestone 1: Walk the meadow (feel, on a phone).** "Does moving a cat around and interacting feel good with touch *and* keyboard, at 60 fps on a phone, from the Pages link?"
  - Scope: one 480x270 meadow screen; the cat walks (8 directions, analog on touch) and trots; bushes block; the cow is an NPC you walk up to and interact with ("Moo!"). Title screen ("tap to start", fullscreen button where supported). "Rotate your phone" overlay in portrait. Touch controls (joystick left, paw/interact right) only on touch devices. Build label plus fps in a corner.
  - Done when: the game loads and plays on a phone and a PC from the GitHub Pages link; touch controls work and feel as good as the keyboard; it holds 60 fps on the phone (read the fps in the corner), not just the PC.
- **Milestone 2: It talks.** "Do branching conversations with choices feel good on a phone and a PC, and do choices visibly change later lines?"
  - Scope: Fern talks to Bram (gruff mentor), Sorrel (elder) and Wick (rival) in the meadow; the cow stays as a test NPC ("Moo!"). Conversations are JSON (see "Dialogue files"); choices set flags and bonds; after its full conversation each cat switches to a short repeat line; the vole choice (Wick) changes both Sorrel's and Wick's later lines. Dialogue box (bottom, ~40% of the height, name plate, plain coloured portrait square), typewriter text with voice blips, choices by keys/gamepad or tap. CI validates every dialogue file.
  - Done when: all three conversations play start to finish in any order on a phone and a PC from the Pages link; the vole choice changes Sorrel's and Wick's lines; repeat lines work; CI is green.
- **Milestone 3: It's a place.** "Does standing still in the meadow, with sound on, feel pleasant, on a phone at 60 fps?" Style and atmosphere only: no new characters or systems, cat sprites untouched.
  - Scope: dialogue box at most the bottom quarter, drawn at the world's pixel scale (3 lines, 32 px portrait, compact right-hand choice stack with a cursor, 0.15 s slide/fade); the world reaches every screen edge (forest frame, no letterbox); ground variety (grass patches, worn path, flower clusters, tall grass), landmarks (trees with overhanging canopies, rocks, a log, a shimmering pond), varied bushes; wind sway, rustle, butterflies, pollen, cloud and bird shadows; warm grade and drop shadows; afternoon -> dusk -> night over 8 s after the three conversations (grade cools, fireflies, pond darkens, night music); audio on five buses with a volume toggle and a CREDITS.md line per file.
  - Done when: standing still in the meadow with sound on feels pleasant, the dialogue covers no more than the bottom quarter, and it all runs at 60 fps on the phone.
- **Milestone 4:** TODO (planned: the ending scene, the choice log file, real portraits and sprites, real music).

**Out of scope until a milestone asks for it:** saves, final art (portraits and cat sprites are placeholders), final music (the tracks are labelled placeholders), the ending, a choice log file, menus beyond what a milestone needs, settings screens (the volume button is the only setting), localisation, native mobile apps, multiplayer.

## One-time setup (the human does these)
1. Create the GitHub repo (public if you want free Pages) and give Claude access to it.
2. Repo **Settings > Pages > Build and deployment > Source: GitHub Actions.** Without this the deploy job fails.
3. For cloud Claude sessions: the environment's network must reach `github.com` and `objects.githubusercontent.com` (Godot downloads come from GitHub releases).
4. After the first green run, bookmark the Pages URL (`https://<user>.github.io/<repo>/`) on your phone.

## Setup (every Claude session)
Run `tools/setup_godot.sh` before tests (`tools/setup_godot.sh --web` before a local web export). It installs the exact Godot version CI uses (read from `.github/workflows/ci.yml`) into `~/.local/bin` only when it is missing, so it is safe to run every time. Add `~/.local/bin` to `PATH` if `godot` is not found.

## Milestone 0 checklist (build these, in this order, small commits)
1. **Project skeleton.** `project.godot` for Godot **4.3** (or the pinned version), **Compatibility renderer** for desktop *and* mobile (`renderer/rendering_method` and `.mobile` = `gl_compatibility`), `stretch/mode = canvas_items`, `stretch/aspect = expand`, default texture filter **Nearest**. `.gitignore` ignores `.godot/`, `build/` and `data/build.json`. Commit the `*.import` files next to the art and `export_presets.cfg`. `.gitattributes` marking `*.png` as binary and `*.gd`/`*.tscn`/`*.json` as `text eol=lf`.
2. **`tools/setup_godot.sh [--web]`.** Reads `GODOT_VERSION` from `ci.yml`; installs the Linux editor binary as `godot` and, with `--web`, only the `web_nothreads_release.zip`/`web_nothreads_debug.zip` templates (+ `version.txt`) into `~/.local/share/godot/export_templates/<ver>.stable/`. Does nothing if already present.
3. **The cow art.** `art/cow.png`, 48x48, transparent background, a few flat colours (white body, black patches, pink nose, dark outline). Make it with a script, not by hand: `tools/make_cow.gd` (run with `godot --headless --script`) draws the pixels from a small character grid into an `Image` and calls `save_png`. Commit both the script and the PNG. Import it with filter off / no mipmaps.
4. **Asset lookup by key.** `scripts/core/asset_catalog.gd` (`preload`-ed, no `class_name`): `data/assets.json` maps keys (`cow.idle`) to paths; unlisted keys fall back to `res://art/<key>.png`. A missing asset logs **one** warning and returns a generated magenta-checker placeholder; it never crashes. No file paths in game code.
5. **The Hello Cow scene** (`scenes/hello.tscn`, `scripts/view/hello.gd`, the main scene):
   - Background colour, the cow centred, drawn at the **largest whole-number scale** that fits (target about 1/3 of the short screen side), re-snapped on resize so every art pixel is whole device pixels (account for `devicePixelRatio` on web).
   - Tap/click the cow: a speech bubble with "Moo!" appears above it for ~1.5 s (tap again restarts it). The cow does a 2-frame squash or bob so you can see input landed. Tapping empty space does nothing.
   - The tap target is at least 48 CSS px even if the cow were drawn small.
   - The text "Moo!" comes from `data/strings.json`, not code (proves the data pipeline).
   - A small build label in a corner: `build <sha> <date>` from `data/build.json` (written by the build script; `dev` when missing). This is how you know the phone is running the latest push.
   - All UI inside the safe area (notch, gesture bar). See `screen_metrics.gd` below.
6. **`scripts/view/screen_metrics.gd`.** One place for scale, DPR and safe-area insets. On web read `env(safe-area-inset-*)` and `devicePixelRatio` through `JavaScriptBridge.eval`; on desktop use `DisplayServer`. Keep 1 UI unit close to 1 CSS px on phones so 48-unit buttons are 48 CSS px.
7. **Tests** (see "Running tests"): `tests/run_tests.gd` runner, `tests/test_base.gd` (assert helpers that collect failures), `tests/test_assets.gd` (known key loads, missing key returns placeholder and warns once, cow is 48x48), `tests/hello_smoke.gd` (instantiates the real main scene at a **phone size (390x844)** and a **desktop size (1280x720)**, checks the cow is centred, integer-scaled, inside the safe area, simulates a tap on the cow and asserts the bubble shows the text from `strings.json`, simulates a tap elsewhere and asserts nothing happens; saves screenshots when `--shots=<dir>` is given).
8. **`export_presets.cfg`** with one preset named `Web`: export path `build/web/index.html`, **threads off** (no SharedArrayBuffer, so it works on GitHub Pages and iOS Safari without special headers), `html/head_include` = `<meta name="robots" content="noindex, nofollow">`, canvas resize policy adaptive, focus canvas on start, virtual keyboard off.
9. **`tools/build_web.sh [godot]`** (also used by CI): clean `build/web`; write `data/build.json` with the short SHA and UTC date (removed again on exit); `--import`; `--export-release "Web"`; verify `index.wasm` exists; **cache-bust** by rewriting `index.html` so it loads `index.pck?v=<sha>` (`"mainPack"` in the engine config) and `index.js?v=<sha>`; add `viewport-fit=cover` to the viewport meta; write `robots.txt` (`Disallow: /`) and `.nojekyll`. `grep -q` each rewrite so a Godot template change fails the build loudly instead of silently.
10. **`.github/workflows/ci.yml`** with `env: GODOT_VERSION: "4.3"` as the single source of truth and three jobs:
    - `test` (push to `main`, pull requests, manual): install Godot, `godot --headless --path . --import || true`, run the tests.
    - `build` (needs test, not on PRs): install Godot + the two no-threads templates, `tools/build_web.sh godot`, `actions/upload-pages-artifact`.
    - `deploy` (needs build): `actions/deploy-pages` with `pages: write`, `id-token: write`, concurrency group `pages`.
11. **Check it for real.** Push, wait for green, open the Pages URL on a phone (portrait and landscape) and a desktop browser. Confirm the build label matches the pushed SHA, the cow is crisp (no blur, no uneven pixels), and a tap says "Moo!". Report the URL and the SHA.

## Web build settings (locked in)
- **Compatibility renderer only.** It's the only renderer Godot's web export supports; don't build lighting or effects that need Forward+/Mobile.
- **Threads off** (no-threads templates, Godot 4.3+). GitHub Pages can't send the cross-origin isolation headers threaded builds need.
- **Particles: `CPUParticles2D`, never `GPUParticles2D`** (e.g. for fireflies). More reliable in browsers, especially on phones.
- **The world renders into a small `SubViewport`, stretch aspect "expand" with integer scaling.** k = the largest whole number at which the 480x270 base view (`view.base` in tuning.json) fits the whole screen, in device pixels; the view then grows to fill the screen at that k (`view.max`, 1280x720, is only a sanity cap no real screen reaches): **no letterbox, no dead margins**. Wider screens see more meadow, never a blurry or uneven pixel. The `Camera2D` (top-left anchored, whole pixels) is limited to `world.camera_bounds()` = the meadow (`world.json` size, 720x405) grown by `border` (72 px of tree line and forest); a view bigger than that is centred, and the forest tile is drawn `FOREST_REACH` further out, so even a 32:9 or 5:4 screen shows forest, never flat colour (tests: `test_camera_limits_cover_every_view`, `test_no_dead_margins_on_odd_screens`). Fill cost stays tiny on phones. The dialogue box draws at the same k in its own SubViewport; touch controls, the hud and corner buttons draw at full resolution on top, in UI units.
- **Fullscreen:** the tap/click/key that starts the game calls `ScreenMetrics.request_fullscreen()` from inside the input handler (browsers allow it nowhere else), then locks orientation to landscape; failures are ignored. A small corner button (`fullscreen_button.gd`) does the same and hides while fullscreen or when launched from the home screen. iPhone Safari has no fullscreen for web pages: there the button is hidden and players use Add to Home Screen.
- **PWA on:** manifest with `display: fullscreen`, `orientation: landscape`, icons baked by `make_art.gd`; iPhone home-screen meta tags in `html/head_include`. `build_web.sh` **replaces Godot's service worker** with `tools/web/service_worker.js`: Godot's serves `index.html` cache-first and only updates after every tab closes, which would show the previous build after each push. Ours is network-first, revalidates the page, takes over immediately and caches only the offline page.

## Milestone 2: dialogue (how it fits together)
- **Core (headless, preload):** `scripts/core/game_state.gd` (flags + bonds), `dialogue.gd` (runs one conversation node by node), `dialogue_validator.gd`, `typewriter.gd` (cps, pauses, blip counting). The **autoloads** `GameState` and `DialogueManager` (`scripts/autoload/`, registered in `project.godot`) are thin Nodes around them; tests use the core classes directly. The game screen calls `GameState.reset()` when it starts (a new game).
- **Registries:** `data/state.json` lists every flag (`bool`, or `string` with its `values`), the cats that have bonds (`bonds`, each starts at 0) and the `expressions` (neutral/happy/sad/annoyed). `data/speakers.json` has each speaker's name, colour (portrait + name plate), `side` (`fern` is `right`) and voice (`pitch`, `volume_db`, `blip_ms`). A new flag or speaker goes in these first or validation fails.
- **NPCs:** `world.json` `npcs` entries have `id` (= speaker id), `art`, `frames`, `pos` (or a pacing `path` + `speed` + `pause`), `footprint`, `talk_radius` (22), `behavior` (`sit`/`lie`/`pace`/`stand`) and `dialogue` (file path). `scenes/npc.tscn` (`scripts/view/npc.gd`) is the reusable NPC scene; its exports (id, display name, voice pitch, dialogue file, ...) are filled from those files. Keep NPC feet at world y <= ~235: below that, the camera (limited to the world edge) can't lift them above the dialogue box at view.max (a smoke test checks every NPC).
- **Talking:** Interact next to the nearest NPC in range (it gets the bobbing paw print) calls `World.interact()`, which locks movement, stops the NPC and turns both to face each other, then `DialogueManager.start(file)`. While the box is open the touch controls hide, a tap anywhere advances, and the camera eases so both cats sit above the box.
- **Dialogue box** (`scripts/view/dialogue_box.gd`): see Milestone 3 below. Interact finishes the line, then advances; a blinking arrow marks a finished line. Choices appear after the line has typed out. Font: Pixelify Sans (`fonts/`, SIL OFL, license in `fonts/PixelifySans-OFL.txt`), looked up by key `font.dialogue`.
- **Voice** (`scripts/view/voice.gd`): generated tones (no audio files), one every `blip_every` (2) characters, pitch +- `pitch_jitter` (5%), on the `Voice` bus (`default_bus_layout.tres`). Created by the game screen, so nothing plays before tap-to-start.

## Milestone 3: a place (how it fits together)
- **Dialogue box at the world's pixel scale.** The box, its text, portrait and choices are laid out in world pixels inside their own transparent `SubViewport` (the size of the world view), shown as a `Sprite2D` at the world's k. One font pixel = one world pixel = k x k device pixels. Pixelify Sans is pixel-exact at 12 px (`font_px`) with antialiasing off and `oversampling = 1`. tuning.json `dialogue`: `lines` 3, `line_px`, `portrait_px` 32, `plate_px`, `margin_px` / `bottom_margin_px` / `padding_px`, `text_trim_px` (Pixelify's blank rows above capitals / below descenders, allowed to overlap the padding), `max_height` 0.25 (box + name plate, measured from the screen's bottom edge, gesture bar included), choice rows `touch_choice_css` 38 (clamped to `min_choice_css`..`max_choice_css`, 36-40) on touch screens, `anim_s` 0.15 / `anim_slide_px` for the slide/fade, `camera_lift_px`. Choices are a stack just above the box's right edge, each only as wide as its text, with a ▶ cursor on the selected row (keyboard / gamepad; touch shows it on press). The UI-unit rects (`box_rect`, `choice_rects`...) are for input, tests and the camera. `ui_event` signals drive the UI sounds. `close()` clears `is_open` at once; the box stays `visible` until its slide-out ends (`animating()`).
- **The meadow** (`world.json`, `scripts/core/world.gd`): `prop_types` (art, footprint, `shadow`, `sway`, `rustle`, trees' `canopy` + `canopy_offset`) and `props` that reference them (`flip` mirrors); `tree_line` generates trees round all four edges (only the top row has trunks in the meadow; the others are canopies over the forest floor); `pond` (solid, `lap_radius` for its sound); `path` lines (`world.surface()` = "path"/"grass" for footsteps); `tall_grass` patches (blades y-sorted with Fern so she walks through them); `flowers` clusters (2-3 colours, never on the path or pond); `decor` scatter (tufts); `ground_paint` (seed, patch size). Every random placement uses the world's seeded RNG.
- **World view layers** (`scripts/view/world_view.gd`, bottom to top): Forest (tiled `forest.tile`), Ground (`art/ground.png`, pond with `shaders/pond.gdshader` shimmer, sunny spot, drop shadows offset down-right from the afternoon sun), Decor, Sorted (y-sort: props, trunks, NPCs, Fern, tall grass), Life (butterflies), Canopies (over Fern; the one she stands under goes `canopy_fade` see-through), Sky (cloud shadows, bird shadow, pollen), a `CanvasModulate` grade, and an Overlay `CanvasLayer` the grade doesn't touch (fireflies, paw prompt). Wind: `shaders/sway.gdshader` slides each sprite's top edge by whole pixels in a travelling wave with gusts; one material per kind (grass, flower, bush, canopy; amplitudes in tuning.json `wind`), shared so sprites batch. Rustle = a short `skew` when Fern brushes tall grass or a bush (`rustled` signal -> sound). Particles are `CPUParticles2D`; counts in tuning.json `ambience` (`pollen`, `fireflies`, `butterflies`, `clouds`, bird interval and speeds).
- **Time of day** (`scripts/core/day_cycle.gd`, tuning.json `time_of_day`): t stays 0 until every `after_flags` flag is set and the box is closed, then runs to 1 over `duration` (8 s); `dusk_at` 0.5. The view blends `palette.json` `grade.afternoon/dusk/night` (`day.blend()`), fades butterflies, clouds and pollen with `day_amount()`, starts fireflies and darkens the pond with `night_amount()`. `day.set_t()` jumps (tests, screenshots). The ending is Milestone 4.
- **Performance budget** (`data/perf.json`, `tests/perf_smoke.gd`): logic ms per frame (phone size, trotting through tall grass, day and night), draw calls per frame (with a display) and node count. Budgets are a few times the measured values (in `_note`); a failure means something got much slower: find it, don't raise the budget without a reason.

## Palette and generated art
- **`data/palette.json` is the one palette** for everything except the cats and the cow (their hand-made character grids in `tools/make_art.gd` keep their own colours: leave them alone). Named colours and ramps (dark -> light): `ink`, `grass` (4 shades), `grass_dark/light`, `dirt`, `dirt_edge`, `leaf` (5), `bark`, `stone`, `water`, `flower.*`, `berry`, `butterfly`, `shadow`, `pollen`, `firefly`, `grade.*` (the colour grade per time of day), `pond_night`, `ui.*` (dialogue paper / ink / select, letterbox).
- **`tools/art/painters.gd`** paints every meadow PNG from it: lit-from-the-upper-left blobs with ordered (Bayer) dithering for foliage, canopies, bushes and the tileable forest, rocks, the log, the pond, tall grass, tufts, flowers, butterflies, bird/cloud/drop shadows, fireflies, and `ground()` (grass patches from seeded noise, the path from `world.json`). `make_art.gd`'s `PAINTED` table lists each file and its painter call. After changing the palette, a painter or the path: `godot --headless --path . --script res://tools/make_art.gd && godot --headless --path . --import`. `tests/test_art.gd` fails if a PNG is stale or uses colours outside the palette.

## Audio
- **Buses** (`default_bus_layout.tres`): Music, Ambience, SFX, Voice, UI, all into Master. The volume button (`scripts/view/volume_button.gd`, left of the fullscreen button, in the corner while that one is hidden) steps the Master bus through tuning.json `audio.volume_steps` (loud, half, off).
- **`data/audio.json`** names every sound: `music` (`day`, `night`: file + `volume_db`), `ambience` loops (`wind`, `crickets` with `day`/`night` volumes, `pond` with `near`), `sfx` and `ui` one-shots (`files`, `volume_db`, `pitch_jitter`, optional `bus`). `scripts/view/sound.gd` (created by the game screen after tap-to-start) plays them: `play_music(name)` crossfades over `audio.crossfade_s`; `set_time(day, night)` blends ambience and swaps to night music (if one exists); `set_pond_near()` fades the water in; birds chirp by day, laps play near the pond; `footstep(surface)` every `footstep_px` walked; `play(kind)` for the rest. A missing file warns once and stays silent.
- **All current audio is synthesised** by `tools/make_audio.gd` (CC0; deterministic). The music loops are **placeholders** (`audio/music/placeholder_*.wav`, `"placeholder": true` in audio.json). To add a real track: drop the `.ogg` (or `.wav`/`.mp3`) in `audio/music/`, point `audio.json` `music.day` / `music.night` at it, run `--import`, and add its CREDITS.md line. Loops: WAVs loop via their import setting `edit/loop_mode=2`; `sound.gd` also forces looping on any music / ambience stream. Keep WAVs PCM (`compress/mode=0`): the no-threads web build plays them as Web Audio samples.
- **Every file in `audio/` needs a line in `CREDITS.md`** with its path in backticks and its license; `tests/test_audio.gd` fails CI otherwise.

## Dialogue files
One JSON file per conversation in `data/dialogue/` (`bram.json`, `sorrel.json`, `wick.json`, `cow.json`):
```json
{
	"start": "start",
	"nodes": {
		"start": {"branch": [
			{"if": {"talked_wick": true}, "next": "repeat"},
			{"next": "hello"}
		]},
		"hello": {"speaker": "wick", "expression": "happy", "text": "Well, hi.", "choices": [
			{"text": "Eat it.", "next": "kept", "set": {"vole": "kept"}, "bond": {"wick": 1}},
			{"text": "Bring it to Sorrel.", "next": "shared", "set": {"vole": "shared"}}
		]},
		"kept": {"speaker": "wick", "text": "Our secret.", "set": {"talked_wick": true}, "end": true}
	}
}
```
- A **line** node has `speaker` (a speakers.json id: name plate, voice, portrait side), `text`, optional `expression` (default `neutral`) and exactly one of `next` (node id), `choices` (1-3, each `text` + `next` + optional `set`/`bond`) or `"end": true`.
- A **branch** node has only `branch` (plus optional `set`/`bond`): entries are checked in order, the first whose `if` matches wins (`if` = flag -> value, all must match; `null` = string flag unset; unset bools are `false`). The last entry has no `if`: the fallback.
- `set` writes flags (`{"vole": "kept"}`), `bond` changes bonds (`{"wick": 1}`). A node's apply when it is entered (so put `talked_x` on the last line), a choice's when it is picked.
- Repeat lines: the `start` node is a branch on `talked_<cat>`; the full conversation sets it on its last line.
- Fern's own choice is echoed as a `fern` line (shown on the right) before the reply.
- **Validation** (`tools/validate_dialogue.gd`, a CI step, and `tests/test_dialogue_files.gd`) fails on: missing start/next targets, unreachable nodes, unknown flags, values, speakers, bond cats, expressions or fields, more than 3 choices, a line without exactly one exit, a branch without a final fallback (or entries after it), and nodes that can never reach an end.

## Foundation rules (keep these from day one)
- **Logic is plain data, separate from Nodes.** Game state lives in `RefCounted` classes under `scripts/core/` with no Nodes, so it runs and tests headless. The view sends commands, the core validates and mutates state and returns events; the view only shows them.
- **One seeded RNG** in the game state for anything that affects gameplay. Never `randf()`/`randi()` in rules. Cosmetic randomness in the view is fine.
- **Content is JSON** in `data/` (strings, tuning, later: content). Prefer changing data over code. Tests read expected values from `data/` instead of hard-coding them.
- **Art is referenced by key** through `AssetCatalog`. Missing art shows a placeholder and never crashes, so content can land before art.
- **Core scripts use `preload` constants, not `class_name`**, so the tests run without an editor import step.
- **Compatibility renderer, no-threads web export**: the most reliable setup for phone browsers.
- **One command runs every headless test** and exits non-zero on any failure.

## Input and layout rules (PC + phone browser)
- **Landscape only**, base view 480x270 (expands on wider screens, see above). Portrait shows the "rotate your phone" overlay and pauses the game.
- **PC: keyboard** (WASD/arrows move, Shift trots, E/Space/Enter interacts; a gamepad works too). Actions are registered in `scripts/view/game_input.gd`, the one place that merges keyboard, gamepad and touch into a move vector + run + interact.
- **Phone: touch controls** (`scripts/view/touch_controls.gd`), shown only on touch devices and hidden while a keyboard is used or a conversation is open. The joystick base jumps to wherever the left thumb lands (left half); pushing past `stick_trot` trots. The paw button (right) interacts and lights up when something is in range.
- **No double events:** `emulate_mouse_from_touch` stays on so ordinary UI buttons (title, fullscreen) work by touch. The touch controls read only `InputEventScreenTouch`/`Drag` and ignore mouse events. Game-screen nodes ignore mouse events, except the dialogue box, which takes touches *and* real mouse clicks but drops emulated ones (`event.device == InputEvent.DEVICE_ID_EMULATION`). Never handle both for the same widget otherwise.
- **Browsers need a tap first** for audio and fullscreen: the game starts on the title screen. Fullscreen/orientation-lock calls must happen inside an input handler (`ScreenMetrics.toggle_fullscreen`).
- **Touch targets at least 48 CSS px**, kept `edge_margin` (data/tuning.json) inside the safe area, away from edges, notches and gesture bars. The world may draw under notches; controls, text and the fullscreen button never do. Everything re-lays out on resize, including mid-touch when the browser enters fullscreen.
- **Pixel art stays crisp**: nearest filtering, whole-number scaling, positions snapped to whole pixels.
- No pinch zoom, no browser scrolling: the canvas owns the whole page.

## Structure
- `data/*.json`: content, strings and tuning (`assets.json`, `strings.json`, `tuning.json`, `world.json` = meadow layout, `speakers.json`, `state.json` = flag/bond/expression registry, `palette.json` = every meadow colour, `audio.json` = sounds by name, `perf.json` = performance budgets; `build.json` is generated, never committed)
- `data/dialogue/*.json`: one conversation per file (see "Dialogue files")
- `art/`: PNGs referenced by key (all generated); `fonts/`: the dialogue font and its license; `audio/`: music, ambience, sfx, ui (all generated; each credited in `CREDITS.md`); `shaders/`: `sway.gdshader`, `pond.gdshader` (keys `shader.*`)
- `scripts/core/`: headless logic: `world.gd` (movement, collision, focus, pacing NPCs, talk lock, props / tree line / pond / path / tall grass / flowers; the seeded RNG), `day_cycle.gd` (afternoon -> dusk -> night), `game_state.gd`, `dialogue.gd`, `dialogue_validator.gd`, `typewriter.gd`, `asset_catalog.gd`, `game_strings.gd` (text from `strings.json`), `json_data.gd`. No Nodes.
- `scripts/autoload/`: `game_state.gd` (`GameState`), `dialogue_manager.gd` (`DialogueManager`): thin Nodes around the core
- `scripts/view/`: `app.gd` (screens, rotate overlay, build/fps label, fullscreen button), `fullscreen_button.gd`, `title.gd`, `game.gd` (SubViewport + overlays, talking, camera framing), `world_view.gd` (draws the world in layers, sway, life, grade, paw prompt), `npc.gd`, `dialogue_box.gd`, `voice.gd`, `sound.gd` (music, ambience, SFX, UI), `volume_button.gd`, `touch_controls.gd`, `game_input.gd`, `rotate_overlay.gd`, `screen_metrics.gd`
- `scenes/`: `app.tscn` is the main scene (its children are built in code); `npc.tscn` the reusable NPC
- `tests/`: `run_tests.gd` (runner, `SUITES` list), `test_base.gd`, `test_*.gd` suites (incl. `test_art.gd`, `test_audio.gd`, `test_day_cycle.gd`), `*_smoke.gd` real-scene tests (`app_smoke.gd` incl. time of day and odd screens, `dialogue_smoke.gd`, `perf_smoke.gd`)
- `tools/`: `setup_godot.sh`, `build_web.sh` (`BUILD_SHA=x` overrides the label for local update tests), `run_tests.sh`, `validate_dialogue.gd`, `make_art.gd` (bakes every PNG in `art/`: cats, cow, paw prompt and icons from character grids, everything else via `art/painters.gd` from `palette.json`), `make_audio.gd` (synthesises every file in `audio/`), `perf_probe.gd`, `web/service_worker.js`
- `.github/workflows/ci.yml`, `export_presets.cfg` (includes `data/dialogue/*.json`), `default_bus_layout.tres` (Music, Ambience, SFX, Voice, UI), `CREDITS.md` (every audio file, the font, the art)

## Running tests
```sh
tools/setup_godot.sh                                            # once per session
godot --headless --path . --import || true                      # first run / after adding art
tools/run_tests.sh                                              # all tests; non-zero exit on any failure or script error
```
`tools/run_tests.sh` wraps `godot --headless --path . --script res://tests/run_tests.gd` and also fails when Godot prints `SCRIPT ERROR`: a test that crashes mid-way would otherwise be reported as PASS. CI runs it twice: headless, then under `xvfb-run` so the pixel checks (game view in day, dusk, night and with the box open at phone and desktop size, the dialogue box with a line and with choices, edge pixels on odd screens) really run; the screenshots are uploaded as the `screenshots` artifact. `godot --headless --path . --script res://tools/validate_dialogue.gd` validates the dialogue files on its own. With a display (`xvfb-run -a tools/run_tests.sh -- --shots=<dir>`) the smoke tests also save phone and desktop screenshots. **Look at them** before saying a visual change works. Headless runs have no renderer, so smoke tests must skip pixel checks (not fail) when `DisplayServer.get_name() == "headless"`.

Arguments for the runner go after `--` (`-- --shots=<dir>`, `-- --only=<substring>`). Smoke tests fake DPR, safe-area insets, touch and fullscreen through `ScreenMetrics.override_dpr` / `override_insets_css` / `override_touch` / `override_fullscreen` (requests are then only counted in `fullscreen_requests`, never sent to the OS), drive touch with `InputEventScreenTouch`/`Drag` and keys with `Input.action_press`; with a display they also check that the on-screen world is the SubViewport image scaled by exactly k (every world pixel covers k x k device pixels of its colour).

Add `test_*` methods to a suite (register new suites in `SUITES`). Each test records failures instead of stopping, and the runner prints `PASS`/`FAIL` per test.

To try the web build locally: `tools/setup_godot.sh --web && tools/build_web.sh && python3 -m http.server -d build/web 8000`, then open it in a headless Chromium (Playwright) at a phone viewport and a desktop viewport and screenshot both. Real multi-touch needs CDP `Input.dispatchTouchEvent`. Web builds publish `window.catRpgStats` (fps, low, logic_ms, screen, player position, view_size, dialogue text shown so far, speaker, choices, voice_blips, flags, bonds, time_of_day, phase, music, volume) for scripted checks. Stats refresh twice a second: drive the cat with short key pulses, not long holds.

**Performance:** the corner shows fps and the lowest fps of the last half second. 60 fps can only be confirmed on the real phone. Headless Chromium uses a software GPU and is far slower, so don't read its fps. `logic_ms` (in `catRpgStats`) and `tools/perf_probe.gd` measure our own per-frame script cost; if a phone is slow while `logic_ms` is small, the cost is rendering or the browser.

## Working agreement
- **Check every feature against the pillars and the current milestone question.** Ask before building something neither covers.
- Small, focused commits with clear messages. Run the tests before every push. Never skip or delete a failing test to get green.
- When something is done, say how it was verified (tests, screenshots, the live URL and build SHA). If something wasn't checked, say so.
- Keep this file current: when a rule or structure changes, update it in the same commit.
- Tabs for indentation; typed GDScript where inference works.
- **Public repo**: never commit secrets, keys, tokens or personal info.

## Known pitfalls (learned the hard way)
- **Phones cache old builds.** That's why the build label and the `?v=<sha>` cache-busting exist. If the label shows an old SHA, reload; if it still does, the cache-busting rewrite broke.
- **Threaded web exports fail on GitHub Pages** (no cross-origin isolation headers). Always use the no-threads templates.
- **Blurry pixel art** comes from non-integer scale, linear filtering, or sub-pixel positions. Check all three.
- **iOS Safari safe areas** are only reported with `viewport-fit=cover` in the viewport meta.
- **Double taps on touch**: touch-to-mouse emulation plus a touch handler gives two events per tap.
- **`class_name` in core scripts** breaks headless tests on a fresh checkout (no import cache). Use `preload`.
- **The first headless run needs `--import`** or new PNGs won't load.
- **Controls snap to whole UI units** (`gui/common/snap_controls_to_pixels`). At DPR 2-3 that's a fraction of a device pixel off, which shifts pixel art by a row. Draw pixel art with `Sprite2D`, not `TextureRect`.
- **`set_anchors_preset()` keeps old offsets**; for nodes built in code use `set_anchors_and_offsets_preset()`.
- **GDScript keeps running after a runtime error**, so the runner can't see a crashed test. That's why CI runs `tools/run_tests.sh`.
- **`Performance.TIME_PROCESS` isn't per-frame script time**; measure with timestamps (see `app.gd` / `perf_probe.gd`).
- **Godot's PWA service worker is cache-first**: with it, every push shows the *previous* build once (or until all tabs close). Keep `build_web.sh`'s swap to `tools/web/service_worker.js`.
- **Fullscreen and orientation lock only work during a "user activation"**, and on phones a touch only counts when the finger **lifts** (`touchend`), while Godot delivers the touch when it lands. `request_fullscreen()` therefore requests at once only if `navigator.userActivation.isActive`, otherwise arms one-shot `touchend`/`click`/`keydown` listeners that request synchronously. iPhone Safari/Chrome don't support fullscreen for pages at all; the title then suggests Add to Home Screen.
- **`JavaScriptBridge.eval` returns JS booleans as 1/0**, not `"true"`. Use `ScreenMetrics.js_bool()`. (Comparing to `"true"` once hid the fullscreen button in every browser.)
- **Headless Chromium is lenient about fullscreen**: it grants it on touch-down, never resizes the page, and Playwright's `page.evaluate` counts as a user gesture. Test the no-activation path with CDP `Runtime.evaluate` and `userGesture: false`; test the resize in Godot smoke tests (`_resize`). `window.catRpgStats.fullscreen_button` shows whether the button is up.
- **Pixelify Sans has an "fi" ligature that reads as an "A"** ("first" -> "Arst"). The dialogue box wraps the font in a `FontVariation` with `liga` off; keep it.
- **Labels reshape while typing** with the default `visible_characters_behavior`, so words jump to the next line mid-word. The box uses `VC_CHARS_AFTER_SHAPING`.
- **The tap that opens or closes the dialogue box must not count twice.** The box ignores taps in the frame it opened, swallows the taps it uses (`set_input_as_handled`) and is added after the touch controls so it sees taps first (`_input` runs on later siblings first).
- **`get_image()` copies the texture**: never call it per frame (NPC head offsets are cached in `npc.gd`, sprite feet rows in `world_view.gd`).
- **Fonts are rasterised at the window's oversampling** (DPR), not at the size a SubViewport draws them. In the box viewport that gave smeared glyphs; the box sets `oversampling = 1.0` and antialiasing off on the font. Pixelify Sans is only pixel-exact at 12 px.
- **In a `canvas_item` fragment shader, `COLOR` already holds texture x modulate.** Sampling `TEXTURE` again and multiplying squares the colours (the pond went navy).
- **A `SubViewport` that is never displayed doesn't render** with the default update mode; set `render_target_update_mode` (the box: `UPDATE_ALWAYS` while open, `UPDATE_DISABLED` once closed).
- **Labels draw a pixel or two wider than `Font.get_string_size()`**: the choice rows add 2 px of slack.
- **`CanvasModulate` darkens everything in its canvas**, fireflies and prompts included: anything that must glow at night goes on the Overlay `CanvasLayer` (`follow_viewport_enabled`).
- **`json.dump(indent=...)` from Python explodes `world.json`** into one value per line; keep its compact one-entry-per-line style when editing it by script.
