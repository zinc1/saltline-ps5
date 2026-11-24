extends Node
## Procedural audio. Every sound is synthesised into a PCM buffer at boot — the
## web build generated its audio the same way, and this keeps the pack tiny.
## Autoloaded as `Sfx`.

const MIX_RATE := 22050

var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _rain: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_build()
	Game.enemy_hit.connect(func(_e, killed, _w): play("kill" if killed else "hit"))
	Game.player_damaged.connect(func(_a, _f): play("hurt"))
	Game.relay_cut.connect(func(_i): play("relay"))
	Game.explosion.connect(func(_p, _r): play("boom"))
	_start_rain()


func play(name: String, vol_db := 0.0, pitch_jitter := 0.06) -> void:
	var stream: AudioStream = _cache.get(name)
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = vol_db
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return


func _start_rain() -> void:
	var stream: AudioStream = _cache.get("rain")
	if stream == null:
		return
	_rain = AudioStreamPlayer.new()
	_rain.stream = stream
	_rain.volume_db = -14.0
	add_child(_rain)
	_rain.play()


# --- synthesis -------------------------------------------------------------

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _noise(dur: float, amp: float, decay: float, tone := 0.0, tone_f := 180.0) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * decay)
		var s := (randf() * 2.0 - 1.0) * amp
		if tone > 0.0:
			phase += TAU * tone_f / MIX_RATE
			s += sin(phase) * tone * env
		out[i] = s * env
	return _wav(out)


func _sweep(dur: float, amp: float, f0: float, f1: float, decay := 6.0) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		phase += TAU * f / MIX_RATE
		out[i] = sin(phase) * amp * exp(-t * decay)
	return _wav(out)


func _click(dur: float, amp: float, freq := 1400.0) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		out[i] = sin(TAU * freq * t) * amp * exp(-t * 260.0)
	return _wav(out)


func _rain_loop(dur := 2.0) -> AudioStreamWAV:
	var n := int(dur * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var white := randf() * 2.0 - 1.0
		lp = lp * 0.94 + white * 0.06          # cheap low-pass: distant rain
		var hiss := white * 0.02
		out[i] = (lp * 0.9 + hiss) * 0.55
	# crossfade the tail into the head so the loop seam is inaudible
	var fade := int(0.12 * MIX_RATE)
	for i in fade:
		var k := float(i) / fade
		out[i] = out[i] * k + out[n - fade + i] * (1.0 - k)
	return _wav(out, true)


func _build() -> void:
	_cache["fire"] = _noise(0.16, 0.85, 26.0, 0.5, 150.0)
	_cache["fire_ads"] = _noise(0.13, 0.6, 30.0, 0.35, 190.0)
	_cache["dry"] = _click(0.05, 0.5, 2200.0)
	_cache["reload"] = _click(0.07, 0.45, 900.0)
	_cache["reload_end"] = _click(0.09, 0.6, 640.0)
	_cache["hit"] = _noise(0.09, 0.5, 44.0, 0.2, 420.0)
	_cache["kill"] = _sweep(0.35, 0.5, 320.0, 70.0, 7.0)
	_cache["hurt"] = _noise(0.3, 0.55, 12.0, 0.3, 90.0)
	_cache["melee"] = _noise(0.14, 0.5, 30.0, 0.2, 260.0)
	_cache["relay"] = _sweep(0.7, 0.6, 140.0, 38.0, 3.5)
	_cache["boom"] = _noise(0.9, 0.9, 6.0, 0.5, 60.0)
	_cache["land"] = _sweep(0.18, 0.45, 120.0, 46.0, 14.0)
	_cache["jump"] = _sweep(0.12, 0.22, 260.0, 400.0, 18.0)
	_cache["step"] = _noise(0.07, 0.22, 60.0, 0.1, 120.0)
	_cache["ui"] = _click(0.04, 0.35, 1100.0)
	_cache["ui_move"] = _click(0.03, 0.2, 1800.0)
	_cache["rain"] = _rain_loop()
