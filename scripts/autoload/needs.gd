extends Node
## Autoload "Needs": Fern's hunger and thirst for the session. A thin Node
## around scripts/core/needs.gd (tests use that directly). The game screen
## calls reset() when it starts and step() every unpaused frame; eating and
## drinking go through World.interact(Needs.needs), then refresh().
## The rates are exported: change them in the remote Inspector
## (Scene dock > Remote > root > Needs) while the game runs.

signal needs_changed(hunger: int, thirst: int)

const NeedsCore := preload("res://scripts/core/needs.gd")

var needs := NeedsCore.new()

## Seconds per hunger point lost.
@export_range(0.0, 60.0, 0.1) var hunger_every_s := 6.0:
	set(v):
		hunger_every_s = v
		needs.hunger_every_s = v
## Seconds per thirst point lost.
@export_range(0.0, 60.0, 0.1) var thirst_every_s := 4.0:
	set(v):
		thirst_every_s = v
		needs.thirst_every_s = v

var _shown := Vector2i(-1, -1)


func _init() -> void:
	# Defaults from tuning.json; the Inspector can override them live.
	hunger_every_s = needs.hunger_every_s
	thirst_every_s = needs.thirst_every_s


## A new game: values back to the start (rates keep any Inspector change).
func reset() -> void:
	needs.reset()
	refresh()


func step(dt: float) -> void:
	needs.step(dt)
	refresh()


## Emits needs_changed if a value changed since the last emit.
func refresh() -> void:
	var now := Vector2i(needs.hunger, needs.thirst)
	if now != _shown:
		_shown = now
		needs_changed.emit(now.x, now.y)


func hunger() -> int:
	return needs.hunger


func thirst() -> int:
	return needs.thirst
