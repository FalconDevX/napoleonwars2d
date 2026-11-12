class_name CorpseLayer
extends Node2D
## Polegli żołnierze, konie, plamy krwi i leje po kulach (pod żywymi oddziałami).
## Mapa podzielona na kawałki: po czyjejś śmierci przerysowuje się tylko jego kawałek, nie całe pole bitwy.

const CHUNK := 800.0
const MAX_PER_CHUNK := 900

var _chunks := {}   # Vector2i -> Chunk


class Chunk extends Node2D:
	var corpses: Array = []  # [pos, color, angle, horse, sprite_key]
	var blood := PackedVector3Array()   # (x, y, rozmiar)
	var craters: Array = []  # węzły Crater (każdy rysuje się raz - nie przerysowuje się przy każdym poległym)
	var dirty := false
	var _mms := {}           # rodzaj żołnierza -> MultiMesh z poległymi tego rodzaju
	var bufs := {}           # rodzaj żołnierza -> dane instancji poległych (12 liczb na ciało)
	var no_tex := 0          # ilu poległych bez sprite'a (rysowanych kształtami)
	var blood_buf := PackedFloat32Array()
	var _blood_mm: MultiMesh
	static var _btex: ImageTexture

	static func _blood_tex() -> ImageTexture:
		## Plama krwi 32x32: ciemny środek, jaśniejsza kropla z boku, miękki brzeg (jak dawne dwa koła).
		if _btex == null:
			var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			for y in 32:
				for x in 32:
					var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
					var d2 := Vector2(x - 20.0, y - 11.5).length() / 9.0
					var a := clampf((1.0 - d) * 3.0, 0.0, 1.0) * 0.5
					var col := Color(0.32, 0.04, 0.03, a)
					if d2 < 1.0:
						col = col.lerp(Color(0.42, 0.05, 0.04, maxf(a, 0.45)), clampf((1.0 - d2) * 3.0, 0.0, 1.0))
					im.set_pixel(x, y, col)
			im.generate_mipmaps()
			_btex = ImageTexture.create_from_image(im)
		return _btex

	static func blood_inst(b: Vector3) -> PackedFloat32Array:
		var r := 6.4 * b.z
		return PackedFloat32Array([r, 0.0, 0.0, b.x, 0.0, -r, 0.0, b.y, 1.0, 1.0, 1.0, 1.0])

	static func corpse_inst(p: Vector2, a: float) -> PackedFloat32Array:
		## Ciało jako instancja MultiMesh: obrót, spłaszczenie (leży), przygaszony kolor.
		var S := Regiment.SPRITE_WORLD
		var cs := cos(a) * S
		var sn := sin(a) * S
		return PackedFloat32Array([cs, -sn * 0.82, 0.0, p.x, sn, cs * 0.82, 0.0, p.y, 0.66, 0.62, 0.58, 0.95])

	func rebuild_blood() -> void:
		blood_buf = PackedFloat32Array()
		for b in blood:
			blood_buf.append_array(blood_inst(b))

	func rebuild_bufs() -> void:
		bufs.clear()
		no_tex = 0
		for c in corpses:
			if c.size() <= 4 or c[4] == "":
				no_tex += 1
			if c.size() > 4 and c[4] != "":
				if not bufs.has(c[4]):
					bufs[c[4]] = PackedFloat32Array()
				var b: PackedFloat32Array = bufs[c[4]]
				b.append_array(corpse_inst(c[0], c[2]))
				bufs[c[4]] = b
	static var _qm: QuadMesh

	static func _quad() -> QuadMesh:
		if _qm == null:
			_qm = QuadMesh.new()
			_qm.size = Vector2(1, 1)
		return _qm

	func _draw() -> void:
		var _pt := Time.get_ticks_usec() if Battle.PROF else 0
		_draw_impl()
		if Battle.PROF:
			Battle.pf("d_corpses", _pt)


	func _draw_impl() -> void:
		# plamy krwi: jeden MultiMesh z gotową teksturą plamy (tysiące plam = jedno polecenie rysowania)
		if not blood_buf.is_empty():
			if _blood_mm == null:
				_blood_mm = MultiMesh.new()
				_blood_mm.transform_format = MultiMesh.TRANSFORM_2D
				_blood_mm.use_colors = true
				_blood_mm.mesh = _quad()
			if _blood_mm.instance_count != blood_buf.size() / 12:
				_blood_mm.instance_count = blood_buf.size() / 12
			_blood_mm.buffer = blood_buf
			draw_multimesh(_blood_mm, _blood_tex())
		# Polegli ze sprite'ami: jeden MultiMesh na rodzaj żołnierza (setki ciał = kilka poleceń rysowania).
		# Bufory dopisywane przy każdej śmierci (add_corpse) - tu tylko podanie gotowych danych karcie.
		for key in bufs:
			var tex: Texture2D = Regiment.sprite_tex.get(key)
			var buf: PackedFloat32Array = bufs[key]
			if tex == null or buf.is_empty():
				continue
			var mm: MultiMesh = _mms.get(key)
			if mm == null:
				mm = MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_2D
				mm.use_colors = true
				mm.mesh = _quad()
				_mms[key] = mm
			if mm.instance_count != buf.size() / 12:
				mm.instance_count = buf.size() / 12
			mm.buffer = buf
			draw_multimesh(mm, tex)
		for c in corpses:
			if no_tex == 0:
				break   # wszyscy polegli mają sprite'y - narysowani wyżej
			if c.size() > 4 and Regiment.sprite_tex.has(c[4]):
				continue
			var p: Vector2 = c[0]
			var col: Color = c[1]
			var dir := Vector2.from_angle(c[2])
			if c[3]:
				draw_line(p - dir * 5.0, p + dir * 5.0, Color(0.28, 0.18, 0.1), 4.0)
				draw_line(p + dir * 4.0, p + dir * 7.0 + dir.orthogonal() * 2.0, Color(0.28, 0.18, 0.1), 2.0)
			draw_line(p - dir * 3.0 + dir.orthogonal() * 3.0, p + dir * 5.0 + dir.orthogonal() * 3.0, Color(0.25, 0.17, 0.1, 0.8), 0.8)
			draw_circle(p, 2.5, col.darkened(0.55))
			draw_circle(p + dir * 1.5, 1.8, col.darkened(0.3))


class Crater extends Node2D:
	## Lej po kuli jako osobny element: rysowany raz, pod poległymi i krwią (za rodzicem).
	var sz := 1.0
	var ang := 0.0
	var seed_v := 1

	func _draw() -> void:
		_draw_crater(Vector2.ZERO, sz, ang, seed_v)

	static func _blob(p: Vector2, r: float, rng: RandomNumberGenerator, rough: float, n := 14) -> PackedVector2Array:
		## Nieregularny, zamknięty kształt (poszarpany brzeg leja, wału ziemi, osmalenia).
		var pts := PackedVector2Array()
		var ph := rng.randf() * TAU
		var w1 := rng.randf_range(0.5, 1.0)
		for k in n:
			var a := TAU * k / n
			var f := 1.0 + rough * (0.55 * sin(a * 2.0 + ph) * w1 + rng.randf_range(-0.45, 0.45))
			pts.append(p + Vector2.from_angle(a) * r * f)
		return pts

	func _draw_crater(p: Vector2, sz: float, ang: float, seed_v: int) -> void:
		## Lej po kuli: osmalona, zryta trawa, rozbryzgi i grudy wyrzuconej ziemi (więcej w kierunku lotu),
		## wypiętrzony wał, a w środku dół - ściana od strony światła w cieniu, przeciwległa oświetlona.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		var s := maxf(sz, 0.35) * 1.15
		var light := Vector2(-0.7, -0.7)   # światło z góry-lewej, jak na sprite'ach
		var fly := Vector2.from_angle(ang)
		# osmalona i zdeptana trawa wokół
		draw_colored_polygon(_blob(p, 17.0 * s, rng, 0.35, 16), Color(0.16, 0.13, 0.07, 0.16))
		draw_colored_polygon(_blob(p, 11.5 * s, rng, 0.3, 14), Color(0.2, 0.15, 0.08, 0.2))
		# promienie rozbryzgu ziemi
		for k in rng.randi_range(9, 15):
			var d := Vector2.from_angle(rng.randf() * TAU)
			if rng.randf() < 0.45:
				d = (d + fly * 1.2).normalized()   # ziemia leci dalej w kierunku lotu kuli
			var r0 := 6.0 * s
			var r1 := rng.randf_range(10.0, 21.0) * s
			var wd := rng.randf_range(0.8, 2.2) * s
			var side := d.orthogonal() * wd
			draw_colored_polygon(PackedVector2Array([p + d * r0 + side, p + d * r1, p + d * r0 - side]),
				Color(0.33, 0.25, 0.15, rng.randf_range(0.3, 0.55)))
		# grudy ziemi i darni
		for k in rng.randi_range(14, 24):
			var d := Vector2.from_angle(rng.randf() * TAU)
			if rng.randf() < 0.35:
				d = (d + fly).normalized()
			var q := p + d * rng.randf_range(7.5, 24.0) * s
			var cr := rng.randf_range(0.45, 1.3) * s
			var turf := rng.randf() < 0.3
			draw_circle(q + Vector2(0.4, 0.4) * cr, cr, Color(0.06, 0.05, 0.03, 0.35))   # cień grudy
			draw_circle(q, cr, Color(0.28, 0.33, 0.14, 0.9) if turf else Color(0.4, 0.3, 0.19, 0.92))
		# wał wyrzuconej ziemi
		draw_colored_polygon(_blob(p, 8.6 * s, rng, 0.22, 16), Color(0.36, 0.27, 0.17, 0.92))
		draw_colored_polygon(_blob(p + light * 1.1 * s, 7.6 * s, rng, 0.18, 16), Color(0.45, 0.35, 0.22, 0.85))   # zbocze wału w słońcu
		# dół
		draw_colored_polygon(_blob(p, 6.0 * s, rng, 0.2, 14), Color(0.13, 0.09, 0.06, 0.97))
		draw_colored_polygon(_blob(p - light * 1.3 * s, 4.4 * s, rng, 0.2, 12), Color(0.27, 0.19, 0.12, 0.95))   # ściana oświetlona (naprzeciw światła)
		draw_colored_polygon(_blob(p + light * 0.6 * s, 2.3 * s, rng, 0.25, 10), Color(0.08, 0.06, 0.04, 0.95))   # dno
		# kamyki i odłamki na dnie
		for k in rng.randi_range(2, 4):
			draw_circle(p + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)) * s, rng.randf_range(0.3, 0.6) * s,
				Color(0.5, 0.45, 0.38, 0.8))


func _chunk(p: Vector2) -> Chunk:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	var c: Chunk = _chunks.get(key)
	if c == null:
		c = Chunk.new()
		c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(c)
		_chunks[key] = c
	c.dirty = true
	return c


func add_corpse(p: Vector2, col: Color, angle: float, horse := false, key := "") -> void:
	Net.record([7, p, col, angle, horse, key])
	var c := _chunk(p)
	# piechur pada w bok albo do tyłu (obrót ±60-180°); koń przewraca się na bok
	var fall := randf_range(-0.6, 0.6) if horse else randf_range(1.0, PI) * (1.0 if randf() < 0.5 else -1.0)
	c.corpses.append([p, col, angle + fall, horse, key])
	if c.corpses.size() > MAX_PER_CHUNK:
		c.corpses = c.corpses.slice(100)   # najstarsze znikają setkami - rzadkie przebudowanie buforów
		c.rebuild_bufs()
	elif key == "":
		c.no_tex += 1
	else:
		if not c.bufs.has(key):
			c.bufs[key] = PackedFloat32Array()
		var b: PackedFloat32Array = c.bufs[key]
		b.append_array(Chunk.corpse_inst(p, angle + fall))
		c.bufs[key] = b


func add_blood(p: Vector2, size := 1.0) -> void:
	var c := _chunk(p)
	var b := Vector3(p.x + randf_range(-1, 1), p.y + randf_range(-1, 1), size)
	c.blood.append(b)
	if c.blood.size() > MAX_PER_CHUNK:
		c.blood = c.blood.slice(100)
		c.rebuild_blood()
	else:
		c.blood_buf.append_array(Chunk.blood_inst(b))


func add_crater(p: Vector2, size := 1.0) -> void:
	var c := _chunk(p)
	var cr := Crater.new()
	cr.position = p
	cr.sz = size
	cr.ang = randf() * TAU
	cr.seed_v = randi()
	cr.show_behind_parent = true   # pod poległymi i krwią
	c.add_child(cr)
	c.craters.append(cr)
	if c.craters.size() > 200:
		(c.craters.pop_front() as Node).queue_free()


var _redraw_t := 0.0


func _process(delta: float) -> void:
	# Przerysowanie fragmentu z poległymi najwyżej 4 razy na sekundę: w wielkiej bitwie ktoś pada co klatkę,
	# a każde przerysowanie to setki ciał - ciało pojawia się z opóźnieniem najwyżej ćwierć sekundy.
	_redraw_t -= delta
	if _redraw_t > 0.0:
		return
	_redraw_t = 0.25
	for c in _chunks.values():
		if c.dirty:
			c.dirty = false
			c.queue_redraw()
