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
	var craters: Array = []  # [pos, size, angle]
	var dirty := false

	func _draw() -> void:
		for c in craters:
			var p: Vector2 = c[0]
			var sz: float = c[1]
			draw_circle(p, 9.0 * sz, Color(0.2, 0.15, 0.1, 0.22))
			draw_circle(p, 5.5 * sz, Color(0.12, 0.09, 0.06, 0.38))
			var d := Vector2.from_angle(c[2])
			draw_circle(p + d * 6.0 * sz, 2.2 * sz, Color(0.3, 0.22, 0.14, 0.35))
			draw_circle(p - d.orthogonal() * 6.5 * sz, 1.8 * sz, Color(0.3, 0.22, 0.14, 0.3))
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


func _chunk(p: Vector2) -> Chunk:
	var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	var c: Chunk = _chunks.get(key)
	if c == null:
		c = Chunk.new()
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
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
	c.craters.append([p, size, randf() * TAU])
	if c.craters.size() > 200:
		c.craters.remove_at(0)


func _process(_delta: float) -> void:
	for c in _chunks.values():
		if c.dirty:
			c.dirty = false
			c.queue_redraw()
