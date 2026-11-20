extends Node
## Autoload "Needs": Fern's hunger and thirst for the session. A thin Node
## around scripts/core/needs.gd (tests use that directly). The game screen
## calls reset() when it starts and step() every unpaused frame; eating and
## drinking go through World.interact(Needs.needs), then refresh().
## Passing out (either at 0) is run by game.gd; restore() values are
## exported too.
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

## What hunger and thirst are set to when Fern wakes after passing out.
@export_range(0, 100) var restore_hunger := 60:
	set(v):
		restore_hunger = v
		needs.restore_hunger = v
@export_range(0, 100) var restore_thirst := 60:
	set(v):
		restore_thirst = v
		needs.restore_thirst = v

var _shown := Vector2i(-1, -1)


func _init() -> void:
	# Defaults from tuning.json; the Inspector can override them live.
	hunger_every_s = needs.hunger_every_s
	thirst_every_s = needs.thirst_every_s
	restore_hunger = needs.restore_hunger
	restore_thirst = needs.restore_thirst


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


## Debug / tests: sets one need ("hunger" or "thirst") directly.
func set_value(which: String, value: int) -> void:
	value = clampi(value, 0, needs.max_value)
	if which == "hunger":
		needs.hunger = value
	elif which == "thirst":
		needs.thirst = value
	refresh()


func hunger() -> int:
	return needs.hunger


func thirst() -> int:
	return needs.thirst
