extends SceneTree
## Synthesises every sound in audio/ (no samples, no downloads): the two
## PLACEHOLDER music loops, ambience loops (wind, crickets, pond), one-shot
## SFX (footsteps, rustle, bird chirps, pond laps) and UI sounds. All are our
## own work, CC0 (see CREDITS.md). Deterministic: a fixed RNG seed per sound.
## Run: godot --headless --path . --script res://tools/make_audio.gd
## Then: godot --headless --path . --import  (and tools/fix_audio_imports.sh)
##
## Real music: drop an .ogg (or .wav/.mp3) in audio/music/ and point
## data/audio.json "music" at it; add its CREDITS.md line.

const RATE := 22050
const OUT := "res://audio/"

var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "music"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "ambience"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "sfx"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "ui"))
	var ok := true
	ok = _save("music/placeholder_day", _music_day()) and ok
	ok = _save("music/placeholder_night", _music_night()) and ok
	ok = _save("ambience/wind", _wind(8.0)) and ok
	ok = _save("ambience/crickets", _crickets(4.0)) and ok
	ok = _save("ambience/pond", _pond_loop(4.0)) and ok
	for i in 3:
		ok = _save("sfx/bird_%d" % (i + 1), _chirp(i)) and ok
	for i in 2:
		ok = _save("sfx/step_grass_%d" % (i + 1), _step_grass(i)) and ok
		ok = _save("sfx/step_path_%d" % (i + 1), _step_path(i)) and ok
		ok = _save("sfx/pond_lap_%d" % (i + 1), _lap(i)) and ok
	ok = _save("sfx/rustle", _rustle()) and ok
	ok = _save("ui/open", _notes([660.0, 990.0], 0.05, 0.35)) and ok
	ok = _save("ui/move", _tick(1500.0, 0.03, 0.25)) and ok
	ok = _save("ui/confirm", _notes([740.0, 1110.0], 0.06, 0.4)) and ok
	ok = _save("ui/advance", _tick(900.0, 0.035, 0.22)) and ok
	quit(0 if ok else 1)


# --- Building blocks (buffers are PackedFloat32Array, -1..1)


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Adds a tone into `b` (wrapping round the end when `wrap`, for seamless
## loops). Harmonics: amplitudes of the 1st, 2nd, 3rd... partials.
func _tone(b: PackedFloat32Array, start: float, dur: float, hz: float, amp: float, attack: float, decay: float, harmonics: Array = [1.0], wrap: bool = true) -> void:
	var n := b.size()
	var i0 := int(start * RATE)
	var len := int(dur * RATE)
	for i in len:
		var t := float(i) / RATE
		var env := minf(1.0, t / maxf(attack, 0.001)) * exp(-t * decay)
		var tail := float(len - i) / RATE
		env *= minf(1.0, tail / 0.05)
		var s := 0.0
		for h in harmonics.size():
			s += sin(TAU * hz * (h + 1) * t) * float(harmonics[h])
		var idx := i0 + i
		if wrap:
			idx = posmod(idx, n)
		elif idx >= n:
			break
		b[idx] += s * env * amp


## A feedback echo (wrapping), for a little space.
func _echo(b: PackedFloat32Array, delay: float, feedback: float, passes: int) -> void:
	var d := int(delay * RATE)
	var n := b.size()
	for p in passes:
		var src := b.duplicate()
		for i in n:
			b[(i + d) % n] += src[i] * feedback


## One-pole low-pass filter in place.
func _lowpass(b: PackedFloat32Array, cutoff: float, wrap: bool = false) -> void:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := b[b.size() - 1] if wrap else 0.0
	for i in b.size():
		y += a * (b[i] - y)
		b[i] = y


func _noise(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for i in b.size():
		b[i] = _rng.randf_range(-1.0, 1.0)
	return b


func _normalize(b: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	for i in b.size():
		b[i] = b[i] / m * peak
	return b


## Crossfades the last `fade` seconds into the start, then drops them, so
## the loop has no seam.
func _seamless(b: PackedFloat32Array, fade: float) -> PackedFloat32Array:
	var f := int(fade * RATE)
	var n := b.size() - f
	for i in f:
		var t := float(i) / f
		b[i] = b[i] * t + b[n + i] * (1.0 - t)
	return b.slice(0, n)


func _midi(note: int) -> float:
	return 440.0 * pow(2.0, (note - 69) / 12.0)


# --- Music (PLACEHOLDERS: replace with a real track, see data/audio.json)


## Afternoon: 90 bpm, Cmaj7 - Am7 - Fmaj7 - G6, soft pad + plucked arpeggio.
func _music_day() -> PackedFloat32Array:
	_rng.seed = 101
	var beat := 60.0 / 90.0
	var chords := [[48, 55, 59, 64], [45, 52, 55, 60], [41, 48, 52, 57], [43, 50, 55, 59]]
	var bar := beat * 4.0
	var b := _buf(bar * 8.0)
	for c in 8:
		var chord: Array = chords[c % 4]
		var t0 := c * bar
		for note in chord:
			_tone(b, t0, bar + 0.8, _midi(note), 0.06, 0.6, 0.35, [1.0, 0.25, 0.08])
		var pattern := [0, 2, 3, 2, 1, 3, 2, 3]
		for e in 8:
			if c % 2 == 1 and e == 7:
				continue
			var note: int = chord[pattern[e]] + 12
			_tone(b, t0 + e * beat / 2.0, 1.4, _midi(note), 0.11 if e % 2 == 0 else 0.08, 0.005, 3.2, [1.0, 0.35, 0.12])
		# A slow, high melody note every other bar.
		if c % 2 == 0:
			_tone(b, t0 + beat * 1.5, beat * 3.0, _midi(chord[3] + 24), 0.04, 0.15, 1.0, [1.0, 0.2])
	_echo(b, beat * 0.75, 0.28, 2)
	_lowpass(b, 3200.0, true)
	return _normalize(b, 0.7)


## Night: 66 bpm, Am - Fmaj7 - C - Em, sparse, lower, more echo.
func _music_night() -> PackedFloat32Array:
	_rng.seed = 202
	var beat := 60.0 / 66.0
	var chords := [[45, 52, 57, 60], [41, 48, 52, 57], [48, 52, 55, 60], [40, 47, 52, 55]]
	var bar := beat * 4.0
	var b := _buf(bar * 4.0)
	for c in 4:
		var chord: Array = chords[c]
		var t0 := c * bar
		for note in chord:
			_tone(b, t0, bar + 1.2, _midi(note), 0.07, 1.2, 0.25, [1.0, 0.15])
		for e in [0, 3, 5]:
			_tone(b, t0 + e * beat / 2.0, 2.0, _midi(chord[(e + c) % 4] + 12), 0.08, 0.01, 1.8, [1.0, 0.25, 0.05])
	_echo(b, beat, 0.35, 3)
	_lowpass(b, 2200.0, true)
	return _normalize(b, 0.6)


# --- Ambience loops


## Wind: low-passed noise breathing slowly in and out.
func _wind(seconds: float) -> PackedFloat32Array:
	_rng.seed = 303
	var fade := 1.0
	var b := _noise(seconds + fade)
	_lowpass(b, 420.0)
	_lowpass(b, 600.0)
	for i in b.size():
		var t := float(i) / RATE
		b[i] *= 0.55 + 0.3 * sin(TAU * t / 4.0) + 0.15 * sin(TAU * t / 1.7 + 1.0)
	return _normalize(_seamless(b, fade), 0.8)


## Crickets: two crickets, short bursts of a high tone, exactly periodic.
func _crickets(seconds: float) -> PackedFloat32Array:
	var b := _buf(seconds)
	for cricket in [[4400.0, 0.5, 0.0, 3], [3900.0, 0.8, 0.21, 4]]:
		var hz: float = cricket[0]
		var every: float = cricket[1]
		var t := float(cricket[2])
		while t < seconds:
			for p in int(cricket[3]):
				_tone(b, t + p * 0.035, 0.022, hz, 0.25, 0.003, 30.0, [1.0, 0.1])
			t += every
	return _normalize(b, 0.6)


## Water against the bank: soft low bubbling, seamless.
func _pond_loop(seconds: float) -> PackedFloat32Array:
	_rng.seed = 404
	var fade := 0.6
	var b := _noise(seconds + fade)
	_lowpass(b, 260.0)
	_lowpass(b, 300.0)
	var t := 0.1
	while t < seconds:
		_tone(b, t, 0.25, _rng.randf_range(160.0, 260.0), 0.08, 0.01, 12.0, [1.0], false)
		t += _rng.randf_range(0.3, 0.9)
	return _normalize(_seamless(b, fade), 0.6)


# --- One-shots


func _chirp(variant: int) -> PackedFloat32Array:
	_rng.seed = 500 + variant
	var b := _buf(0.6)
	var t := 0.0
	var count: int = [3, 2, 4][variant]
	for c in count:
		var dur := _rng.randf_range(0.06, 0.11)
		var f0 := _rng.randf_range(2600.0, 3400.0)
		var f1 := f0 + _rng.randf_range(600.0, 1400.0) * (1.0 if c % 2 == 0 else -0.6)
		var i0 := int(t * RATE)
		var phase := 0.0
		for i in int(dur * RATE):
			var u := float(i) / (dur * RATE)
			var hz := lerpf(f0, f1, u) + sin(u * 40.0) * 120.0
			phase += TAU * hz / RATE
			var env := sin(PI * u)
			if i0 + i < b.size():
				b[i0 + i] += sin(phase) * env * 0.5
		t += dur + _rng.randf_range(0.03, 0.07)
	return _normalize(b, 0.7)


## A soft swish of grass underfoot.
func _step_grass(variant: int) -> PackedFloat32Array:
	_rng.seed = 600 + variant
	var b := _noise(0.09)
	var hp := b.duplicate()
	_lowpass(hp, 1800.0)
	for i in b.size():
		var u := float(i) / b.size()
		b[i] = (b[i] - hp[i]) * pow(1.0 - u, 2.0) * minf(1.0, u * 12.0)
	_lowpass(b, 5000.0)
	return _normalize(b, 0.5)


## A dull pad on dirt: a low thump plus a little grit.
func _step_path(variant: int) -> PackedFloat32Array:
	_rng.seed = 700 + variant
	var b := _noise(0.08)
	_lowpass(b, 900.0)
	for i in b.size():
		var u := float(i) / b.size()
		b[i] = (b[i] * pow(1.0 - u, 3.0) * 1.6 + sin(TAU * (110.0 - u * 40.0) * u * 0.08) * pow(1.0 - u, 4.0) * 0.6) * minf(1.0, u * 25.0)
	return _normalize(b, 0.55)


func _rustle() -> PackedFloat32Array:
	_rng.seed = 800
	var b := _noise(0.4)
	var lo := b.duplicate()
	_lowpass(lo, 1200.0)
	for i in b.size():
		var u := float(i) / b.size()
		var crackle := 0.6 + 0.4 * sin(u * 90.0) * sin(u * 37.0)
		b[i] = (b[i] - lo[i]) * crackle * sin(PI * minf(1.0, u * 1.15)) * (1.0 - u)
	_lowpass(b, 6000.0)
	return _normalize(b, 0.5)


func _lap(variant: int) -> PackedFloat32Array:
	_rng.seed = 900 + variant
	var b := _noise(0.5)
	_lowpass(b, 500.0)
	for i in b.size():
		var u := float(i) / b.size()
		b[i] *= sin(PI * u) * (1.0 - u)
	_tone(b, 0.05, 0.2, 140.0 + variant * 30.0, 0.15, 0.02, 10.0, [1.0], false)
	_tone(b, 0.18, 0.15, 200.0 + variant * 25.0, 0.1, 0.02, 14.0, [1.0], false)
	return _normalize(b, 0.55)


## Short notes in a row (UI open / confirm).
func _notes(hz: Array, each: float, amp: float) -> PackedFloat32Array:
	var b := _buf(each * hz.size() + 0.12)
	for i in hz.size():
		_tone(b, i * each, each + 0.1, hz[i], amp, 0.003, 28.0, [1.0, 0.3], false)
	return _normalize(b, amp)


func _tick(hz: float, dur: float, amp: float) -> PackedFloat32Array:
	var b := _buf(dur + 0.02)
	_tone(b, 0.0, dur, hz, amp, 0.002, 60.0, [1.0, 0.2], false)
	return _normalize(b, amp)


func _save(name: String, b: PackedFloat32Array) -> bool:
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		data.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	var path := ProjectSettings.globalize_path(OUT + name + ".wav")
	var err := w.save_to_wav(path)
	print("make_audio: wrote %s (%.2f s) err=%d" % [name, float(b.size()) / RATE, err])
	return err == OK
