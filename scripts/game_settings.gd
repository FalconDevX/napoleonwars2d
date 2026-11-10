class_name GameSettings
extends RefCounted
## Ustawienia gracza zapisywane w user://settings.cfg: głośności, dźwięki interfejsu, pełny ekran.

const PATH := "user://settings.cfg"

static var master := 0.9
static var sfx := 0.8
static var ui := 0.7
static var fullscreen := false
static var music := 0.6
static var vsync := true
static var hold_fire := true          # piechota gracza domyślnie strzela tylko na rozkaz
static var deselect_after := true     # po rozkazie pułki same się odznaczają
static var men_mult := 2.0            # wielkość pułków (1 / 1.5 / 2) - od następnej bitwy
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		master = float(cf.get_value("audio", "master", master))
		sfx = float(cf.get_value("audio", "sfx", sfx))
		ui = float(cf.get_value("audio", "ui", ui))
		fullscreen = bool(cf.get_value("video", "fullscreen", fullscreen))
		music = float(cf.get_value("audio", "music", music))
		vsync = bool(cf.get_value("video", "vsync", vsync))
		hold_fire = bool(cf.get_value("game", "hold_fire", hold_fire))
		deselect_after = bool(cf.get_value("game", "deselect_after", deselect_after))
		men_mult = float(cf.get_value("game", "men_mult", men_mult))
	apply()


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("audio", "master", master)
	cf.set_value("audio", "sfx", sfx)
	cf.set_value("audio", "ui", ui)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("audio", "music", music)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("game", "hold_fire", hold_fire)
	cf.set_value("game", "deselect_after", deselect_after)
	cf.set_value("game", "men_mult", men_mult)
	cf.save(PATH)


static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master, 0.0001)))
	AudioServer.set_bus_mute(0, master <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and not (not fullscreen and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(want)


static func get_value(key: String) -> float:
	match key:
		"master": return master
		"sfx": return sfx
		"ui": return ui
		"music": return music
	return 0.0


static func set_option(key: String, v: Variant) -> void:
	## Przełączniki z ustawień (pozostałe pola): zapis od razu.
	match key:
		"vsync": vsync = bool(v)
		"hold_fire": hold_fire = bool(v)
		"deselect_after": deselect_after = bool(v)
		"men_mult": men_mult = float(v)
	apply()
	save()


static func set_value(key: String, v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	match key:
		"master": master = v
		"sfx": sfx = v
		"ui": ui = v
		"music": music = v
	apply()
	save()
