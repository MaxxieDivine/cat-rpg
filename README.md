# cat-rpg

Godot 4.3 (GDScript) prototype: a pixel-art cat (480x270, landscape) walking a meadow, playable in a phone or desktop browser. Every push to `main` is tested and published to GitHub Pages: https://maxxiedivine.github.io/cat-rpg/

Controls: WASD/arrows to move, Shift to trot, E/Space to interact. On a phone: left thumb moves (push far to trot), paw button interacts.

See [CLAUDE.md](CLAUDE.md) for goals, rules and structure.

```sh
tools/setup_godot.sh                                          # install pinned Godot into ~/.local/bin
godot --headless --path . --import || true
tools/run_tests.sh                                            # all tests
tools/setup_godot.sh --web && tools/build_web.sh              # web build into build/web
python3 -m http.server -d build/web 8000
```
