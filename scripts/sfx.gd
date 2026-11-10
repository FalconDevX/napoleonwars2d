class_name Sfx
extends Node
## Dźwięki bitwy generowane proceduralnie (bez plików): wystrzał muszkietu i huk działa.
## Z bliska: wystrzały muszkietów i huk dział; z daleka (oddalona kamera) - tylko odległy pomruk artylerii.

const RATE := 22050
const MUSKET_VARIANTS := 4
const CANNON_VARIANTS := 3
const MIN_ZOOM := 0.45        # poniżej tego zbliżenia nie słychać nic
const MUSKET_GAP := 0.03      # salwa: najwyżej ~33 wystrzały na sekundę (reszta zlewa się)

var battle: Battle
var _musket: Array[AudioStreamWAV] = []
var _cannon: Array[AudioStreamWAV] = []
var _musket_pool: Array[AudioStreamPlayer] = []
var _cannon_pool: Array[AudioStreamPlayer] = []
var _cannon_far: Array[AudioStreamWAV] = []        # odległy huk dział (oddalona kamera / działo daleko)
var _far_pool: Array[AudioStreamPlayer] = []
var _fi := 0
var _last_far := -1.0
const BALL_PRE := 1.3          # w plikach ball_N.wav szczyt świstu (= uderzenie) wypada 1.3 s od początku
var _impact: Array[AudioStreamWAV] = []   # uderzenie kuli w ziemię
var _impact_pool: Array[AudioStreamPlayer] = []
var _ii := 0
var _last_impact := -1.0
var _ball: Array[AudioStreamWAV] = []
var _ball_pool: Array[AudioStreamPlayer] = []
var _bi := 0
var _last_ball := -1.0
const FAR_RANGE := 9000.0     # z tej odległości (jednostki świata) dalekie działa cichną
const FAR_GAP := 0.16         # wielka bateria: najwyżej ~6 dalekich huków na sekundę
var _mi := 0
var _clash: Array[AudioStreamWAV] = []     # zderzenie dwóch oddziałów jazdy: łoskot koni i szczęk szabel
var _clash_pool: Array[AudioStreamPlayer] = []
var _ki := 0
var _last_clash := -1.0
var _ci := 0
var _last_musket := -1.0


func setup(p_battle: Battle) -> void:
	battle = p_battle
	GameSettings.ensure_loaded()
	# Nagrane wystrzały (assets/sfx/musket_1.wav ... musket_N.wav, losowane), a gdy ich brak - syntetyczne.
	for k in range(1, 13):
		var rec := _load_wav("res://assets/sfx/musket_%d.wav" % k)
		if rec != null:
			_musket.append(rec)
	if _musket.is_empty():
		for v in MUSKET_VARIANTS:
			_musket.append(_make_musket(v))
	# Nagrane wystrzały dział (assets/sfx/cannon_1.wav ...), a gdy ich brak - syntetyczne.
	for k in range(1, 13):
		var rec := _load_wav("res://assets/sfx/cannon_%d.wav" % k)
		if rec != null:
			_cannon.append(rec)
	if _cannon.is_empty():
		for v in CANNON_VARIANTS:
			_cannon.append(_make_cannon(v))
	for k in range(1, 13):
		var rec := _load_wav("res://assets/sfx/cannon_far_%d.wav" % k)
		if rec != null:
			_cannon_far.append(rec)
	for i in 4:
		_far_pool.append(_player())
	for k in range(1, 13):
		var rec := _load_wav("res://assets/sfx/ball_%d.wav" % k)
		if rec != null:
			_ball.append(rec)
	for i in 4:
		_ball_pool.append(_player())
	for k in range(1, 13):
		var rec := _load_wav("res://assets/sfx/impact_%d.wav" % k)
		if rec != null:
			_impact.append(rec)
	for i in 5:
		_impact_pool.append(_player())
	for i in 14:
		_musket_pool.append(_player())
	for v in 3:
		_clash.append(_make_cav_clash(v))
	for i in 3:
		_clash_pool.append(_player())
	for i in 5:
		_cannon_pool.append(_player())


# ------------------------------------------------------------------ muzyka

## Menu: własny motyw. Bitwa: playlista (utwory po kolei), w teatrze zimowym zaczyna motyw rosyjski.
## Muzyka bitwy jest cichsza, żeby nie zagłuszać wystrzałów. Zmiana kontekstu = płynne przejście.
const MUSIC_DIR := "res://assets/music/"
const MENU_TRACKS := ["menu_banner_over_the_ridge.mp3"]
const BATTLE_TRACKS := ["battle_crown_and_cannon.mp3", "battle_bayonets_at_dawn.mp3"]
const WINTER_TRACKS := ["winter_snows_of_smolensk.mp3"]
const MENU_DB := -6.0
const BATTLE_DB := -15.0
static var _music: AudioStreamPlayer      # przeżywa przeładowanie sceny (wisi na korzeniu drzewa)
static var _music_ctx := ""               # "menu" / "battle" - co teraz gra
static var _music_track := ""
static var _battle_idx := 0
static var _streams := {}
var _music_vol := -1.0


func _stream(file: String) -> AudioStreamMP3:
	if _streams.has(file):
		return _streams[file]
	var abs_path := ProjectSettings.globalize_path(MUSIC_DIR + file)
	var st: AudioStreamMP3 = null
	if FileAccess.file_exists(abs_path):
		st = AudioStreamMP3.load_from_file(abs_path)
	_streams[file] = st
	return st


func _playlist(ctx: String) -> Array:
	if ctx == "menu":
		return MENU_TRACKS
	var winter := float(Terrain.tv("snow")) > 0.5
	return WINTER_TRACKS + BATTLE_TRACKS if winter else BATTLE_TRACKS


func _next_track(ctx: String) -> String:
	var list := _playlist(ctx)
	if ctx == "menu":
		return list[0]
	var t: String = list[_battle_idx % list.size()]
	_battle_idx += 1
	return t


func _process(delta: float) -> void:
	if battle == null or not is_inside_tree():
		return
	if _music == null or not is_instance_valid(_music):
		_music = AudioStreamPlayer.new()
		_music.volume_db = -80.0
		get_tree().root.add_child.call_deferred(_music)
		return
	if not _music.is_inside_tree():
		return
	var ctx := "menu" if battle.menu_open and battle.overlay != null and battle.overlay.title else "battle"
	if _autotest_quiet():
		ctx = ""
	if _music_vol < 0.0:
		# nowa scena: kontynuujemy od bieżącej głośności (bez urwania)
		_music_vol = clampf(db_to_linear(_music.volume_db - (MENU_DB if _music_ctx == "menu" else BATTLE_DB)) / maxf(GameSettings.music, 0.01), 0.0, 1.0) if _music.playing else 0.0
	if ctx != _music_ctx:
		# przejście: wyciszenie starego utworu, potem nowy
		_music_vol = move_toward(_music_vol, 0.0, delta / 1.8)
		if _music_vol <= 0.0:
			_music.stop()
			_music_ctx = ctx
			if ctx == "battle":
				_battle_idx = 0 if float(Terrain.tv("snow")) > 0.5 else randi() % BATTLE_TRACKS.size()
			if ctx != "":
				_music_track = _next_track(ctx)
				var st := _stream(_music_track)
				if st != null:
					st.loop = ctx == "menu"
					_music.stream = st
					_music.play()
					print("music: ", _music_track)
	else:
		_music_vol = move_toward(_music_vol, 1.0 if ctx != "" else 0.0, delta / 2.5)
		if ctx == "battle" and not _music.playing:
			# koniec utworu w bitwie: krótka cisza i następny z playlisty
			_music_track = _next_track(ctx)
			var st2 := _stream(_music_track)
			if st2 != null:
				st2.loop = false
				_music.stream = st2
				_music_vol = 0.0
				_music.play()
	_music.volume_db = (MENU_DB if _music_ctx == "menu" else BATTLE_DB) + linear_to_db(maxf(_music_vol * GameSettings.music, 0.0001))


func _autotest_quiet() -> bool:
	return "--autotest" in OS.get_cmdline_user_args()


func _load_wav(path: String) -> AudioStreamWAV:
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	return AudioStreamWAV.load_from_file(abs_path)


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	add_child(p)
	return p


func _audibility(world_pos: Vector2) -> float:
	var cam := battle.cam
	var z := cam.zoom.x
	if z < MIN_ZOOM:
		return 0.0
	var vs := get_viewport().get_visible_rect().size
	var half := vs.length() * 0.5
	var d := (world_pos - cam.get_screen_center_position()).length() * z / half
	var near := clampf((z - MIN_ZOOM) / 0.6, 0.0, 1.0)
	return clampf(1.15 - d, 0.0, 1.0) * near


func musket(world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_musket < MUSKET_GAP:
		return
	var a := _audibility(world_pos)
	if a < 0.04:
		return
	_last_musket = now
	var p := _musket_pool[_mi]
	_mi = (_mi + 1) % _musket_pool.size()
	p.stream = _musket[randi() % _musket.size()]
	p.pitch_scale = randf_range(0.85, 1.1)   # zmienna wysokość: salwa nie brzmi jak jeden dźwięk powielony
	p.volume_db = linear_to_db(a * maxf(GameSettings.sfx, 0.0001)) - 9.0
	p.play()


func cannon(world_pos: Vector2) -> void:
	var a := _audibility(world_pos)
	_cannon_distant(world_pos, a)
	if a < 0.04:
		return
	var p := _cannon_pool[_ci]
	_ci = (_ci + 1) % _cannon_pool.size()
	p.stream = _cannon[randi() % _cannon.size()]
	p.pitch_scale = randf_range(0.9, 1.08)
	p.volume_db = linear_to_db(a * maxf(GameSettings.sfx, 0.0001)) - 1.0
	p.play()


func cav_clash(pos: Vector2) -> void:
	## Jazda wpada na jazdę: głuche zderzenie koni, tętent i szczęk krzyżowanych szabel.
	var a := _audibility(pos)
	if a < 0.05:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_clash < 0.35:
		return
	_last_clash = now
	var p := _clash_pool[_ki]
	_ki = (_ki + 1) % _clash_pool.size()
	p.stream = _clash[randi() % _clash.size()]
	p.pitch_scale = randf_range(0.94, 1.06)
	p.volume_db = linear_to_db(a * maxf(GameSettings.sfx, 0.0001)) - 2.0
	p.play()


func _make_cav_clash(seed_v: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + seed_v
	var n := int(RATE * 1.5)
	var out := PackedFloat32Array()
	out.resize(n)
	# 1) zderzenie mas: niski łomot + stłumiony szum; 2) tętent: szybkie, nieregularne uderzenia kopyt
	var lp := 0.0
	var lp2 := 0.0
	var gallop := rng.randf_range(9.0, 12.0)
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.10
		lp2 += (w - lp2) * 0.03
		var thud := sin(TAU * 68.0 * t * (1.0 + 0.5 * exp(-t * 20.0))) * exp(-t * 9.0) * 1.1 + lp * exp(-t * 14.0) * 1.3
		var beat := pow(maxf(0.0, sin(TAU * gallop * t + sin(t * 23.0) * 0.8)), 6.0)
		var hooves := lp2 * beat * exp(-t * 2.6) * 2.6
		out[i] = (thud + hooves) * minf(1.0, t / 0.002)
	# 3) szable: kilkanaście brzęknięć stali o różnej wysokości, gęsto na początku, rzadziej potem
	var hits := 11 + seed_v * 2
	for k in hits:
		var t0 := pow(rng.randf(), 1.6) * 1.05 + 0.02
		var f := rng.randf_range(1350.0, 2400.0)
		var dec := rng.randf_range(16.0, 38.0)
		var amp := rng.randf_range(0.25, 0.6) * (1.0 - t0 * 0.5)
		var s0 := int(t0 * RATE)
		var ph1 := rng.randf() * TAU
		var slp := 0.0
		for i in range(s0, mini(n, s0 + int(RATE * 0.32))):
			var t := float(i - s0) / RATE
			var ring := sin(TAU * f * t + ph1) * 0.6 + sin(TAU * f * 2.76 * t) * 0.3 + sin(TAU * f * 4.07 * t) * 0.14
			var ww := rng.randf_range(-1.0, 1.0)
			slp += (ww - slp) * 0.7
			out[i] += (ring * exp(-t * dec) + slp * exp(-t * 220.0) * 0.5) * amp * minf(1.0, t / 0.0006)
	# krótkie echo pola
	var d := int(RATE * 0.09)
	for i in range(n - 1, d - 1, -1):
		out[i] += out[i - d] * 0.22
	for i in int(RATE * 0.1):
		out[n - 1 - i] *= float(i) / (RATE * 0.1)
	return _to_wav(out)


func ball_impact(pos: Vector2) -> void:
	## Kula uderza w ziemię: głuche tąpnięcie i rozrzucona ziemia - tylko z bliska.
	if _impact.is_empty():
		return
	var a := _audibility(pos)
	if a < 0.06:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_impact < 0.08:
		return
	_last_impact = now
	var p := _impact_pool[_ii]
	_ii = (_ii + 1) % _impact_pool.size()
	p.stream = _impact[randi() % _impact.size()]
	p.pitch_scale = randf_range(0.9, 1.08)
	p.volume_db = linear_to_db(a * maxf(GameSettings.sfx, 0.0001)) - 4.0
	p.play()


func ball_incoming(impact: Vector2, time_left: float) -> void:
	## Świst kuli zbliżającej się do miejsca upadku - słychać go tylko z bliska (kamera nad miejscem uderzenia).
	if _ball.is_empty():
		return
	var a := _audibility(impact)
	if a < 0.08:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_ball < 0.12:
		return
	_last_ball = now
	var p := _ball_pool[_bi]
	_bi = (_bi + 1) % _ball_pool.size()
	p.stream = _ball[randi() % _ball.size()]
	p.pitch_scale = 1.0   # bez zmiany wysokości - inaczej szczyt nie trafi w moment uderzenia
	p.volume_db = linear_to_db(a * maxf(GameSettings.sfx, 0.0001)) - 5.0
	p.play(maxf(0.0, BALL_PRE - time_left))


func _cannon_distant(world_pos: Vector2, near_a: float) -> void:
	## Daleki huk: słychać go przy oddalonej kamerze i z dział poza ekranem; przenika się z bliskim (1 - near_a).
	if _cannon_far.is_empty():
		return
	var cam := battle.cam
	var dw := world_pos.distance_to(cam.get_screen_center_position())
	var vol := clampf(1.15 - dw / FAR_RANGE, 0.0, 1.0) * (1.0 - near_a)
	if vol < 0.05:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_far < FAR_GAP:
		return
	_last_far = now
	var p := _far_pool[_fi]
	_fi = (_fi + 1) % _far_pool.size()
	p.stream = _cannon_far[randi() % _cannon_far.size()]
	p.pitch_scale = randf_range(0.92, 1.06)
	p.volume_db = linear_to_db(vol * maxf(GameSettings.sfx, 0.0001)) - 4.0
	p.play()


# ------------------------------------------------------------------ synteza

func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in samples:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / peak * 0.95, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _make_musket(seed_v: int) -> AudioStreamWAV:
	## Ostry trzask (szum z bardzo krótkim wybrzmieniem) + głuchy "puf" prochu + krótkie echo.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + seed_v
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var crack_decay := rng.randf_range(70.0, 95.0)
	var body_decay := rng.randf_range(11.0, 15.0)
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.35
		lp2 += (lp - lp2) * 0.12
		var attack := minf(1.0, t / 0.0015)
		var crack := white * exp(-t * crack_decay)
		var body := lp * exp(-t * body_decay) * 0.9
		var thump := sin(TAU * 95.0 * t) * exp(-t * 35.0) * 0.6
		var echo := 0.0
		if t > 0.11:
			echo = lp2 * exp(-(t - 0.11) * 9.0) * 0.5
		out[i] = (crack + body + thump + echo) * attack
	return _to_wav(out)


func _make_cannon(seed_v: int) -> AudioStreamWAV:
	## Niski grzmot: filtrowany szum + opadający ton + długie dudnienie.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + seed_v
	var n := int(RATE * 2.4)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var phase := 0.0
	var f0 := rng.randf_range(48.0, 62.0)
	for i in n:
		var t := float(i) / RATE
		var white := rng.randf_range(-1.0, 1.0)
		lp += (white - lp) * 0.08
		lp2 += (lp - lp2) * 0.05
		lp3 += (lp2 - lp3) * 0.03
		var attack := minf(1.0, t / 0.004)
		var crack := white * exp(-t * 40.0) * 0.5
		var blast := lp * exp(-t * 6.0) * 1.6
		var freq := f0 * (1.0 + 1.5 * exp(-t * 9.0))
		phase += TAU * freq / RATE
		var boom := sin(phase) * exp(-t * 3.2) * 0.9
		var rumble := lp3 * exp(-t * 1.4) * 9.0
		out[i] = (crack + blast + boom + rumble) * attack
	return _to_wav(out)
