class_name Settlement
extends Node2D
## Miasto lub wioska: daje złoto właścicielowi i pozwala rekrutować oddziały.
## Zdobywa się ją, stojąc w jej obrębie bez obecności wroga.

const CITY_INCOME := 3.0      # złota na sekundę
const VILLAGE_INCOME := 1.0
const CITY_RADIUS := 320.0
const VILLAGE_RADIUS := 180.0
const CITY_CAPTURE := 25.0    # sekund
const VILLAGE_CAPTURE := 10.0

var s_name := ""
var is_city := false
var faction := -1
var radius := 180.0
var income := 1.0
var capture_team := -1
var capture := 0.0            # 0..1
var queue: Array = []         # [klucz_jednostki, pozostały_czas, czas_całkowity]
var contested := false
var houses: Array = []        # [pos, size, angle, roof, rodzaj, strzecha] — battle.gd buduje z [0..2] kolizje


func setup(p_name: String, pos: Vector2, city: bool, p_faction: int) -> void:
	s_name = p_name
	position = pos
	is_city = city
	faction = p_faction
	radius = CITY_RADIUS if city else VILLAGE_RADIUS
	income = CITY_INCOME if city else VILLAGE_INCOME
	_generate_houses()


func capture_time() -> float:
	return CITY_CAPTURE if is_city else VILLAGE_CAPTURE


func allowed_units() -> Array:
	var out := []
	for key in Battle.roster(Battle.nation(faction) if faction >= 0 else 0):
		var t: Dictionary = Battle.UNIT_TYPES[key]
		if is_city or not t["city_only"]:
			out.append(key)
	return out


# --- wygląd: organiczny układ — główne drogi z mapy przechodzą przez osadę, kręte uliczki, zagrody
# (dom + stodoła + ogrodzone podwórze + ogród), kościół, staw, sad; miasto z murami, krzywym rynkiem
# i obwodnicą zamiast szachownicy. Styl domów i dachów zależy od motywu (Terrain.theme).
var streets: Array = []      # [PackedVector2Array, szerokość, brukowana]
var yards: Array = []        # [środek, rozmiar, kąt, kolor, rodzaj: "yard"/"garden"/"churchyard"]
var trees: Array = []        # [pozycja, promień, odcień, rodzaj: "round"/"palm"/"conifer"]
var stacks: Array = []       # stogi siana
var ponds: Array = []        # PackedVector2Array (wielokąty stawów)
var wall_pts := PackedVector2Array()
var square := PackedVector2Array()
var _main: Array = []        # polilinie dróg głównych w obrębie osady (współrzędne lokalne)
var _occ: Array = []         # zajęte koła [pos, r] (plac, staw, kościół)
var _flag_pos := Vector2(14, 6)
var _church_pos := Vector2.INF

# motyw
var _style := "timber"
var _church_style := "spire"
var _snow := 0.0
var _roofs: Array = []
var _thatch: Array = []
var _wall := Color(0.86, 0.82, 0.70)
var _yard := Color(0.36, 0.48, 0.21)
var _dirt := Color(0.55, 0.47, 0.33)
var _tree_kind := "round"

const TIMBER := Color(0.27, 0.19, 0.13)


func _generate_houses() -> void:
	_style = str(Terrain.tv("house"))
	_church_style = str(Terrain.tv("church"))
	_snow = float(Terrain.tv("snow"))
	_roofs = Terrain.tv("roofs")
	_thatch = Terrain.tv("thatch")
	_wall = Terrain.tv("wall")
	_yard = Terrain.tv("yard")
	_dirt = Terrain.tv("dirt")
	var tw: Dictionary = Terrain.tv("trees")
	if float(tw.get("palm", 0.0)) > 0.3:
		_tree_kind = "palm"
	elif float(tw.get("conifer", 0.0)) > 0.5:
		_tree_kind = "conifer"
	_main = _road_lines(radius + 90.0)
	if is_city:
		_gen_city()
	else:
		_gen_village()


# ------------------------------------------------------------------ geometria pomocnicza

func _road_lines(ext: float) -> Array:
	## Odcinki dróg z mapy (Terrain.current.roads) w promieniu ext — jako polilinie lokalne.
	var out: Array = []
	var t := Terrain.current
	if t != null:
		for rd in t.roads:
			var rp: PackedVector2Array = rd
			var run := PackedVector2Array()
			for k in rp.size():
				var q := rp[k] - position
				if q.length() < ext:
					if run.is_empty() and k > 0:
						run.append(rp[k - 1] - position)
					run.append(q)
				elif not run.is_empty():
					run.append(q)
					if run.size() >= 2:
						out.append(_from_center(run))
					run = PackedVector2Array()
			if run.size() >= 2:
				out.append(_from_center(run))
	if out.is_empty():
		var d := Vector2.from_angle(randf() * PI)
		out.append(PackedVector2Array([Vector2.ZERO, d * ext]))
		out.append(PackedVector2Array([Vector2.ZERO, -d * ext]))
	return out


func _from_center(run: PackedVector2Array) -> PackedVector2Array:
	# polilinia zaczyna się bliżej środka osady
	if run[0].length() > run[run.size() - 1].length():
		var r := run.duplicate()
		r.reverse()
		return r
	return run


func _poly_len(pts: PackedVector2Array) -> float:
	var L := 0.0
	for i in pts.size() - 1:
		L += pts[i].distance_to(pts[i + 1])
	return L


func _poly_at(pts: PackedVector2Array, t: float) -> Array:
	## Punkt i kierunek na polilinii w odległości t od początku.
	for i in pts.size() - 1:
		var L := pts[i].distance_to(pts[i + 1])
		if t <= L or i == pts.size() - 2:
			var d := (pts[i + 1] - pts[i]) / maxf(L, 0.001)
			return [pts[i] + d * minf(t, L), d]
		t -= L
	return [pts[0], Vector2.RIGHT]


func _dist_poly(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


func _road_clear(p: Vector2, r: float) -> bool:
	## Czy koło (p, r) nie wchodzi na drogę główną ani uliczkę.
	var main_half := Terrain.ROAD_WIDTH * 0.5 if not is_city else 11.0
	for m in _main:
		if _dist_poly(p, m) < main_half + r:
			return false
	for st in streets:
		if _dist_poly(p, st[0]) < float(st[1]) * 0.5 + r:
			return false
	return true


func _house_ok(c: Vector2, sz: Vector2, lim: float) -> bool:
	var r := sz.length() * 0.5
	if c.length() + r * 0.5 > lim:
		return false
	for hs in houses:
		var hr: float = (hs[1] as Vector2).length() * 0.5
		if (hs[0] as Vector2).distance_to(c) < (hr + r) * 0.78:
			return false
	for o in _occ:
		if (o[0] as Vector2).distance_to(c) < float(o[1]) + r * 0.7:
			return false
	if not square.is_empty() and Geometry2D.is_point_in_polygon(c, square):
		return false
	return _road_clear(c, minf(sz.x, sz.y) * 0.5 - 1.0)


func _roof(thatch: bool) -> Color:
	var list: Array = _thatch if thatch else _roofs
	return list[randi() % list.size()]


func _wobbly(c: Vector2, r: float, n: int, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var ph := randf() * TAU
	for k in n:
		var a := k * TAU / n
		pts.append(c + Vector2.from_angle(a) * r * (1.0 + amp * sin(a * 2.0 + ph) + randf_range(-amp, amp) * 0.5))
	return pts


func _curve(a: Vector2, b: Vector2, bend: float, n := 8) -> PackedVector2Array:
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * bend
	var pts := PackedVector2Array()
	for s in n + 1:
		var t := float(s) / n
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return pts


# ------------------------------------------------------------------ wieś

func _gen_village() -> void:
	var lim := radius - 10.0          # domy
	var outer := radius + 60.0        # ogrody i sady za zagrodami
	var main_w := Terrain.ROAD_WIDTH
	# błonie ze studnią przy drodze
	var green_c := Vector2.ZERO
	_occ.append([green_c, 14.0])
	# staw na skraju błonia
	if randf() < 0.55:
		for tries in 10:
			var pc := Vector2.from_angle(randf() * TAU) * randf_range(45.0, 110.0)
			if _road_clear(pc, 26.0):
				ponds.append(_wobbly(pc, randf_range(13.0, 20.0), 12, 0.18))
				_occ.append([pc, 24.0])
				break
	# kościół z cmentarzem przy głównej drodze (nie w każdej wsi)
	if randf() < 0.6:
		var m: PackedVector2Array = _main[randi() % _main.size()]
		for tries in 8:
			var at := _poly_at(m, randf_range(30.0, 90.0))
			var dir: Vector2 = at[1]
			var side := -1.0 if randf() < 0.5 else 1.0
			var c: Vector2 = at[0] + dir.orthogonal() * side * (main_w * 0.5 + 24.0)
			if c.length() < lim and _road_clear(c, 18.0):
				var ang := dir.angle() + randf_range(-0.08, 0.08)
				yards.append([c, Vector2(56, 40), ang, _yard.lightened(0.06), "churchyard"])
				houses.append([c, Vector2(32.0, 14.0), ang, Color(0.38, 0.39, 0.43), "church", false])
				_occ.append([c, 30.0])
				_church_pos = c
				for k in 3:
					trees.append([c + Vector2.from_angle(randf() * TAU) * randf_range(22.0, 27.0), randf_range(4.5, 6.5), randf(), _tree_kind])
				break
	# kręte uliczki odchodzące od drogi głównej
	var nl := randi_range(1, 3)
	for k in nl:
		var m: PackedVector2Array = _main[randi() % _main.size()]
		var at := _poly_at(m, randf_range(15.0, 100.0))
		var dir: Vector2 = at[1]
		var side := -1.0 if randf() < 0.5 else 1.0
		var ldir := dir.rotated(side * (PI * 0.5 + randf_range(-0.5, 0.5)))
		var a: Vector2 = at[0] + ldir * main_w * 0.4
		var b: Vector2 = a + ldir * randf_range(80.0, 150.0)
		var pts := _curve(a, b, randf_range(-30.0, 30.0))
		var clip := PackedVector2Array()
		for p in pts:
			if p.length() > lim + 20.0:
				break
			clip.append(p)
		if clip.size() >= 3:
			streets.append([clip, 9.0, false])
	# zagrody wzdłuż dróg i uliczek
	for m in _main:
		_farmsteads(m, main_w, lim, outer, 0.85)
	for st in streets:
		_farmsteads(st[0], st[1], lim, outer, 0.8)
	# sad: tam, gdzie najdalej od dróg
	var best_a := 0.0
	var best_d := -1.0
	for k in 12:
		var a := k * TAU / 12.0
		var p := Vector2.from_angle(a) * 130.0
		var d := INF
		for m in _main:
			d = minf(d, _dist_poly(p, m))
		if d > best_d:
			best_d = d
			best_a = a
	var oc := Vector2.from_angle(best_a) * randf_range(115.0, 150.0)
	var ou := Vector2.from_angle(best_a + randf_range(-0.4, 0.4))
	var ov := ou.orthogonal()
	var rows := randi_range(3, 4)
	var cols := randi_range(3, 5)
	for i in cols:
		for j in rows:
			var p := oc + ou * (i - (cols - 1) * 0.5) * 16.0 + ov * (j - (rows - 1) * 0.5) * 16.0 + Vector2(randf_range(-2, 2), randf_range(-2, 2))
			if p.length() < outer and _road_clear(p, 7.0) and _free_of_houses(p, 8.0) and randf() < 0.9:
				trees.append([p, randf_range(5.0, 6.5), 0.3 + randf() * 0.4, "palm" if _tree_kind == "palm" else "round"])
	# pojedyncze drzewa między zagrodami
	for k in 8:
		var p := Vector2.from_angle(randf() * TAU) * randf_range(30.0, lim)
		if _road_clear(p, 8.0) and _free_of_houses(p, 9.0):
			trees.append([p, randf_range(5.5, 8.0), randf(), _tree_kind])
	_flag_pos = _church_pos + Vector2(-20, -8) if _church_pos != Vector2.INF else Vector2(14, 6)


func _free_of_houses(p: Vector2, r: float) -> bool:
	for hs in houses:
		var hr: float = (hs[1] as Vector2).length() * 0.5
		if (hs[0] as Vector2).distance_to(p) < hr + r:
			return false
	for o in _occ:
		if (o[0] as Vector2).distance_to(p) < float(o[1]) + r * 0.5:
			return false
	return true


func _farmsteads(poly: PackedVector2Array, sw: float, lim: float, outer: float, density: float) -> void:
	## Zagrody po obu stronach drogi: dom (frontem albo szczytem do drogi), za nim ogrodzone podwórze,
	## czasem stodoła prostopadle (układ w "L"), stóg siana i ogród warzywny na tyłach.
	var total := _poly_len(poly)
	for side in [-1.0, 1.0]:
		var t := randf_range(4.0, 22.0)
		while t < total:
			var at := _poly_at(poly, t)
			var pos: Vector2 = at[0]
			var dir: Vector2 = at[1]
			if pos.length() > lim:
				break
			if randf() > density:
				t += randf_range(14.0, 30.0)
				continue
			var gable := randf() < 0.3
			var w := randf_range(15.0, 24.0)
			var d := randf_range(10.0, 13.0)
			var along := d if gable else w
			var across := w if gable else d
			var nrm: Vector2 = dir.orthogonal() * side
			var setback := randf_range(2.0, 10.0)
			var c: Vector2 = pos + dir * along * 0.5 + nrm * (sw * 0.5 + setback + across * 0.5)
			var ang := dir.angle() + (PI * 0.5 if gable else 0.0) + randf_range(-0.14, 0.14)
			if _house_ok(c, Vector2(w, d), lim):
				var thatch := _style != "mud" and _style != "stucco"
				houses.append([c, Vector2(w, d), ang, _roof(thatch), "house", thatch])
				var back: Vector2 = c + nrm * (across * 0.5 + 13.0)
				var yard_sz := Vector2(along + 16.0, 24.0)
				if _road_clear(back, 8.0):
					yards.append([back, yard_sz, dir.angle(), _yard.lerp(_dirt, randf_range(0.2, 0.6)), "yard"])
				if randf() < 0.55:
					var bsz := Vector2(randf_range(20.0, 28.0), randf_range(11.0, 14.0))
					var bs := -1.0 if randf() < 0.5 else 1.0
					var bc: Vector2 = back + nrm * 6.0 + dir * bs * (along * 0.5 + 4.0)
					var bang := dir.angle() + PI * 0.5 + randf_range(-0.08, 0.08)
					if _house_ok(bc, bsz, lim + 25.0):
						var broof := Color(0.44, 0.40, 0.33) if randf() < 0.5 else Color(0.40, 0.33, 0.24)
						if _style == "mud" or _style == "stucco":
							broof = _roof(false).darkened(0.08)
						elif _style == "log":
							broof = _roof(true).darkened(0.1)
						houses.append([bc, bsz, bang, broof, "barn", _style != "mud" and _style != "stucco"])
						if randf() < 0.6:
							var sp: Vector2 = bc + nrm * (bsz.x * 0.5 + 9.0) + dir * randf_range(-6.0, 6.0)
							if sp.length() < outer and _free_of_houses(sp, 6.0):
								stacks.append(sp)
				if randf() < 0.7:
					var gc: Vector2 = back + nrm * 25.0
					if gc.length() < outer and _road_clear(gc, 12.0):
						yards.append([gc, Vector2(along + 8.0, 20.0), dir.angle(), _dirt.darkened(0.15), "garden"])
				if randf() < 0.35:
					var tp: Vector2 = back + dir * randf_range(-along * 0.5, along * 0.5) + nrm * randf_range(-4.0, 8.0)
					if _free_of_houses(tp, 6.0):
						trees.append([tp, randf_range(5.0, 7.5), randf(), _tree_kind])
			t += along + randf_range(5.0, 18.0)


# ------------------------------------------------------------------ miasto

func _gen_city() -> void:
	var wall_r := radius - 50.0
	var lim := wall_r - 18.0
	# mury: nieregularny wielobok z basztami w narożach
	var sides := 11
	var ph := randf() * TAU
	for k in sides:
		var ang := ph + k * TAU / sides + randf_range(-0.07, 0.07)
		wall_pts.append(Vector2.from_angle(ang) * wall_r * randf_range(0.93, 1.04))
	wall_pts.append(wall_pts[0])
	# główne ulice: drogi z mapy, brukowane
	for m in _main:
		var clip := PackedVector2Array()
		for p in m:
			clip.append(p)
			if p.length() > wall_r + 28.0:
				break
		streets.append([clip, 22.0, true])
	# rynek: krzywy czworobok
	var a0 := randf() * PI
	for k in 4:
		square.append(Vector2.from_angle(a0 + k * PI * 0.5 + randf_range(-0.25, 0.25)) * randf_range(58.0, 76.0))
	_occ.append([Vector2.ZERO, 30.0])
	# kościół i ratusz przy pierzejach rynku
	var cdir := Vector2.from_angle(a0 + PI * 0.25)
	var cpos := cdir * 70.0
	houses.append([cpos, Vector2(40.0, 18.0), cdir.orthogonal().angle(), Color(0.40, 0.41, 0.45), "church", false])
	_church_pos = cpos
	var hpos := -cdir * 66.0
	houses.append([hpos, Vector2(30.0, 17.0), cdir.orthogonal().angle(), Color(0.30, 0.34, 0.42), "hall", false])
	_flag_pos = hpos
	# obwodnica wewnątrz murów (kręta) i zaułki między głównymi ulicami
	var ring := PackedVector2Array()
	var rr := lim * randf_range(0.6, 0.7)
	for k in 17:
		var a := k * TAU / 16.0
		ring.append(Vector2.from_angle(a) * rr * (1.0 + 0.07 * sin(a * 3.0 + ph)))
	streets.append([ring, 10.0, true])
	var exits: Array = []
	for m in _main:
		var mm: PackedVector2Array = m
		exits.append((mm[mm.size() - 1]).angle())
	exits.sort()
	for i in exits.size():
		var e0: float = exits[i]
		var e1: float = exits[(i + 1) % exits.size()] + (TAU if i == exits.size() - 1 else 0.0)
		var span := e1 - e0
		var n := 1 if span < 2.0 else 2
		for j in n:
			var a := e0 + span * (j + 1) / (n + 1) + randf_range(-0.15, 0.15)
			var p0 := Vector2.from_angle(a) * 62.0
			var p1 := Vector2.from_angle(a + randf_range(-0.2, 0.2)) * (lim + 4.0)
			streets.append([_curve(p0, p1, randf_range(-20.0, 20.0), 6), 9.0, true])
	# kamienice wzdłuż wszystkich ulic, gęsto
	for st in streets:
		for side in [-1.0, 1.0]:
			_row_along(st[0], float(st[1]), side, lim)
	# oficyny i zabudowa w głębi kwartałów, zwrócone do najbliższej ulicy
	var added := 0
	for k in 220:
		if added >= 55:
			break
		var p := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * lim
		var best := INF
		var bdir := Vector2.RIGHT
		for st in streets:
			var pts: PackedVector2Array = st[0]
			for i in pts.size() - 1:
				var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
				if q.distance_to(p) < best:
					best = q.distance_to(p)
					bdir = (pts[i + 1] - pts[i]).normalized()
		var sz := Vector2(randf_range(12.0, 19.0), randf_range(10.0, 14.0))
		if _house_ok(p, sz, lim):
			houses.append([p, sz, bdir.angle() + randf_range(-0.05, 0.05), _roof(false), "house", false])
			added += 1
	# zieleń w podwórzach kwartałów
	for k in 40:
		var p := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * lim
		if _free_of_houses(p, 6.0) and _road_clear(p, 5.0) and not Geometry2D.is_point_in_polygon(p, square):
			trees.append([p, randf_range(5.0, 8.0), randf(), _tree_kind])


func _row_along(poly: PackedVector2Array, sw: float, side: float, lim: float) -> void:
	## Pierzeja: kamienice frontem do ulicy, różne szerokości i głębokości, prawie bez przerw.
	var total := _poly_len(poly)
	var t := randf_range(2.0, 8.0)
	while t < total:
		var at := _poly_at(poly, t)
		var pos: Vector2 = at[0]
		var dir: Vector2 = at[1]
		var w := randf_range(13.0, 22.0)
		var d := randf_range(12.0, 18.0)
		var nrm: Vector2 = dir.orthogonal() * side
		var c: Vector2 = pos + dir * w * 0.5 + nrm * (sw * 0.5 + 1.5 + d * 0.5)
		if pos.length() < lim and _house_ok(c, Vector2(w, d), lim):
			var thatch := randf() < 0.08 and _style == "timber"
			houses.append([c, Vector2(w, d), dir.angle() + randf_range(-0.04, 0.04), _roof(thatch), "house", thatch])
			if randf() < 0.35:
				var yc: Vector2 = c + nrm * (d * 0.5 + 8.0)
				if yc.length() < lim and _road_clear(yc, 6.0):
					yards.append([yc, Vector2(w * 0.9, 13.0), dir.angle(), _yard.lerp(_dirt, 0.3), "yard"])
		t += w + randf_range(0.5, 3.0)


# ------------------------------------------------------------------ rysowanie

const STONE := Color(0.58, 0.55, 0.50)
const STONE_DARK := Color(0.36, 0.34, 0.31)


func _cobble() -> Color:
	return Color(0.52, 0.49, 0.44) if _style != "mud" else Color(0.70, 0.62, 0.48)


func _rect_pts(c: Vector2, sz: Vector2, ang: float, grow := 0.0) -> PackedVector2Array:
	var d := Vector2.from_angle(ang)
	var s := d.orthogonal()
	var hx := d * (sz.x * 0.5 + grow)
	var hy := s * (sz.y * 0.5 + grow)
	return PackedVector2Array([c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy])


func _snowy(c: Color, k := 1.0) -> Color:
	return c.lerp(Color(0.90, 0.92, 0.96), _snow * 0.72 * k)


# ------------------------------------------------------------------ wypiekanie do pikselowej tekstury
# Zabudowa jest statyczna: rysujemy ją raz do małej tekstury (1 teksel = BAKE_PX jednostek świata)
# i wyświetlamy bez wygładzania — lekko pikselowy wygląd jak w pixel-arcie. Flaga rysowana na żywo.
const BAKE_PX := 1.5
var _ci: CanvasItem = self
var _baked := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return   # serwer bez okna: nic nie wypiekamy
	_bake.call_deferred()


func _bake_ext() -> float:
	return radius + (50.0 if is_city else 85.0)


func _bake() -> void:
	var ext := _bake_ext()
	var px := int(ceil(ext * 2.0 / BAKE_PX))
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Node2D.new()
	painter.position = Vector2(ext, ext) / BAKE_PX
	painter.scale = Vector2.ONE / BAKE_PX
	painter.draw.connect(func() -> void:
		_ci = painter
		_paint_static()
		_ci = self)
	vp.add_child(painter)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return
	img.generate_mipmaps()
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	spr.scale = Vector2(BAKE_PX, BAKE_PX)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	spr.show_behind_parent = true
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA   # przezroczysty viewport daje kolory premnożone
	spr.material = m
	add_child(spr)
	_baked = true
	queue_redraw()


func _draw() -> void:
	if not _baked:
		_ci = self
		_paint_static()
	_draw_flag()


func _fence_col() -> Color:
	match _style:
		"mud": return _wall.darkened(0.15)
		"stucco": return Color(0.62, 0.58, 0.52)
	return Color(0.36, 0.27, 0.17)


func _paint_static() -> void:
	# podwórza, ogrody, cmentarz
	for y in yards:
		var kind: String = y[4]
		var pts := _rect_pts(y[0], y[1], y[2])
		var col: Color = y[3]
		if kind == "garden":
			_ci.draw_colored_polygon(pts, Color(_snowy(col, 0.8), 0.9))
			# grządki: rzędy zieleni wzdłuż ogrodu
			var d := Vector2.from_angle(y[2])
			var s := d.orthogonal()
			var sz: Vector2 = y[1]
			var n := int(sz.y / 4.0)
			var veg := _snowy(Color(0.30, 0.46, 0.18), 0.9)
			for k in n:
				var off := (k + 0.5 - n * 0.5) * 4.0
				_ci.draw_line(y[0] + s * off - d * (sz.x * 0.5 - 2.0), y[0] + s * off + d * (sz.x * 0.5 - 2.0), veg, 1.6)
		else:
			_ci.draw_colored_polygon(pts, Color(_snowy(col, 0.9), 0.75 if kind == "yard" else 0.85))
	# stawy
	for pd in ponds:
		var poly: PackedVector2Array = pd
		var rim := PackedVector2Array()
		var c := Vector2.ZERO
		for p in poly:
			c += p
		c /= poly.size()
		for p in poly:
			rim.append(c + (p - c) * 1.18)
		_ci.draw_colored_polygon(rim, _snowy(Color(0.30, 0.40, 0.18), 0.6))
		var water := Color(0.25, 0.42, 0.45) if _snow < 0.5 else Color(0.74, 0.82, 0.88)
		_ci.draw_colored_polygon(poly, water)
		var inner := PackedVector2Array()
		for p in poly:
			inner.append(c + (p - c) * 0.6 + Vector2(-2, -2))
		_ci.draw_colored_polygon(inner, water.lightened(0.12))
		for k in 5:   # trzciny
			var p: Vector2 = poly[randi() % poly.size()]
			_ci.draw_circle(p, 2.2, Color(0.28, 0.38, 0.15))
	# płoty zagród i mur cmentarza
	var fc := _fence_col()
	for y in yards:
		if y[4] == "garden":
			continue
		if is_city and y[4] == "yard":
			continue
		var pts := _rect_pts(y[0], y[1], y[2], 1.0)
		pts.append(pts[0])
		if y[4] == "churchyard":
			_ci.draw_polyline(pts, STONE_DARK, 2.2)
			_ci.draw_polyline(pts, STONE, 1.2)
		else:
			_ci.draw_polyline(pts, Color(fc, 0.85), 1.6 if _style == "mud" else 0.8)
			if _style != "mud":
				for k in 4:   # słupki w narożach
					_ci.draw_rect(Rect2(pts[k] - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), fc.darkened(0.3))
	# ulice: obrzeże, potem nawierzchnia (bruk w mieście, ubita ziemia na wsi)
	for st in streets:
		var pts: PackedVector2Array = st[0]
		var col := Color(0.40, 0.37, 0.33) if st[2] else _dirt.darkened(0.18)
		_ci.draw_polyline(pts, _snowy(col, 0.5), float(st[1]) + 3.0)
	for st in streets:
		var pts: PackedVector2Array = st[0]
		var col := _cobble() if st[2] else _dirt
		_ci.draw_polyline(pts, _snowy(col, 0.5), float(st[1]))
		if st[2]:
			_ci.draw_polyline(pts, Color(0.42, 0.40, 0.37, 0.5), 1.0)   # rynsztok
	if is_city:
		# rynek: brukowany plac z fontanną
		var big := PackedVector2Array()
		for p in square:
			big.append(p * 1.04)
		_ci.draw_colored_polygon(big, Color(0.40, 0.37, 0.33))
		_ci.draw_colored_polygon(square, _snowy(_cobble().lightened(0.12), 0.5))
		for k in range(-6, 7):
			var u := Vector2.from_angle((square[1] - square[0]).angle())
			var v := u.orthogonal()
			_ci.draw_line(u * k * 10.8 - v * 64.0, u * k * 10.8 + v * 64.0, Color(0.5, 0.47, 0.42, 0.18), 0.6)
		_ci.draw_circle(Vector2(3, 4), 10.0, Color(0, 0, 0, 0.25))
		_ci.draw_circle(Vector2.ZERO, 10.0, STONE_DARK)
		_ci.draw_circle(Vector2.ZERO, 8.0, Color(0.30, 0.45, 0.55) if _snow < 0.5 else Color(0.75, 0.82, 0.88))
		_ci.draw_circle(Vector2.ZERO, 2.5, STONE)
		_draw_walls()
	else:
		_ci.draw_circle(Vector2.ZERO, 13.0, Color(_snowy(_dirt), 0.75))
		_ci.draw_circle(Vector2(1.5, 2), 4.5, Color(0, 0, 0, 0.3))
		_ci.draw_circle(Vector2.ZERO, 4.5, STONE_DARK)   # studnia
		_ci.draw_circle(Vector2.ZERO, 2.8, Color(0.15, 0.2, 0.25))
	for p in stacks:
		_ci.draw_circle(p + Vector2(3, 4), 6.0, Color(0, 0, 0, 0.3))
		_ci.draw_circle(p, 6.5, Color(0.45, 0.36, 0.18))
		_ci.draw_circle(p, 5.8, _snowy(Color(0.72, 0.62, 0.32)))
		_ci.draw_circle(p - Vector2(1.5, 1.5), 3.3, _snowy(Color(0.84, 0.74, 0.42)))
	# cienie wszystkich budynków najpierw, żeby nie zachodziły na dachy sąsiadów
	for hs in houses:
		_ci.draw_colored_polygon(_rect_pts(hs[0] + Vector2(4, 5), hs[1], hs[2]), Color(0, 0, 0, 0.32))
	# od góry do dołu: ściana frontowa niższego domu zachodzi na dach wyższego (lekki widok z góry, nie izometria)
	var order := houses.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector2).y < (b[0] as Vector2).y)
	for hs in order:
		match str(hs[4]) if hs.size() > 4 else "house":
			"church": _draw_church(hs[0], hs[1], hs[2])
			"hall": _draw_hall(hs[0], hs[1], hs[2], hs[3])
			_: _draw_house(hs[0], hs[1], hs[2], hs[3], hs.size() > 5 and hs[5])
	# drzewa (korony z cieniem)
	for t in trees:
		_draw_tree(t[0], t[1], float(t[2]), str(t[3]) if t.size() > 3 else "round")


func _draw_tree(tp: Vector2, tr: float, shade: float, kind: String) -> void:
	_ci.draw_circle(tp + Vector2(3, 4), tr, Color(0, 0, 0, 0.12 if (_snow > 0.5 and kind == "round") else 0.28))
	match kind:
		"palm":
			var g := Color(0.30, 0.44, 0.15).lerp(Color(0.42, 0.54, 0.20), shade)
			var n := 8
			var ph := shade * TAU
			for k in n:   # obrys liści
				var a := ph + k * TAU / n
				_ci.draw_line(tp, tp + Vector2.from_angle(a) * (tr + 2.5), g.darkened(0.6), 3.4)
			for k in n:
				var a := ph + k * TAU / n
				var lit := Vector2.from_angle(a).dot(Vector2(-0.7, -0.7)) > 0.0
				_ci.draw_line(tp, tp + Vector2.from_angle(a) * (tr + 1.8), g.lightened(0.15) if lit else g, 1.8)
			_ci.draw_circle(tp, 1.6, Color(0.40, 0.30, 0.16))
		"conifer":
			var g := Color(0.15, 0.28, 0.19).lerp(Color(0.22, 0.36, 0.22), shade)
			var pts := PackedVector2Array()
			var n := 16
			for k in n:
				pts.append(tp + Vector2.from_angle(k * TAU / n) * tr * (1.15 if k % 2 == 0 else 0.75))
			var ol := PackedVector2Array()
			for p in pts:
				ol.append(tp + (p - tp) * 1.15)
			_ci.draw_colored_polygon(ol, g.darkened(0.6))
			_ci.draw_colored_polygon(pts, g)
			_ci.draw_circle(tp - Vector2(tr, tr) * 0.2, tr * 0.5, _snowy(g.lightened(0.15), 1.1))
		_:
			var g := Color(0.24, 0.42, 0.17).lerp(Color(0.36, 0.52, 0.20), shade)
			if _snow > 0.5:
				# bezlistne zimą: konary rozchodzące się od pnia
				var bc := Color(0.30, 0.24, 0.18)
				for k in 7:
					var a := shade * TAU + k * TAU / 7.0
					var e := tp + Vector2.from_angle(a) * tr
					_ci.draw_line(tp, e, bc, 1.3)
					_ci.draw_line(e, e + Vector2.from_angle(a + 0.6) * tr * 0.35, bc.lightened(0.1), 0.8)
				_ci.draw_circle(tp, 1.6, bc.darkened(0.3))
				return
			var tc: Array = Terrain.tv("tree_cols")
			if str(Terrain.theme_name).contains("Autumn"):
				g = (tc[int(shade * 97.0) % tc.size()] as Color)
			_ci.draw_circle(tp, tr + 0.9, g.darkened(0.6))   # obrys
			_ci.draw_circle(tp, tr, g.darkened(0.25))
			_ci.draw_circle(tp - Vector2(tr, tr) * 0.18, tr * 0.78, g)
			_ci.draw_circle(tp - Vector2(tr, tr) * 0.35, tr * 0.35, _snowy(g.lightened(0.15), 1.2))


func _draw_flag() -> void:
	# flaga właściciela (w mieście na ratuszu) — zawsze rysowana na żywo (zmienia kolor po zdobyciu)
	var fc := Battle.owner_color(faction)
	var pole := _flag_pos
	draw_line(pole + Vector2(2, 2), pole + Vector2(2, -34), Color(0, 0, 0, 0.3), 2.0)
	draw_line(pole, pole + Vector2(0, -36), Color(0.25, 0.18, 0.1), 2.0)
	draw_rect(Rect2(pole + Vector2(1, -36), Vector2(20, 12)), fc)
	draw_rect(Rect2(pole + Vector2(1, -36), Vector2(20, 12)), fc.darkened(0.4), false, 1.0)


func _gate_cut(a: Vector2, b: Vector2) -> float:
	## Czy któraś ulica główna przecina ten odcinek muru? Zwraca parametr t przecięcia albo -1.
	for m in _main:
		var mm: PackedVector2Array = m
		for i in mm.size() - 1:
			var hit = Geometry2D.segment_intersects_segment(a, b, mm[i], mm[i + 1])
			if hit != null:
				return clampf(a.distance_to(hit) / maxf(a.distance_to(b), 0.01), 0.08, 0.92)
	return -1.0


func _draw_walls() -> void:
	## Mury miejskie: korona muru z blankami, baszty w narożach, wieże bramne przy wylotach głównych ulic.
	var n := wall_pts.size() - 1
	for k in n:
		var a: Vector2 = wall_pts[k]
		var b: Vector2 = wall_pts[k + 1]
		var cut := _gate_cut(a, b)
		var segs: Array = [[a, b]]
		var gl := 17.0 / maxf(a.distance_to(b), 1.0)
		if cut >= 0.0:
			segs = [[a, a.lerp(b, maxf(cut - gl, 0.0))], [a.lerp(b, minf(cut + gl, 1.0)), b]]
		for sg in segs:
			var p0: Vector2 = sg[0]
			var p1: Vector2 = sg[1]
			if p0.distance_to(p1) < 1.0:
				continue
			_ci.draw_line(p0 + Vector2(4, 5), p1 + Vector2(4, 5), Color(0, 0, 0, 0.3), 9.0)
			_ci.draw_line(p0, p1, STONE_DARK, 9.0)
			_ci.draw_line(p0, p1, _snowy(STONE, 0.6), 6.0)
			var L := p0.distance_to(p1)
			var dir := (p1 - p0) / maxf(L, 0.01)
			var nrm := dir.orthogonal()
			var m := 3.0
			while m < L - 2.0:   # blanki
				_ci.draw_line(p0 + dir * m - nrm * 2.6, p0 + dir * (m + 2.2) - nrm * 2.6, STONE_DARK, 1.6)
				m += 5.0
		if cut >= 0.0:
			for t2 in [cut - gl, cut + gl]:
				_tower(a.lerp(b, clampf(t2, 0.0, 1.0)), 7.5, _tower_roof().darkened(0.05))
	for k in n:
		_tower(wall_pts[k], 10.0, _tower_roof())


func _tower_roof() -> Color:
	match _style:
		"mud": return Color(0.80, 0.72, 0.56)
		"log": return Color(0.30, 0.42, 0.33)
	return Color(0.52, 0.30, 0.21)


func _tower(p: Vector2, r: float, roof: Color) -> void:
	roof = _snowy(roof)
	_ci.draw_circle(p + Vector2(4, 5), r, Color(0, 0, 0, 0.32))
	_ci.draw_circle(p, r, STONE_DARK)
	_ci.draw_circle(p, r - 1.6, roof.darkened(0.15))
	_ci.draw_circle(p - Vector2(r, r) * 0.18, (r - 1.6) * 0.62, roof.lightened(0.1))   # stożkowy dach w świetle
	_ci.draw_circle(p, 1.3, roof.darkened(0.45))


func _front_edge(p: Vector2, hx: Vector2, hy: Vector2, dir: Vector2, side: Vector2) -> Array:
	# ściana frontowa: krawędź, której normalna najbardziej patrzy w dół ekranu
	var edges := [[p - hx + hy, p + hx + hy, side], [p + hx - hy, p - hx - hy, -side],
		[p + hx + hy, p + hx - hy, dir], [p - hx - hy, p - hx + hy, -dir]]
	var front: Array = edges[0]
	for e in edges:
		if (e[2] as Vector2).y > (front[2] as Vector2).y:
			front = e
	return front


func _draw_house(p: Vector2, sz: Vector2, ang: float, roof: Color, thatch := false) -> void:
	## Dom z góry: dwuspadowy dach (kalenica wzdłuż dłuższej osi), połać zwrócona ku światłu (lewa-góra) jaśniejsza,
	## a od dołu ekranu widać kawałek ściany frontowej. Styl ścian zależy od motywu: szachulec, bielone
	## ściany, bale (chata z bali) albo płaski dach z gliny (Egipt). Ciemny obrys jak w pixel-arcie.
	if _style == "mud":
		_draw_flat_house(p, sz, ang, roof)
		return
	var dir := Vector2.from_angle(ang)
	var side := dir.orthogonal()
	var hx := dir * sz.x * 0.5
	var hy := side * sz.y * 0.5
	var front := _front_edge(p, hx, hy, dir, side)
	var fn: Vector2 = front[2]
	if fn.y > 0.25:
		var wall_h := 5.0 * fn.y + 1.5
		var e0: Vector2 = front[0]
		var e1: Vector2 = front[1]
		var down := Vector2(0, wall_h)
		var wall := PackedVector2Array([e0, e1, e1 + down, e0 + down])
		_ci.draw_colored_polygon(wall, _wall.darkened(0.08 + 0.12 * (1.0 - fn.y)))
		var wl := e0.distance_to(e1)
		if _style == "log":
			for k in 3:   # bale ułożone poziomo
				var o := down * (0.3 + 0.3 * k)
				_ci.draw_line(e0 + o, e1 + o, _wall.darkened(0.4), 0.8)
		elif _style == "timber":
			var n := maxi(2, int(wl / 10.0))
			for k in n + 1:   # belki szachulca
				var q := e0.lerp(e1, float(k) / n)
				_ci.draw_line(q, q + down, TIMBER, 1.0)
		var door := e0.lerp(e1, 0.3 + fposmod(p.x * 0.37, 0.4))
		_ci.draw_line(door + down * 0.35, door + down, Color(0.18, 0.12, 0.08), 2.2)
		var win := e0.lerp(e1, 0.15 + fposmod(p.y * 0.29, 0.25))
		_ci.draw_rect(Rect2(win + down * 0.2 - Vector2(0.9, 0), Vector2(1.8, 1.6)), Color(0.14, 0.15, 0.18))
		var wpts := wall.duplicate()
		wpts.append(wpts[0])
		_ci.draw_polyline(wpts, TIMBER.darkened(0.4) if _style != "stucco" else _wall.darkened(0.45), 1.0)
	# dach: połać zwrócona do światła jaśniejsza
	roof = _snowy(roof)
	var outline := roof.darkened(0.62)
	var light := Vector2(-0.7, -0.7)
	var lit_side := -1.0 if (-side).dot(light) > 0.0 else 1.0
	var lit := roof.lightened(0.16)
	var dark := roof.darkened(0.22)
	var grow := 1.6 if thatch else 0.8     # strzecha mocno wystaje poza ściany
	var eave := _rect_pts(p, sz, ang, grow)
	_ci.draw_colored_polygon(eave, outline)
	var inner := _rect_pts(p, sz, ang, grow - 0.9)
	var half_a := PackedVector2Array([inner[0], inner[1], (inner[1] + inner[2]) * 0.5, (inner[0] + inner[3]) * 0.5])
	var half_b := PackedVector2Array([(inner[0] + inner[3]) * 0.5, (inner[1] + inner[2]) * 0.5, inner[2], inner[3]])
	_ci.draw_colored_polygon(half_a, lit if lit_side < 0.0 else dark)
	_ci.draw_colored_polygon(half_b, dark if lit_side < 0.0 else lit)
	var ix := dir * (sz.x * 0.5 + grow - 1.2)
	var iy := side * (sz.y * 0.5 + grow - 1.2)
	if thatch:
		# pasy słomy równoległe do okapu (faktura strzechy)
		for k in [0.6]:
			for sg in [-1.0, 1.0]:
				var c := roof.lightened(0.05) if sg == lit_side else roof.darkened(0.35)
				_ci.draw_line(p - ix + iy * k * sg, p + ix + iy * k * sg, c, 0.9)
		_ci.draw_line(p - ix, p + ix, roof.darkened(0.5), 1.6)   # gruba kalenica ze słomy
		_ci.draw_line(p - ix * 0.9 - iy * 0.12 * lit_side, p + ix * 0.9 - iy * 0.12 * lit_side, roof.lightened(0.3), 0.7)
	else:
		for k in [0.33, 0.66]:   # rzędy dachówek / desek
			_ci.draw_line(p - ix + iy * k * lit_side, p + ix + iy * k * lit_side, roof.darkened(0.05), 0.7)
			_ci.draw_line(p - ix - iy * k * lit_side, p + ix - iy * k * lit_side, roof.darkened(0.36), 0.7)
		_ci.draw_line(p - ix, p + ix, roof.darkened(0.45), 1.3)   # kalenica
	if int(absf(p.x * 7.0 + p.y * 3.0)) % 3 != 0:   # komin
		var cp := p + hx * 0.45 - hy * 0.35
		_ci.draw_rect(Rect2(cp - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(0.20, 0.13, 0.10))
		_ci.draw_rect(Rect2(cp - Vector2(1.4, 1.4), Vector2(2.8, 2.8)), Color(0.50, 0.33, 0.25))
		_ci.draw_rect(Rect2(cp - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), Color(0.10, 0.08, 0.07))


func _draw_flat_house(p: Vector2, sz: Vector2, ang: float, roof: Color) -> void:
	## Dom z cegły mułowej: płaski dach z niskim attykiem, ciemny otwór schodów na dach, ściana od dołu.
	var dir := Vector2.from_angle(ang)
	var side := dir.orthogonal()
	var hx := dir * sz.x * 0.5
	var hy := side * sz.y * 0.5
	var front := _front_edge(p, hx, hy, dir, side)
	var fn: Vector2 = front[2]
	if fn.y > 0.25:
		var e0: Vector2 = front[0]
		var e1: Vector2 = front[1]
		var down := Vector2(0, 5.5 * fn.y + 1.5)
		var wall := PackedVector2Array([e0, e1, e1 + down, e0 + down])
		_ci.draw_colored_polygon(wall, _wall.darkened(0.12 + 0.12 * (1.0 - fn.y)))
		var door := e0.lerp(e1, 0.3 + fposmod(p.x * 0.37, 0.4))
		_ci.draw_line(door + down * 0.3, door + down, Color(0.22, 0.15, 0.10), 2.4)
		var wpts := wall.duplicate()
		wpts.append(wpts[0])
		_ci.draw_polyline(wpts, _wall.darkened(0.55), 1.0)
	_ci.draw_colored_polygon(_rect_pts(p, sz, ang, 0.6), roof.darkened(0.6))
	_ci.draw_colored_polygon(_rect_pts(p, sz, ang, -0.3), roof.darkened(0.1))                     # attyka
	_ci.draw_colored_polygon(_rect_pts(p + Vector2(0.5, 0.5), sz - Vector2(4.0, 4.0), ang), roof.lightened(0.06))
	var hc := p + hx * 0.5 + hy * 0.3
	_ci.draw_colored_polygon(_rect_pts(hc, Vector2(3.5, 3.0), ang), Color(0.25, 0.18, 0.12))      # zejście
	if int(absf(p.x * 5.0 + p.y * 11.0)) % 4 == 0:
		_ci.draw_circle(p - hx * 0.4, minf(sz.x, sz.y) * 0.28, roof.darkened(0.25))               # kopułka
		_ci.draw_circle(p - hx * 0.4 - Vector2(0.8, 0.8), minf(sz.x, sz.y) * 0.2, roof.lightened(0.12))


func _draw_hall(p: Vector2, sz: Vector2, ang: float, roof: Color) -> void:
	## Ratusz: wieżyczka z miedzianym hełmem pośrodku kalenicy.
	_draw_house(p, sz, ang, roof if _style != "mud" else _roofs[0])
	_ci.draw_circle(p, 5.0, STONE_DARK)
	_ci.draw_circle(p, 3.6, Color(0.30, 0.42, 0.40))
	_ci.draw_circle(p - Vector2(1, 1), 1.4, Color(0.55, 0.65, 0.55))


func _bulb(c: Vector2, r: float, col: Color) -> void:
	_ci.draw_circle(c + Vector2(2.5, 3.0), r, Color(0, 0, 0, 0.3))
	_ci.draw_circle(c, r + 0.9, col.darkened(0.6))
	_ci.draw_circle(c, r, col)
	_ci.draw_circle(c - Vector2(r, r) * 0.3, r * 0.45, col.lightened(0.35))
	_ci.draw_circle(c, 0.9, Color(0.95, 0.82, 0.35))


func _draw_church(p: Vector2, sz: Vector2, ang: float) -> void:
	## Kościół zależny od motywu: wieża z iglicą, dzwonnica (Hiszpania), cerkiew z cebulastymi kopułami,
	## meczet z kopułą i minaretem (Egipt).
	var dir := Vector2.from_angle(ang)
	var side := dir.orthogonal()
	match _church_style:
		"onion":
			_draw_house(p, sz, ang, Color(0.40, 0.42, 0.44))
			_bulb(p + dir * sz.x * 0.15, sz.y * 0.42, Color(0.30, 0.52, 0.36))
			_bulb(p - dir * (sz.x * 0.5 + 2.0), sz.y * 0.36, Color(0.82, 0.66, 0.24))
			for s in [-1.0, 1.0]:
				_bulb(p + dir * sz.x * 0.3 + side * s * sz.y * 0.35, sz.y * 0.18, Color(0.30, 0.52, 0.36))
			return
		"dome":
			_draw_flat_house(p, sz + Vector2(4.0, 10.0), ang, Color(0.90, 0.87, 0.80))
			var dc := p + dir * 2.0
			var r := sz.y * 0.55
			_ci.draw_circle(dc + Vector2(3, 4), r, Color(0, 0, 0, 0.3))
			_ci.draw_circle(dc, r + 1.0, Color(0.42, 0.38, 0.32))
			_ci.draw_circle(dc, r, Color(0.86, 0.82, 0.74))
			_ci.draw_circle(dc - Vector2(r, r) * 0.25, r * 0.55, Color(0.96, 0.94, 0.88))
			var mn := p - dir * (sz.x * 0.5 + 5.0) - side * (sz.y * 0.5 + 2.0)
			_ci.draw_circle(mn + Vector2(4, 5), 4.5, Color(0, 0, 0, 0.3))
			_ci.draw_circle(mn, 4.8, Color(0.42, 0.38, 0.32))
			_ci.draw_circle(mn, 3.8, Color(0.88, 0.84, 0.76))
			_ci.draw_circle(mn - Vector2(0.8, 0.8), 1.6, Color(0.96, 0.94, 0.88))
			return
	var roof: Color = Color(0.38, 0.39, 0.43) if _church_style != "bell" else _roofs[0]
	_draw_house(p + dir * 2.0, sz, ang, roof)
	_draw_house(p + dir * 8.0, Vector2(12.0, sz.y + 16.0), ang + PI * 0.5, roof)
	_ci.draw_circle(p + dir * (sz.x * 0.5 + 3.0), sz.y * 0.42, _snowy(roof.darkened(0.2)))
	_ci.draw_circle(p + dir * (sz.x * 0.5 + 2.0), sz.y * 0.32, _snowy(roof))
	var tw := p - dir * (sz.x * 0.5 + 3.0)
	_ci.draw_colored_polygon(_rect_pts(tw + Vector2(4, 5), Vector2(15, 15), ang), Color(0, 0, 0, 0.3))
	_ci.draw_colored_polygon(_rect_pts(tw, Vector2(15, 15), ang), STONE_DARK if _church_style != "bell" else _wall.darkened(0.3))
	var c := _rect_pts(tw, Vector2(12, 12), ang)
	var shades := [0.18, -0.05, -0.25, 0.05]
	for k in 4:   # hełm wieży: cztery połacie zbiegające się w iglicy
		var sh: float = shades[k]
		var rc := _snowy(roof.lightened(sh) if sh > 0.0 else roof.darkened(-sh), 0.8)
		_ci.draw_colored_polygon(PackedVector2Array([c[k], c[(k + 1) % 4], tw]), rc)
	_ci.draw_circle(tw, 1.4, Color(0.85, 0.7, 0.3))


func set_faction(t: int) -> void:
	faction = t
	queue.clear()
	queue_redraw()
