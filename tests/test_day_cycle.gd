extends "res://tests/test_base.gd"
## Afternoon -> dusk -> night after the three conversations.

const DayCycle := preload("res://scripts/core/day_cycle.gd")
const JsonData := preload("res://scripts/core/json_data.gd")

var tod: Dictionary


func before_each() -> void:
	tod = JsonData.load_dict("res://data/tuning.json")["time_of_day"]


func _all_talked() -> Dictionary:
	var f := {}
	for k in tod["after_flags"]:
		f[k] = true
	return f


func test_stays_afternoon_until_every_conversation_is_done() -> void:
	var d = DayCycle.new(tod)
	var flags := _all_talked()
	flags.erase(tod["after_flags"][0])
	for i in 600:
		d.step(1.0 / 60.0, flags, false)
	check_eq(d.t, 0.0, "still afternoon with one conversation left")
	check_eq(d.phase(), "afternoon", "phase")


func test_waits_for_the_box_to_close() -> void:
	var d = DayCycle.new(tod)
	check(d.step(1.0, _all_talked(), true).is_empty(), "no nightfall mid-conversation")
	check(not d.started, "not started while talking")
	var ev: Array = d.step(0.0, _all_talked(), false)
	check(ev.size() == 1 and ev[0]["type"] == "nightfall", "starts once the box closes")


func test_turns_to_night_over_the_duration() -> void:
	var d = DayCycle.new(tod)
	var dur := float(tod["duration"])
	check_near(dur, 8.0, 2.0, "about 8 seconds")
	var seen := {}
	var night_at := -1.0
	var time := 0.0
	while time < dur + 1.0:
		for e in d.step(0.1, _all_talked(), false):
			if e["type"] == "night":
				night_at = time + 0.1
		seen[d.phase()] = true
		time += 0.1
	check(seen.has("afternoon") and seen.has("dusk") and seen.has("night"), "passes through every phase (%s)" % [seen.keys()])
	check_near(night_at, dur, 0.15, "night after %s s" % dur)
	check_eq(d.t, 1.0, "stays night")
	check_eq(d.night_amount(), 1.0, "fully night")
	check_near(d.day_amount(), 0.0, 0.001, "no day left")


func test_blend_hits_each_stage() -> void:
	var d = DayCycle.new(tod)
	var a := Color.RED
	var b := Color.GREEN
	var c := Color.BLUE
	d.set_t(0.0)
	check_eq(d.blend(a, b, c), a, "afternoon")
	d.set_t(float(tod["dusk_at"]))
	check_eq(d.blend(a, b, c), b, "dusk")
	d.set_t(1.0)
	check_eq(d.blend(a, b, c), c, "night")
	check_near(d.blend(0.0, 1.0, 2.0), 2.0, 0.0001, "floats blend too")
