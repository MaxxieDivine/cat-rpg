# cat-rpg

Godot 4.3 (GDScript) prototype. Milestone 0 is **Hello Cow**: a crisp pixel-art cow that says "Moo!" when tapped, built and deployed to GitHub Pages by CI so it can be checked on a phone and a PC.

See [CLAUDE.md](CLAUDE.md) for goals, rules and structure.

```sh
tools/setup_godot.sh                                          # install pinned Godot into ~/.local/bin
godot --headless --path . --import || true
godot --headless --path . --script res://tests/run_tests.gd   # all tests
tools/setup_godot.sh --web && tools/build_web.sh              # web build into build/web
python3 -m http.server -d build/web 8000
```
