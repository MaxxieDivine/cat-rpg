# CLAUDE.md

> Starter instructions for a new Godot 4 project. The pipeline comes first: Godot, git, headless tests, CI, and a web build that runs on a phone and a PC. Game content comes later.
> **Fill in the `TODO` sections (Pillars, Milestones) before Milestone 1.** Milestone 0 needs nothing from you except the GitHub settings in "One-time setup".

## Goal
A Godot 4 (GDScript) prototype of **TODO: one-line pitch**.

The first thing it does is **Hello Cow**: a 48x48 pixel-art cow in the middle of the screen. Tap or click it and it says "Moo!". When the cow shows up crisp on a phone browser and a desktop browser from the GitHub Pages build, and CI is green, the pipeline works.

## Pillars
TODO: 3-5 short statements every feature is checked against. If a feature doesn't serve a pillar or the current milestone question, don't build it.

1. TODO
2. TODO
3. TODO

## Milestones
Each milestone has one **question** it is meant to answer. Build the smallest thing that answers it.

- **Milestone 0: Hello Cow (pipeline).** "Can we change the game, push, and see the change on a phone and a PC within minutes, with tests guarding it?" Done when everything in "Milestone 0 checklist" below holds.
- **Milestone 1:** TODO question. TODO scope.
- **Milestone 2:** TODO
- **Milestone 3:** TODO

**Out of scope until a milestone asks for it:** TODO (start list: saves, music, sound, final art, menus beyond what a milestone needs, settings screens, localisation, native mobile apps, multiplayer).

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

## Foundation rules (keep these from day one)
- **Logic is plain data, separate from Nodes.** Game state lives in `RefCounted` classes under `scripts/core/` with no Nodes, so it runs and tests headless. The view sends commands, the core validates and mutates state and returns events; the view only shows them.
- **One seeded RNG** in the game state for anything that affects gameplay. Never `randf()`/`randi()` in rules. Cosmetic randomness in the view is fine.
- **Content is JSON** in `data/` (strings, tuning, later: content). Prefer changing data over code. Tests read expected values from `data/` instead of hard-coding them.
- **Art is referenced by key** through `AssetCatalog`. Missing art shows a placeholder and never crashes, so content can land before art.
- **Core scripts use `preload` constants, not `class_name`**, so the tests run without an editor import step.
- **Compatibility renderer, no-threads web export**: the most reliable setup for phone browsers.
- **One command runs every headless test** and exits non-zero on any failure.

## Input and layout rules (PC + phone browser)
- Design for a **portrait phone first**. Larger screens use the extra space (landscape layouts) without shrinking text.
- **One input model for mouse and touch**: tap/click to select, tap/click again to confirm. Nothing depends on hover, right-click or keyboard. Long-press or an Info button shows details. Turn on `input_devices/pointing/emulate_mouse_from_touch` *or* handle `InputEventScreenTouch` explicitly, but never get two events for one tap; keep gesture handling in one input script, separate from game logic.
- **Touch targets at least 48 CSS px.** Respect safe areas.
- **Pixel art stays crisp**: nearest filtering, whole-number scaling, positions snapped to whole pixels.
- No pinch zoom, no browser scrolling: the canvas owns the whole page.

## Structure
- `data/*.json`: content, strings and tuning (`assets.json`, `strings.json`, `tuning.json`; `build.json` is generated, never committed)
- `art/`: PNGs referenced by key
- `scripts/core/`: headless logic, `asset_catalog.gd`, `game_strings.gd` (text from `strings.json`), `json_data.gd`. No Nodes.
- `scripts/view/`: scenes' scripts, `screen_metrics.gd`, input
- `scenes/`: `.tscn` files (main scene: `scenes/hello.tscn` for Milestone 0; later an `app.tscn` that swaps screens)
- `tests/`: `run_tests.gd` (runner, `SUITES` list), `test_base.gd`, `test_*.gd` suites, `*_smoke.gd` real-scene tests
- `tools/`: `setup_godot.sh`, `build_web.sh`, `make_cow.gd`
- `.github/workflows/ci.yml`, `export_presets.cfg`

## Running tests
```sh
tools/setup_godot.sh                                            # once per session
godot --headless --path . --import || true                      # first run / after adding art
godot --headless --path . --script res://tests/run_tests.gd     # all tests; non-zero exit on failure
```
With a display (`xvfb-run -a godot --path . --script res://tests/run_tests.gd -- --shots=<dir>`) the smoke tests also save phone and desktop screenshots. **Look at them** before saying a visual change works. Headless runs have no renderer, so smoke tests must skip pixel checks (not fail) when `DisplayServer.get_name() == "headless"`.

Arguments for the runner go after `--` (`-- --shots=<dir>`, `-- --only=<substring>`). Smoke tests fake DPR and safe-area insets through `ScreenMetrics.override_dpr` / `override_insets_css`; with a display they also check every cow art pixel covers exactly k x k device pixels of its colour.

Add `test_*` methods to a suite (register new suites in `SUITES`). Each test records failures instead of stopping, and the runner prints `PASS`/`FAIL` per test.

To try the web build locally: `tools/setup_godot.sh --web && tools/build_web.sh && python3 -m http.server -d build/web 8000`, then open it in a headless Chromium (Playwright) at a phone viewport and a desktop viewport and screenshot both.

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
