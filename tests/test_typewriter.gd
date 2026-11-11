extends "res://tests/test_base.gd"
## Typewriter timing and blips, with settings from tuning.json "dialogue".

const Typewriter := preload("res://scripts/core/typewriter.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

var t: Dictionary
var tw


func before_each() -> void:
	t = JsonData.load_dict("res://data/tuning.json")["dialogue"]
	tw = Typewriter.new()
	tw.configure(t)


func _run(seconds: float) -> int:
	var blips := 0
	for i in roundi(seconds * 2000.0):
		blips += tw.step(1.0 / 2000.0)
	return blips


func test_speed_is_cps() -> void:
	tw.start("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz")
	_run(0.5)
	check_near(tw.shown, float(t["cps"]) * 0.5, 1.0, "characters after 0.5 s")


func test_pauses_after_commas_and_periods() -> void:
	var c := 1.0 / float(t["cps"])
	var comma := float(t["comma_pause"])
	var period := float(t["period_pause"])
	tw.start("ab,cd.ef")
	check_near(tw.duration(), 8.0 * c + comma + period, 0.0001, "duration")
	# a b , | pause | c d . | pause | e f
	var after_comma := 3.0 * c
	var c_at := after_comma + comma + c
	var e_at := c_at + 2.0 * c + period + c
	_run_to(after_comma + 0.005)
	check_eq(tw.shown, 3, "comma shown")
	_run_to(c_at - 0.005)
	check_eq(tw.shown, 3, "still pausing after the comma")
	_run_to(c_at + 0.005)
	check_eq(tw.shown, 4, "goes on after the comma pause")
	_run_to(e_at - 0.005)
	check_eq(tw.shown, 6, "pausing after the period")
	_run_to(e_at + c + 0.005)
	check(tw.is_done(), "done")


var _elapsed := 0.0


func _run_to(total: float) -> void:
	_run(total - _elapsed)
	_elapsed = total


func test_no_pause_after_the_last_character() -> void:
	tw.start("Moo!")
	check_near(tw.duration(), 4.0 / float(t["cps"]), 0.0001, "no trailing pause")


func test_blip_every_two_characters() -> void:
	tw.start("abcdef gh")
	var blips := _run(5.0)
	check_eq(blips, 4, "8 visible characters -> 4 blips (spaces don't count)")
	check(tw.is_done(), "done")


func test_finish_shows_everything() -> void:
	tw.start("There you are.")
	tw.step(0.05)
	check(not tw.is_done(), "not done yet")
	tw.finish()
	check(tw.is_done(), "finish shows the whole line")
	check_eq(tw.step(1.0), 0, "no blips after finishing")
