# cat-rpg

Godot 4.3 (GDScript) prototype: a pixel-art cat, Fern (480x270, landscape), walking a meadow and talking to Bram, Sorrel and Wick, playable in a phone or desktop browser. Every push to `main` is tested and published to GitHub Pages: https://maxxiedivine.github.io/cat-rpg/

Controls: WASD/arrows to move, Shift to trot, E/Space to interact (talk, finish a line, advance); Up/Down picks a choice. On a phone: left thumb moves (push far to trot), paw button talks, then tap anywhere to advance and tap a choice to pick it.

The dialogue font is [Pixelify Sans](https://github.com/eifetx/Pixelify-Sans) under the SIL Open Font License ([fonts/PixelifySans-OFL.txt](fonts/PixelifySans-OFL.txt)).

Starting the game goes fullscreen (landscape-locked on Android). On iPhone, Safari can't do fullscreen for web pages: tap Share → **Add to Home Screen** and launch it from there for a full-screen, app-like game.

See [CLAUDE.md](CLAUDE.md) for goals, rules and structure.

```sh
tools/setup_godot.sh                                          # install pinned Godot into ~/.local/bin
godot --headless --path . --import || true
tools/run_tests.sh                                            # all tests
tools/setup_godot.sh --web && tools/build_web.sh              # web build into build/web
python3 -m http.server -d build/web 8000
```
