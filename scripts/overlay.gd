class_name Overlay
extends Control
## Interfejs gracza (po angielsku): górny pasek, minimapa, karty oddziałów, panele jednostki/osady,
## menu (sterowanie + statystyki) oraz znaczniki na mapie. Rysowany "na bieżąco" (immediate mode):
## każdy przycisk rejestruje swój prostokąt w `_hits`, a kliknięcia obsługuje `hud_click`.

const STATE_NAMES := ["Ready", "Marching", "Charging!", "Melee", "Routing!"]

# --- paleta
const BG := Color(0.07, 0.075, 0.09, 0.94)
const BG2 := Color(0.12, 0.125, 0.145, 0.96)
const BG3 := Color(0.17, 0.175, 0.2, 0.96)
const GOLD := Color(0.84, 0.69, 0.38)
const GOLD_DIM := Color(0.55, 0.45, 0.25)
const CREAM := Color(0.95, 0.92, 0.82)
const DIM := Color(0.64, 0.62, 0.57)
const GOOD := Color(0.48, 0.85, 0.45)
const BAD := Color(0.95, 0.42, 0.36)
const MORALE := Color(1.0, 0.78, 0.28)

const TOP_H := 44.0
const MINI_W := 240.0
const MINI_H := 160.0
const SIDE_W := 330.0
const BANNER := Vector2(66, 160)   # większe sztandary w dolnym pasku (portrety lepiej widoczne)
const BANNER_GAP := 5.0
const ARMY_GAP := 14.0

const CONTROLS := [
	["Selection", [
		["Left click", "select a regiment, town or village"],
		["Shift + drag", "box-select regiments"],
		["Shift + click", "add / remove from selection"],
		["Ctrl + A", "select the whole army"],
		["Banners", "click: select, double-click: jump"],
		["G  /  U", "form army from selection / leave army"],
		["Ctrl + 1..9", "put selection into army 1..9"],
		["1..9", "select army (press twice: jump to it)"],
	]],
	["Orders", [
		["Left drag", "draw battle line: place, facing, width"],
		["Right click", "march to a point (keeps formation)"],
		["Right click enemy", "charge with bayonets / sabres"],
		["H", "halt"],
		["Q", "infantry square vs cavalry (toggle)"],
		["Hold Space", "show all regiments and their orders"],
	]],
	["Camera & game", [
		["Mouse wheel", "zoom in / out (far out = whole map)"],
		["WASD / middle drag", "move camera (or click the minimap)"],
		["F  /  C", "focus selection  /  jump to your capital"],
		["P  /  + -", "pause  /  game speed faster / slower"],
		["Esc / F1", "this menu       Ctrl + R: restart"],
	]],
	["Tips", [
		["Economy", "town +180, village +60 gold/min"],
		["Garrison", "3 regiments in a town, 1 in a village: no upkeep"],
		["Terrain", "swamp/ravine slow, mountains impassable"],
		["Rivers", "infantry and cavalry wade across slowly; guns need a bridge or ford"],
		["Fatigue", "running, charging and melee tire men; rest restores them"],
		["Army limit", "over your limit, upkeep and recruit costs climb steeply"],
		["Support", "regiments near friends hold morale; isolated ones waver"],
		["Artillery", "limbers up to march fast, unlimbers to fire"],
		["Flanking", "attacks from side x1.5, from rear x2.2"],
		["Encircled", "ringed on 5 of 8 sides: morale bleeds, broken units surrender"],
	]],
]

var battle: Battle
var font: Font          # treść: EB Garamond
var font_title: Font    # nagłówki i napisy wersalikami: Cinzel
const BODY_SCALE := 1.15   # Garamond ma niskie litery, więc nieco powiększamy
var menu_tab := 0
var recruit_tab := 0       # zakładka werbunku (Francja: Liniowe/Elita/Gwardia/Wsparcie/Sojusznicy)
var _portraits := {}
var draw_us := 0  # czas rysowania HUD (diagnostyka)
var _hits: Array = []       # [Rect2, akcja, dane]
var _blockers: Array = []   # prostokąty paneli (kliknięcie w nie nie trafia w mapę)
var _minimap: ImageTexture
var _mini_rect := Rect2()


var _ip_edit: LineEdit
var _chat_edit: LineEdit
var _chat_team := false      # Shift+Enter: wiadomość tylko do sojuszników
var _name_edit: LineEdit
var _ip_rect := Rect2()
var _name_rect := Rect2()
static var _last_ip := "127.0.0.1"
static var _last_name := ""


var title := false        # ekran tytułowy (menu główne) zamiast menu pauzy
var sub := ""             # podstrona menu głównego: "", "battle", "mp", "howto", "settings"
const MP_COMING_SOON := true   # gra sieciowa jeszcze niedostępna: pozycja w menu jest wyszarzona ("Coming soon")
var _vol_drag: Array = [] # przeciągany suwak głośności: [klucz, prostokąt]


func _click_sound(action: String) -> void:
	if action in ["card", "army", "minimap", "vol"]:
		return
	if action in ["restart", "quick", "net_start", "start_title"]:
		UiSound.play("start")
	elif action in ["back", "resume", "close", "net_stop"]:
		UiSound.play("back")
	else:
		UiSound.play("click")


func open_title(page := "") -> void:
	title = true
	sub = page
	menu_tab = 3 if page == "mp" else (2 if page == "battle" else 0)
	battle.menu_open = true


func title_back() -> bool:
	## Esc na ekranie tytułowym: z podstrony wraca do menu; z menu - do trwającej bitwy (jeśli jest).
	if sub != "":
		sub = ""
		menu_tab = 0
		UiSound.play("back")
		return true
	if _can_continue():
		title = false
		battle.menu_open = false
		UiSound.play("back")
		return true
	return true


func _can_continue() -> bool:
	return battle.sim_time > 0.5 and battle.result_text == ""


func _process(_d: float) -> void:
	if _ip_edit == null or battle == null:
		return
	if not _vol_drag.is_empty():
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var vr: Rect2 = _vol_drag[1]
			GameSettings.set_value(_vol_drag[0], (get_local_mouse_position().x - vr.position.x) / vr.size.x)
		else:
			if _vol_drag[0] == "ui":
				UiSound.play("click")   # próbka głośności dźwięków interfejsu
			_vol_drag = []
	var show := battle.menu_open and menu_tab == 3 and battle.result_text == "" and (Net.inst == null or Net.inst.role == Net.Role.NONE) \
		and (not title or sub == "mp")
	_ip_edit.visible = show
	_name_edit.visible = show
	if show:
		_ip_edit.position = _ip_rect.position
		_ip_edit.size = _ip_rect.size
		_name_edit.position = _name_rect.position
		_name_edit.size = _name_rect.size
	_last_ip = _ip_edit.text
	_last_name = _name_edit.text


func _make_edit(txt: String, hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = txt
	e.placeholder_text = hint
	e.visible = false
	e.add_theme_font_override("font", _load_font("EBGaramond.ttf", 520))
	e.add_theme_font_size_override("font_size", 17)
	add_child(e)
	return e


func _ready() -> void:
	# portrety (600x800) rysowane w małych kartach: mipmapy dają gładki obraz zamiast poszarpanego
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_ip_edit = _make_edit(_last_ip, "host IP, e.g. 192.168.1.10")
	if _last_name == "":
		_last_name = OS.get_environment("USERNAME") if OS.get_environment("USERNAME") != "" else "Player"
	_name_edit = _make_edit(_last_name, "your name")
	_name_edit.max_length = 20
	_chat_edit = _make_edit("", "")
	_chat_edit.max_length = 160
	_chat_edit.text_submitted.connect(_on_chat_submit)
	_chat_edit.gui_input.connect(_on_chat_key)
	font = _load_font("EBGaramond.ttf", 520)
	font_title = _load_font("Cinzel.ttf", 700)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_minimap()
	if UiSound.inst == null:
		# pod korzeniem drzewa: przeżywa przeładowanie sceny, więc werbel startu nie urywa się
		var us := UiSound.new()
		us.name = "UiSound"
		get_tree().root.add_child.call_deferred(us)


# ================================================================== rysowanie: główne

func _draw() -> void:
	var _pt := Time.get_ticks_usec() if Battle.PROF else 0
	_draw_impl()
	if Battle.PROF:
		Battle.pf("d_overlay", _pt)


func _draw_impl() -> void:
	if battle == null:
		return
	var _t0 := Time.get_ticks_usec()
	_hits.clear()
	_blockers.clear()
	var t := Time.get_ticks_msec() / 1000.0
	_dt = clampf(t - _last_draw_t, 0.0, 0.1)
	_last_draw_t = t
	_hover_key = ""
	if battle.menu_open and title and battle.result_text == "":
		_draw_title()
		_after_draw()
		return
	var xf := battle.get_viewport().get_canvas_transform()
	for s in battle.settlements:
		_draw_settlement(s, xf)
	for r in battle.regiments:
		if r.team == 0:
			_draw_orders(r, xf)
	for r in battle.regiments:
		_draw_icon(r, xf, t)   # portrety zawsze - z bliska wiszą nad pułkiem
	if battle.soldier_alpha > 0.3 and battle.icon_alpha < 0.25:
		for r in battle.regiments:
			_draw_label(r, xf)
	_draw_drag_preview(xf)
	if battle.box_active:
		var rect := Rect2(battle.box_start, get_local_mouse_position() - battle.box_start).abs()
		draw_rect(rect, Color(1, 1, 1, 0.08))
		draw_rect(rect, Color(GOLD, 0.8), false, 1.0)

	_draw_top_bar()
	_draw_messages()
	_draw_chat()
	_draw_minimap(xf)
	_draw_cards()
	_draw_tutorial()
	if battle.selected_settlement != null:
		_draw_settlement_panel()
	elif not battle.selected.is_empty():
		_draw_unit_panel()
	if battle.result_text != "":
		_draw_result()
	elif battle.menu_open:
		_draw_menu()
	_after_draw()
	draw_us = Time.get_ticks_usec() - _t0


func _after_draw() -> void:
	## Dźwięk przy wjechaniu kursorem na nowy przycisk; przyciski, których już nie ma, tracą podświetlenie.
	for k in _anim.keys():
		if not _anim_seen.has(k):
			_anim.erase(k)
	_anim_seen.clear()
	if _hover_key != _hover_prev:
		if _hover_key != "":
			UiSound.play("hover")
		_hover_prev = _hover_key


# ================================================================== pomocnicze

func _load_font(file: String, weight: int) -> Font:
	## Czcionki z assets/fonts (wczytywane bezpośrednio z pliku .ttf, bez importu edytora).
	var ff := FontFile.new()
	if not FileAccess.file_exists("res://assets/fonts/" + file) and ResourceLoader.exists("res://assets/fonts/" + file):
		# wersja wyeksportowana (np. przeglądarkowa): w paczce jest tylko czcionka zaimportowana przez edytor
		ff = (load("res://assets/fonts/" + file) as FontFile).duplicate()
	elif ff.load_dynamic_font("res://assets/fonts/" + file) != OK:
		return ThemeDB.fallback_font
	ff.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	ff.hinting = TextServer.HINTING_LIGHT
	ff.oversampling = 1.0
	var fv := FontVariation.new()
	fv.base_font = ff
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


static var _caps_cache := {}


func _font_for(s: String, size: int) -> Array:
	## [czcionka, rozmiar]: duże napisy i WERSALIKI -> Cinzel, reszta -> Garamond (powiększony).
	var caps: Variant = _caps_cache.get(s)
	if caps == null:
		caps = s.to_upper() == s and s.to_lower() != s
		if _caps_cache.size() > 4000:
			_caps_cache.clear()
		_caps_cache[s] = caps
	if size >= 18 or caps:
		return [font_title, size]
	return [font, int(round(size * BODY_SCALE))]


func _text(s: String, pos: Vector2, size: int, col: Color, align := 0, outline := true) -> void:
	## align: 0 = lewo, 1 = środek, 2 = prawo
	var p := pos
	var w := _tw(s, size)
	if align == 1:
		p.x -= w * 0.5
	elif align == 2:
		p.x -= w
	var fs := _font_for(s, size)
	var f: Font = fs[0]
	var sz: int = fs[1]
	if outline:
		draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.7))
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_wrap(s: String, box: Rect2, size: int, col: Color) -> void:
	## Tekst łamany po słowach w prostokącie (opisy cech jednostek).
	var line := ""
	var y := box.position.y + size + 2
	for word in s.split(" "):
		var cand := word if line == "" else line + " " + word
		if _tw(cand, size) > box.size.x and line != "":
			_text(line, Vector2(box.position.x, y), size, col, 0, false)
			y += size + 4
			line = word
			if y > box.end.y:
				return
		else:
			line = cand
	if line != "":
		_text(line, Vector2(box.position.x, y), size, col, 0, false)


func _tw(s: String, size: int) -> float:
	var key := "%s|%d" % [s, size]
	var w: Variant = _tw_cache.get(key)
	if w == null:
		if _tw_cache.size() > 6000:
			_tw_cache.clear()
		var fs := _font_for(s, size)
		w = (fs[0] as Font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs[1]).x
		_tw_cache[key] = w
	return w


var _fit_cache := {}
var _tw_cache := {}


func _fit(s: String, size: int, width: float) -> String:
	## Przycina napis do szerokości (wynik zapamiętany - liczenie szerokości tekstu jest drogie).
	var key := "%s|%d|%d" % [s, size, int(width)]
	if _fit_cache.has(key):
		return _fit_cache[key]
	if _fit_cache.size() > 4000:
		_fit_cache.clear()
	var out := s
	while out.length() > 3 and _tw(out, size) > width:
		out = out.left(out.length() - 1)
	out = out if out == s else out.strip_edges() + "."
	_fit_cache[key] = out
	return out


func _panel(r: Rect2, title := "", block := true) -> void:
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.35))
	draw_rect(r, BG)
	draw_rect(r.grow(-3), Color(1, 1, 1, 0.02), false, 1.0)
	draw_rect(r, GOLD_DIM, false, 1.5)
	if title != "":
		var band := Rect2(r.position, Vector2(r.size.x, 26))
		draw_rect(band, BG3)
		draw_line(band.position + Vector2(0, band.size.y), band.end, GOLD_DIM, 1.0)
		_text(title, band.position + Vector2(10, 18), 13, GOLD, 0, false)
	if block:
		_blockers.append(r)


# --- animacja przycisków: płynne podświetlenie, dźwięk przy najechaniu
var _anim := {}            # klucz przycisku -> 0..1 (stopień podświetlenia)
var _hover_key := ""       # przycisk pod kursorem w tej klatce
var _hover_prev := ""
var _last_draw_t := 0.0
var _dt := 0.016


var test_mouse := Vector2.INF   # test: wymuszona pozycja kursora (okno bez fokusu)


func _mouse() -> Vector2:
	return test_mouse if test_mouse != Vector2.INF else get_local_mouse_position()


var _anim_seen := {}       # przyciski narysowane w tej klatce (reszta traci podświetlenie)


func _hover_amount(key: String, hover: bool) -> float:
	_anim_seen[key] = true
	var a: float = _anim.get(key, 0.0)
	a = move_toward(a, 1.0 if hover else 0.0, _dt * (9.0 if hover else 5.0))
	if a > 0.0:
		_anim[key] = a
	else:
		_anim.erase(key)
	if hover:
		_hover_key = key
	return a


func _grad_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _grad_rect_h(r: Rect2, left: Color, right: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([left, right, right, left]))


func _diamond(c: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)


func _button(r: Rect2, label: String, action: String, data: Variant = null, active := false, enabled := true, size := 13) -> void:
	## Przycisk: płaski ciemny panel ze ściętymi rogami i cienką złotą ramką (bez gradientów i połysku),
	## napis wersalikami w Cinzel. Najechanie rozjaśnia ramkę i tło, wybrana opcja ma pełne złote tło.
	var key := "%s|%s|%d|%d" % [action, str(data), int(r.position.x), int(r.position.y)]
	var hover := r.has_point(_mouse()) and enabled
	var a := _hover_amount(key, hover)
	var pressed := hover and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rr := Rect2(r.position + Vector2(0, 1.0 if pressed else 0.0), r.size)
	var fill: Color
	var border: Color
	var col: Color
	if not enabled:
		fill = Color(0.08, 0.08, 0.08, 0.9)
		border = Color(0.28, 0.27, 0.25)
		col = Color(0.42, 0.41, 0.39)
	elif active:
		fill = Color(0.55, 0.41, 0.17).lerp(Color(0.64, 0.49, 0.21), a)
		border = Color(0.95, 0.82, 0.48)
		col = Color(0.10, 0.07, 0.04)
	else:
		fill = Color(0.075, 0.07, 0.065, 0.94).lerp(Color(0.15, 0.12, 0.08, 0.96), a)
		border = GOLD_DIM.lerp(GOLD, a)
		col = CREAM.lerp(Color(1.0, 0.92, 0.70), a)
	var c := 4.0 if rr.size.y >= 22.0 else 2.0   # ścięcie rogów
	var oct := PackedVector2Array([rr.position + Vector2(c, 0), Vector2(rr.end.x - c, rr.position.y), Vector2(rr.end.x, rr.position.y + c),
		Vector2(rr.end.x, rr.end.y - c), Vector2(rr.end.x - c, rr.end.y), Vector2(rr.position.x + c, rr.end.y),
		Vector2(rr.position.x, rr.end.y - c), rr.position + Vector2(0, c)])
	var shadow := PackedVector2Array()
	for v in oct:
		shadow.append(v + Vector2(0, 2))
	if not pressed:
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
	draw_colored_polygon(oct, fill)
	var ring := oct.duplicate()
	ring.append(oct[0])
	draw_polyline(ring, border, 1.0)
	if a > 0.01 and not active:
		draw_line(Vector2(rr.position.x + c + 2, rr.end.y - 3), Vector2(rr.end.x - c - 2, rr.end.y - 3), Color(GOLD.r, GOLD.g, GOLD.b, 0.55 * a), 1.0)
	var txt := label.to_upper()
	var ts := maxi(10, size - 2)
	_text(txt, Vector2(rr.get_center().x, rr.get_center().y + ts * 0.38), ts, col, 1, false)
	if enabled:
		_hits.append([r, action, data])


func _menu_button(r: Rect2, label: String, sub: String, action: String, data: Variant = null, enabled := true) -> void:
	## Duża pozycja menu głównego: złota belka z lewej rośnie przy najechaniu, napis odsuwa się w prawo.
	var key := "M|%s|%s|%d" % [action, str(data), int(r.position.y)]
	var hover := r.has_point(_mouse()) and enabled
	var a := _hover_amount(key, hover)
	var pressed := hover and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var ez := a * a * (3.0 - 2.0 * a)
	_grad_rect_h(r, Color(0.45, 0.33, 0.14, 0.55 * ez), Color(0.45, 0.33, 0.14, 0.0))
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + r.size.x * (0.35 + 0.65 * ez), r.end.y), Color(GOLD.r, GOLD.g, GOLD.b, 0.25 + 0.55 * ez), 1.0)
	draw_rect(Rect2(r.position, Vector2(3.0 + 3.0 * ez, r.size.y)), GOLD if enabled else Color(0.35, 0.35, 0.35))
	var x := r.position.x + 22.0 + 12.0 * ez + (2.0 if pressed else 0.0)
	if ez > 0.02:
		_diamond(Vector2(x - 11.0, r.position.y + 21.0), 4.0 * ez, GOLD)
	var col := CREAM.lerp(Color(1.0, 0.86, 0.52), ez) if enabled else Color(0.42, 0.42, 0.42)
	_text(label.to_upper(), Vector2(x, r.position.y + 29.0), 22, col, 0, true)
	if sub != "":
		_text(sub, Vector2(x + 2.0, r.position.y + 48.0), 12, Color(DIM.r, DIM.g, DIM.b, 0.65 + 0.35 * ez), 0, false)
	if enabled:
		_hits.append([r, action, data])


func _bar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(1, 1, 1, 0.08), false, 1.0)


func _coin(c: Vector2, rad: float) -> void:
	draw_circle(c, rad, Color(0.55, 0.42, 0.12))
	draw_circle(c, rad * 0.8, Color(0.95, 0.78, 0.3))
	draw_circle(c + Vector2(-rad * 0.25, -rad * 0.25), rad * 0.25, Color(1, 0.95, 0.7, 0.8))


func _man_icon(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(0, -5), 3.0, col)
	draw_rect(Rect2(c + Vector2(-3.5, -1.5), Vector2(7, 8)), col)


func _house_icon(c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -1), c + Vector2(0, -8), c + Vector2(7, -1)]), col)
	draw_rect(Rect2(c + Vector2(-5, -1), Vector2(10, 7)), col)


func _unit_symbol(rect: Rect2, kind: String, key: String, col: Color) -> void:
	## Symbol jak na mapie sztabowej: X piechota, / kawaleria, ● artyleria.
	match kind:
		"cav":
			draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), col, 1.5)
			key = Battle.base_of(key)
			if key == "lancers":
				draw_line(rect.position + Vector2(rect.size.x * 0.5, 0), Vector2(rect.position.x + rect.size.x * 0.5, rect.end.y), col, 1.0)
			elif key == "dragoons":
				draw_line(rect.position + Vector2(0, rect.size.y * 0.5), rect.end - Vector2(0, rect.size.y * 0.5), col, 1.0)
			elif key == "cuirassiers":
				draw_line(Vector2(rect.position.x, rect.end.y - 3), Vector2(rect.end.x - 3, rect.position.y), col, 1.5)
		"art":
			key = Battle.base_of(key)
			draw_circle(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.25, col)
			if key == "horse_art":
				draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), col, 1.0)
		_:
			key = Battle.base_of(key)
			draw_line(rect.position, rect.end, col, 1.5)
			draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), col, 1.5)
			if key == "light" or key == "rifles":
				draw_line(rect.position + Vector2(0, rect.size.y * 0.5), rect.end - Vector2(0, rect.size.y * 0.5), col, 1.5)
			if key == "rifles":
				draw_circle(rect.get_center(), 2.5, col)
			elif key == "militia":
				draw_rect(rect.grow(-2), col, false, 1.0)
	if key == "grenadier" or key == "guard":
		draw_circle(Vector2(rect.get_center().x, rect.position.y - 3), 2.5, Color(1, 0.85, 0.3, col.a))


func _arrow(from: Vector2, to: Vector2, col: Color, width: float, outline := true) -> void:
	## Strzałka w kolorze oddziału, z ciemnym obrysem, żeby była widoczna na każdym terenie.
	var d := to - from
	if d.length() < 4.0:
		return
	var dir := d.normalized()
	var head := 8.0 + width * 2.0
	var tri := PackedVector2Array([
		to, to - dir * head + dir.orthogonal() * head * 0.5, to - dir * head - dir.orthogonal() * head * 0.5,
	])
	var end := to - dir * head * 0.7
	if outline:
		var oc := Color(0.04, 0.03, 0.02, minf(1.0, col.a * 0.95))
		draw_line(from, end, oc, width + 3.2, true)
		var big := PackedVector2Array()
		var c := (tri[0] + tri[1] + tri[2]) / 3.0
		for q in tri:
			big.append(c + (q - c) * 1.45)
		draw_colored_polygon(big, oc)
	draw_line(from, end, col, width, true)
	draw_colored_polygon(tri, col)


func _line_out(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, Color(0.04, 0.03, 0.02, minf(1.0, col.a * 0.95)), width + 3.2, true)
	draw_line(a, b, col, width, true)


# ================================================================== kliknięcia w interfejs

func over_hud(pos: Vector2) -> bool:
	if battle.menu_open or battle.result_text != "":
		return true
	for r in _blockers:
		if (r as Rect2).has_point(pos):
			return true
	return false


func hud_click(pos: Vector2, button: int, shift: bool, dbl: bool) -> bool:
	## Zwraca true, gdy kliknięcie zostało obsłużone przez interfejs.
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if (h[0] as Rect2).has_point(pos):
			if button == MOUSE_BUTTON_LEFT or h[1] == "minimap":
				_click_sound(h[1])
				_do(h[1], h[2], button, shift, dbl, pos)
			return true
	return over_hud(pos)


func _do(action: String, data: Variant, button: int, shift: bool, dbl: bool, pos: Vector2) -> void:
	match action:
		"speed":
			if not Net.active():
				battle.time_scale = data
				battle.paused = false
		"pause":
			if not Net.active():
				battle.paused = not battle.paused
		"menu":
			battle.menu_open = true
		"menu_tab":
			menu_tab = data
		"resume":
			battle.menu_open = false
			title = false
			sub = ""
		"restart":
			title = false
			battle.restart_game()
		"quick":
			# Szybka bitwa: mapa za menu jest już wygenerowana z tymi ustawieniami - wystarczy zamknąć menu.
			title = false
			sub = ""
			if battle.can_start_in_place():
				battle.menu_open = false
			else:
				battle.restart_game()
		"sub":
			sub = data
			menu_tab = 3 if data == "mp" else (2 if data == "battle" else 0)
		"tutorial":
			title = false
			sub = ""
			Battle.begin_tutorial(get_tree())
		"tut_next":
			if battle.tutorial != null:
				battle.tutorial.next()
		"tut_quit":
			if battle.tutorial != null:
				Battle.end_tutorial(get_tree())
		"back":
			title_back()
		"main_menu":
			open_title()
		"result_continue":
			# zwycięstwo potwierdzone: zamykamy okno wyniku i gramy dalej na tym samym polu
			battle.victory_ack = true
			battle.result_text = ""
			battle.menu_open = false
		"result_menu":
			# po bitwie: nowa mapa w tle i ekran tytułowy
			Battle.show_title_next = true
			battle.restart_game()
		"vol":
			_vol_drag = [data[0], data[1]]
			GameSettings.set_value(data[0], (pos.x - (data[1] as Rect2).position.x) / (data[1] as Rect2).size.x)
		"fullscreen":
			GameSettings.fullscreen = data
			GameSettings.apply()
			GameSettings.save()
		"opt":
			if data[0] == "fullscreen":
				GameSettings.fullscreen = data[1]
				GameSettings.apply()
				GameSettings.save()
			else:
				GameSettings.set_option(data[0], data[1])
		"map_size":
			Battle.chosen_size = data
			_lobby_sync()
		"map_type":
			Battle.chosen_map = data
			_lobby_sync()
		"theme":
			Battle.chosen_theme = data
			_lobby_sync()
		"net_host":
			Net.inst.my_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Host"
			Net.inst.host_game()
		"net_join":
			Net.inst.my_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Player"
			Net.inst.join_game(_ip_edit.text)
		"net_stop":
			var was_match := Net.active()
			Net.inst.stop()
			Net.inst.status = "Disconnected"
			if was_match:
				get_tree().reload_current_scene()
		"net_side":
			Net.inst.choose_side(data)
		"net_ready":
			Net.inst.set_ready(data)
		"net_start":
			Net.inst.start_match()
		"cycle":
			_cycle_setting(str(data[0]), int(data[1]))
		"scenario":
			Battle.chosen_scenario = data
			_lobby_sync()
		"side":
			var row: int = data[0]
			var nat: int = data[1]
			if int(Battle.side_nation[1 - row]) == nat:
				Battle.side_nation[1 - row] = Battle.side_nation[row]   # zamiana stron
			Battle.side_nation[row] = nat
			_lobby_sync()
		"quit":
			get_tree().quit()
		"card":
			var r: Regiment = data
			var sel: Array[Regiment] = []
			if shift:
				sel.assign(battle.selected)
				if sel.has(r):
					sel.erase(r)
				else:
					sel.append(r)
			else:
				sel.append(r)
			battle._set_selection(sel)
			if dbl:
				battle._focus_selected()
		"army":
			var sel: Array[Regiment] = []
			if shift:
				sel.assign(battle.selected)
			for r in battle.regiments:
				if r.team == 0 and r.army_id == data and not sel.has(r):
					sel.append(r)
			battle._set_selection(sel)
			if dbl:
				battle._focus_selected()
		"square":
			battle.toggle_square()
		"wedge":
			battle.toggle_wedge()
		"ammo":
			battle.cycle_ammo()
		"fire_will":
			battle.toggle_fire_at_will()
		"form_army":
			battle.form_army()
		"leave_army":
			battle.leave_army()
		"recruit":
			if not battle.recruit(battle.selected_settlement, data):
				if Battle.UNIT_TYPES[data].has("unique") and battle.unique_count(0, data) >= int(Battle.UNIT_TYPES[data]["unique"]):
					battle.message("%s: unit limit reached." % Battle.UNIT_TYPES[data]["name"])
				else:
					battle.message("Not enough gold or the queue is full.")
		"recruit_tab":
			recruit_tab = int(data)
		"close":
			battle.selected_settlement = null
			var none: Array[Regiment] = []
			battle._set_selection(none)
		"halt":
			for r in battle.selected:
				r.order_halt()
		"minimap":
			var wp := (pos - _mini_rect.position) / _mini_rect.size * battle.map_size
			if button == MOUSE_BUTTON_RIGHT and not battle.selected.is_empty():
				for plan in battle.plan_move(wp, wp, false):
					(plan[0] as Regiment).order_move(plan[1], plan[2], -1, plan[4])
			else:
				battle.cam.position = wp


# ================================================================== górny pasek

func _draw_top_bar() -> void:
	var vs := size
	var bar := Rect2(0, 0, vs.x, TOP_H)
	draw_rect(bar, BG)
	draw_line(Vector2(0, TOP_H), Vector2(vs.x, TOP_H), GOLD_DIM, 1.5)
	_blockers.append(bar)

	var x := 8.0
	_button(Rect2(x, 8, 70, 28), "MENU", "menu")
	x += 80.0
	# czas i prędkość
	var secs := int(battle.sim_time)
	_text("%02d:%02d" % [secs / 60, secs % 60], Vector2(x, 28), 16, CREAM, 0, false)
	x += 58.0
	if Net.active():
		# gra sieciowa: bez pauzy i przyspieszania - tylko znacznik
		var tag := Rect2(x, 8, 34 + 37 * 4 - 3, 28)
		draw_rect(tag, Color(0.2, 0.32, 0.2, 0.9))
		draw_rect(tag, GOLD_DIM, false, 1.0)
		_text("ONLINE  -  %s" % ("HOST" if Net.is_host() else "GUEST"), Vector2(tag.get_center().x, tag.get_center().y + 4.5), 12, CREAM, 1, false)
		x += tag.size.x + 3.0
	else:
		_button(Rect2(x, 8, 30, 28), "II", "pause", null, battle.paused)
		x += 34.0
		for sp in [1.0, 2.0, 4.0, 8.0]:
			_button(Rect2(x, 8, 34, 28), "x%d" % int(sp), "speed", sp, not battle.paused and battle.time_scale == sp, true, 12)
			x += 37.0
	x += 14.0
	draw_line(Vector2(x, 8), Vector2(x, TOP_H - 8), GOLD_DIM, 1.0)
	x += 16.0

	# skarbiec (bitwa w polu: bez złota i osad)
	var field := Battle.is_field()
	if field:
		pass
	else:
		_draw_treasury(x)
		x += 24.0 + maxf(_tw("%d" % int(battle.gold[0]), 17), 64.0) + 14.0 + 92.0 + 16.0
	_draw_army_bar(x, field)
	_draw_balance(vs)


func _draw_treasury(x: float) -> void:
	_coin(Vector2(x + 9, 22), 9.0)
	x += 24.0
	_text("%d" % int(battle.gold[0]), Vector2(x, 21), 17, GOLD, 0, false)
	var net: float = (battle.income[0] - battle.upkeep[0]) * 60.0
	_text("%s%d / min" % ["+" if net >= 0.0 else "", int(net)], Vector2(x, 37), 11, GOOD if net >= 0.0 else BAD, 0, false)
	x += maxf(_tw("%d" % int(battle.gold[0]), 17), 64.0) + 14.0
	_text("Income  +%d" % int(battle.income[0] * 60.0), Vector2(x, 20), 11, DIM, 0, false)
	_text("Upkeep  -%d" % int(battle.upkeep[0] * 60.0), Vector2(x, 35), 11, DIM, 0, false)
	x += 92.0
	draw_line(Vector2(x, 8), Vector2(x, TOP_H - 8), GOLD_DIM, 1.0)


func _army_counts() -> Array:
	var men := [0, 0]
	var regs := [0, 0]
	for r in battle.regiments:
		men[r.team] += r.alive_count()
		regs[r.team] += 1
	return [men, regs]


func _draw_army_bar(x: float, field: bool) -> void:
	# armia
	var men := [0, 0]
	var regs := [0, 0]
	for r in battle.regiments:
		men[r.team] += r.alive_count()
		regs[r.team] += 1
	_man_icon(Vector2(x + 6, 24), CREAM)
	x += 20.0
	_text("%d men" % men[0], Vector2(x, 21), 15, CREAM, 0, false)
	if field:
		_text("%d regiments - no reinforcements" % regs[0], Vector2(x, 37), 11, DIM, 0, false)
		return
	var lim := battle.command_limit(0)
	_text("%d / %d regiments" % [regs[0], lim], Vector2(x, 37), 11, BAD if regs[0] > lim else DIM, 0, false)
	x += 112.0
	# osady
	var towns := 0
	var villages := 0
	for s in battle.settlements:
		if s.faction == 0:
			if s.is_city:
				towns += 1
			else:
				villages += 1
	_house_icon(Vector2(x + 8, 24), CREAM)
	x += 22.0
	_text("%d towns" % towns, Vector2(x, 21), 15, CREAM, 0, false)
	_text("%d villages" % villages, Vector2(x, 37), 11, DIM, 0, false)


func _draw_balance(vs: Vector2) -> void:
	# równowaga sił (prawa strona)
	var ac := _army_counts()
	var men: Array = ac[0]
	var regs: Array = ac[1]
	var bw := 260.0
	var bx := vs.x - bw - 52.0
	var em0 := _emblem(0)
	var em1 := _emblem(1)
	if em0 != null:
		_draw_fit(em0, Rect2(bx - 36, 6, 32, 34))
	if em1 != null:
		_draw_fit(em1, Rect2(bx + bw + 4, 6, 32, 34))
	var total := maxf(1.0, float(men[0] + men[1]))
	var split: float = men[0] / total
	_text("BALANCE OF POWER", Vector2(bx + bw * 0.5, 16), 10, DIM, 1, false)
	var br := Rect2(bx, 21, bw, 12)
	draw_rect(br, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(br.position, Vector2(bw * split, 12)), Battle.owner_color(0))
	draw_rect(Rect2(br.position + Vector2(bw * split, 0), Vector2(bw * (1.0 - split), 12)), Battle.owner_color(1))
	draw_line(Vector2(bx + bw * 0.5, 19), Vector2(bx + bw * 0.5, 35), Color(1, 1, 1, 0.6), 1.0)
	draw_rect(br, GOLD_DIM, false, 1.0)
	_text("%d" % men[0], Vector2(bx + 4, 42), 11, CREAM, 0, false)
	_text("%d enemy (%d regts)" % [men[1], regs[1]], Vector2(bx + bw - 4, 42), 11, CREAM, 2, false)


# ------------------------------------------------------------------ czat graczy (Enter)

func chat_available() -> bool:
	return Net.inst != null and Net.inst.role != Net.Role.NONE


func open_chat(team_only: bool) -> void:
	## Enter: pole wiadomości (Shift+Enter - tylko do sojuszników). Enter wysyła, Esc anuluje.
	if not chat_available() or _chat_edit == null:
		return
	_chat_team = team_only
	_chat_edit.text = ""
	_chat_edit.placeholder_text = "to allies..." if team_only else "to all players..."
	_chat_edit.visible = true
	_chat_edit.grab_focus()


func chat_open() -> bool:
	return _chat_edit != null and _chat_edit.visible


func _close_chat() -> void:
	_chat_edit.release_focus()
	_chat_edit.visible = false


func _on_chat_submit(text: String) -> void:
	if text.strip_edges() != "":
		Net.inst.send_chat(text, _chat_team)
	_close_chat()


func _on_chat_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_close_chat()
		get_viewport().set_input_as_handled()


func _draw_chat() -> void:
	## Ostatnie wiadomości nad minimapą: znikają po ~12 s, podczas pisania widać całą historię.
	if not chat_available():
		if chat_open():
			_close_chat()
		return
	var log: Array = Net.inst.chat_log
	var typing := chat_open()
	var x := 16.0
	var y := size.y - 232.0
	if typing:
		var r := Rect2(x, y - 4, 420, 30)
		draw_rect(r.grow(2), Color(0, 0, 0, 0.75))
		draw_rect(r.grow(2), GOLD_DIM, false, 1.0)
		var tag := "[ALLIES]" if _chat_team else "[ALL]"
		_text(tag, Vector2(x + 6, y + 16), 12, GOLD if not _chat_team else Color(0.6, 0.9, 0.6), 0, false)
		_chat_edit.position = Vector2(x + 72, y - 4)
		_chat_edit.size = Vector2(346, 30)
		y -= 10.0
	var now := Time.get_ticks_msec()
	var shown := 0
	for k in range(log.size() - 1, -1, -1):
		if shown >= (12 if typing else 6):
			break
		var m: Array = log[k]
		var age := (now - int(m[0])) / 1000.0
		var a := 1.0 if typing else clampf((14.0 - age) / 2.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var team: int = m[3]
		var nc: Color = Battle.TEAM_COLORS[Battle.nation(team)].lightened(0.35)
		var head := ("(allies) " if m[4] else "") + str(m[1]) + ":"
		var line := Rect2(x - 4, y - 20, 430, 22)
		draw_rect(line, Color(0, 0, 0, 0.5 * a))
		_text(head, Vector2(x, y - 4), 13, Color(nc, a), 0, false)
		_text(str(m[2]), Vector2(x + _tw(head, 13) + 6.0, y - 4), 13, Color(CREAM, a), 0, false)
		y -= 24.0
		shown += 1


func _draw_messages() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var y := TOP_H + 12.0
	for m in battle.messages:
		var age: float = now - float(m[1])
		if age > 7.0:
			continue
		var a := clampf(7.0 - age, 0.0, 1.0)
		var w := _tw(m[0], 14) + 30.0
		var r := Rect2(size.x * 0.5 - w * 0.5, y, w, 26)
		draw_rect(r, Color(BG, 0.85 * a))
		draw_rect(r, Color(GOLD_DIM, a), false, 1.0)
		_text(m[0], Vector2(size.x * 0.5, y + 18), 14, Color(CREAM, a), 1, false)
		y += 30.0


# ================================================================== minimapa

const MINI_SS := 2   # minimapa liczona w 2x większej rozdzielczości: widać pola, drogi, korony drzew, zabudowę


func _build_minimap() -> void:
	var t := battle.terrain
	var w := int(MINI_W) * MINI_SS
	var h := int(MINI_H) * MINI_SS
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	# kolory wg teatru wojny (śnieg, piasek, zieleń...): trawa, las, woda, droga, góry, wąwóz, bagno, bród
	var tc := Terrain.theme_minimap_colors()
	var cols := [tc["grass"], tc["forest"], tc["water"], tc["road"], tc["mountain"],
		(tc["mountain"] as Color).darkened(0.35), tc["swamp"], (tc["water"] as Color).lightened(0.3)]
	var field: Color = tc.get("field", tc["grass"])
	var cells := PackedByteArray()
	cells.resize(w * h)
	var cw := battle.map_size.x / w
	var ch := battle.map_size.y / h
	for y in h:
		for x in w:
			cells[y * w + x] = t.cell_at(Vector2((x + 0.5) * cw, (y + 0.5) * ch))
	for y in h:
		for x in w:
			var p := Vector2((x + 0.5) * cw, (y + 0.5) * ch)
			var c: int = cells[y * w + x]
			var col: Color = cols[c]
			var hv := float(((x * 73856093) ^ (y * 19349663)) & 1023) / 1023.0   # stałe ziarno - tekstura terenu
			if c == Terrain.GRASS:
				# uprawy: delikatny odcień pól w paski (nie pełne plamy - to tylko podpowiedź, gdzie są pola)
				var fa := smoothstep(0.3, 0.8, t.farm_at(p))
				var stripe := 0.5 + 0.5 * sin((p.x * 0.7 + p.y * 0.4) / 90.0)
				col = col.lerp(field, fa * (0.18 + 0.22 * stripe))
				col = col.darkened((hv - 0.5) * 0.06)
			elif c == Terrain.FOREST:
				# korony drzew: jaśniejsze plamki na ciemnym tle, ciemniejszy skraj lasu
				var edge := false
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + o
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and cells[q.y * w + q.x] != Terrain.FOREST:
						edge = true
				col = col.lightened(0.14) if hv > 0.62 else col.darkened(0.12 if hv < 0.25 else 0.0)
				if edge:
					col = col.darkened(0.3)
			elif c == Terrain.MOUNTAIN:
				# cieniowanie zboczy: światło z lewej-góry
				var d := t.mount_strength(p - Vector2(cw, ch)) - t.mount_strength(p + Vector2(cw, ch))
				col = col.lightened(clampf(d * 3.0, 0.0, 0.35)) if d > 0.0 else col.darkened(clampf(-d * 3.0, 0.0, 0.35))
			elif c == Terrain.WATER:
				col = col.darkened(0.12) if t.is_deep_fast(p) else col
			img.set_pixel(x, y, col)
	# zabudowa: dachy domów w osadach
	for s in battle.settlements:
		for hs in s.houses:
			var hp: Vector2 = (s.position + hs[0]) / Vector2(cw, ch)
			var hsz: Vector2 = hs[1]
			var r := maxi(1, int(maxf(hsz.x, hsz.y) / cw * 0.5))
			for yy in range(int(hp.y) - r, int(hp.y) + r + 1):
				for xx in range(int(hp.x) - r, int(hp.x) + r + 1):
					if xx >= 0 and yy >= 0 and xx < w and yy < h:
						img.set_pixel(xx, yy, Color(0.55, 0.3, 0.22) if (xx + yy) % 3 != 0 else Color(0.38, 0.22, 0.16))
	_minimap = ImageTexture.create_from_image(img)


func _draw_minimap(xf: Transform2D) -> void:
	var vs := size
	var outer := Rect2(10, vs.y - MINI_H - 40, MINI_W + 12, MINI_H + 32)
	_panel(outer, "MAP")
	_mini_rect = Rect2(outer.position + Vector2(6, 28), Vector2(MINI_W, MINI_H))
	draw_texture_rect(_minimap, _mini_rect, false)
	var sc := _mini_rect.size / battle.map_size
	for s in battle.settlements:
		var p := _mini_rect.position + s.position * sc
		var c := Battle.owner_color(s.faction)
		if s.is_city:
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color(0, 0, 0))
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), c)
		else:
			draw_circle(p, 3.0, Color(0, 0, 0))
			draw_circle(p, 2.2, c)
	var tnow := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(tnow * 6.0)
	# trasy marszu zaznaczonych pułków (cienka linia do celu)
	for r in battle.regiments:
		if r.selected and r.state == Regiment.State.MOVING and not r.s_pos.is_empty():
			var a0 := _mini_rect.position + r.centroid() * sc
			var a1 := _mini_rect.position + r.move_target * sc
			draw_dashed_line(a0, a1, Color(1, 1, 0.7, 0.75), 1.0, 3.0)
	for r in battle.regiments:
		if r.s_pos.is_empty():
			continue
		# pułk w kształcie i kierunku szyku, tam, gdzie faktycznie są ludzie (nie w celu marszu)
		var p := _mini_rect.position + r.centroid() * sc
		var col: Color = Color(1, 1, 0.6) if r.selected else r.color.lightened(0.15)
		if r.state == Regiment.State.ROUTING:
			col.a = 0.35 + 0.4 * pulse   # ucieka: miga i blednie
		var fw := maxf(3.0, r.formation_width() * sc.x)
		var dp := maxf(2.4, r.formation_depth() * sc.x * 1.5)
		if r.square:
			fw = maxf(3.0, fw * 0.5)
			dp = fw
		draw_set_transform(p, r.facing, Vector2.ONE)
		if r.kind == "art":
			draw_circle(Vector2.ZERO, 2.2, Color(0, 0, 0, col.a))
			draw_circle(Vector2.ZERO, 1.5, col)
			draw_line(Vector2.ZERO, Vector2(3.2, 0), Color(0, 0, 0, col.a), 1.2)   # lufa w stronę frontu
		elif r.kind == "cav" and r.wedge:
			var tri := PackedVector2Array([Vector2(dp * 0.6 + 1.0, 0), Vector2(-dp * 0.6 - 1.0, -fw * 0.5), Vector2(-dp * 0.6 - 1.0, fw * 0.5)])
			draw_colored_polygon(tri, Color(0, 0, 0, col.a))
			draw_colored_polygon(PackedVector2Array([tri[0] * 0.7, tri[1] * 0.75, tri[2] * 0.75]), col)
		else:
			draw_rect(Rect2(-dp * 0.5 - 0.6, -fw * 0.5 - 0.6, dp + 1.2, fw + 1.2), Color(0, 0, 0, col.a))
			draw_rect(Rect2(-dp * 0.5, -fw * 0.5, dp, fw), col)
			if r.kind == "cav":
				draw_line(Vector2(-dp * 0.5, -fw * 0.5), Vector2(dp * 0.5, fw * 0.5), Color(0, 0, 0, 0.6 * col.a), 0.8)   # znak jazdy: ukośna kreska
		draw_set_transform(Vector2.ZERO)
		# walka wręcz: pulsujący czerwony znacznik (rysowany raz, przy pułku gracza albo gdy walczą dwa obce)
		if r.state == Regiment.State.MELEE and (r.team == 0 or r.melee_enemies.is_empty() or r.melee_enemies[0].team != 0):
			var mp := p
			if r._melee_pt != Vector2.INF:
				mp = _mini_rect.position + r._melee_pt * sc
			draw_arc(mp, 3.5 + pulse * 2.0, 0.0, TAU, 12, Color(1.0, 0.25, 0.15, 0.85), 1.2)
			draw_line(mp + Vector2(-2, -2), mp + Vector2(2, 2), Color(1, 0.9, 0.7, 0.9), 1.0)
			draw_line(mp + Vector2(-2, 2), mp + Vector2(2, -2), Color(1, 0.9, 0.7, 0.9), 1.0)
	# widok kamery
	var inv := xf.affine_inverse()
	var a := inv * Vector2.ZERO
	var b := inv * vs
	var vr := Rect2(_mini_rect.position + a * sc, (b - a) * sc).intersection(_mini_rect)
	draw_rect(vr, Color(1, 1, 1, 0.9), false, 1.0)
	draw_rect(_mini_rect, GOLD_DIM, false, 1.0)
	_hits.append([_mini_rect, "minimap", null])


# ================================================================== karty oddziałów

var _tut_portrait: Texture2D
var _tut_portrait_tried := false


func _draw_tutorial() -> void:
	## Samouczek: panel generała (portret, kwestia, zadanie, przyciski) + znaczniki celów na polu bitwy.
	var tut = battle.tutorial
	if tut == null or tut.finished or tut.step < 0:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	# pułki, o które chodzi w zadaniu: pulsująca obwódka wokół karty
	for r in tut.unit_marks:
		if r == null or r.dead:
			continue
		var cp := card_screen_pos(r)
		draw_arc(cp, 30.0 + pulse * 6.0, 0.0, TAU, 40, Color(GOLD, 0.9), 2.5)
		draw_arc(cp, 36.0 + pulse * 6.0, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 1.0)
	# cele na polu: pierścień na ziemi, strzałka nad nim i podpis; poza ekranem - strzałka przy krawędzi
	var vs := get_viewport_rect().size
	for m in tut.markers:
		var sp := battle.world_to_screen(m[0])
		var inside := Rect2(Vector2(40, 90), vs - Vector2(80, 300)).has_point(sp)
		if inside:
			var rr := 22.0 + pulse * 5.0
			draw_arc(sp, rr, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 5.0)
			draw_arc(sp, rr, 0.0, TAU, 40, Color(1.0, 0.86, 0.35), 2.5)
			var top := sp - Vector2(0, 46.0 + pulse * 8.0)
			draw_colored_polygon(PackedVector2Array([top + Vector2(-11, -16), top + Vector2(11, -16), top + Vector2(0, 4)]), Color(0, 0, 0, 0.6))
			draw_colored_polygon(PackedVector2Array([top + Vector2(-8, -14), top + Vector2(8, -14), top]), Color(1.0, 0.86, 0.35))
			_text(String(m[1]), top - Vector2(0, 22), 13, CREAM, 1)
		else:
			var c := vs * 0.5
			var d := (sp - c).normalized()
			var edge := c + d * minf((vs.x * 0.5 - 60.0) / maxf(absf(d.x), 0.001), (vs.y * 0.5 - 150.0) / maxf(absf(d.y), 0.001))
			var n := d.orthogonal()
			draw_colored_polygon(PackedVector2Array([edge + d * 18.0, edge - d * 8.0 + n * 12.0, edge - d * 8.0 - n * 12.0]), Color(1.0, 0.86, 0.35))
			_text(String(m[1]), edge - d * 30.0, 12, CREAM, 1)
	# panel generała u góry ekranu
	var w := minf(780.0, vs.x - 560.0)
	var st: Array = tut.cur()
	var p := Rect2((vs.x - w) * 0.5, 54.0, w, 206.0)
	_panel(p)
	if not _tut_portrait_tried:
		_tut_portrait_tried = true
		_tut_portrait = _load_png(tut.PORTRAIT)
	var px := p.position.x + 12.0
	if _tut_portrait != null:
		var ph := p.size.y - 24.0
		var pw := ph * float(_tut_portrait.get_width()) / maxf(1.0, float(_tut_portrait.get_height()))
		draw_rect(Rect2(px, p.position.y + 12.0, pw, ph), Color(0.10, 0.11, 0.14))
		draw_texture_rect(_tut_portrait, Rect2(px, p.position.y + 12.0, pw, ph), false)
		draw_rect(Rect2(px, p.position.y + 12.0, pw, ph), GOLD_DIM, false, 1.0)
		px += pw + 14.0
	_text(tut.GENERAL, Vector2(px, p.position.y + 26.0), 14, GOLD, 0, false)
	_text("Lesson %d / %d   -   %s" % [tut.step + 1, tut.total(), String(st[1])], Vector2(p.end.x - 14.0, p.position.y + 26.0), 12, DIM, 2, false)
	# kwestia "pisze się" na ekranie
	var say := String(st[2])
	var shown := say.substr(0, int(tut.step_t * tut.type_speed))
	_text_wrap(shown, Rect2(px, p.position.y + 34.0, p.end.x - px - 14.0, 100.0), 13, CREAM)
	var by := p.end.y - 38.0
	var task := String(st[3])
	if task != "":
		var done: bool = tut.done_t >= 0.0
		# zadanie w osobnym wierszu nad przyciskami, podpowiedź obok przycisków
		_text(_fit(("Done!  " if done else "Your task:  ") + task, 13, p.end.x - px - 14.0), Vector2(px, by - 12.0), 13, Color(0.55, 0.9, 0.5) if done else Color(1.0, 0.86, 0.35), 0, false)
		if tut.hint != "" and not done:
			_text(_fit(tut.hint, 12, p.end.x - px - 250.0), Vector2(px, by + 18.0), 12, Color(1.0, 0.6, 0.45), 0, false)
	var bx := p.end.x - 14.0
	_button(Rect2(bx - 96.0, by, 96.0, 28.0), "Quit", "tut_quit")
	bx -= 104.0
	if tut.is_talk():
		_button(Rect2(bx - 150.0, by, 150.0, 28.0), "Finish" if tut.step >= tut.total() - 1 else "Continue", "tut_next", null, true)
	else:
		_button(Rect2(bx - 110.0, by, 110.0, 28.0), "Skip lesson", "tut_next")


func _load_png(path: String) -> Texture2D:
	## Wczytuje obrazek bez importu (działa też, gdy gra startuje bez edytora).
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		abs_path = path   # w wersji wyeksportowanej (np. przeglądarkowej) plik leży w paczce gry, nie na dysku
	if not FileAccess.file_exists(abs_path):
		# brak surowego pliku (wersja wyeksportowana): bierzemy teksturę zaimportowaną przez edytor
		return (load(path) as Texture2D) if ResourceLoader.exists(path) else null
	var img := Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _unit_portrait(key: String, team := 0, variant := 0) -> Texture2D:
	## Grafika jednostki: assets/units/<fr|gb>/<key>.png (+ warianty <key>_2.png, <key>_3.png ...),
	## a gdy ich brak - wspólna assets/units/<key>.png. Każdy pułk dostaje stały wariant.
	var nat := Battle.nation(clampi(team, 0, 1))
	var ck := "%d/%s" % [nat, key]
	if not _portraits.has(ck):
		var list: Array = []
		var dirs := ["res://assets/units/%s/" % Battle.NATION_DIRS[nat], "res://assets/units/"]
		for d in dirs:
			for n in range(1, 13):
				var base := key if n == 1 else "%s_%d" % [key, n]
				for ext in ["png", "jpg", "webp"]:
					var tex := _load_png("%s%s.%s" % [d, base, ext])
					if tex != null:
						list.append(tex)
						break
			if not list.is_empty():
				break
		_portraits[ck] = list
	var arr: Array = _portraits[ck]
	if arr.is_empty():
		return null
	return arr[posmod(variant, arr.size())]


func _ui_tex(name: String) -> Texture2D:
	## Grafiki interfejsu z assets/ui/ (wczytywane raz; brak pliku = null i rysowanie zastępcze).
	var ck := "ui/" + name
	if not _portraits.has(ck):
		_portraits[ck] = _load_png("res://assets/ui/" + name)
	return _portraits[ck]


func _banner_texture(team: int) -> Texture2D:
	## Płótno sztandaru danej strony: assets/ui/fr_banner.png / gb_banner.png
	return _ui_tex("%s_banner.png" % Battle.NATION_DIRS[Battle.nation(clampi(team, 0, 1))])


func _emblem(team: int) -> Texture2D:
	return _ui_tex("%s_emblem.png" % Battle.NATION_DIRS[Battle.nation(clampi(team, 0, 1))])


func _draw_fit(tex: Texture2D, box: Rect2, mod := Color.WHITE) -> void:
	## Rysuje teksturę wpasowaną w prostokąt z zachowaniem proporcji (wyśrodkowaną).
	var ts := tex.get_size()
	var sc := minf(box.size.x / ts.x, box.size.y / ts.y)
	var sz := ts * sc
	draw_texture_rect(tex, Rect2(box.get_center() - sz * 0.5, sz), false, mod)


func _draw_cover(tex: Texture2D, box: Rect2, mod := Color.WHITE) -> void:
	## Wypełnia prostokąt teksturą (przycina nadmiar), jak tło ekranu.
	var ts := tex.get_size()
	var sc := maxf(box.size.x / ts.x, box.size.y / ts.y)
	var src := box.size / sc
	draw_texture_rect_region(tex, box, Rect2((ts - src) * 0.5, src), mod)


func _draw_cards() -> void:
	## Dolny pasek: armie (grupy pułków) z pionowymi sztandarami; pułki bez armii w "Reserve".
	var vs := size
	var groups := battle.army_groups()
	if groups.is_empty():
		return
	var count := 0
	for g in groups:
		count += (g[1] as Array).size() + (1 if g[0] >= 0 else 0)   # +1: karta generała
	var left := MINI_W + 32.0
	var right := vs.x - SIDE_W - 20.0
	var avail := right - left - 16.0 - (groups.size() - 1) * ARMY_GAP
	var bw := clampf(avail / count - BANNER_GAP, 22.0, BANNER.x)
	var total := 16.0 + (groups.size() - 1) * ARMY_GAP
	for g in groups:
		total += ((g[1] as Array).size() + (1 if g[0] >= 0 else 0)) * (bw + BANNER_GAP) - BANNER_GAP
	var strip := Rect2(left + (right - left - total) * 0.5, vs.y - BANNER.y - 46.0, total, BANNER.y + 40.0)
	_panel(strip)
	var x := strip.position.x + 8.0
	var t := Time.get_ticks_msec() / 1000.0
	var mouse := get_local_mouse_position()
	var tip_r: Regiment = null
	var tip_at := Vector2.ZERO
	for g in groups:
		var units: Array = g[1]
		var cards := units.size() + (1 if g[0] >= 0 else 0)
		var gw := cards * (bw + BANNER_GAP) - BANNER_GAP
		var head := Rect2(x, strip.position.y + 5.0, gw, 17.0)
		var men := 0
		var any_sel := false
		for r in units:
			men += r.alive_count()
			any_sel = any_sel or r.selected
		var hov := head.has_point(mouse)
		draw_rect(head, BG3 if hov else BG2)
		if g[0] >= 0:
			draw_rect(Rect2(head.position, Vector2(3, head.size.y)), GOLD if any_sel else GOLD_DIM)
		var label: String = battle.army_name(g[0])
		_text(_fit(label.to_upper(), 10, gw - 30.0), head.position + Vector2(6, 12.5), 10, GOLD if g[0] >= 0 else DIM, 0, false)
		if gw > 70.0:
			_text("%d" % men, head.end - Vector2(4, 4.5), 10, CREAM, 2, false)
		_hits.append([head, "army", g[0]])
		if g[0] >= 0:
			var gr := Rect2(Vector2(x, strip.position.y + 26.0 - (5.0 if any_sel else 0.0)), Vector2(bw, BANNER.y))
			_draw_general(g[0], gr, any_sel)
			_hits.append([gr, "army", g[0]])
			x += bw + BANNER_GAP
		for r in units:
			var rect := Rect2(Vector2(x, strip.position.y + 26.0 - (5.0 if r.selected else 0.0)), Vector2(bw, BANNER.y))
			_draw_banner(r, rect, t)
			_hits.append([rect, "card", r])
			if rect.has_point(mouse):
				tip_r = r
				tip_at = Vector2(rect.get_center().x, strip.position.y - 4.0)
			x += bw + BANNER_GAP
		x += ARMY_GAP - BANNER_GAP
	if tip_r != null:
		_tooltip("%s  -  %s" % [tip_r.reg_name, tip_r.unit_type], tip_at)


func _draw_general(army_id: int, rect: Rect2, sel: bool) -> void:
	## Karta dowódcy armii: portret generała w złotej ramie; klik zaznacza całą armię.
	var hover := rect.has_point(get_local_mouse_position())
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.45))
	draw_rect(rect, BG3 if hover else BG2)
	var tex := _unit_portrait("general", 0, army_id)
	var pic := Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, rect.size.y - 34))
	if tex != null:
		_draw_portrait(tex, pic, 1.25, 0.05)
	else:
		draw_rect(pic, Color(0, 0, 0, 0.3))
		_text("*", pic.get_center() + Vector2(0, 8), 22, GOLD, 1)
	draw_rect(pic, GOLD_DIM, false, 1.0)
	draw_rect(rect, GOLD if sel else GOLD_DIM, false, 2.0 if sel else 1.0)
	var em := _emblem(0)
	if em != null:
		_draw_fit(em, Rect2(rect.get_center().x - 9, pic.end.y + 2, 18, 13))
	_text("GEN.", Vector2(rect.get_center().x, rect.end.y - 4.0), 9, GOLD, 1, false)


const FR_BLUE := Color(0.10, 0.20, 0.52)
const FR_WHITE := Color(0.93, 0.91, 0.84)
const FR_RED := Color(0.72, 0.12, 0.12)
const GB_BLUE := Color(0.08, 0.14, 0.38)
const GB_RED := Color(0.72, 0.10, 0.12)


func _clip_fill(shape: PackedVector2Array, poly: PackedVector2Array, col: Color) -> void:
	for part in Geometry2D.intersect_polygons(shape, poly):
		if part.size() >= 3:
			draw_colored_polygon(part, col)


func _flag_fill(shape: PackedVector2Array, a: Rect2, team: int, tint: Color, t: float) -> void:
	## Płat sztandaru w barwach narodowych: Francja - trójkolor, Wielka Brytania - Union Flag,
	## Austria - czarno-żółta, Rosja - biała z niebieskim krzyżem św. Andrzeja, Prusy - czarno-biało-czarna.
	var nat := Battle.nation(team)
	if nat >= 2:
		var bands: Array = [[Color(0.08, 0.08, 0.08), Color(0.95, 0.78, 0.15), Color(0.08, 0.08, 0.08)], [], [Color(0.08, 0.08, 0.08), Color(0.94, 0.93, 0.9), Color(0.08, 0.08, 0.08)]][nat - 2]
		if nat == 3:
			draw_colored_polygon(shape, Color(0.94, 0.93, 0.9) * tint)
			var c := a.get_center()
			for diag in [Vector2(a.size.x * 0.5, a.size.y * 0.5), Vector2(a.size.x * 0.5, -a.size.y * 0.5)]:
				var d: Vector2 = (diag as Vector2).normalized()
				var nn := d.orthogonal()
				var L: float = (diag as Vector2).length() + 10.0
				var wd := a.size.x * 0.13
				_clip_fill(shape, PackedVector2Array([c - d * L + nn * wd, c + d * L + nn * wd, c + d * L - nn * wd, c - d * L - nn * wd]), Color(0.1, 0.25, 0.65) * tint)
		else:
			var hh := (a.size.y + 2.0) / bands.size()
			for k in bands.size():
				var y0 := a.position.y + hh * k
				_clip_fill(shape, PackedVector2Array([Vector2(a.position.x, y0), Vector2(a.end.x, y0),
					Vector2(a.end.x, y0 + hh + 0.5), Vector2(a.position.x, y0 + hh + 0.5)]), (bands[k] as Color) * tint)
	elif nat == 0:
		var w := a.size.x / 3.0
		var cols := [FR_BLUE, FR_WHITE, FR_RED]
		for k in 3:
			var x := a.position.x + w * k
			_clip_fill(shape, PackedVector2Array([Vector2(x, a.position.y), Vector2(x + w + 0.5, a.position.y),
				Vector2(x + w + 0.5, a.end.y + 2), Vector2(x, a.end.y + 2)]), cols[k] * tint)
	else:
		draw_colored_polygon(shape, GB_BLUE * tint)
		var c := a.get_center()
		var hw := a.size.x * 0.5
		var hh := a.size.y * 0.5
		# ukośne krzyże (białe szersze, czerwone węższe)
		for diag in [Vector2(hw, hh), Vector2(hw, -hh)]:
			var d: Vector2 = diag.normalized()
			var n := d.orthogonal()
			var L: float = (diag as Vector2).length() + 10.0
			for spec in [[0.17, FR_WHITE], [0.06, GB_RED]]:
				var wd: float = a.size.x * spec[0]
				_clip_fill(shape, PackedVector2Array([c - d * L + n * wd, c + d * L + n * wd, c + d * L - n * wd, c - d * L - n * wd]), (spec[1] as Color) * tint)
		# krzyż prosty
		for spec in [[0.24, FR_WHITE], [0.14, GB_RED]]:
			var wd: float = a.size.x * spec[0]
			_clip_fill(shape, PackedVector2Array([Vector2(c.x - wd, a.position.y), Vector2(c.x + wd, a.position.y),
				Vector2(c.x + wd, a.end.y + 2), Vector2(c.x - wd, a.end.y + 2)]), (spec[1] as Color) * tint)
			_clip_fill(shape, PackedVector2Array([Vector2(a.position.x, c.y - wd * 0.8), Vector2(a.end.x, c.y - wd * 0.8),
				Vector2(a.end.x, c.y + wd * 0.8), Vector2(a.position.x, c.y + wd * 0.8)]), (spec[1] as Color) * tint)
	# fałdy płótna: delikatne pionowe cienie, lekko falujące
	var folds := 3
	for k in folds:
		var fx := a.position.x + a.size.x * (k + 0.5) / folds + sin(t * 1.3 + k * 2.0) * 1.5
		_clip_fill(shape, PackedVector2Array([Vector2(fx, a.position.y), Vector2(fx + a.size.x * 0.12, a.position.y),
			Vector2(fx + a.size.x * 0.12, a.end.y + 2), Vector2(fx, a.end.y + 2)]), Color(0, 0, 0, 0.12))


func _draw_banner(r: Regiment, rect: Rect2, t: float) -> void:
	## Pionowy sztandar: drzewce z poprzeczką, płat w barwach strony, jaskółczy ogon u dołu.
	var routing := r.state == Regiment.State.ROUTING
	var hover := rect.has_point(get_local_mouse_position())
	var cloth := r.color.darkened(0.25)
	if routing:
		cloth = cloth.lerp(Color(0.55, 0.08, 0.08), 0.5 + 0.5 * sin(t * 8.0))
	elif hover:
		cloth = cloth.lightened(0.12)
	var x0 := rect.position.x
	var x1 := rect.end.x
	var top := rect.position.y + 5.0
	var tail := rect.end.y - 16.0
	var tip := rect.end.y - 4.0
	var cx := rect.get_center().x
	var shape := PackedVector2Array([Vector2(x0, top), Vector2(x1, top), Vector2(x1, tip), Vector2(cx, tail), Vector2(x0, tip)])
	var shadow := PackedVector2Array()
	for p in shape:
		shadow.append(p + Vector2(2, 3))
	var tex := _banner_texture(r.team)
	if tex != null:
		# płótno z grafiki (z drążkiem i frędzlami); kolor modulowany przy rozbiciu / najechaniu
		var mod := Color.WHITE
		if routing:
			mod = Color(1, 0.45, 0.45).lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 8.0))
		elif hover or r.selected:
			mod = Color(1.15, 1.12, 1.05)
		var full := Rect2(x0 - 3.0, top - 4.0, rect.size.x + 6.0, rect.end.y - top + 4.0)
		draw_texture_rect(tex, Rect2(full.position + Vector2(2, 3), full.size), false, Color(0, 0, 0, 0.4))
		draw_texture_rect(tex, full, false, mod)
		if r.selected:
			draw_line(Vector2(x0, top + 1), Vector2(x1, top + 1), GOLD, 2.0)
	else:
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
		var tint := Color.WHITE
		if routing:
			tint = Color(1, 0.5, 0.5).lerp(Color.WHITE, 0.5 + 0.5 * sin(t * 8.0))
		elif hover:
			tint = Color(1.12, 1.12, 1.12)
		_flag_fill(shape, Rect2(x0, top, rect.size.x, tip - top), r.team, tint, t + rect.position.x * 0.05)
		draw_rect(Rect2(x0, top, rect.size.x, 3.0), Color(GOLD_DIM, 0.8))
		var outline := shape.duplicate()
		outline.append(shape[0])
		draw_polyline(outline, GOLD if r.selected else Color(GOLD_DIM, 0.9), 2.0 if r.selected else 1.0)
		# drzewce: poprzeczka z gałkami i grot
		draw_line(Vector2(x0 - 3, top - 1), Vector2(x1 + 3, top - 1), Color(0.42, 0.30, 0.16), 3.0)
		draw_circle(Vector2(x0 - 3, top - 1), 2.2, GOLD)
		draw_circle(Vector2(x1 + 3, top - 1), 2.2, GOLD)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 3, top - 2), Vector2(cx, top - 7), Vector2(cx + 3, top - 2)]), GOLD)
	# portret jednostki lub symbol sztabowy
	var inset := 8.0 if rect.size.x >= 36.0 else 6.0
	var pic := Rect2(x0 + inset, top + 6, rect.size.x - inset * 2.0, minf((rect.size.x - inset * 2.0) * 1.9, 102.0))
	var portrait := _unit_portrait(r.unit_key, r.team, r.reg_name.hash())
	if portrait != null:
		draw_rect(pic.grow(1.0), Color(0, 0, 0, 0.55))
		draw_rect(pic, Color(0.16, 0.14, 0.12, 0.85))
		_draw_portrait(portrait, pic, 1.12, -0.07)   # zsunięty niżej - czapki nie ucinane
		draw_rect(pic.grow(1.0), Color(GOLD_DIM, 0.9), false, 1.0)
	else:
		draw_rect(pic, Color(0, 0, 0, 0.18))
		var symw := minf(28.0, pic.size.x - 6.0)
		var sym := Rect2(pic.get_center() - Vector2(symw * 0.5, symw * 0.32), Vector2(symw, symw * 0.64))
		draw_rect(sym, Color(1, 1, 1, 0.9), false, 1.2)
		_unit_symbol(sym, r.kind, r.unit_key, Color(1, 1, 1, 0.9))
	if r.selected:
		draw_rect(pic, GOLD, false, 1.5)
	var y := pic.end.y + 15.0
	_text("%d" % r.alive_count(), Vector2(cx, y), 14 if rect.size.x > 30 else 11, CREAM, 1)
	# pionowe paski wzdłuż krawędzi płatu: ludzie (lewy) i morale (prawy)
	var bar_top := top + 6.0
	var bar_h := tip - 10.0 - bar_top
	var bwid := inset - 4.0
	_vbar(Rect2(x0 + 2, bar_top, bwid, bar_h), r.health_frac(), GOOD)
	_vbar(Rect2(x1 - 2 - bwid, bar_top, bwid, bar_h), r.morale / 100.0, MORALE)
	if r.march_mode and r.state == Regiment.State.MOVING:
		_text("road", Vector2(cx, y + 14.0), 9, GOLD, 1)
	# stan pod sztandarem
	var st := ""
	var sc2 := DIM
	match r.state:
		Regiment.State.MOVING:
			st = "column" if r._in_column else "march"
		Regiment.State.CHARGING:
			st = "charge"
			sc2 = BAD
		Regiment.State.MELEE:
			st = "melee"
			sc2 = BAD
		Regiment.State.ROUTING:
			st = "ROUT"
			sc2 = BAD
		_:
			if r.square:
				st = "square"
				sc2 = GOLD
			elif r.fire_target != null:
				st = "firing"
				sc2 = MORALE
			elif r.garrisoned:
				st = "garrison"
				sc2 = GOOD
	if r.in_water_ratio > 0.2:
		st = "water!"
		sc2 = Color(0.5, 0.75, 1.0)
	elif r.is_surrounded():
		st = "SURROUNDED"
		sc2 = BAD
	elif r.is_flanked():
		st = "flanked"
		sc2 = BAD
	if st != "" and rect.size.x >= 34.0:
		_text(_fit(st, 8, rect.size.x + 4.0), Vector2(cx, rect.end.y + 9.0), 8, sc2, 1, false)
	elif st != "" and sc2 == BAD:
		draw_circle(Vector2(cx, rect.end.y + 6.0), 2.5, BAD)


func _draw_portrait(tex: Texture2D, dst: Rect2, zoom := 1.12, anchor_y := 0.06, mod := Color.WHITE) -> void:
	## Wypełnia prostokąt obrazkiem z zachowaniem proporcji; przybliżenie na głowę i tors.
	var ts := tex.get_size()
	var sc := maxf(dst.size.x / ts.x, dst.size.y / ts.y) * zoom
	var src_size := dst.size / sc
	var src_pos := Vector2((ts.x - src_size.x) * 0.5, (ts.y - src_size.y) * anchor_y)
	if anchor_y < 0.0:
		# ujemne zakotwiczenie: obrazek zsunięty w dół (pusty pasek u góry), nic nie wychodzi poza ramkę
		var gap := ts.y * -anchor_y
		src_pos.y = 0.0
		var d2 := Rect2(dst.position + Vector2(0, gap * sc), Vector2(dst.size.x, dst.size.y - gap * sc))
		draw_texture_rect_region(tex, d2, Rect2(src_pos, Vector2(src_size.x, src_size.y - gap)), mod)
		return
	draw_texture_rect_region(tex, dst, Rect2(src_pos, src_size), mod)


func _vbar(r: Rect2, frac: float, col: Color) -> void:
	draw_rect(r, Color(0, 0, 0, 0.55))
	var h := r.size.y * clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), col)


func _tooltip(s: String, at: Vector2) -> void:
	var w := _tw(s, 12) + 16.0
	var box := Rect2(at - Vector2(w * 0.5, 22), Vector2(w, 22))
	box.position.x = clampf(box.position.x, 4.0, size.x - w - 4.0)
	draw_rect(box, Color(BG, 0.97))
	draw_rect(box, GOLD_DIM, false, 1.0)
	_text(s, Vector2(box.get_center().x, box.end.y - 7), 12, CREAM, 1, false)


# ================================================================== panel jednostki

func _draw_unit_panel() -> void:
	var vs := size
	var sel := battle.selected
	var h := 266.0 if sel.size() == 1 else 214.0   # pojedynczy pułk: miejsce na rząd przycisku ognia
	var p := Rect2(vs.x - SIDE_W - 10, vs.y - h - 10, SIDE_W, h)
	if sel.size() == 1:
		var r := sel[0]
		_panel(p, r.reg_name.to_upper())
		var portrait := _unit_portrait(r.unit_key, r.team, r.reg_name.hash())
		var tx := p.position.x + 80.0
		if portrait != null:
			var pr := Rect2(p.position + Vector2(12, 34), Vector2(54, 56))
			draw_rect(pr.grow(2), r.color.darkened(0.2))
			_draw_portrait(portrait, pr, 1.15, 0.06)
		else:
			var icon := Rect2(p.position + Vector2(12, 38), Vector2(56, 40))
			draw_rect(icon, r.color.darkened(0.2))
			var sym := Rect2(icon.position + Vector2(8, 8), Vector2(40, 24))
			draw_rect(sym, Color(1, 1, 1, 0.9), false, 1.5)
			_unit_symbol(sym, r.kind, r.unit_key, Color(1, 1, 1, 0.9))
		_text(r.unit_type, Vector2(tx, p.position.y + 52), 15, CREAM, 0, false)
		var st: String = STATE_NAMES[r.state]
		if r.kind == "inf" and not r.officer_alive and r.state == Regiment.State.IDLE:
			st = "Fire at will"
		if r.state == Regiment.State.IDLE and r.fire_target != null:
			st = "Firing"
		elif r.state == Regiment.State.MOVING and r._in_column:
			st = "Column march"
		elif r.is_limbering():
			st = "Limbering up"
		elif r.is_unlimbering():
			st = "Unlimbering guns"
		elif r.kind == "art" and r.state == Regiment.State.MOVING and r.limber_u >= 1.0:
			st = "On the move (limbered)"
		if r.garrisoned and r.state == Regiment.State.IDLE:
			st += "  -  garrison"
		if r.is_surrounded():
			st += "  -  SURROUNDED"
		elif r.is_flanked():
			st += "  -  flanked"
		elif r.fatigue_name() != "":
			st += "  -  " + r.fatigue_name()
		_text(st, Vector2(tx, p.position.y + 72), 12, GOLD, 0, false)
		var y := p.position.y + 96.0
		_text("Men", Vector2(p.position.x + 12, y + 9), 12, DIM, 0, false)
		_bar(Rect2(p.position.x + 80, y, SIDE_W - 150, 10), r.health_frac(), GOOD)
		_text("%d / %d" % [r.alive_count(), r.initial_count], Vector2(p.end.x - 12, y + 10), 12, CREAM, 2, false)
		y += 20.0
		_text("Morale", Vector2(p.position.x + 12, y + 9), 12, DIM, 0, false)
		_bar(Rect2(p.position.x + 80, y, SIDE_W - 150, 10), r.morale / 100.0, MORALE)
		_text("%d%%" % int(r.morale), Vector2(p.end.x - 12, y + 10), 12, CREAM, 2, false)
		y += 20.0
		_text("Stamina", Vector2(p.position.x + 12, y + 9), 12, DIM, 0, false)
		var sc := GOOD if r.stamina >= 55.0 else (MORALE if r.stamina >= 25.0 else BAD)
		_bar(Rect2(p.position.x + 80, y, SIDE_W - 150, 10), r.stamina / 100.0, sc)
		_text("%d%%" % int(r.stamina), Vector2(p.end.x - 12, y + 10), 12, CREAM, 2, false)
		y += 26.0
		var t: Dictionary = Battle.UNIT_TYPES[r.unit_key]
		_text("Terrain: %s" % Terrain.cell_name(battle.terrain.cell_at(r.center)), Vector2(p.position.x + 12, y), 12, CREAM, 0, false)
		var upk := 0 if r.garrisoned else int(float(t["upkeep"]) * 60.0 * battle.upkeep_mult(r.team))
		_text("Upkeep: %d/min" % upk, Vector2(p.end.x - 12, y), 12, CREAM, 2, false)
		y += 18.0
		var rng := "melee only" if r.fire_range <= 0.0 else "%d paces" % int(r.fire_range / 10.0)
		_text("Range: %s" % rng, Vector2(p.position.x + 12, y), 12, CREAM, 0, false)
		_text("Melee x%.1f  Disc. x%.1f" % [r.melee_skill, r.discipline], Vector2(p.end.x - 12, y), 12, CREAM, 2, false)
	else:
		_panel(p, "%d REGIMENTS SELECTED" % sel.size())
		var men := 0
		var cap := 0
		var hsum := 0.0
		var mor := 0.0
		for r in sel:
			men += r.alive_count()
			cap += r.initial_count
			hsum += r.health_frac() * r.initial_count
			mor += r.morale
		var y := p.position.y + 48.0
		_text("Men", Vector2(p.position.x + 12, y + 9), 12, DIM, 0, false)
		_bar(Rect2(p.position.x + 80, y, SIDE_W - 150, 10), hsum / maxf(1.0, cap), GOOD)
		_text("%d" % men, Vector2(p.end.x - 12, y + 10), 12, CREAM, 2, false)
		y += 20.0
		_text("Morale", Vector2(p.position.x + 12, y + 9), 12, DIM, 0, false)
		_bar(Rect2(p.position.x + 80, y, SIDE_W - 150, 10), mor / sel.size() / 100.0, MORALE)
		_text("%d%%" % int(mor / sel.size()), Vector2(p.end.x - 12, y + 10), 12, CREAM, 2, false)
		y += 30.0
		var x := p.position.x + 12.0
		for r in sel:
			if x > p.end.x - 34:
				break
			var ic := Rect2(x, y, 26, 20)
			draw_rect(ic, r.color.darkened(0.2))
			_unit_symbol(ic.grow(-4), r.kind, r.unit_key, Color(1, 1, 1, 0.9))
			x += 30.0
	var by := p.end.y - 40.0
	var in_army := false
	for r in sel:
		in_army = in_army or r.army_id >= 0
	# górny rząd przycisków: armia i tryb ognia, szerokości dzielone po równo
	var upper: Array = []
	if sel.size() > 1:
		upper.append(["Form army (G)", "form_army", false])
	if in_army and sel.size() > 1:
		upper.append(["Leave army (U)", "leave_army", false])
	var inf_sel := false
	var fmode := 0
	for r in sel:
		if r.kind == "inf":
			inf_sel = true
			fmode = maxi(fmode, r.fire_mode)
	if inf_sel:
		upper.append(["%s (T)" % Regiment.FIRE_MODE_NAMES[fmode], "fire_will", fmode != Regiment.FIRE_MELEE])
	for r in sel:
		if r.kind == "art":
			upper.append(["Ammo: %s (B)" % Regiment.AMMO_NAMES[r.ammo], "ammo", r.ammo != 0])
			break
	if not upper.is_empty():
		var uw := (SIDE_W - 24.0 - 6.0 * (upper.size() - 1)) / upper.size()
		for k in upper.size():
			_button(Rect2(p.position.x + 12 + k * (uw + 6.0), by - 34, uw, 28), upper[k][0], upper[k][1], null, upper[k][2], true, 12 if upper.size() > 2 else 13)
	_button(Rect2(p.position.x + 12, by, 90, 28), "Halt (H)", "halt")
	var any_inf := false
	var all_sq := true
	for r in sel:
		if r.kind == "inf":
			any_inf = true
			all_sq = all_sq and r.square
	if any_inf:
		_button(Rect2(p.position.x + 110, by, 120, 28), "Break square" if all_sq else "Square (Q)", "square", null, all_sq)
	var any_cav := false
	var all_w := true
	for r in sel:
		if r.kind == "cav":
			any_cav = true
			all_w = all_w and r.wedge
	if any_cav:
		_button(Rect2(p.position.x + (238.0 if any_inf else 110.0), by, 110, 28), "Line" if all_w else "Wedge (V)", "wedge", null, all_w)
	_button(Rect2(p.end.x - 80, by, 68, 28), "Close", "close")


# ================================================================== panel osady i rekrutacji

func _draw_settlement_panel() -> void:
	var s := battle.selected_settlement
	var vs := size
	var units: Array = s.allowed_units() if s.faction == 0 else []
	# długa lista (Francja: 39 jednostek) - zakładki według rangi oddziału
	var tabs: Array = []
	for i in Battle.TIER_TABS.size():
		for key in Battle.roster(Battle.nation(0)):
			if Battle.UNIT_TYPES[key].get("tier", "") == Battle.TIER_TABS[i]:
				tabs.append(i)
				break
	if tabs.size() > 1 and s.faction == 0:
		if not tabs.has(recruit_tab):
			recruit_tab = tabs[0]
		var keep: Array = []
		for key in units:
			if Battle.UNIT_TYPES[key].get("tier", "") == Battle.TIER_TABS[recruit_tab]:
				keep.append(key)
		units = keep
	var tab_h := 30.0 if tabs.size() > 1 and s.faction == 0 else 0.0
	var row_h := 36.0
	var h := 92.0 + tab_h + maxi(units.size(), 1) * row_h + (34.0 + Battle.MAX_QUEUE * 18.0 if s.faction == 0 else 40.0)
	var p := Rect2(vs.x - SIDE_W - 10, vs.y - h - 10, SIDE_W, h)
	_panel(p, ("TOWN OF " if s.is_city else "VILLAGE OF ") + s.s_name.to_upper())
	var owner_s := "Yours" if s.faction == 0 else ("Enemy" if s.faction == 1 else "Neutral")
	draw_rect(Rect2(p.position + Vector2(12, 36), Vector2(12, 12)), Battle.owner_color(s.faction))
	_text(owner_s, Vector2(p.position.x + 30, p.position.y + 47), 13, CREAM, 0, false)
	_coin(Vector2(p.position.x + 130, p.position.y + 42), 6.0)
	_text("+%d gold / min" % int(s.income * 60.0), Vector2(p.position.x + 142, p.position.y + 47), 13, GOLD, 0, false)
	_button(Rect2(p.end.x - 30, p.position.y + 3, 22, 20), "x", "close")
	if s.capture > 0.0 and s.capture_team >= 0:
		_text("Being captured", Vector2(p.position.x + 12, p.position.y + 68), 11, BAD if s.capture_team == 1 else GOOD, 0, false)
		_bar(Rect2(p.position.x + 110, p.position.y + 60, SIDE_W - 124, 9), s.capture, Battle.owner_color(s.capture_team))
	if s.faction != 0:
		_text("Capture this settlement to recruit here.", Vector2(p.position.x + 12, p.position.y + 88), 12, DIM, 0, false)
		return
	_text("RECRUIT", Vector2(p.position.x + 12, p.position.y + 86), 11, DIM, 0, false)
	var y := p.position.y + 92.0
	if tab_h > 0.0:
		var tw := (SIDE_W - 20.0) / tabs.size()
		for i in tabs.size():
			var ti: int = tabs[i]
			var tr := Rect2(p.position.x + 10 + i * tw, y, tw - 3, 24)
			var on := ti == recruit_tab
			var th := tr.has_point(_mouse())
			draw_rect(tr, BG3 if on or th else BG2)
			draw_rect(tr, GOLD if on else Color(1, 1, 1, 0.1), false, 1.0)
			_text(Battle.TIER_LABELS[ti], Vector2(tr.get_center().x, tr.position.y + 17), 11, GOLD if on else CREAM, 1, false)
			_hits.append([tr, "recruit_tab", ti])
		y += tab_h
	if units.is_empty():
		_text("This unit can only be recruited in cities.", Vector2(p.position.x + 14, y + 22), 11, DIM, 0, false)
		y += row_h
	var tip_key := ""
	var tip_rect := Rect2()
	for key in units:
		var t: Dictionary = Battle.UNIT_TYPES[key]
		var r := Rect2(p.position.x + 10, y, SIDE_W - 20, 32)
		var ok := battle.can_recruit(s, key)
		var hover := r.has_point(get_local_mouse_position()) and ok
		if r.has_point(_mouse()):
			tip_key = key
			tip_rect = r
		draw_rect(r, BG3 if hover else BG2)
		draw_rect(r, GOLD if hover else Color(1, 1, 1, 0.08), false, 1.0)
		var sym := Rect2(r.position + Vector2(6, 8), Vector2(26, 16))
		draw_rect(sym, Battle.owner_color(0).darkened(0.2))
		_unit_symbol(sym, t["kind"], key, Color(1, 1, 1, 0.9))
		var tc := CREAM if ok else Color(0.5, 0.5, 0.5)
		var nm := "%s  (%d)" % [t["name"], Regiment.men_count(t)]
		var nsz := 13 if _tw(nm, 13) <= r.size.x - 106 else 11
		_text(_fit(nm, nsz, r.size.x - 106), r.position + Vector2(40, 14), nsz, tc, 0, false)
		_text("%ds  -  upkeep %d/min" % [int(t["time"]), int(float(t["upkeep"]) * 60.0)], r.position + Vector2(40, 27), 10, Color(tc, 0.7), 0, false)
		_coin(Vector2(r.end.x - 52, r.get_center().y), 5.0)
		var price := battle.unit_cost(0, key)
		var pc := (BAD if price > int(t["cost"]) else GOLD) if ok else GOLD_DIM
		_text("%d" % price, Vector2(r.end.x - 8, r.get_center().y + 5), 14, pc, 2, false)
		if ok:
			_hits.append([r, "recruit", key])
		y += row_h
	if tip_key != "":
		_recruit_tip(tip_key, tip_rect)
	_text("QUEUE  %d / %d" % [s.queue.size(), Battle.MAX_QUEUE], Vector2(p.position.x + 12, y + 14), 11, DIM, 0, false)
	y += 20.0
	for i in s.queue.size():
		var q: Array = s.queue[i]
		var t: Dictionary = Battle.UNIT_TYPES[q[0]]
		var r := Rect2(p.position.x + 10, y, SIDE_W - 20, 15)
		var prog := 1.0 - float(q[1]) / float(q[2])
		draw_rect(r, Color(0, 0, 0, 0.5))
		if i == 0:
			draw_rect(Rect2(r.position, Vector2(r.size.x * prog, r.size.y)), Color(0.3, 0.55, 0.3, 0.9))
		_text(t["name"], r.position + Vector2(6, 12), 10, CREAM, 0, false)
		if i == 0:
			_text("%ds" % int(q[1]), Vector2(r.end.x - 6, r.position.y + 12), 10, CREAM, 2, false)
		y += 18.0


func _recruit_tip(key: String, row: Rect2) -> void:
	## Karta jednostki obok panelu werbunku: portret, statystyki i cechy specjalne z arkusza.
	var t: Dictionary = Battle.UNIT_TYPES[key]
	var w := 300.0
	var hh := 208.0
	var box := Rect2(row.position.x - w - 14, clampf(row.position.y - 80, 10, size.y - hh - 10), w, hh)
	draw_rect(box, Color(0.06, 0.05, 0.04, 0.94))
	draw_rect(box, GOLD_DIM, false, 1.0)
	var tex := _unit_portrait(key, 0, 0)
	var pic := Rect2(box.position + Vector2(10, 10), Vector2(96, 120))
	if tex != null:
		_draw_portrait(tex, pic, 1.25, 0.05)
	draw_rect(pic, GOLD_DIM, false, 1.0)
	var x := box.position.x + 116
	_text(str(t["name"]), Vector2(x, box.position.y + 26), 14, GOLD, 0, false)
	var lines := [
		"Men: %d    Morale: %.2f" % [Regiment.men_count(t), float(t["discipline"])],
		"Melee: attack %.2f / defense %.2f" % [float(t["melee"]), float(t.get("defense", t["melee"]))],
	]
	if float(t["range"]) > 0.0:
		lines.append("Fire: accuracy %.2f, range %d" % [float(t["accuracy"]), int(t["range"])])
		lines.append("Reload: %.1f s" % float(t["reload"]))
	if t.has("charge"):
		lines.append("Charge: x%.2f" % float(t["charge"]))
	lines.append("March: %d / run %d" % [int(t["walk"]), int(t["run"])])
	var ly := box.position.y + 46
	for l in lines:
		_text(l, Vector2(x, ly), 11, CREAM, 0, false)
		ly += 16
	var desc := str(t.get("desc", ""))
	if desc != "":
		_text("CECHY", Vector2(box.position.x + 12, box.position.y + 148), 10, DIM, 0, false)
		_text_wrap(desc, Rect2(box.position.x + 12, box.position.y + 152, w - 24, 50), 12, CREAM)


# ================================================================== menu

const BG_SHOW := 14.0   # ile sekund wisi jeden obraz
const BG_FADE := 2.5    # przenikanie
var _bg_list: Array = []
var _bg_start := -1


func _draw_backdrop(dim: float) -> void:
	## Tło ekranów menu / końca bitwy: obrazy bitew z assets/ui/menu_bg_*.jpg, przenikające się
	## z powolnym przybliżaniem. Kolejność losowa przy każdym uruchomieniu gry.
	var vs := size
	if _bg_list.is_empty():
		for i in range(1, 13):
			var t := _ui_tex("menu_bg_%d.jpg" % i)
			if t != null:
				_bg_list.append(t)
		if _bg_list.is_empty() and _ui_tex("menu_bg.jpg") != null:
			_bg_list.append(_ui_tex("menu_bg.jpg"))
		_bg_list.shuffle()
	if _bg_list.is_empty():
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
		return
	var now := Time.get_ticks_msec() / 1000.0
	var n := _bg_list.size()
	var slot := now / BG_SHOW
	var k := int(slot)
	var f := slot - k   # postęp w obrębie slotu
	var v := 1.0 - dim
	_draw_bg(_bg_list[k % n], vs, f, Color(v, v, v))
	var fade_from := 1.0 - BG_FADE / BG_SHOW
	if n > 1 and f > fade_from:
		var a := smoothstep(0.0, 1.0, (f - fade_from) / (1.0 - fade_from))
		_draw_bg(_bg_list[(k + 1) % n], vs, f - 1.0, Color(v, v, v, a))
	# winieta: płynnie ciemniejsze brzegi (gradienty zamiast schodkowych ramek)
	var e := minf(vs.x, vs.y) * 0.28
	var dark := Color(0, 0, 0, 0.55)
	var clear := Color(0, 0, 0, 0.0)
	_grad_rect(Rect2(0, 0, vs.x, e), dark, clear)
	_grad_rect(Rect2(0, vs.y - e, vs.x, e), clear, dark)
	_grad_rect_h(Rect2(0, 0, e, vs.y), dark, clear)
	_grad_rect_h(Rect2(vs.x - e, 0, e, vs.y), clear, dark)


func _draw_bg(tex: Texture2D, vs: Vector2, f: float, col: Color) -> void:
	## Obraz "cover" z lekkim przybliżeniem (efekt Kena Burnsa); f od -0.2 do 1.
	var zoom := 1.04 + 0.06 * clampf((f + 0.2) / 1.2, 0.0, 1.0)
	var c := vs * 0.5
	var r := Rect2(c - vs * zoom * 0.5, vs * zoom)
	_draw_cover(tex, r, col)


# ================================================================== ekran tytułowy

const TITLE_TIPS := [
	"Infantry and cavalry can wade a river, slowly. Guns must use a bridge or the ford beside it.",
	"Tired regiments reload slower and break sooner. Rest them before the decisive charge.",
	"Infantry in a square laughs at cavalry - and dies to cannon.",
	"Each town supports 3 more regiments, each village 1. Beyond that, upkeep soars.",
	"A regiment beside its friends holds its nerve; alone under fire it wavers.",
	"Strike the flank: attacks from the side hit 1.5x harder, from the rear 2.2x.",
	"Infantry inside a town is hard to hit. Bring guns, not just numbers.",
	"Right-click with a mixed army: infantry forms the line, guns behind, cavalry on the wings.",
]


func _draw_title() -> void:
	var vs := size
	var t := Time.get_ticks_msec() / 1000.0
	_draw_backdrop(0.12)
	# lewa kolumna przyciemniona gradientem, żeby napisy były czytelne na każdym obrazie
	_grad_rect_h(Rect2(0, 0, minf(720.0, vs.x * 0.55), vs.y), Color(0.02, 0.02, 0.03, 0.88), Color(0.02, 0.02, 0.03, 0.0))
	_grad_rect(Rect2(0, vs.y - 120, vs.x, 120), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.6))
	_blockers.append(Rect2(Vector2.ZERO, vs))
	if sub != "":
		_draw_title_sub()
		return
	var x := 84.0
	var y := maxf(110.0, vs.y * 0.15)
	var em := _emblem(0)
	if em != null:
		_draw_fit(em, Rect2(x - 4, y - 92, 64, 58), Color(1, 1, 1, 0.9))
	_text("WINGS OF", Vector2(x, y), 62, GOLD)
	_text("EMPIRE", Vector2(x + 4, y + 52), 40, CREAM)
	var ly := y + 74.0
	draw_line(Vector2(x, ly), Vector2(x + 400, ly), GOLD_DIM, 1.0)
	_diamond(Vector2(x + 200, ly), 5.0, GOLD)
	_diamond(Vector2(x, ly), 3.0, GOLD_DIM)
	_diamond(Vector2(x + 400, ly), 3.0, GOLD_DIM)
	_text("Battles of the Grande Armée  -  1805 to 1815", Vector2(x, ly + 26), 14, DIM, 0, false)
	var items: Array = []
	if _can_continue():
		items.append(["Continue", "Return to the battle in progress", "resume", null])
	items.append(["New Battle", "Choose nations, scenario, terrain and map size", "sub", "battle"])
	items.append(["Quick Battle", "%s  -  %s  -  %s  -  %s" % [Battle.chosen_scenario, Battle.chosen_map, Battle.chosen_theme.get_slice(" (", 0), Battle.chosen_size], "quick", null])
	if MP_COMING_SOON:
		items.append(["Multiplayer", "Coming soon", "", null])
	else:
		items.append(["Multiplayer", "Team battles over LAN or the internet", "sub", "mp"])
	items.append(["Tutorial", "Général Duval teaches you to command - hands-on lessons", "tutorial", null])
	items.append(["How to Play", "Controls, orders and tips", "sub", "howto"])
	items.append(["Settings", "Sound and display", "sub", "settings"])
	items.append(["Quit", "Leave the field", "quit", null])
	var by := ly + 58.0
	var step := clampf((vs.y - by - 90.0) / items.size(), 50.0, 64.0)
	for it in items:
		_menu_button(Rect2(x - 20, by, 440, step - 1), it[0], it[1], it[2], it[3], String(it[2]) != "")
		by += step
	# porada (zmienia się co kilka sekund) i stopka
	var tip: String = TITLE_TIPS[int(t / 9.0) % TITLE_TIPS.size()]
	var fade := clampf(minf(fmod(t, 9.0), 9.0 - fmod(t, 9.0)) / 0.6, 0.0, 1.0)
	_text("TIP", Vector2(x, vs.y - 30), 12, Color(GOLD.r, GOLD.g, GOLD.b, fade), 0, false)
	_text(tip, Vector2(x + 34, vs.y - 30), 13, Color(CREAM.r, CREAM.g, CREAM.b, 0.85 * fade), 0, false)
	_text("Wings of Empire", Vector2(vs.x - 24, vs.y - 30), 12, DIM, 2, false)


func _draw_title_sub() -> void:
	var vs := size
	var names := {"battle": "NEW BATTLE", "mp": "MULTIPLAYER", "howto": "HOW TO PLAY", "settings": "SETTINGS"}
	var p := Rect2(vs.x * 0.5 - 470, vs.y * 0.5 - 290, 940, 580)
	_panel(p)
	_text(names.get(sub, ""), Vector2(p.get_center().x, p.position.y + 46), 30, GOLD, 1)
	var ly := p.position.y + 62.0
	draw_line(Vector2(p.get_center().x - 180, ly), Vector2(p.get_center().x + 180, ly), GOLD_DIM, 1.0)
	_diamond(Vector2(p.get_center().x, ly), 4.0, GOLD)
	var body := Rect2(p.position + Vector2(20, 80), Vector2(p.size.x - 40, p.size.y - 146))
	draw_rect(body, Color(0, 0, 0, 0.25))
	draw_rect(body, GOLD_DIM, false, 1.0)
	match sub:
		"battle":
			_draw_new_battle(body)
		"mp":
			_draw_multiplayer(body)
		"howto":
			_draw_controls(body)
		"settings":
			_draw_settings(body)
	var by := p.end.y - 52.0
	_button(Rect2(p.position.x + 20, by, 150, 36), "Back  (Esc)", "back")
	if sub == "battle":
		_button(Rect2(p.end.x - 300, by - 2, 280, 40), "START BATTLE", "restart", null, true, true, 16)


func _draw_settings(body: Rect2) -> void:
	## Ustawienia (menu główne i pauza pod Esc): po lewej dźwięk, po prawej obraz i rozgrywka. Zapis automatyczny.
	var x0 := body.position.x + 28.0
	var y := body.position.y + 40.0
	var colw := body.size.x * 0.5 - 40.0
	_text("SOUND", Vector2(x0, y), 13, GOLD, 0, false)
	y += 34.0
	for row in [["Master", "master"], ["Music", "music"], ["Battle sounds", "sfx"], ["Interface", "ui"]]:
		var key: String = row[1]
		var v := GameSettings.get_value(key)
		_text(row[0], Vector2(x0, y + 5), 14, CREAM, 0, false)
		var bar := Rect2(x0 + 130, y - 7, colw - 190, 14)
		var hover := bar.grow(6).has_point(get_local_mouse_position())
		var a2 := _hover_amount("vol|" + key, hover)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * v, bar.size.y)), GOLD.lerp(Color(1, 0.9, 0.6), a2 * 0.4))
		draw_rect(bar, GOLD_DIM.lerp(GOLD, a2), false, 1.0)
		var knob := Vector2(bar.position.x + bar.size.x * v, bar.get_center().y)
		draw_rect(Rect2(knob - Vector2(5, 9) + Vector2(1, 2), Vector2(10, 18)), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(knob - Vector2(5, 9), Vector2(10, 18)), Color(0.25, 0.19, 0.09))
		draw_rect(Rect2(knob - Vector2(3, 7), Vector2(6, 14)), GOLD.lerp(Color(1, 0.92, 0.65), a2))
		_text("%d%%" % roundi(v * 100.0), Vector2(bar.end.x + 50, y + 5), 13, CREAM, 2, false)
		_hits.append([bar.grow(6), "vol", [key, bar]])
		y += 44.0
	var x1 := body.position.x + body.size.x * 0.5 + 12.0
	var y1 := body.position.y + 40.0
	_text("DISPLAY", Vector2(x1, y1), 13, GOLD, 0, false)
	y1 += 18.0
	_opt_row(x1, y1, "Window", [["Windowed", false], ["Fullscreen", true]], "fullscreen", GameSettings.fullscreen)
	y1 += 40.0
	_opt_row(x1, y1, "VSync", [["On", true], ["Off", false]], "vsync", GameSettings.vsync)
	y1 += 52.0
	_text("GAMEPLAY", Vector2(x1, y1), 13, GOLD, 0, false)
	y1 += 18.0
	_opt_row(x1, y1, "Infantry fire", [["On orders", true], ["At will", false]], "hold_fire", GameSettings.hold_fire)
	y1 += 40.0
	_opt_row(x1, y1, "After an order", [["Deselect", true], ["Keep", false]], "deselect_after", GameSettings.deselect_after)
	y1 += 40.0
	_opt_row(x1, y1, "Regiment size", [["Small", 1.0], ["Medium", 1.5], ["Large", 2.0]], "men_mult", GameSettings.men_mult)
	y1 += 36.0
	_text("Regiment size applies from the next battle (smaller = faster on weak PCs).", Vector2(x1, y1 + 4), 11, DIM, 0, false)
	_text("Settings are saved automatically.", Vector2(x0, body.end.y - 16), 11, DIM, 0, false)


func _opt_row(x: float, y: float, label: String, opts: Array, key: String, cur: Variant) -> void:
	## Wiersz przełącznika: etykieta i kilka płaskich przycisków (wybrany - złoty).
	_text(label, Vector2(x, y + 19), 14, CREAM, 0, false)
	var bw := minf(88.0, 260.0 / opts.size())
	for k in opts.size():
		var o: Array = opts[k]
		var active := false
		if typeof(o[1]) == TYPE_FLOAT:
			active = absf(float(o[1]) - float(cur)) < 0.01
		else:
			active = o[1] == cur
		_button(Rect2(x + 130 + k * (bw + 6.0), y, bw, 28), o[0], "opt", [key, o[1]], active, true, 12)


func _draw_menu() -> void:
	var vs := size
	_draw_backdrop(0.35)
	var p := Rect2(vs.x * 0.5 - 460, vs.y * 0.5 - 270, 920, 540)
	_panel(p)
	_text("WINGS OF EMPIRE", Vector2(p.get_center().x, p.position.y + 44), 30, GOLD, 1)
	var em0 := _emblem(0)
	var em1 := _emblem(1)
	if em0 != null:
		_draw_fit(em0, Rect2(p.position.x + 24, p.position.y + 12, 70, 62))
	if em1 != null:
		_draw_fit(em1, Rect2(p.end.x - 94, p.position.y + 12, 70, 62))
	_text("- game paused -", Vector2(p.get_center().x, p.position.y + 66), 12, DIM, 1, false)
	var tabs := ["Controls", "Statistics", "New Battle", "Multiplayer", "Settings"]
	for i in tabs.size():
		var soon := MP_COMING_SOON and i == 3 and not Net.active()
		_button(Rect2(p.position.x + 20 + i * 130, p.position.y + 82, 122, 30), "MP - soon" if soon else tabs[i], "menu_tab", i, menu_tab == i, not soon)
	var body := Rect2(p.position + Vector2(20, 120), Vector2(p.size.x - 40, p.size.y - 180))
	draw_rect(body, Color(0, 0, 0, 0.25))
	draw_rect(body, GOLD_DIM, false, 1.0)
	if menu_tab == 0:
		_draw_controls(body)
	elif menu_tab == 1:
		_draw_stats(body)
	elif menu_tab == 2:
		_draw_new_battle(body)
	elif menu_tab == 4:
		_draw_settings(body)
	elif MP_COMING_SOON and not Net.active():
		_text("MULTIPLAYER", Vector2(body.get_center().x, body.get_center().y - 14.0), 22, GOLD, 1, false)
		_text("Coming soon", Vector2(body.get_center().x, body.get_center().y + 16.0), 15, DIM, 1, false)
	else:
		_draw_multiplayer(body)
	var by := p.end.y - 48.0
	_button(Rect2(p.position.x + 20, by, 160, 34), "Resume  (Esc)", "resume")
	if menu_tab == 2 and not Net.is_client():
		_button(Rect2(p.get_center().x - 130, by - 2, 260, 38), "START BATTLE", "restart", null, true, true, 15)
	_button(Rect2(p.end.x - 270, by, 120, 34), "Main menu", "main_menu", null, false, not Net.active())
	_button(Rect2(p.end.x - 140, by, 120, 34), "Quit game", "quit")


func _lobby_sync() -> void:
	if Net.inst != null and Net.inst.role == Net.Role.HOST and not Net.inst.in_match:
		Net.inst._broadcast_lobby()


func _draw_multiplayer(body: Rect2) -> void:
	var net := Net.inst
	if net == null:
		return
	if net.role == Net.Role.NONE:
		_draw_mp_connect(body)
	else:
		_draw_mp_lobby(body)


func _draw_mp_connect(body: Rect2) -> void:
	## Przed połączeniem: imię, założenie gry albo dołączenie po adresie.
	var x0 := body.position.x + 16.0
	var w := body.size.x - 32.0
	var y := body.position.y + 26.0
	_text("TEAM BATTLES ONLINE  -  UP TO %d PLAYERS" % Net.MAX_PLAYERS, Vector2(x0, y), 12, GOLD, 0, false)
	y += 22.0
	_text("France against Britain. Each player commands his own regiments; allies share the treasury.", Vector2(x0, y), 13, CREAM, 0, false)
	y += 18.0
	_text("A side without human players is led by the AI - so you can also play together against the computer.", Vector2(x0, y), 13, CREAM, 0, false)
	y += 26.0
	_text("Your name:", Vector2(x0, y + 4), 13, CREAM, 0, false)
	_name_rect = Rect2(x0 + 90, y - 18, 220, 30)
	y += 26.0
	var hr := Rect2(x0, y, w * 0.5 - 8.0, 128)
	draw_rect(hr, Color(0, 0, 0, 0.22))
	draw_rect(hr, GOLD_DIM, false, 1.0)
	_text("HOST A GAME ON THIS PC", Vector2(hr.position.x + 12, hr.position.y + 22), 12, GOLD, 0, false)
	_text("%s  -  %s  -  %s" % [Battle.chosen_scenario, Battle.chosen_map, Battle.chosen_size], Vector2(hr.position.x + 12, hr.position.y + 42), 12, DIM, 0, false)
	_text("Your IP: %s" % ", ".join(Net.local_ips()), Vector2(hr.position.x + 12, hr.position.y + 60), 12, DIM, 0, false)
	_button(Rect2(hr.position.x + 12, hr.end.y - 44, 180, 32), "HOST GAME", "net_host", null, true)
	var jr := Rect2(x0 + w * 0.5 + 8.0, y, w * 0.5 - 8.0, 128)
	draw_rect(jr, Color(0, 0, 0, 0.22))
	draw_rect(jr, GOLD_DIM, false, 1.0)
	_text("JOIN A GAME OR SERVER", Vector2(jr.position.x + 12, jr.position.y + 22), 12, GOLD, 0, false)
	_text("Address (IP or IP:port):", Vector2(jr.position.x + 12, jr.position.y + 42), 12, DIM, 0, false)
	_ip_rect = Rect2(jr.position.x + 12, jr.position.y + 50, jr.size.x - 24, 30)
	_button(Rect2(jr.position.x + 12, jr.end.y - 44, 180, 32), "JOIN", "net_join", null, true)
	y += 142.0
	_text("Dedicated server (nobody has to host): run serwer.bat or ./graj.sh --server on any PC or VPS and everyone joins it.", Vector2(x0, y), 12, DIM, 0, false)
	y += 17.0
	_text("Over the internet open UDP port %d on the host/server, or use a VPN such as Radmin VPN / ZeroTier." % Net.PORT, Vector2(x0, y), 12, DIM, 0, false)
	if Net.inst.status != "":
		_text(Net.inst.status, Vector2(x0, y + 22), 13, GOLD, 0, false)


func _draw_mp_lobby(body: Rect2) -> void:
	## Lobby: gracze obu stron, zmiana strony, gotowość, start.
	var net := Net.inst
	var x0 := body.position.x + 16.0
	var w := body.size.x - 32.0
	var y := body.position.y + 26.0
	var me := Net.my_id()
	var host := net.role == Net.Role.HOST
	var st: Dictionary = net.settings
	_text("LOBBY  -  %d / %d PLAYERS" % [net.players.size(), Net.MAX_PLAYERS], Vector2(x0, y), 12, GOLD, 0, false)
	_text("%s  -  %s  -  %s" % [st.get("scenario", "?"), st.get("map", "?"), st.get("size", "?")], Vector2(x0 + w, y), 12, CREAM, 2, false)
	y += 14.0
	for team in 2:
		var nat := net.nation_of_team(team)
		var col := Rect2(x0 + team * (w * 0.5 + 8.0), y, w * 0.5 - 8.0, 196)
		draw_rect(col, Color(0, 0, 0, 0.25))
		draw_rect(col, Battle.TEAM_COLORS[nat].darkened(0.2), false, 1.5)
		var em := _ui_tex("%s_emblem.png" % Battle.NATION_DIRS[nat])
		if em != null:
			_draw_fit(em, Rect2(col.position + Vector2(8, 6), Vector2(28, 26)))
		_text(Battle.NATIONS[nat].to_upper(), Vector2(col.position.x + 44, col.position.y + 25), 14, CREAM, 0, false)
		var py := col.position.y + 52.0
		var any := false
		var ids: Array = net.players.keys()
		ids.sort()
		for id in ids:
			var p: Dictionary = net.players[id]
			if int(p["team"]) != team:
				continue
			any = true
			var line := "%s%s" % [p["name"], "  (you)" if id == me else ""]
			if id == 1 and not net.dedicated and host:
				line += "  - host"
			_text(line, Vector2(col.position.x + 14, py), 14, GOLD if id == me else CREAM, 0, false)
			var ready_ok: bool = p["ready"]
			_text("ready" if ready_ok else "not ready", Vector2(col.end.x - 12, py), 12, GOOD if ready_ok else DIM, 2, false)
			py += 21.0
		if not any:
			_text("(AI)", Vector2(col.position.x + 14, py), 13, DIM, 0, false)
		var mine: Dictionary = net.players.get(me, {})
		if not net.in_match and net.role == Net.Role.CLIENT and (mine.is_empty() or int(mine.get("team", 0)) != team):
			_button(Rect2(col.position.x + 12, col.end.y - 40, 160, 30), "Join %s" % Battle.NATIONS[nat], "net_side", team)
	y += 210.0
	if net.status != "":
		_text(net.status, Vector2(x0, y), 13, GOOD if net.in_match else GOLD, 0, false)
	var by := body.end.y - 46.0
	if not net.in_match:
		if net.role == Net.Role.CLIENT:
			var mine2: Dictionary = net.players.get(me, {})
			var rd: bool = mine2.get("ready", false)
			_button(Rect2(x0, by, 180, 34), "Not ready" if rd else "READY", "net_ready", not rd, not rd)
			_text("The battle starts when the host launches it" + (" or everyone is ready." if true else "."), Vector2(x0 + 196, by + 22), 12, DIM, 0, false)
		elif host and not net.dedicated:
			_button(Rect2(x0, by, 220, 34), "START BATTLE", "net_start", null, net.players.size() > 1, net.players.size() > 1)
			_text("Settings come from the New Battle tab.", Vector2(x0 + 236, by + 22), 12, DIM, 0, false)
	_button(Rect2(body.end.x - 196, by, 180, 34), "Leave", "net_stop")


func _draw_new_battle(body: Rect2) -> void:
	## Ekran bitwy własnej jak w grach strategicznych: po lewej kilka wierszy ustawień ze strzałkami < >,
	## po prawej karta odprawy (strony, scenariusz, teatr wojny, teren) - zamiast siatki wszystkich opcji naraz.
	var split := body.position.x + body.size.x * 0.55
	var x0 := body.position.x + 18.0
	var row_w := split - x0 - 16.0
	var rows := [
		["YOUR NATION", "you", Battle.NATIONS[int(Battle.side_nation[0])]],
		["ENEMY", "enemy", Battle.NATIONS[int(Battle.side_nation[1])]],
		["BATTLE", "scenario", Battle.chosen_scenario],
		["TERRAIN", "map", Battle.chosen_map],
		["THEATRE", "theme", Battle.chosen_theme],
		["MAP SIZE", "size", Battle.chosen_size],
	]
	var rh := minf(58.0, (body.size.y - 24.0) / rows.size())
	var y := body.position.y + 14.0
	var mouse := _mouse()
	for row in rows:
		var r := Rect2(x0, y, row_w, rh - 8.0)
		var hov := r.has_point(mouse)
		draw_rect(r, Color(1, 1, 1, 0.05) if hov else Color(0, 0, 0, 0.18))
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), GOLD if hov else GOLD_DIM)
		_text(row[0], Vector2(r.position.x + 14, r.get_center().y + 4), 12, GOLD, 0, false)
		var vx := r.position.x + 150.0
		var vw := r.end.x - vx - 8.0
		var ab := Vector2(34, r.size.y - 12.0)
		_button(Rect2(Vector2(vx, r.position.y + 6.0), ab), "<", "cycle", [row[1], -1], false, true, 15)
		_button(Rect2(Vector2(r.end.x - 8.0 - ab.x, r.position.y + 6.0), ab), ">", "cycle", [row[1], 1], false, true, 15)
		var val_r := Rect2(vx + ab.x + 6.0, r.position.y + 6.0, vw - ab.x * 2.0 - 12.0, ab.y)
		_button(val_r, "", "cycle", [row[1], 1], false, true, 14)
		var label: String = row[2]
		if row[1] == "you" or row[1] == "enemy":
			var nat := int(Battle.side_nation[0 if row[1] == "you" else 1])
			_draw_nation_flag(Rect2(val_r.position + Vector2(14, val_r.size.y * 0.5 - 8), Vector2(32, 16)), nat)
		_text(_fit(label.to_upper(), 14, val_r.size.x - 56.0), val_r.get_center() + Vector2(6, 5), 14, CREAM, 1, false)   # Cinzel jak na przyciskach
		y += rh
	# --- karta odprawy
	var card := Rect2(split, body.position.y + 14.0, body.end.x - split - 16.0, body.size.y - 28.0)
	draw_rect(card, Color(0, 0, 0, 0.3))
	draw_rect(card, GOLD_DIM, false, 1.0)
	var cx := card.get_center().x
	var ey := card.position.y + 18.0
	for side in 2:
		var nat := int(Battle.side_nation[side])
		var em := _ui_tex("%s_emblem.png" % Battle.NATION_DIRS[nat])
		var box := Rect2(Vector2(cx + (-164.0 if side == 0 else 60.0), ey + 10), Vector2(104, 52))
		_draw_nation_flag(box, nat)
		if em != null:
			_draw_fit(em, Rect2(box.end - Vector2(26, 26), Vector2(34, 34)), Color(1, 1, 1, 0.95))
		_text(Battle.NATIONS[nat].to_upper(), Vector2(box.get_center().x, box.end.y + 26), 14, CREAM, 1, false)
	_text("VS", Vector2(cx, ey + 44), 22, GOLD, 1)
	var ty := ey + 130.0
	draw_line(Vector2(card.position.x + 20, ty - 14), Vector2(card.end.x - 20, ty - 14), GOLD_DIM, 1.0)
	_diamond(Vector2(cx, ty - 14), 3.0, GOLD)
	_text(Battle.chosen_scenario.to_upper(), Vector2(cx, ty + 6), 18, GOLD, 1)
	var sdesc: String = Battle.SCENARIOS[Battle.chosen_scenario]["desc"]
	_text_wrap(sdesc, Rect2(card.position.x + 20, ty + 18, card.size.x - 40, 50), 12, CREAM)
	var tdesc := "A different theatre of war every battle."
	if Terrain.THEMES.has(Battle.chosen_theme):
		tdesc = Terrain.THEMES[Battle.chosen_theme]["desc"]
	var mdesc := "A different landscape every battle."
	if Terrain.MAP_TYPES.has(Battle.chosen_map):
		mdesc = Terrain.MAP_TYPES[Battle.chosen_map]["desc"]
	var iy := ty + 78.0
	_text("THEATRE", Vector2(card.position.x + 20, iy), 11, GOLD, 0, false)
	_text_wrap(tdesc, Rect2(card.position.x + 20, iy + 8, card.size.x - 40, 40), 12, DIM)
	_text("TERRAIN", Vector2(card.position.x + 20, iy + 68), 11, GOLD, 0, false)
	_text_wrap(mdesc, Rect2(card.position.x + 20, iy + 76, card.size.x - 40, 40), 12, DIM)
	_text("%s map" % Battle.chosen_size, Vector2(cx, card.end.y - 14), 11, DIM, 1, false)


func _draw_nation_flag(r: Rect2, nat: int, wave := true) -> void:
	## Flaga narodowa w pikselach (te same barwy co sztandary w bitwie), lekko falująca, z drzewcem.
	const C := 48   # gęsta siatka: detale flag (np. przesunięty krzyż na Union Flag) muszą być widoczne
	const R := 24
	var cw := r.size.x / C
	var ch := r.size.y / R
	var t := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(r.position + Vector2(-3, -2), Vector2(2, r.size.y + 8)), Color(0.35, 0.25, 0.13))
	draw_rect(Rect2(r.position + Vector2(-4, -4), Vector2(4, 3)), Color(0.92, 0.75, 0.28))
	for cx in C:
		var u := (cx + 0.5) / C
		var dy := roundf(sin(t * 2.4 - u * 9.0) * 1.6 * u) if wave else 0.0
		var shade := 1.0 + (roundf(cos(t * 2.4 - u * 9.0) * u * 2.0) * 0.07 if wave else 0.0)
		for ry in R:
			var v := (ry + 0.5) / R
			var col := Regiment._flag_color(nat, u, v)
			draw_rect(Rect2(r.position + Vector2(cx * cw, ry * ch + dy), Vector2(cw + 0.5, ch + 0.5)), Color(col * shade, 1.0))


func _cycle_setting(field: String, step: int) -> void:
	## Strzałki < > w ekranie bitwy własnej: następna / poprzednia wartość ustawienia (z zawijaniem).
	match field:
		"you", "enemy":
			var row := 0 if field == "you" else 1
			var n := Battle.NATIONS.size()
			var nat := int(Battle.side_nation[row])
			for k in n:
				nat = posmod(nat + step, n)
				if nat != int(Battle.side_nation[1 - row]):
					break
			Battle.side_nation[row] = nat
		"scenario":
			Battle.chosen_scenario = _cycled(Battle.SCENARIO_ORDER, Battle.chosen_scenario, step)
		"map":
			Battle.chosen_map = _cycled(Terrain.MAP_TYPE_ORDER, Battle.chosen_map, step)
		"theme":
			Battle.chosen_theme = _cycled(Terrain.THEME_ORDER, Battle.chosen_theme, step)
		"size":
			Battle.chosen_size = _cycled(Battle.MAP_SIZE_ORDER, Battle.chosen_size, step)
	_lobby_sync()


static func _cycled(list: Array, cur: String, step: int) -> String:
	var i := list.find(cur)
	return list[posmod((i if i >= 0 else 0) + step, list.size())]


func _draw_controls(body: Rect2) -> void:
	var col_w := body.size.x * 0.5
	var x := body.position.x + 14.0
	var y := body.position.y + 22.0
	var col := 0
	for group in CONTROLS:
		var rows: Array = group[1]
		if col == 0 and y + 26 + rows.size() * 17 > body.end.y and x < body.position.x + col_w:
			x += col_w
			y = body.position.y + 22.0
			col = 1
		_text(group[0].to_upper(), Vector2(x, y), 12, GOLD, 0, false)
		y += 18.0
		for row in rows:
			_text(row[0], Vector2(x, y), 11, CREAM, 0, false)
			_text(_fit(row[1], 11, col_w - 148), Vector2(x + 132, y), 11, DIM, 0, false)
			y += 17.0
		y += 10.0


func _draw_stats(body: Rect2) -> void:
	var st: Dictionary = battle.stats
	var men := [0, 0]
	var regs := [0, 0]
	for r in battle.regiments:
		men[r.team] += r.alive_count()
		regs[r.team] += 1
	var held := [0, 0]
	for s in battle.settlements:
		if s.faction >= 0:
			held[s.faction] += 1
	var rows := [
		["Soldiers in the field", men[0], men[1]],
		["Regiments", regs[0], regs[1]],
		["Largest army", st["peak_men"][0], st["peak_men"][1]],
		["Enemy soldiers killed", st["kills"][0], st["kills"][1]],
		["Own losses", st["losses"][0], st["losses"][1]],
		["   of which drowned", st["drowned"][0], st["drowned"][1]],
		["Enemies taken prisoner", st["prisoners"][0], st["prisoners"][1]],
		["Settlements held", held[0], held[1]],
		["Settlements captured", st["captured"][0], st["captured"][1]],
		["Regiments raised", st["recruited"][0], st["recruited"][1]],
		["Gold in treasury", int(battle.gold[0]), int(battle.gold[1])],
		["Gold earned", int(st["earned"][0]), int(st["earned"][1])],
		["Gold spent on recruits", int(st["spent"][0]), int(st["spent"][1])],
		["Income per minute", int(battle.income[0] * 60.0), int(battle.income[1] * 60.0)],
		["Upkeep per minute", int(battle.upkeep[0] * 60.0), int(battle.upkeep[1] * 60.0)],
	]
	var x0 := body.position.x + 20.0
	var c1 := body.position.x + body.size.x * 0.62
	var c2 := body.position.x + body.size.x * 0.86
	var y := body.position.y + 26.0
	_text("YOU", Vector2(c1, y), 12, Battle.owner_color(0).lightened(0.3), 2, false)
	_text("ENEMY", Vector2(c2, y), 12, Battle.owner_color(1).lightened(0.3), 2, false)
	var secs := int(battle.sim_time)
	_text("Battle time %02d:%02d" % [secs / 60, secs % 60], Vector2(x0, y), 12, GOLD, 0, false)
	y += 10.0
	for i in rows.size():
		var row: Array = rows[i]
		y += 19.0
		if i % 2 == 0:
			draw_rect(Rect2(body.position.x + 8, y - 14, body.size.x - 16, 19), Color(1, 1, 1, 0.03))
		_text(row[0], Vector2(x0, y), 12, CREAM, 0, false)
		var a: int = row[1]
		var b: int = row[2]
		_text(str(a), Vector2(c1, y), 12, CREAM, 2, false)
		_text(str(b), Vector2(c2, y), 12, CREAM, 2, false)


func _draw_result() -> void:
	var vs := size
	_draw_backdrop(0.3)
	var p := Rect2(vs.x * 0.5 - 400, vs.y * 0.5 - 250, 800, 520)
	_panel(p)
	var win := battle.result_text == "VICTORY"
	var em := _emblem(0 if win else 1)
	if em != null:
		_draw_fit(em, Rect2(p.get_center().x - 40, p.position.y - 70, 80, 80))
	_text(battle.result_text, Vector2(p.get_center().x, p.position.y + 62), 48, GOLD if win else BAD, 1)
	var sub := "The enemy has lost all its towns." if win else "Your last town has fallen."
	if Battle.is_field():
		sub = "The enemy army is destroyed or in flight." if win else "Your army is destroyed or in flight."
	if battle.result_text == "DISCONNECTED":
		sub = "The connection to the host was lost."
	_text(sub, Vector2(p.get_center().x, p.position.y + 90), 14, CREAM, 1, false)
	draw_line(Vector2(p.position.x + 24, p.position.y + 108), Vector2(p.end.x - 24, p.position.y + 108), GOLD_DIM, 1.0)

	# --- tabela: obie strony obok siebie
	var st: Dictionary = battle.stats
	var hist: Array = battle.stats_hist
	var men := [0, 0]
	for r in battle.regiments:
		if not r.dead and r.team >= 0 and r.team < 2:
			men[r.team] += r.alive_count()
	var start := [men[0], men[1]]
	if not hist.is_empty():
		start = [int(hist[0][1]), int(hist[0][2])]
	var rows := [
		["Soldiers at the start", start[0], start[1]],
		["Largest army", maxi(st["peak_men"][0], start[0]), maxi(st["peak_men"][1], start[1])],
		["Soldiers still standing", men[0], men[1]],
		["Killed, wounded and fled", st["losses"][0], st["losses"][1]],
		["   of which drowned", st["drowned"][0], st["drowned"][1]],
		["Enemy soldiers killed", st["kills"][0], st["kills"][1]],
		["Enemies taken prisoner", st["prisoners"][0], st["prisoners"][1]],
	]
	if not Battle.is_field():
		rows.append(["Settlements captured", st["captured"][0], st["captured"][1]])
		rows.append(["Regiments raised", st["recruited"][0], st["recruited"][1]])
	var col_you := Battle.owner_color(0).lightened(0.35)
	var col_foe := Battle.owner_color(1).lightened(0.3)
	var tx := p.position.x + 28.0
	var c1 := p.position.x + 268.0
	var c2 := p.position.x + 338.0
	var y := p.position.y + 134.0
	var secs := int(battle.sim_time)
	_text("Battle time %02d:%02d" % [secs / 60, secs % 60], Vector2(tx, y), 12, GOLD, 0, false)
	_text("YOU", Vector2(c1, y), 12, col_you, 2, false)
	_text("ENEMY", Vector2(c2, y), 12, col_foe, 2, false)
	y += 8.0
	for i in rows.size():
		var row: Array = rows[i]
		y += 21.0
		if i % 2 == 0:
			draw_rect(Rect2(tx - 8, y - 15, c2 - tx + 16, 21), Color(1, 1, 1, 0.03))
		_text(row[0], Vector2(tx, y), 12, CREAM, 0, false)
		_text(str(row[1]), Vector2(c1, y), 12, CREAM, 2, false)
		_text(str(row[2]), Vector2(c2, y), 12, CREAM, 2, false)

	# --- wykresy przebiegu bitwy
	var gx := p.position.x + 384.0
	var gw := p.end.x - 28.0 - gx
	_draw_history_chart(Rect2(gx, p.position.y + 124, gw, 138), "SOLDIERS IN THE FIELD", 1, 2, col_you, col_foe)
	_draw_history_chart(Rect2(gx, p.position.y + 286, gw, 138), "LOSSES OVER TIME", 3, 4, col_you, col_foe)

	var by := p.end.y - 56.0
	if win and not Net.active():
		# po zwycięstwie można zostać na polu bitwy (dobić uciekających, obejrzeć pole) albo wyjść
		_button(Rect2(p.get_center().x - 240, by, 114, 36), "Continue", "result_continue", null, true)
		_button(Rect2(p.get_center().x - 120, by, 114, 36), "New battle", "restart")
		_button(Rect2(p.get_center().x, by, 114, 36), "Main menu", "result_menu")
		_button(Rect2(p.get_center().x + 120, by, 114, 36), "Quit", "quit")
	else:
		_button(Rect2(p.get_center().x - 230, by, 145, 36), "New battle", "restart")
		_button(Rect2(p.get_center().x - 72, by, 145, 36), "Main menu", "result_menu", null, false, not Net.active())
		_button(Rect2(p.get_center().x + 86, by, 145, 36), "Quit", "quit")


func _draw_history_chart(r: Rect2, title: String, ia: int, ib: int, ca: Color, cb: Color) -> void:
	## Wykres liniowy dwóch stron w czasie bitwy (kolumny `ia`, `ib` z battle.stats_hist).
	_text(title, Vector2(r.position.x, r.position.y + 11), 11, GOLD, 0, false)
	var plot := Rect2(r.position.x + 34, r.position.y + 20, r.size.x - 34, r.size.y - 38)
	draw_rect(plot, Color(0, 0, 0, 0.28))
	draw_rect(plot, Color(GOLD_DIM, 0.5), false, 1.0)
	var hist: Array = battle.stats_hist
	if hist.size() < 2:
		_text("The battle was too short to chart.", plot.get_center() + Vector2(0, 4), 11, DIM, 1, false)
		return
	var t0: float = hist[0][0]
	var t1: float = hist[hist.size() - 1][0]
	var top := 1.0
	for h in hist:
		top = maxf(top, maxf(float(h[ia]), float(h[ib])))
	# okrągła górna wartość osi
	var unit := pow(10.0, floorf(log(top) / log(10.0)))
	var nice := ceilf(top / unit) * unit
	if nice / unit <= 2.0 and unit >= 10.0:
		nice = ceilf(top / (unit * 0.2)) * unit * 0.2
	for k in 3:
		var gy := plot.position.y + plot.size.y * k / 2.0
		if k > 0:
			draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), Color(1, 1, 1, 0.06), 1.0)
		_text(str(int(nice * (2 - k) / 2.0)), Vector2(plot.position.x - 5, gy + 4), 10, DIM, 2, false)
	var span := maxf(t1 - t0, 0.001)
	for series in [[ib, cb], [ia, ca]]:
		var pts := PackedVector2Array()
		for h in hist:
			pts.append(Vector2(plot.position.x + (float(h[0]) - t0) / span * plot.size.x,
				plot.end.y - float(h[series[0]]) / nice * plot.size.y))
		draw_polyline(pts, series[1], 2.0, true)
		draw_circle(pts[pts.size() - 1], 2.5, series[1])
	var s1 := int(t1)
	_text("0:00", Vector2(plot.position.x, plot.end.y + 13), 10, DIM, 0, false)
	_text("%d:%02d" % [s1 / 60, s1 % 60], Vector2(plot.end.x, plot.end.y + 13), 10, DIM, 2, false)
	# legenda w prawym górnym rogu nagłówka
	var lx := r.end.x
	_text("ENEMY", Vector2(lx, r.position.y + 11), 10, cb, 2, false)
	lx -= _tw("ENEMY", 10) + 8.0
	draw_line(Vector2(lx - 14, r.position.y + 7), Vector2(lx, r.position.y + 7), cb, 2.0)
	lx -= 26.0
	_text("YOU", Vector2(lx, r.position.y + 11), 10, ca, 2, false)
	lx -= _tw("YOU", 10) + 8.0
	draw_line(Vector2(lx - 14, r.position.y + 7), Vector2(lx, r.position.y + 7), ca, 2.0)


# ================================================================== znaczniki na mapie

func _ghost_formation(xf: Transform2D, r: Regiment, pos: Vector2, f: float, files: int, col: Color) -> void:
	var n := r.alive_count()
	var z := xf.get_scale().x
	var fwd := Vector2.from_angle(f)
	var dot := maxf(Regiment.SOLDIER_RADIUS * z * 0.85, 1.4)
	for i in n:
		var wp := r.preview_slot(i, n, pos, f, files)   # ten sam szyk, w jakim pułk stanie (linia / klin / czworobok)
		var sp := xf * wp
		draw_circle(sp, dot, Color(col, col.a * 0.6))
		if z > 0.8:
			draw_line(sp, sp + xf.basis_xform(fwd) * 6.0, Color(col, col.a * 0.45), maxf(z * 0.6, 1.0))


# Pikselowe ikonki osad (1 znak = 1 piksel ikony). Kolory: o obrys, y strzecha, Y jasna strzecha, c komin,
# w tynk, b okno, d drzwi/brama, g ziemia, k kamień jasny, K kamień ciemny, s łupek, S jasny łupek, x krzyż.
const ICON_VILLAGE := [
	"......oo.....",
	"....ooYYoocc.",
	"...oYYyyyocc.",
	"..oYYyyyyyyo.",
	".oYyyyyyyyyyo",
	"oyyyyyyyyyyyo",
	".owwwwwwwwwo.",
	".owbbwwwbbwo.",
	".owbbwddwwwo.",
	".owwwwddwwwo.",
	"ggggggddggggg",
]
const ICON_CITY := [
	"........x........",
	".......oso.......",
	".......sSs.......",
	"o.o.o.osSso.o.o.o",
	"ooooo.osSso.ooooo",
	"okkko.oKkKo.okkko",
	"okbko.oKbKo.okbko",
	"okkkooooooooookko",
	"okkkoKkKkKkKokkko",
	"okkkokKkKkKkokkko",
	"okbkoKkddKkKokbko",
	"okkkokkdddkkokkko",
	"ooooooodddooooooo",
]


var _site_icons := {}   # gotowe tekstury ikon osad: "miasto|kolor" -> ImageTexture


func _draw_settlement_icon(c: Vector2, city: bool, oc: Color, a: float, sel: bool) -> void:
	## Pikselowa ikonka osady na okrągłej tarczy w barwach właściciela + chorągiewka.
	var art: Array = ICON_CITY if city else ICON_VILLAGE
	const PX := 3.0
	var w := float((art[0] as String).length()) * PX
	var h := float(art.size()) * PX
	var rad := maxi(int((maxf(w, h) * 0.5 + 6.0) / PX), 8)
	# Ikonka trzyma się swojego punktu na mapie co do piksela (bez przyciągania do grubej siatki - przez nie
	# przy zoomie skakała po 3 piksele), a tarcza z rysunkiem to jedna gotowa tekstura zamiast setek prostokątów.
	var center := c.round()
	var key := "%d|%s" % [int(city), oc.to_html(false)]
	if not _site_icons.has(key):
		var n := rad * 2 + 1
		var img := Image.create(n * int(PX), n * int(PX), false, Image.FORMAT_RGBA8)
		for yy in range(-rad, rad + 1):
			for xx in range(-rad, rad + 1):
				var d := Vector2(xx, yy).length()
				if d <= rad:
					var col := oc.darkened(0.45) if d > rad - 1.2 else oc.darkened(0.08 if yy < 0 else 0.2)
					img.fill_rect(Rect2i((xx + rad) * int(PX), (yy + rad) * int(PX), int(PX), int(PX)), Color(col, 0.92))
		var pal := {
			"o": Color(0.12, 0.09, 0.07), "y": Color(0.72, 0.58, 0.30), "Y": Color(0.88, 0.74, 0.42),
			"c": Color(0.45, 0.28, 0.22), "w": Color(0.90, 0.86, 0.74), "b": Color(0.20, 0.24, 0.32),
			"d": Color(0.38, 0.24, 0.13), "g": Color(0.30, 0.45, 0.20), "k": Color(0.74, 0.71, 0.64),
			"K": Color(0.56, 0.53, 0.48), "s": Color(0.36, 0.38, 0.44), "S": Color(0.55, 0.58, 0.66),
			"x": Color(0.92, 0.78, 0.35),
		}
		var ox := rad - int(w * 0.5 / PX)
		var oy := rad - int(h * 0.5 / PX)
		for yy in art.size():
			var row: String = art[yy]
			for xx in row.length():
				var ch := row[xx]
				if ch != ".":
					img.fill_rect(Rect2i((ox + xx) * int(PX), (oy + yy) * int(PX), int(PX), int(PX)), pal.get(ch, Color.MAGENTA))
		_site_icons[key] = ImageTexture.create_from_image(img)
	draw_texture(_site_icons[key], center - Vector2(rad, rad) * PX, Color(1, 1, 1, a))
	if sel:
		draw_arc(center + Vector2(PX, PX) * 0.5, (rad + 1.5) * PX, 0, TAU, 48, Color(GOLD, a), 2.0)
	var origin := center - (Vector2(w, h) * 0.5 / PX).floor() * PX
	# chorągiewka właściciela nad dachem / wieżą
	var pole := origin + Vector2((8.0 if city else 6.0) * PX, -PX * (2.0 if city else 1.0))
	draw_rect(Rect2(pole, Vector2(PX * 0.67, PX * 5.0)), Color(0.25, 0.17, 0.09, a))
	for fy in 3:
		for fx in 4:
			var fc := oc.lightened(0.1) if (fx + fy) % 2 == 0 else oc
			draw_rect(Rect2(pole + Vector2(PX * 0.67 + fx * PX * 0.9, fy * PX * 0.75 + sin(battle.sim_time * 4.0 + fx) * 0.8), Vector2(PX * 0.9, PX * 0.75)), Color(fc, a))


func _draw_settlement(s: Settlement, xf: Transform2D) -> void:
	var sp := xf * s.position
	if not get_rect().grow(120).has_point(sp):
		return
	var z := battle.cam.zoom.x
	var oc := Battle.owner_color(s.faction)
	var sel := s == battle.selected_settlement
	var rad := s.radius * z
	if sel or battle.show_all or s.capture > 0.0:
		draw_arc(sp, rad, 0, TAU, 64, Color(oc, 0.5), 1.5)
	if s.capture > 0.0 and s.capture_team >= 0:
		var cc := Battle.owner_color(s.capture_team)
		draw_arc(sp, maxf(rad, 18.0) + 4.0, -PI * 0.5, -PI * 0.5 + TAU * s.capture, 48, cc, 4.0)
	var a := battle.icon_alpha
	if a > 0.01:
		_draw_settlement_icon(sp, s.is_city, oc, a, sel)
	var label_a := maxf(a, 0.85)
	var lift := 24.0 if a > 0.5 else (s.radius * z * 0.75 + 10.0)
	var title := s.s_name
	if s.contested:
		title += "  (fighting)"
	_text(title, sp + Vector2(0, lift + 4.0), 14 if s.is_city else 12, Color(CREAM, label_a), 1)
	_text("+%d/min" % int(s.income * 60.0), sp + Vector2(0, lift + 18.0), 10, Color(GOLD, label_a * 0.85), 1)


func _draw_orders(r: Regiment, xf: Transform2D) -> void:
	var show := r.selected or battle.show_all
	# Strzałki rozkazów: pełne krycie i jasny, nasycony kolor strony na ciemnym obrysie - czytelne na trawie,
	# polach, śniegu i piasku. Rozkazy niezaznaczonych pułków są cieńsze i lekko przygaszone, ale nadal widoczne.
	var a := 1.0 if show else 0.62
	var tc := r.color.lightened(0.45)
	tc.s = minf(1.0, tc.s * 1.15)
	if r.state == Regiment.State.MOVING:
		var prev := xf * r.anchor()
		var pts: Array[Vector2] = r.waypoints if not r.waypoints.is_empty() else [r.move_target]
		var w := (3.0 if show else 2.0) + (0.6 if r.march_mode else 0.0)
		for k in pts.size():
			var nxt := xf * pts[k]
			if k == pts.size() - 1:
				_arrow(prev, nxt, Color(tc, a), w)
			else:
				_line_out(prev, nxt, Color(tc, a), w)
			prev = nxt
		if show:
			var fl := r._pending_files if r._pending_files > 0 else r.base_files
			_ghost_formation(xf, r, r.final_target(), r._final_facing if r.waypoints.size() > 0 else r.move_facing, fl, Color(tc.lightened(0.3), a))
	elif r.state == Regiment.State.CHARGING and r.attack_target != null:
		# szarża: gruba strzałka w kolorze oddziału z czerwonym grotem
		var from := xf * r.anchor()
		var to := xf * r.attack_target.centroid()
		_arrow(from, to, Color(tc, minf(1.0, a + 0.15)), 4.0 if show else 3.0)
		var dir := (to - from).normalized()
		draw_colored_polygon(PackedVector2Array([to, to - dir * 9.0 + dir.orthogonal() * 4.0, to - dir * 9.0 - dir.orthogonal() * 4.0]),
			Color(1, 0.25, 0.15, minf(1.0, a + 0.15)))
	elif show and r.state == Regiment.State.IDLE and r.fire_target != null:
		# ogień: przerywana linia w kolorze oddziału
		var from := xf * r.center
		var to := xf * r.fire_target.center
		var d := to - from
		var segs := int(d.length() / 14.0)
		for k in range(0, segs - 1, 2):
			_line_out(from + d * (float(k) / segs), from + d * (float(k + 1) / segs), Color(tc, 0.95), 2.0)
		_arrow(from + d * (float(maxi(segs - 1, 0)) / maxf(segs, 1)), to, Color(tc, 0.95), 2.0)


func _draw_drag_preview(xf: Transform2D) -> void:
	if not battle.form_active:
		return
	for plan in battle.plan_move(battle.order_start, battle.order_drag_now, true):
		_ghost_formation(xf, plan[0], plan[1], plan[2], plan[3], Color(0.6, 1.0, 0.6, 0.95))


func _draw_fire_fx(c: Vector2, dir: Vector2, t: float, big: bool, a: float, seed_t: float) -> void:
	## Pikselowa animacja wystrzału przy portrecie: błysk z lufy (krzyżyk i iskry), potem kłęby dymu
	## rosnące i dryfujące z wiatrem, gasnące. Wszystko na siatce 3-pikselowych kratek (styl pixel-art).
	const PX := 3.0
	var sc := 1.5 if big else 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_t * 1000.0)
	var side := dir.orthogonal()
	var snap := func(v: Vector2) -> Vector2: return (v / PX).floor() * PX
	# dym: 5 kłębów, każdy z kilku kratek, rośnie i przesuwa się w kierunku strzału i lekko w górę
	var smoke_t := clampf(t / 1.1, 0.0, 1.0)
	for k in 5:
		var off := dir * (4.0 + k * 3.5 + smoke_t * 14.0) * sc + side * rng.randf_range(-5, 5) * sc + Vector2(0, -smoke_t * 8.0)
		var rad := (2.0 + smoke_t * 4.0 + rng.randf() * 2.0) * sc
		var g := 0.93 - k * 0.04
		var al := (1.0 - smoke_t) * 0.75 * a * clampf(t / 0.1, 0.0, 1.0)
		for yy in range(-int(rad / PX), int(rad / PX) + 1):
			for xx in range(-int(rad / PX), int(rad / PX) + 1):
				if Vector2(xx, yy).length() * PX <= rad:
					var q: Vector2 = snap.call(c + off + Vector2(xx, yy) * PX)
					var shade := g - 0.08 * float(yy > 0)
					draw_rect(Rect2(q, Vector2(PX, PX)), Color(shade, shade, shade * 0.97, al))
	# błysk: pierwsze ~0.15 s - jasny rdzeń, ramiona krzyża i iskry
	if t < 0.16:
		var f := 1.0 - t / 0.16
		var core: Vector2 = snap.call(c)
		var arm := int((2 + 3 * f) * sc)
		for k in range(-arm, arm + 1):
			var hot := Color(1.0, 0.95, 0.7, f * a) if absi(k) < 2 else Color(1.0, 0.65, 0.2, f * a)
			draw_rect(Rect2(core + snap.call(dir * k * PX), Vector2(PX, PX)), hot)
			if absi(k) <= arm / 2:
				draw_rect(Rect2(core + snap.call(side * k * PX), Vector2(PX, PX)), hot)
		for k in 6:
			var sp2: Vector2 = snap.call(c + (dir * rng.randf_range(4, 14) + side * rng.randf_range(-7, 7)) * sc * (1.2 - f))
			draw_rect(Rect2(sp2, Vector2(PX, PX)), Color(1.0, 0.8, 0.3, f * a))


func card_screen_pos(r: Regiment) -> Vector2:
	## Gdzie na ekranie stoi karta z portretem pułku - wspólne dla rysowania i klikania (przy każdym zoomie).
	# karta stoi dokładnie na środku faktycznych pozycji żołnierzy (przy każdym zoomie)
	var n := r.s_pos.size()
	if n == 0:
		return battle.world_to_screen(r.center)
	var step := maxi(1, n / 32)
	var sum := Vector2.ZERO
	var cnt := 0
	for k in range(0, n, step):
		sum += r.s_pos[k]
		cnt += 1
	return battle.world_to_screen(sum / cnt)


func _crossed_sabres(c: Vector2, a: float) -> void:
	## Znak walki wręcz: dwie skrzyżowane szable - zakrzywione stalowe głownie, mosiężne jelce, ciemne rękojeści.
	var steel := Color(0.90, 0.92, 0.96, a)
	var edge := Color(0.08, 0.06, 0.05, a)
	var brass := Color(0.92, 0.74, 0.30, a)
	var grip := Color(0.30, 0.16, 0.10, a)
	draw_circle(c, 13.0, Color(0.55, 0.08, 0.06, 0.55 * a))   # czerwone tło, żeby znak odcinał się od mapy
	for sgn in [-1.0, 1.0]:
		# szabla od rękojeści (na dole) do sztychu (u góry), wygięta na zewnątrz
		var hilt: Vector2 = c + Vector2(-8.0 * sgn, 9.0)
		var tip: Vector2 = c + Vector2(9.0 * sgn, -10.0)
		var dir: Vector2 = (tip - hilt).normalized()
		var nrm: Vector2 = Vector2(-dir.y, dir.x) * sgn
		var guard: Vector2 = hilt + dir * 4.5
		var blade := PackedVector2Array()
		for k in 9:
			var u := float(k) / 8.0
			blade.append(guard.lerp(tip, u) + nrm * sin(u * PI) * -2.6)
		draw_polyline(blade, edge, 4.2, true)
		draw_polyline(blade, steel, 2.2, true)
		draw_line(hilt, guard, edge, 4.4, true)
		draw_line(hilt, guard, grip, 2.4, true)
		draw_line(guard - nrm * 3.6, guard + nrm * 3.6, edge, 3.6, true)
		draw_line(guard - nrm * 3.2, guard + nrm * 3.2, brass, 2.0, true)
		draw_circle(hilt, 1.7, brass)


func _draw_icon(r: Regiment, xf: Transform2D, t: float) -> void:
	var a := maxf(battle.icon_alpha, 0.9)
	var sp := card_screen_pos(r)
	if not get_rect().grow(80).has_point(sp):
		return
	var col := r.color
	var ally := Net.active() and r.team == 0 and r.commander != Net.my_id()
	if ally:
		col = col.lerp(Color.WHITE, 0.35)
	var routing := r.state == Regiment.State.ROUTING
	if routing:
		col = col.lerp(Color.WHITE, 0.35 + 0.35 * sin(t * 10.0))
	var portrait := _unit_portrait(r.unit_key, r.team, r.reg_name.hash())
	_draw_unit_card(r, sp, portrait, col, a)
	var since := battle.sim_time - r.last_fire_time
	if since < 1.1:
		_draw_fire_fx(sp + xf.basis_xform(r.forward()).normalized() * 26.0, xf.basis_xform(r.forward()).normalized(), since, r.kind == "art", a, r.last_fire_time)
	if r.state == Regiment.State.MELEE:
		_crossed_sabres(sp + Vector2(0, -32), a)
	if r.in_water_ratio > 0.2:
		draw_arc(sp, 26.0, 0, TAU, 24, Color(0.5, 0.75, 1.0, a), 2.0)
	var y := sp.y + CARD.y * 0.5 + 5.0
	draw_rect(Rect2(sp.x - 18, y - 1, 36, 10), Color(0, 0, 0, 0.6 * a))
	draw_rect(Rect2(sp.x - 17, y, 34.0 * r.health_frac(), 3.5), Color(GOOD, a))
	draw_rect(Rect2(sp.x - 17, y + 4.5, 34.0 * r.morale / 100.0, 3.5), Color(MORALE, a))
	if battle.cam.zoom.x > 0.2 or r.selected:
		var label := r.reg_name
		if ally:
			label += "  [%s]" % Net.inst.player_name(r.commander)
		if routing:
			label += "  - ROUTING"
		_text(label, Vector2(sp.x, y + 24.0), 12, Color(CREAM, a), 1)
		_text("%d men" % r.alive_count(), Vector2(sp.x, y + 37.0), 10, Color(DIM, a * 0.9), 1)



const CARD := Vector2(30, 36)
const CARD_BAND := 14.0


func _draw_unit_card(r: Regiment, sp: Vector2, tex: Texture2D, col: Color, a: float) -> void:
	## Znacznik oddziału na oddalonej mapie: portret jednostki w ramce w barwach strony, flaga kraju
	## na drzewcu, charakterystyczna ikona typu jednostki i strzałka kierunku, w którą stronę patrzy oddział.
	## Bez portretu karta jest wypełniona barwą strony, a ikona rysowana jest duża na środku.
	var rect := Rect2(sp - CARD * 0.5, CARD)
	# strzałka kierunku na obwodzie
	var fd := Vector2.from_angle(r.facing)
	var tip := sp + fd * 27.0
	var base := sp + fd * 20.0
	draw_colored_polygon(PackedVector2Array([tip, base + fd.orthogonal() * 6.0, base - fd.orthogonal() * 6.0]), Color(0, 0, 0, 0.55 * a))
	draw_colored_polygon(PackedVector2Array([tip - fd * 1.5, base + fd.orthogonal() * 4.5 + fd, base - fd.orthogonal() * 4.5 + fd]), Color(col.lightened(0.35), a))
	# cień i ramka
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.45 * a))
	var frame := GOLD if r.selected else col.lightened(0.15)
	draw_rect(rect.grow(2), Color(frame.darkened(0.45), a))
	draw_rect(rect.grow(1), Color(frame, a))
	var gid := _glyph_id(r.unit_key)
	if tex != null:
		draw_rect(rect, Color(0.10, 0.09, 0.08, a))
		_draw_portrait(tex, rect, 1.2, 0.04, Color(1, 1, 1, a))
		# pasek w barwach strony u dołu + ikona typu jednostki
		var band := Rect2(rect.position.x, rect.end.y - CARD_BAND, rect.size.x, CARD_BAND)
		draw_rect(band, Color(col.darkened(0.3), 0.94 * a))
		draw_line(band.position, Vector2(band.end.x, band.position.y), Color(GOLD_DIM, 0.8 * a), 1.0)
		_draw_glyph(gid, band.get_center() + Vector2(0, 0.5), (CARD_BAND - 1.5) / 10.0, Color(1, 1, 1, 0.95 * a))
	else:
		draw_rect(rect, Color(col.darkened(0.2), a))
		_draw_glyph(gid, rect.get_center(), 2.1, Color(1, 1, 1, 0.95 * a))
	if battle.show_all and not r.selected:
		draw_rect(rect.grow(4), Color(1, 1, 1, 0.5 * a), false, 1.2)
	# flaga kraju na drzewcu przy prawym górnym rogu
	var pole := rect.position + Vector2(rect.size.x - 2, -1)
	draw_line(pole + Vector2(0, 3), pole + Vector2(0, -13), Color(0.25, 0.17, 0.08, a), 1.3)
	draw_circle(pole + Vector2(0, -13), 1.1, Color(GOLD, a))
	_nation_flag(Rect2(pole + Vector2(1, -12), Vector2(12, 8)), Battle.nation(r.team), a)


func _glyph_id(key: String) -> String:
	## Charakterystyczna ikona jednostki: najpierw jednostki specjalne (po kluczu), potem typ bazowy.
	if not Battle.UNIT_TYPES.has(key):
		return "musket"
	if key.contains("napoleon"):
		return "bicorne"
	if key.contains("wellington") or key.contains("marshal") or key.contains("general"):
		return "star"
	if key.contains("larrey") or key.contains("surgeon"):
		return "medic"
	if key.contains("commissariat"):
		return "wagon"
	if key.contains("pontonier"):
		return "bridge"
	if key.contains("sapper"):
		return "axe"
	if key.contains("marin"):
		return "anchor"
	if key.contains("rocket"):
		return "rocket"
	var t: Dictionary = Battle.UNIT_TYPES[key]
	if key.contains("howitzer") or (t.has("gun") and t["gun"].get("how", false)):
		return "howitzer"
	match Battle.base_of(key):
		"light": return "horn"
		"rifles": return "rifles"
		"militia": return "pitchfork"
		"grenadier": return "grenade"
		"guard": return "crown"
		"hussars": return "sabre"
		"dragoons": return "helmet"
		"cuirassiers": return "cuirass"
		"lancers": return "lance"
		"artillery": return "cannon"
		"horse_art": return "horse_cannon"
	return "musket"


func _draw_glyph(id: String, c: Vector2, u: float, col: Color) -> void:
	## Ikona w polu ok. 10x10 jednostek (u = skala w pikselach na jednostkę), z ciemnym cieniem.
	draw_set_transform(c + Vector2(0.7, 0.8), 0.0, Vector2(u, u))
	_glyph_shapes(id, Color(0, 0, 0, 0.6 * col.a), true)
	draw_set_transform(c, 0.0, Vector2(u, u))
	_glyph_shapes(id, col, false)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _glyph_shapes(id: String, col: Color, shadow: bool) -> void:
	var w := 1.3
	match id:
		"musket":   # muszkiet z bagnetem
			draw_line(Vector2(-3.0, 3.0), Vector2(3.6, -3.6), col, w)
			draw_line(Vector2(3.6, -3.6), Vector2(5.2, -5.2), col, 0.7)
			draw_line(Vector2(-4.8, 4.8), Vector2(-2.4, 2.4), col, 2.6)
		"rifles":   # skrzyżowane karabiny
			draw_line(Vector2(-3.4, 3.4), Vector2(4.4, -4.4), col, 1.1)
			draw_line(Vector2(-4.8, 4.8), Vector2(-2.6, 2.6), col, 2.4)
			draw_line(Vector2(3.4, 3.4), Vector2(-4.4, -4.4), col, 1.1)
			draw_line(Vector2(4.8, 4.8), Vector2(2.6, 2.6), col, 2.4)
		"horn":     # trąbka myśliwska - lekka piechota
			draw_arc(Vector2(-0.8, 0.6), 2.9, 0.0, TAU, 18, col, 1.3)
			draw_colored_polygon(PackedVector2Array([Vector2(1.6, -0.6), Vector2(5.2, -3.6), Vector2(5.2, 2.0)]), col)
			draw_line(Vector2(-3.4, -0.6), Vector2(-5.2, -3.2), col, 1.0)
		"pitchfork":  # widły - milicja / pospolite ruszenie
			draw_line(Vector2(0, 5.0), Vector2(0, -1.0), col, 1.3)
			draw_line(Vector2(-3.0, -1.0), Vector2(3.0, -1.0), col, 1.2)
			for x in [-3.0, 0.0, 3.0]:
				draw_line(Vector2(x, -0.6), Vector2(x, -5.0), col, 1.0)
		"grenade":  # płonący granat - grenadierzy
			draw_circle(Vector2(0, 1.6), 3.3, col)
			draw_colored_polygon(PackedVector2Array([Vector2(-1.4, -1.4), Vector2(-0.4, -5.6), Vector2(0.4, -3.0), Vector2(1.6, -5.0), Vector2(1.4, -1.4)]),
				col if shadow else Color(1.0, 0.72, 0.25, col.a))
		"crown":    # korona - gwardia
			draw_colored_polygon(PackedVector2Array([Vector2(-4.8, 3.2), Vector2(-4.8, -3.0), Vector2(-2.2, 0.2), Vector2(0, -4.2),
				Vector2(2.2, 0.2), Vector2(4.8, -3.0), Vector2(4.8, 3.2)]), col if shadow else Color(1.0, 0.82, 0.3, col.a))
			if not shadow:
				draw_line(Vector2(-4.8, 2.2), Vector2(4.8, 2.2), Color(0.55, 0.35, 0.1, col.a), 0.9)
		"sabre":    # zakrzywiona szabla - huzarzy, szaserzy
			var pts := PackedVector2Array()
			for i in 9:
				var f := i / 8.0
				pts.append(Vector2(lerpf(-3.0, 4.6, f), lerpf(3.0, -4.6, f)) + Vector2(1, 1) * sin(f * PI) * 1.8)
			draw_polyline(pts, col, 1.3)
			draw_line(Vector2(-4.4, 1.6), Vector2(-1.6, 4.4), col, 1.1)
			draw_line(Vector2(-3.0, 3.0), Vector2(-4.8, 4.8), col, 1.8)
		"helmet":   # hełm z kitą - dragoni
			var dome := PackedVector2Array()
			for i in 9:
				dome.append(Vector2(0, 2.0) + Vector2.from_angle(PI + PI * i / 8.0) * 3.6)
			draw_colored_polygon(dome, col)
			draw_line(Vector2(-4.8, 2.4), Vector2(4.8, 2.4), col, 1.2)
			draw_polyline(PackedVector2Array([Vector2(1.0, -1.8), Vector2(-1.0, -3.0), Vector2(-3.6, -2.0), Vector2(-5.0, 1.6)]), col, 1.2)
		"cuirass":  # napierśnik - kirasjerzy, karabinierzy konni
			draw_colored_polygon(PackedVector2Array([Vector2(-4.2, -4.2), Vector2(-1.6, -3.0), Vector2(1.6, -3.0), Vector2(4.2, -4.2),
				Vector2(3.6, 1.2), Vector2(0, 4.8), Vector2(-3.6, 1.2)]), col)
			if not shadow:
				draw_line(Vector2(0, -2.6), Vector2(0, 4.0), Color(0, 0, 0, 0.45 * col.a), 0.8)
		"lance":    # lanca z proporczykiem - ułani, lansjerzy, kozacy
			draw_line(Vector2(-4.2, 5.0), Vector2(3.6, -3.4), col, 1.1)
			draw_colored_polygon(PackedVector2Array([Vector2(3.0, -2.8), Vector2(5.2, -5.2), Vector2(4.2, -2.2)]), col)
			draw_colored_polygon(PackedVector2Array([Vector2(2.0, -1.6), Vector2(0.4, 0.2), Vector2(-1.2, -2.6)]),
				col if shadow else Color(0.9, 0.2, 0.18, col.a))
		"cannon", "horse_cannon":  # armata (konna: z liniami pędu)
			draw_line(Vector2(-4.2, 1.2), Vector2(4.6, -2.2), col, 2.2)
			draw_arc(Vector2(-0.8, 2.4), 2.3, 0.0, TAU, 14, col, 1.0)
			draw_circle(Vector2(-0.8, 2.4), 0.7, col)
			if id == "horse_cannon":
				draw_line(Vector2(-5.2, -2.6), Vector2(-2.6, -2.6), col, 0.8)
				draw_line(Vector2(-5.2, -0.8), Vector2(-3.4, -0.8), col, 0.8)
		"howitzer":  # haubica / jednorożec: krótka gruba lufa stromo w górę
			draw_line(Vector2(-1.6, 1.4), Vector2(2.2, -3.8), col, 3.2)
			draw_arc(Vector2(-1.0, 2.6), 2.3, 0.0, TAU, 14, col, 1.0)
			draw_circle(Vector2(-1.0, 2.6), 0.7, col)
		"rocket":   # rakieta Congreve'a
			draw_line(Vector2(-2.4, 2.4), Vector2(3.0, -3.0), col, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(2.2, -3.8), Vector2(5.2, -5.2), Vector2(3.8, -2.2)]), col)
			draw_line(Vector2(-2.4, 2.4), Vector2(-5.2, 5.2), col, 0.7)
			draw_colored_polygon(PackedVector2Array([Vector2(-1.8, 3.4), Vector2(-4.6, 2.2), Vector2(-3.4, 4.8)]),
				col if shadow else Color(1.0, 0.6, 0.2, col.a))
		"axe":      # topór - saperzy
			draw_line(Vector2(-3.6, 5.0), Vector2(1.6, -3.6), col, 1.2)
			draw_colored_polygon(PackedVector2Array([Vector2(0.2, -4.4), Vector2(4.4, -5.4), Vector2(4.8, -0.6), Vector2(1.8, -1.6)]), col)
		"bridge":   # most łukowy - pontonierzy
			draw_arc(Vector2(0, 4.2), 4.2, PI, TAU, 14, col, 1.3)
			draw_line(Vector2(-5.2, -1.2), Vector2(5.2, -1.2), col, 1.3)
			draw_line(Vector2(-4.4, -1.2), Vector2(-4.4, 4.2), col, 1.0)
			draw_line(Vector2(4.4, -1.2), Vector2(4.4, 4.2), col, 1.0)
		"anchor":   # kotwica - marynarze, piechota morska
			draw_arc(Vector2(0, -4.0), 1.1, 0.0, TAU, 10, col, 0.9)
			draw_line(Vector2(0, -2.9), Vector2(0, 4.4), col, 1.2)
			draw_line(Vector2(-2.6, -1.6), Vector2(2.6, -1.6), col, 1.1)
			draw_arc(Vector2(0, 0.6), 3.8, PI * 0.12, PI * 0.88, 12, col, 1.2)
		"medic":    # czerwony krzyż na białym polu - chirurdzy, ambulans
			draw_rect(Rect2(-4.6, -4.6, 9.2, 9.2), col)
			if not shadow:
				var red := Color(0.85, 0.12, 0.12, col.a)
				draw_rect(Rect2(-1.2, -3.6, 2.4, 7.2), red)
				draw_rect(Rect2(-3.6, -1.2, 7.2, 2.4), red)
		"wagon":    # wóz taborowy - intendentura
			draw_rect(Rect2(-4.6, -3.2, 9.2, 4.2), col)
			draw_arc(Vector2(-2.6, 2.8), 1.7, 0.0, TAU, 10, col, 1.0)
			draw_arc(Vector2(2.6, 2.8), 1.7, 0.0, TAU, 10, col, 1.0)
		"bicorne":  # pierożek - Napoleon
			draw_colored_polygon(PackedVector2Array([Vector2(-5.4, 2.6), Vector2(-3.2, -1.0), Vector2(0, -3.4), Vector2(3.2, -1.0),
				Vector2(5.4, 2.6), Vector2(0, 1.4)]), col if shadow else Color(0.12, 0.12, 0.14, col.a))
			if not shadow:
				draw_polyline(PackedVector2Array([Vector2(-5.4, 2.6), Vector2(-3.2, -1.0), Vector2(0, -3.4), Vector2(3.2, -1.0),
					Vector2(5.4, 2.6), Vector2(0, 1.4), Vector2(-5.4, 2.6)]), Color(GOLD, col.a), 0.6)
				draw_circle(Vector2(0, -0.6), 0.9, Color(0.85, 0.15, 0.15, col.a))
		"star":     # gwiazda - marszałek, generał, Wellington
			var st := PackedVector2Array()
			for i in 10:
				st.append(Vector2.from_angle(-PI * 0.5 + PI * i / 5.0) * (5.0 if i % 2 == 0 else 2.1))
			draw_colored_polygon(st, col if shadow else Color(1.0, 0.82, 0.3, col.a))


func _nation_flag(fr: Rect2, nat: int, a: float) -> void:
	## Proste flagi stron: Francja (trójkolorowa), Wielka Brytania, Austria, Rosja, Prusy.
	draw_rect(fr.grow(0.6), Color(0, 0, 0, 0.5 * a))
	match nat:
		0:
			var w := fr.size.x / 3.0
			draw_rect(Rect2(fr.position, Vector2(w, fr.size.y)), Color(0.10, 0.20, 0.62, a))
			draw_rect(Rect2(fr.position + Vector2(w, 0), Vector2(w, fr.size.y)), Color(0.96, 0.96, 0.94, a))
			draw_rect(Rect2(fr.position + Vector2(w * 2.0, 0), Vector2(w, fr.size.y)), Color(0.85, 0.12, 0.15, a))
		1:
			draw_rect(fr, Color(0.08, 0.14, 0.45, a))
			draw_line(fr.position, fr.end, Color(0.95, 0.95, 0.95, a), 2.2)
			draw_line(Vector2(fr.position.x, fr.end.y), Vector2(fr.end.x, fr.position.y), Color(0.95, 0.95, 0.95, a), 2.2)
			draw_line(fr.position, fr.end, Color(0.8, 0.1, 0.12, a), 0.8)
			draw_line(Vector2(fr.position.x, fr.end.y), Vector2(fr.end.x, fr.position.y), Color(0.8, 0.1, 0.12, a), 0.8)
			draw_rect(Rect2(fr.position + Vector2(fr.size.x * 0.38, 0), Vector2(fr.size.x * 0.24, fr.size.y)), Color(0.95, 0.95, 0.95, a))
			draw_rect(Rect2(fr.position + Vector2(0, fr.size.y * 0.36), Vector2(fr.size.x, fr.size.y * 0.28)), Color(0.95, 0.95, 0.95, a))
			draw_rect(Rect2(fr.position + Vector2(fr.size.x * 0.44, 0), Vector2(fr.size.x * 0.12, fr.size.y)), Color(0.8, 0.1, 0.12, a))
			draw_rect(Rect2(fr.position + Vector2(0, fr.size.y * 0.42), Vector2(fr.size.x, fr.size.y * 0.16)), Color(0.8, 0.1, 0.12, a))
		2:
			var h := fr.size.y / 3.0
			draw_rect(fr, Color(0.95, 0.95, 0.94, a))
			draw_rect(Rect2(fr.position, Vector2(fr.size.x, h)), Color(0.80, 0.12, 0.14, a))
			draw_rect(Rect2(fr.position + Vector2(0, h * 2.0), Vector2(fr.size.x, h)), Color(0.80, 0.12, 0.14, a))
		3:
			var h := fr.size.y / 3.0
			draw_rect(Rect2(fr.position, Vector2(fr.size.x, h)), Color(0.96, 0.96, 0.94, a))
			draw_rect(Rect2(fr.position + Vector2(0, h), Vector2(fr.size.x, h)), Color(0.12, 0.25, 0.65, a))
			draw_rect(Rect2(fr.position + Vector2(0, h * 2.0), Vector2(fr.size.x, h)), Color(0.82, 0.12, 0.14, a))
		_:
			var h := fr.size.y / 2.0
			draw_rect(Rect2(fr.position, Vector2(fr.size.x, h)), Color(0.08, 0.08, 0.08, a))
			draw_rect(Rect2(fr.position + Vector2(0, h), Vector2(fr.size.x, h)), Color(0.95, 0.95, 0.94, a))


func _draw_label(r: Regiment, xf: Transform2D) -> void:
	var a := battle.soldier_alpha * (1.0 if r.selected or battle.show_all else 0.75)
	var sp := xf * r.centroid()
	if not get_rect().grow(100).has_point(sp):
		return
	var lift := (r.formation_depth() + 30.0) * battle.cam.zoom.x
	var col := Color(GOLD, a) if r.selected else Color(CREAM, a)
	var st: String = STATE_NAMES[r.state]
	if r.kind == "inf" and not r.officer_alive and r.state == Regiment.State.IDLE:
		st = "Fire at will"   # dowódca poległ - ogień nieregularny
	if r.is_limbering():
		st = "Limbering up"
	elif r.is_unlimbering():
		st = "Unlimbering"
	elif r.kind == "art" and r.state == Regiment.State.MOVING and r.limber_u >= 1.0:
		st = "Limbered"
	elif r.state == Regiment.State.MOVING and r._in_column:
		st = "Column"
	elif r.square:
		st = "Square"
	if r.in_water_ratio > 0.2:
		st += " (in water!)"
	if r.is_surrounded():
		st += " - SURROUNDED!"
	elif r.is_flanked():
		st += " - flanked!"
	var who := ""
	if Net.active() and r.team == 0 and r.commander != Net.my_id():
		who = "  [%s]" % Net.inst.player_name(r.commander)
		col = Color(0.75, 0.85, 1.0, a)
	_text("%s%s  (%d)  %s" % [r.reg_name, who, r.alive_count(), st], sp - Vector2(0, lift), 13, col, 1)
