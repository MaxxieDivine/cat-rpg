extends Node
## Voice blips for dialogue: short generated tones (no audio files), one per
## call to blip(), on the "Voice" audio bus (default_bus_layout.tres). Each
## speaker's voice comes from data/speakers.json: pitch (1.0 = Fern), volume
## and blip length; longer blips get a gentler attack, so Sorrel sounds soft
## and slow. Every blip gets a random +-jitter on its pitch (cosmetic, so a
## view RNG is fine).
##
## Only the game screen creates this node, so no sound can play before the
## player's tap-to-start (browsers block audio until then anyway).

const BUS := "Voice"
const MIX_RATE := 22050
## The tone at pitch 1.0 (Hz).
const BASE_HZ := 330.0
const POOL := 4

var jitter := 0.05
## For tests and catRpgStats: how many blips played and their last pitch.
var blips_played := 0
var last_pitch := 0.0

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Voice"
	ensure_bus()
	_rng.randomize()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)


## The bus normally comes from default_bus_layout.tres; add it if missing.
static func ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")


## Plays one blip in `voice` ({"pitch", "volume_db", "blip_ms"}).
func blip(voice: Dictionary) -> void:
	if _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _stream(int(voice.get("blip_ms", 45)))
	last_pitch = float(voice.get("pitch", 1.0)) * (1.0 + _rng.randf_range(-jitter, jitter))
	p.pitch_scale = maxf(0.05, last_pitch)
	p.volume_db = float(voice.get("volume_db", -12.0))
	p.play()
	blips_played += 1


func _stream(ms: int) -> AudioStreamWAV:
	if not _streams.has(ms):
		_streams[ms] = make_blip(ms)
	return _streams[ms]


## A short tone: a sine with a little of its octave for a "voice" colour,
## attack then decay. 16-bit mono.
static func make_blip(ms: int) -> AudioStreamWAV:
	var n := maxi(8, MIX_RATE * ms / 1000)
	var attack := maxi(1, int(n * clampf(ms / 400.0, 0.06, 0.3)))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := float(i) / attack if i < attack else pow(1.0 - float(i - attack) / (n - attack), 2.0)
		var s := sin(TAU * BASE_HZ * t) * 0.8 + sin(TAU * BASE_HZ * 2.0 * t) * 0.2
		data.encode_s16(i * 2, int(clampf(s * env * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
