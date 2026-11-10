class_name UiSound
extends Node
## Dźwięki interfejsu: najechanie (stuknięcie pałeczką o obręcz bębna), kliknięcie (uderzenie w werbel),
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
	p.pitch_scale = randf_range(0.94, 1.07) if kind == "hover" else randf_range(0.97, 1.03)
	var base := {"hover": -10.0, "click": -4.5, "start": -4.0, "back": -6.0}
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


func _room(dry: PackedFloat32Array, wet := 1.0) -> PackedFloat32Array:
	## Wczesne odbicia małej sali (kilka opóźnionych, coraz cichszych i ciemniejszych powtórzeń) + lekkie
	## nasycenie: suchy syntetyczny "pstryk" dostaje ciało i przestrzeń, jak nagrany w pokoju sztabowym.
	var taps := [[0.019, 0.30], [0.031, 0.22], [0.047, 0.16], [0.071, 0.11], [0.103, 0.07]]
	var n := dry.size()
	var out := PackedFloat32Array()
	out.resize(n + int(RATE * 0.16))
	for i in n:
		out[i] = dry[i]
	for tp in taps:
		var d := int(float(tp[0]) * RATE)
		var g: float = float(tp[1]) * wet
		var lp := 0.0
		for i in n:
			lp += (dry[i] - lp) * 0.35      # odbicia są przytłumione
			out[i + d] += lp * g
	var total := out.size()
	var fade := int(RATE * 0.02)
	for i in total:
		var v := tanh(out[i] * 1.4)         # miękkie nasycenie zamiast ostrych szczytów
		if i > total - fade:
			v *= float(total - i) / fade
		out[i] = v
	return out


func _drum(length: float, f0: float, bend: float, body_decay: float, wires: float, stick: float, seed_v: int) -> PackedFloat32Array:
	## Uderzenie w bęben: membrana (ton opadający tuż po uderzeniu + drugi, nieharmoniczny tryb),
	## sprężyny werbla (szum pasmowy) i trzask pałeczki na samym początku.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var ph2 := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := f0 * (1.0 + bend * exp(-t * 48.0))
		ph += TAU * f / RATE
		ph2 += TAU * f * 1.59 / RATE
		var head := sin(ph) * exp(-t * body_decay) + sin(ph2) * exp(-t * body_decay * 1.6) * 0.38
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.55
		lp2 += (lp - lp2) * 0.10
		var band := lp - lp2
		var snare := band * (exp(-t * 30.0) * 0.55 + exp(-t * 170.0) * 0.9) * wires
		var tick := (sin(TAU * 2350.0 * t) * 0.6 + sin(TAU * 3870.0 * t) * 0.3) * exp(-t * 240.0) * stick
		out[i] = (head * 0.9 + snare + tick) * minf(1.0, t / 0.0012)
	return out


func _make_hover() -> AudioStreamWAV:
	## Najechanie: stuknięcie pałeczką o drewnianą obręcz bębna — krótkie, wyraźne, ciepłe.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := int(RATE * 0.11)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.5
		var wood := sin(TAU * 540.0 * t) * exp(-t * 58.0) * 0.75 \
			+ sin(TAU * 1270.0 * t + 0.4) * exp(-t * 85.0) * 0.45 \
			+ sin(TAU * 2180.0 * t + 1.1) * exp(-t * 130.0) * 0.2
		out[i] = (wood + lp * exp(-t * 380.0) * 0.55) * minf(1.0, t / 0.0008)
	return _to_wav(_room(out, 0.7), 0.85)


func _make_click() -> AudioStreamWAV:
	## Kliknięcie: pojedyncze, pewne uderzenie w werbel polowy.
	return _to_wav(_room(_drum(0.26, 165.0, 0.75, 24.0, 1.0, 0.7, 23)), 0.95)


func _make_back() -> AudioStreamWAV:
	## Powrót: niższy, stłumiony bęben bez sprężyn — "odłożenie" zamiast "rozkazu".
	return _to_wav(_room(_drum(0.22, 112.0, 0.5, 30.0, 0.25, 0.35, 29), 0.8), 0.9)


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
