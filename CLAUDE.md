# CLAUDE.md

> Starter instructions for a new Godot 4 project. The pipeline comes first: Godot, git, headless tests, CI, and a web build that runs on a phone and a PC. Game content comes later.
> **Fill in the `TODO` sections (Pillars, Milestones) before Milestone 1.** Milestone 0 needs nothing from you except the GitHub settings in "One-time setup".

## Goal
A Godot 4 (GDScript) prototype of **TODO: one-line pitch**.

Milestone 0 was **Hello Cow** (a tappable 48x48 cow) to prove the pipeline. Milestone 1 turned it into a landscape 480x270 game: a cat (Fern) walking around a meadow, with the cow as the first NPC. Milestone 2 makes it talk: three cats with branching conversations whose choices set flags that change later lines.

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
- **Milestone 3:** TODO (planned: nightfall, the ending, the choice log file, real portraits and sprites).

**Out of scope until a milestone asks for it:** saves, music, sound beyond voice blips, final art (portraits and sprites are placeholders), nightfall, the ending, a choice log file, menus beyond what a milestone needs, settings screens, localisation, native mobile apps, multiplayer.

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
- **The world renders into a small `SubViewport`, stretch aspect "expand" with integer scaling.** k = the largest whole number at which the 480x270 base view (`view.base` in tuning.json) fits the whole screen, in device pixels; the view then grows to fill the screen at that k, up to `view.max` (640x400), letterboxed beyond that. Wider screens see more meadow, never a blurry or uneven pixel. The world (`world.json` size, 720x405) must be at least `view.max` so a `Camera2D` (top-left anchored, limits = world edges, whole pixels) never shows past the edge; a test enforces it. Fill cost stays tiny on phones. Text, bubbles and touch controls draw at full resolution on top, in UI units.
- **Fullscreen:** the tap/click/key that starts the game calls `ScreenMetrics.request_fullscreen()` from inside the input handler (browsers allow it nowhere else), then locks orientation to landscape; failures are ignored. A small corner button (`fullscreen_button.gd`) does the same and hides while fullscreen or when launched from the home screen. iPhone Safari has no fullscreen for web pages: there the button is hidden and players use Add to Home Screen.
- **PWA on:** manifest with `display: fullscreen`, `orientation: landscape`, icons baked by `make_art.gd`; iPhone home-screen meta tags in `html/head_include`. `build_web.sh` **replaces Godot's service worker** with `tools/web/service_worker.js`: Godot's serves `index.html` cache-first and only updates after every tab closes, which would show the previous build after each push. Ours is network-first, revalidates the page, takes over immediately and caches only the offline page.

## Milestone 2: dialogue (how it fits together)
- **Core (headless, preload):** `scripts/core/game_state.gd` (flags + bonds), `dialogue.gd` (runs one conversation node by node), `dialogue_validator.gd`, `typewriter.gd` (cps, pauses, blip counting). The **autoloads** `GameState` and `DialogueManager` (`scripts/autoload/`, registered in `project.godot`) are thin Nodes around them; tests use the core classes directly. The game screen calls `GameState.reset()` when it starts (a new game).
- **Registries:** `data/state.json` lists every flag (`bool`, or `string` with its `values`), the cats that have bonds (`bonds`, each starts at 0) and the `expressions` (neutral/happy/sad/annoyed). `data/speakers.json` has each speaker's name, colour (portrait + name plate), `side` (`fern` is `right`) and voice (`pitch`, `volume_db`, `blip_ms`). A new flag or speaker goes in these first or validation fails.
- **NPCs:** `world.json` `npcs` entries have `id` (= speaker id), `art`, `frames`, `pos` (or a pacing `path` + `speed` + `pause`), `footprint`, `talk_radius` (22), `behavior` (`sit`/`lie`/`pace`/`stand`) and `dialogue` (file path). `scenes/npc.tscn` (`scripts/view/npc.gd`) is the reusable NPC scene; its exports (id, display name, voice pitch, dialogue file, ...) are filled from those files. Keep NPC feet at world y <= ~235: below that, the camera (limited to the world edge) can't lift them above the dialogue box at view.max (a smoke test checks every NPC).
- **Talking:** Interact next to the nearest NPC in range (it gets the bobbing paw print) calls `World.interact()`, which locks movement, stops the NPC and turns both to face each other, then `DialogueManager.start(file)`. While the box is open the touch controls hide, a tap anywhere advances, and the camera eases so both cats sit above the box.
- **Dialogue box** (`scripts/view/dialogue_box.gd`): sizes from tuning.json `dialogue` (box height 40%, font size from the box height, choices >= `min_choice_css` 44 CSS px). Interact finishes the line, then advances; a blinking arrow marks a finished line. Choices appear after the line has typed out, as rows above the box on Fern's side. Font: Pixelify Sans (`fonts/`, SIL OFL, license in `fonts/PixelifySans-OFL.txt`), looked up by key `font.dialogue`.
- **Voice** (`scripts/view/voice.gd`): generated tones (no audio files), one every `blip_every` (2) characters, pitch +- `pitch_jitter` (5%), on the `Voice` bus (`default_bus_layout.tres`). Created by the game screen, so nothing plays before tap-to-start.

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
- `data/*.json`: content, strings and tuning (`assets.json`, `strings.json`, `tuning.json`, `world.json` = meadow layout, `speakers.json`, `state.json` = flag/bond/expression registry; `build.json` is generated, never committed)
- `data/dialogue/*.json`: one conversation per file (see "Dialogue files")
- `art/`: PNGs referenced by key; `fonts/`: the dialogue font and its license
- `scripts/core/`: headless logic: `world.gd` (movement, collision, focus, pacing NPCs, talk lock; the seeded RNG), `game_state.gd`, `dialogue.gd`, `dialogue_validator.gd`, `typewriter.gd`, `asset_catalog.gd`, `game_strings.gd` (text from `strings.json`), `json_data.gd`. No Nodes.
- `scripts/autoload/`: `game_state.gd` (`GameState`), `dialogue_manager.gd` (`DialogueManager`): thin Nodes around the core
- `scripts/view/`: `app.gd` (screens, rotate overlay, build/fps label, fullscreen button), `fullscreen_button.gd`, `title.gd`, `game.gd` (SubViewport + overlays, talking, camera framing), `world_view.gd` (draws the world, paw prompt), `npc.gd`, `dialogue_box.gd`, `voice.gd`, `touch_controls.gd`, `game_input.gd`, `rotate_overlay.gd`, `screen_metrics.gd`
- `scenes/`: `app.tscn` is the main scene (its children are built in code); `npc.tscn` the reusable NPC
- `tests/`: `run_tests.gd` (runner, `SUITES` list), `test_base.gd`, `test_*.gd` suites, `*_smoke.gd` real-scene tests (`app_smoke.gd`, `dialogue_smoke.gd`)
- `tools/`: `setup_godot.sh`, `build_web.sh` (`BUILD_SHA=x` overrides the label for local update tests), `run_tests.sh`, `validate_dialogue.gd`, `make_art.gd` (bakes every PNG in `art/`, including the cats, paw prompt, sunny spot and web-app icons, from character grids), `perf_probe.gd`, `web/service_worker.js`
- `.github/workflows/ci.yml`, `export_presets.cfg` (includes `data/dialogue/*.json`), `default_bus_layout.tres` (the `Voice` bus)

## Running tests
```sh
tools/setup_godot.sh                                            # once per session
godot --headless --path . --import || true                      # first run / after adding art
tools/run_tests.sh                                              # all tests; non-zero exit on any failure or script error
```
`tools/run_tests.sh` wraps `godot --headless --path . --script res://tests/run_tests.gd` and also fails when Godot prints `SCRIPT ERROR`: a test that crashes mid-way would otherwise be reported as PASS. CI runs it twice: headless, then under `xvfb-run` so the pixel checks (game view, dialogue box with a line and with choices) really run; the screenshots are uploaded as the `screenshots` artifact. `godot --headless --path . --script res://tools/validate_dialogue.gd` validates the dialogue files on its own. With a display (`xvfb-run -a tools/run_tests.sh -- --shots=<dir>`) the smoke tests also save phone and desktop screenshots. **Look at them** before saying a visual change works. Headless runs have no renderer, so smoke tests must skip pixel checks (not fail) when `DisplayServer.get_name() == "headless"`.

Arguments for the runner go after `--` (`-- --shots=<dir>`, `-- --only=<substring>`). Smoke tests fake DPR, safe-area insets, touch and fullscreen through `ScreenMetrics.override_dpr` / `override_insets_css` / `override_touch` / `override_fullscreen` (requests are then only counted in `fullscreen_requests`, never sent to the OS), drive touch with `InputEventScreenTouch`/`Drag` and keys with `Input.action_press`; with a display they also check that the on-screen world is the SubViewport image scaled by exactly k (every world pixel covers k x k device pixels of its colour).

Add `test_*` methods to a suite (register new suites in `SUITES`). Each test records failures instead of stopping, and the runner prints `PASS`/`FAIL` per test.

To try the web build locally: `tools/setup_godot.sh --web && tools/build_web.sh && python3 -m http.server -d build/web 8000`, then open it in a headless Chromium (Playwright) at a phone viewport and a desktop viewport and screenshot both. Real multi-touch needs CDP `Input.dispatchTouchEvent`. Web builds publish `window.catRpgStats` (fps, low, logic_ms, screen, player position, dialogue text shown so far, speaker, choices, voice_blips, flags, bonds) for scripted checks. Stats refresh twice a second: drive the cat with short key pulses, not long holds.

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
- **`get_image()` copies the texture**: never call it per frame (NPC head offsets are cached in `npc.gd`).
