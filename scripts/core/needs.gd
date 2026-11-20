extends RefCounted
## Fern's needs: hunger and thirst, whole numbers from 0 to `max_value`.
## Each drops by 1 every `hunger_every_s` / `thirst_every_s` seconds of game
## time (step()); eating and drinking raise them (capped). The HUD warns
## below `low`; when either reaches 0 Fern passes out (collapsed(); game.gd
## runs the collapse) and wakes in camp with restore() values.
## Plain data, no Nodes (the `Needs` autoload wraps it). preload(), no
## class_name. Tuning: data/tuning.json "needs".

const JsonData := preload("res://scripts/core/json_data.gd")
const TUNING_PATH := "res://data/tuning.json"

var max_value := 100
var start := 80
var hunger := 80
var thirst := 80
## Seconds per point lost (0 or less = never).
var hunger_every_s := 6.0
var thirst_every_s := 4.0
## Below this a bar pulses.
var low := 25
## What one bite of fresh-kill and one drink give.
var eat_amount := 40
var drink_amount := 50
## Above this Fern isn't hungry and won't take prey from the pile.
var full_above := 90
## What hunger and thirst are set to when Fern wakes after passing out.
var restore_hunger := 60
var restore_thirst := 60

var _hunger_t := 0.0
var _thirst_t := 0.0


func _init(t: Dictionary = {}) -> void:
	if t.is_empty():
		t = JsonData.load_dict(TUNING_PATH).get("needs", {})
	max_value = int(t.get("max", max_value))
	start = int(t.get("start", start))
	hunger_every_s = float(t.get("hunger_every_s", hunger_every_s))
	thirst_every_s = float(t.get("thirst_every_s", thirst_every_s))
	low = int(t.get("low", low))
	eat_amount = int(t.get("eat", eat_amount))
	drink_amount = int(t.get("drink", drink_amount))
	full_above = int(t.get("full_above", full_above))
	restore_hunger = int(t.get("restore_hunger", restore_hunger))
	restore_thirst = int(t.get("restore_thirst", restore_thirst))
	reset()


func reset() -> void:
	hunger = clampi(start, 0, max_value)
	thirst = clampi(start, 0, max_value)
	_hunger_t = 0.0
	_thirst_t = 0.0


## Advances time. Returns true if a value changed.
func step(dt: float) -> bool:
	var before := Vector2i(hunger, thirst)
	if hunger_every_s > 0.0:
		_hunger_t += dt
		while _hunger_t >= hunger_every_s:
			_hunger_t -= hunger_every_s
			hunger = maxi(0, hunger - 1)
	if thirst_every_s > 0.0:
		_thirst_t += dt
		while _thirst_t >= thirst_every_s:
			_thirst_t -= thirst_every_s
			thirst = maxi(0, thirst - 1)
	return Vector2i(hunger, thirst) != before


func eat(amount: int = -1) -> void:
	hunger = mini(max_value, hunger + (eat_amount if amount < 0 else amount))


func drink(amount: int = -1) -> void:
	thirst = mini(max_value, thirst + (drink_amount if amount < 0 else amount))


## Hunger or thirst is at 0: Fern passes out.
func collapsed() -> bool:
	return hunger <= 0 or thirst <= 0


## After passing out: both set to the restore values (the timers restart,
## so she gets the full interval before the next point drops).
func restore() -> void:
	hunger = clampi(restore_hunger, 0, max_value)
	thirst = clampi(restore_thirst, 0, max_value)
	_hunger_t = 0.0
	_thirst_t = 0.0


func is_full() -> bool:
	return hunger > full_above


func is_low(value: int) -> bool:
	return value < low


## 0..1 for a bar.
func fraction(value: int) -> float:
	return clampf(float(value) / float(maxi(1, max_value)), 0.0, 1.0)
