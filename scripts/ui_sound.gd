class_name UiSound
extends Node
## Dźwięki interfejsu: najechanie (cichy drewniany "tik"), kliknięcie (mosiężny "klak"),
## start bitwy (werbel) i powrót. Najpierw szuka nagrań assets/sfx/ui_hover.wav, ui_click.wav,
## ui_start.wav, ui_back.wav (np. z ElevenLabs) — gdy ich brak, syntetyzuje dźwięk w kodzie.

const RATE := 44100

static var inst: UiSound

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _pi := 0
var _last_hover := -1.0


func _ready() -> void:
	inst = self
	GameSettings.ensure_loaded()
	_streams["hover"] = _load_or("hover", _make_hover())
	_streams["click"] = _load_or("click", _make_click())
	_streams["start"] = _load_or("start", _make_start())
	_streams["back"] = _load_or("back", _make_back())
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func play(kind: String) -> void:
	if inst != null:
		inst._play(kind)


func _play(kind: String) -> void:
	if not _streams.has(kind) or GameSettings.ui <= 0.001:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if kind == "hover":
		if now - _last_hover < 0.045:
			return   # szybkie przejechanie po liście: bez terkotu
		_last_hover = now
	var p := _pool[_pi]
	_pi = (_pi + 1) % _pool.size()
	p.stream = _streams[kind]
	p.pitch_scale = randf_range(0.96, 1.05) if kind == "hover" else randf_range(0.98, 1.02)
	var base := {"hover": -15.0, "click": -7.0, "start": -4.0, "back": -8.0}
	p.volume_db = float(base[kind]) + linear_to_db(maxf(GameSettings.ui, 0.0001))
	p.play()


func _load_or(name: String, fallback: AudioStreamWAV) -> AudioStream:
	var path := ProjectSettings.globalize_path("res://assets/sfx/ui_%s.wav" % name)
	if FileAccess.file_exists(path):
		var w := AudioStreamWAV.load_from_file(path)
		if w != null:
			return w
	return fallback


# ------------------------------------------------------------------ synteza

func _to_wav(s: PackedFloat32Array, gain := 0.9) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i] / peak * gain, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


func _make_hover() -> AudioStreamWAV:
	## Krótki, miękki "tik" jak dotknięcie drewnianej figurki na mapie sztabowej.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(RATE * 0.06)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var hp_prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.25
		var band := lp - hp_prev
		hp_prev += (lp - hp_prev) * 0.05
		var att := minf(1.0, t / 0.0008)
		out[i] = (band * 0.8 * exp(-t * 160.0) + sin(TAU * 1850.0 * t) * 0.35 * exp(-t * 90.0)
			+ sin(TAU * 620.0 * t) * 0.3 * exp(-t * 70.0)) * att
	return _to_wav(out, 0.7)


func _make_click() -> AudioStreamWAV:
	## "Klak": głuche uderzenie + metaliczny dzwięk mosiężnej klamry (nieharmoniczne alikwoty).
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.3
		var f := 170.0 * (1.0 + 0.8 * exp(-t * 60.0))
		ph += TAU * f / RATE
		var thump := sin(ph) * exp(-t * 38.0)
		var snap := lp * exp(-t * 120.0) * 0.9
		var ring := (sin(TAU * 1180.0 * t) * 0.5 + sin(TAU * 1735.0 * t) * 0.35 + sin(TAU * 2610.0 * t) * 0.2) * exp(-t * 26.0) * 0.45
		var att := minf(1.0, t / 0.001)
		out[i] = (thump + snap + ring) * att
	return _to_wav(out)


func _make_back() -> AudioStreamWAV:
	## Powrót: ten sam "klak", ale niższy i krótszy.
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.2
		ph += TAU * 120.0 * (1.0 + 0.5 * exp(-t * 50.0)) / RATE
		var ring := (sin(TAU * 820.0 * t) * 0.5 + sin(TAU * 1240.0 * t) * 0.3) * exp(-t * 34.0) * 0.4
		out[i] = (sin(ph) * exp(-t * 42.0) + lp * exp(-t * 110.0) * 0.8 + ring) * minf(1.0, t / 0.001)
	return _to_wav(out)


func _make_start() -> AudioStreamWAV:
	## Start bitwy: werbel (przednutka + uderzenie) z kotłem pod spodem.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var n := int(RATE * 0.9)
	var out := PackedFloat32Array()
	out.resize(n)
	for hit in [[0.0, 0.45], [0.075, 1.0], [0.30, 0.8]]:
		var t0: float = hit[0]
		var amp: float = hit[1]
		var lp := 0.0
		var lp2 := 0.0
		var ph := 0.0
		var s0 := int(t0 * RATE)
		for i in range(s0, n):
			var t := float(i - s0) / RATE
			if t > 0.6:
				break
			var w := rng.randf_range(-1.0, 1.0)
			lp += (w - lp) * 0.45
			lp2 += (lp - lp2) * 0.08
			var snare := (lp - lp2) * exp(-t * 14.0)          # sprężyny werbla
			var head := sin(TAU * 205.0 * t) * exp(-t * 30.0) * 0.7
			ph += TAU * 72.0 * (1.0 + 0.6 * exp(-t * 18.0)) / RATE
			var tom := sin(ph) * exp(-t * 7.0) * 0.9
			out[i] += (snare + head + tom) * amp * minf(1.0, t / 0.0015)
	return _to_wav(out)
