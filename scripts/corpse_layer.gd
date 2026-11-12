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

	func _draw() -> void:
		for b in blood:
			var bp := Vector2(b.x, b.y)
			draw_circle(bp, 3.2 * b.z, Color(0.32, 0.04, 0.03, 0.5))
			if b.z > 1.0:
				draw_circle(bp + Vector2(0.8, -0.6) * b.z, 1.8 * b.z, Color(0.42, 0.05, 0.04, 0.45))
		for c in corpses:
			var p: Vector2 = c[0]
			var tex: Texture2D = Regiment.sprite_tex.get(c[4]) if c.size() > 4 else null
			if tex != null:
				# poległy: ten sam pikselowy żołnierz (koń z jeźdźcem) co w szyku, przewrócony na bok i przygaszony
				var S := Regiment.SPRITE_WORLD
				draw_set_transform(p, c[2], Vector2(1.0, -0.82))   # sprite odwrócony w osi Y (QuadMesh); spłaszczony = leży
				draw_texture_rect(tex, Rect2(-S * 0.5, -S * 0.5, S, S), false, Color(0.66, 0.62, 0.58, 0.95))
				draw_set_transform(Vector2.ZERO)
				continue
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
		c.corpses.remove_at(0)


func add_blood(p: Vector2, size := 1.0) -> void:
	var c := _chunk(p)
	c.blood.append(Vector3(p.x + randf_range(-1, 1), p.y + randf_range(-1, 1), size))
	if c.blood.size() > MAX_PER_CHUNK:
		c.blood.remove_at(0)


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


func _process(_delta: float) -> void:
	for c in _chunks.values():
		if c.dirty:
			c.dirty = false
			c.queue_redraw()
