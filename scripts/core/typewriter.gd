extends RefCounted
## Reveals a line a character at a time: `cps` characters per second, with
## a short pause after commas and a longer one after sentence ends. Every
## `blip_every`-th visible (non-space) character asks for a voice blip.
## Plain data so it tests headless; the dialogue box calls step() each
## frame. preload() this script. Settings come from tuning.json "dialogue".

const SENTENCE_ENDS := ".!?"

var cps := 40.0
var comma_pause := 0.08
var period_pause := 0.2
var blip_every := 2

var text := ""
## Characters shown so far.
var shown := 0
var _bank := 0.0
var _pause := 0.0
var _visible_count := 0


func configure(t: Dictionary) -> void:
	cps = maxf(1.0, float(t.get("cps", cps)))
	comma_pause = float(t.get("comma_pause", comma_pause))
	period_pause = float(t.get("period_pause", period_pause))
	blip_every = maxi(1, int(t.get("blip_every", blip_every)))


func start(t: String) -> void:
	text = t
	shown = 0
	_bank = 0.0
	_pause = 0.0
	_visible_count = 0


func is_done() -> bool:
	return shown >= text.length()


## Shows the whole line at once.
func finish() -> void:
	shown = text.length()
	_bank = 0.0
	_pause = 0.0


## Advances by dt seconds. Returns how many blips to play (usually 0 or 1).
func step(dt: float) -> int:
	var blips := 0
	_bank += dt
	while shown < text.length():
		var cost := 1.0 / cps + _pause
		if _bank < cost:
			break
		_bank -= cost
		_pause = 0.0
		var ch := text[shown]
		shown += 1
		if ch != " ":
			if _visible_count % blip_every == 0:
				blips += 1
			_visible_count += 1
		if shown < text.length():
			if ch == ",":
				_pause = comma_pause
			elif SENTENCE_ENDS.contains(ch):
				_pause = period_pause
	if is_done():
		_bank = 0.0
	return blips


## Seconds the whole line takes to type out.
func duration() -> float:
	var t := 0.0
	for i in text.length():
		t += 1.0 / cps
		var ch := text[i]
		if i < text.length() - 1:
			if ch == ",":
				t += comma_pause
			elif SENTENCE_ENDS.contains(ch):
				t += period_pause
	return t
