class_name BridgeLayer
extends Node2D
## Drewniane mosty w miejscach, gdzie drogi przecinają rzeki.

var bridges: Array = []  # [pos, kąt, szerokość rzeki]
var fords: Array = []    # [pos, indeks rzeki, czy_most]
var rivers: Array = []   # [PackedVector2Array, szerokość]


func _ready() -> void:
	queue_redraw()


func _draw_fords() -> void:
	## Płyciznę rysuje shader terenu (ford_tex). Tu tylko kamienie wystające z wody w brodzie.
	for f in fords:
		var c: Vector2 = f[0]
		var ri: int = f[1]
		if ri < 0 or ri >= rivers.size():
			continue
		var pts: PackedVector2Array = rivers[ri][0]
		var width: float = rivers[ri][1]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(c.x * 13.0 + c.y * 7.0)
		for m in pts.size() - 1:
			var a := pts[m]
			if a.distance_to(c) > Terrain.FORD_R * 0.85:
				continue
			var tan := (pts[m + 1] - a).normalized()
			for k in 5:
				var p := a + tan * rng.randf_range(0.0, 60.0) + tan.orthogonal() * rng.randf_range(-0.42, 0.42) * width
				var r := rng.randf_range(1.6, 3.4)
				draw_circle(p + Vector2(0.8, 1.0), r, Color(0.1, 0.15, 0.15, 0.35))
				draw_circle(p, r, Color(0.52, 0.50, 0.44, 0.9))
				draw_circle(p - Vector2(0.5, 0.6) * r * 0.4, r * 0.45, Color(0.70, 0.68, 0.60, 0.8))


const BAKE_PX := 1.5   # jak osady: 1 teksel = 1.5 jednostki świata, wyświetlane bez wygładzania
var _baked := false
var _ci: CanvasItem = self


func _visible_bridges() -> Array:
	## Dwie drogi przecinające rzekę tuż obok siebie dawały nachodzące mosty - rysujemy jeden (logika przejść bez zmian).
	var out: Array = []
	for b in bridges:
		var dup := false
		for o in out:
			if (o[0] as Vector2).distance_to(b[0]) < 110.0:
				dup = true
				break
		if not dup:
			out.append(b)
	return out


func _draw() -> void:
	_draw_fords()
	if _baked:
		return
	for b in _visible_bridges():
		_paint_bridge(b, Vector2.ZERO)
	if DisplayServer.get_name() != "headless" and not bridges.is_empty():
		_bake_all.call_deferred()


func _bake_all() -> void:
	if _baked:
		return
	_baked = true
	var jobs: Array = []
	for b in _visible_bridges():
		var ext: float = (float(b[2]) + 60.0) * 0.5 + 40.0
		var px := int(ceil(ext * 2.0 / BAKE_PX))
		var vp := SubViewport.new()
		vp.size = Vector2i(px, px)
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var painter := Node2D.new()
		painter.position = Vector2(ext, ext) / BAKE_PX
		painter.scale = Vector2.ONE / BAKE_PX
		var bb: Array = b
		painter.draw.connect(func() -> void:
			_ci = painter
			_paint_bridge(bb, -(bb[0] as Vector2))
			_ci = self)
		vp.add_child(painter)
		add_child(vp)
		jobs.append([vp, b[0]])
	await RenderingServer.frame_post_draw
	for j in jobs:
		var vp: SubViewport = j[0]
		var img := vp.get_texture().get_image()
		vp.queue_free()
		if img == null or img.is_empty():
			continue
		img.generate_mipmaps()
		var spr := Sprite2D.new()
		spr.texture = ImageTexture.create_from_image(img)
		spr.position = j[1]
		spr.scale = Vector2(BAKE_PX, BAKE_PX)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		spr.material = m
		add_child(spr)
	queue_redraw()


enum BridgeType { STONE, WOOD, PONTOON }


func _bridge_type(b: Array) -> int:
	## Typ mostu stały dla danego miejsca (ziarno z pozycji), zależny od teatru wojny:
	## Rosja - głównie drewniane, Egipt - kamienne, gdzie indziej mieszanka; pontony saperów wszędzie rzadziej.
	var pos: Vector2 = b[0]
	var r := float(absi(int(pos.x * 7.13 + pos.y * 3.71)) % 1000) / 1000.0
	var th: Dictionary = Terrain.theme
	var stone := 0.4
	var wood := 0.4
	if float(th.get("snow", 0.0)) > 0.5:
		stone = 0.25
		wood = 0.55
	elif float(th.get("desert", 0.0)) > 0.5:
		stone = 0.6
		wood = 0.15
	if r < stone:
		return BridgeType.STONE
	if r < stone + wood:
		return BridgeType.WOOD
	return BridgeType.PONTOON


func _paint_bridge(b: Array, off: Vector2) -> void:
	match _bridge_type(b):
		BridgeType.STONE:
			_paint_stone_bridge(b, off)
		BridgeType.PONTOON:
			_paint_pontoon_bridge(b, off)
		_:
			_paint_wood_bridge(b, off)


func _quad_pts(a: Vector2, c: Vector2, side: Vector2, hw: float, shift := Vector2.ZERO) -> PackedVector2Array:
	return PackedVector2Array([a - side * hw + shift, c - side * hw + shift, c + side * hw + shift, a + side * hw + shift])


func _paint_stone_bridge(b: Array, off: Vector2) -> void:
	## Kamienny most łukowy: brukowany pomost, kamienne balustrady z gzymsem, filary z ostrogami wodnymi
	## (klinowe przyczółki łamiące nurt) po obu stronach, cienie łuków na wodzie między filarami.
	var outline := Color(0.14, 0.12, 0.10)
	var stone := Color(0.66, 0.63, 0.57)
	var stone_d := Color(0.48, 0.45, 0.40)
	var p: Vector2 = b[0] + off
	var dir := Vector2.from_angle(b[1])
	var side := dir.orthogonal()
	var length: float = float(b[2]) + 64.0
	var hw := 27.0
	var a := p - dir * length * 0.5
	var c := p + dir * length * 0.5
	var piers := maxi(1, int(length / 46.0))
	_ci.draw_colored_polygon(_quad_pts(a, c, side, hw + 2.0, Vector2(6, 7)), Color(0, 0.03, 0.05, 0.35))
	for k in piers + 1:
		var t0 := float(k) / (piers + 1)
		var t1 := float(k + 1) / (piers + 1)
		var m := a.lerp(c, (t0 + t1) * 0.5)
		for sgn in [-1.0, 1.0]:
			_ci.draw_circle(m + side * sgn * (hw + 3.0), length / (piers + 1) * 0.32, Color(0.02, 0.06, 0.08, 0.22))
	for k in piers:
		var q := a.lerp(c, float(k + 1) / (piers + 1))
		for sgn in [-1.0, 1.0]:
			var base0: Vector2 = q - dir * 8.0 + side * sgn * hw
			var base1: Vector2 = q + dir * 8.0 + side * sgn * hw
			var tip: Vector2 = q + side * sgn * (hw + 16.0)
			_ci.draw_colored_polygon(PackedVector2Array([base0 - side * sgn * 1.5, tip + side * sgn * 1.5, base1 - side * sgn * 1.5]), outline)
			_ci.draw_colored_polygon(PackedVector2Array([base0, tip, base1]), stone_d if sgn > 0.0 else stone)
	_ci.draw_colored_polygon(_quad_pts(a, c, side, hw + 1.5), outline)
	_ci.draw_colored_polygon(_quad_pts(a, c, side, hw), Color(0.58, 0.55, 0.50))
	var rows := int(hw * 2.0 / 4.0)
	var cols := int(length / 4.0)
	for i in cols:
		for j in rows:
			if (i * 7 + j * 13) % 5 == 0:
				var q := a + dir * (i * 4.0 + 1.0) + side * (-hw + j * 4.0 + 1.0)
				_ci.draw_rect(Rect2(q, Vector2(2.4, 2.4)), Color(0.50, 0.47, 0.43) if (i + j) % 2 == 0 else Color(0.66, 0.63, 0.58))
	var light_side := -1.0 if (-side).dot(Vector2(-0.7, -0.7)) > 0.0 else 1.0
	for sgn in [-1.0, 1.0]:
		var e0: Vector2 = a + side * hw * sgn
		var e1: Vector2 = c + side * hw * sgn
		_ci.draw_line(e0, e1, outline, 6.0)
		_ci.draw_line(e0, e1, stone if sgn == light_side else stone_d, 4.0)
		_ci.draw_line(e0 - side * sgn * 0.8, e1 - side * sgn * 0.8, stone.lightened(0.15), 1.0)
		var n := int(length / 6.0)
		for k in n:
			var q: Vector2 = e0.lerp(e1, float(k) / n)
			_ci.draw_line(q - side * 1.8, q + side * 1.8, stone_d.darkened(0.2), 0.6)
	for e in [a, c]:
		var ev: Vector2 = e
		var ed: Vector2 = dir * (10.0 if ev == a else -10.0)
		var q := PackedVector2Array([ev - side * (hw + 8) - ed, ev - side * (hw + 4) + ed * 0.6,
			ev + side * (hw + 4) + ed * 0.6, ev + side * (hw + 8) - ed])
		_ci.draw_colored_polygon(q, outline)
		_ci.draw_colored_polygon(PackedVector2Array([q[0] + side * 1.5, q[1] + side * 1.2, q[2] - side * 1.2, q[3] - side * 1.5]), stone_d)


func _paint_pontoon_bridge(b: Array, off: Vector2) -> void:
	## Most pontonowy saperów: łodzie ustawione w poprzek nurtu (wzdłuż rzeki), na nich belki i pokład z desek,
	## liny kotwiczne skośnie w górę nurtu. Na brzegach drewniane rampy.
	var outline := Color(0.12, 0.08, 0.05)
	var hull := Color(0.30, 0.22, 0.14)
	var plank := Color(0.58, 0.45, 0.29)
	var p: Vector2 = b[0] + off
	var dir := Vector2.from_angle(b[1])
	var side := dir.orthogonal()
	var length: float = float(b[2]) + 56.0
	var hw := 22.0
	var a := p - dir * length * 0.5
	var c := p + dir * length * 0.5
	var boats := maxi(2, int((length - 30.0) / 15.0))
	_ci.draw_colored_polygon(_quad_pts(a, c, side, hw + 9.0, Vector2(5, 6)), Color(0, 0.03, 0.05, 0.28))
	for k in boats:
		var q := a.lerp(c, (k + 1.0) / (boats + 1.0))
		var half_len := hw + 10.0
		var hull_pts := PackedVector2Array([q - side * (half_len + 3.0), q - side * half_len + dir * 4.5, q + side * half_len + dir * 4.5,
			q + side * (half_len + 3.0), q + side * half_len - dir * 4.5, q - side * half_len - dir * 4.5])
		_ci.draw_colored_polygon(hull_pts, outline)
		var inner := PackedVector2Array()
		for v in hull_pts:
			inner.append(q + (v - q) * 0.82)
		_ci.draw_colored_polygon(inner, hull)
		_ci.draw_line(q - side * half_len * 0.8, q + side * half_len * 0.8, hull.darkened(0.3), 1.0)
	for k in [0, boats - 1]:
		var q := a.lerp(c, (float(k) + 1.0) / (boats + 1.0))
		for sgn in [-1.0, 1.0]:
			var anchor: Vector2 = q + side * sgn * (hw + 34.0) + dir * (8.0 if k == 0 else -8.0)
			_ci.draw_line(q + side * sgn * (hw + 10.0), anchor, Color(0.55, 0.48, 0.36, 0.8), 0.6)
			_ci.draw_rect(Rect2(anchor - Vector2(1, 1), Vector2(2, 2)), Color(0.15, 0.13, 0.12))
	_ci.draw_colored_polygon(_quad_pts(a, c, side, hw + 1.2), outline)
	_ci.draw_colored_polygon(_quad_pts(a, c, side, hw), plank)
	var n := int(length / 4.0)
	for k in n:
		var q := a.lerp(c, (k + 0.5) / n)
		_ci.draw_line(q - side * hw, q + side * hw, plank.darkened(0.15) if k % 2 == 0 else plank.lightened(0.06), 2.6)
	for sgn in [-1.0, 1.0]:
		_ci.draw_line(a + side * hw * sgn, c + side * hw * sgn, Color(0.35, 0.25, 0.15), 2.4)
		_ci.draw_line(a + side * hw * 0.35 * sgn, c + side * hw * 0.35 * sgn, Color(0.35, 0.25, 0.15, 0.5), 1.2)
	for e in [a, c]:
		var ev: Vector2 = e
		var ed: Vector2 = dir * (12.0 if ev == a else -12.0)
		_ci.draw_colored_polygon(PackedVector2Array([ev - side * hw - ed, ev - side * hw, ev + side * hw, ev + side * hw - ed]), plank.darkened(0.2))


func _paint_wood_bridge(b: Array, off: Vector2) -> void:
	## Drewniany most na palach (jarzmowy): pokład z desek, poręcze, a po bokach rzędy pali z zastrzałami.
	var p: Vector2 = b[0] + off
	var dir := Vector2.from_angle(b[1])
	var side := dir.orthogonal()
	var length: float = float(b[2]) + 60.0
	var a := p - dir * length * 0.5
	var c := p + dir * length * 0.5
	var outline := Color(0.16, 0.11, 0.07)
	var post := Color(0.30, 0.21, 0.13)
	var bents := maxi(2, int(length / 22.0))
	for k in bents:
		var q := a.lerp(c, (k + 0.5) / bents)
		for sgn in [-1.0, 1.0]:
			var pp: Vector2 = q + side * sgn * 34.0
			_ci.draw_line(q + side * sgn * 24.0, pp, post, 1.6)
			_ci.draw_rect(Rect2(pp - Vector2(2.6, 2.6), Vector2(5.2, 5.2)), outline)
			_ci.draw_rect(Rect2(pp - Vector2(1.7, 1.7), Vector2(3.4, 3.4)), post.lightened(0.15))
	_paint_wood_deck(b, off)


func _paint_wood_deck(b: Array, off: Vector2) -> void:
	## Drewniany most z góry: kamienne przyczółki na brzegach, deski poprzeczne cieniowane od światła z lewej-góry,
	## belki-poręcze ze słupkami, ciemny obrys (styl pixel-art).
	var plank := Color(0.54, 0.40, 0.25)
	var outline := Color(0.16, 0.11, 0.07)
	var rail := Color(0.33, 0.23, 0.14)
	var stone := Color(0.55, 0.53, 0.48)
	var p: Vector2 = b[0] + off
	var dir := Vector2.from_angle(b[1])
	var side := dir.orthogonal()
	var length: float = float(b[2]) + 60.0
	var half_w := 30.0
	var a := p - dir * length * 0.5
	var c := p + dir * length * 0.5
	var sh := Vector2(6, 7)
	# cień na wodzie
	_ci.draw_colored_polygon(PackedVector2Array([a - side * half_w + sh, c - side * half_w + sh,
		c + side * half_w + sh, a + side * half_w + sh]), Color(0, 0.03, 0.05, 0.38))
	# przyczółki z kamienia
	for e in [a, c]:
		var ed: Vector2 = dir * (8.0 if e == a else -8.0)
		var q := PackedVector2Array([e - side * (half_w + 6) - ed, e - side * (half_w + 6) + ed * 2.0,
			e + side * (half_w + 6) + ed * 2.0, e + side * (half_w + 6) - ed])
		_ci.draw_colored_polygon(q, outline)
		var qi := PackedVector2Array([q[0] + side * 1.5 + ed * 0.2, q[1] + side * 1.5 - ed * 0.2, q[2] - side * 1.5 - ed * 0.2, q[3] - side * 1.5 + ed * 0.2])
		_ci.draw_colored_polygon(qi, stone)
		for k in 6:
			var t := (k + 0.5) / 6.0
			var sp: Vector2 = (e - side * (half_w + 4)).lerp(e + side * (half_w + 4), t) + ed * 0.5
			_ci.draw_rect(Rect2(sp - Vector2(1.5, 1.5), Vector2(3, 3)), stone.darkened(0.25 if k % 2 == 0 else 0.1))
	# pomost
	var deck := PackedVector2Array([a - side * half_w, c - side * half_w, c + side * half_w, a + side * half_w])
	var deck_o := PackedVector2Array([a - side * (half_w + 1.5), c - side * (half_w + 1.5), c + side * (half_w + 1.5), a + side * (half_w + 1.5)])
	_ci.draw_colored_polygon(deck_o, outline)
	_ci.draw_colored_polygon(deck, plank)
	var n := int(length / 4.5)
	for k in n:
		var q := a.lerp(c, (k + 0.5) / n)
		var v := fposmod(k * 0.618, 1.0)
		var col := plank.darkened(0.18) if k % 3 == 0 else (plank.lightened(0.1) if v > 0.6 else plank)
		_ci.draw_line(q - side * half_w, q + side * half_w, col, 3.0)
		_ci.draw_line(q + dir * 2.2 - side * half_w, q + dir * 2.2 + side * half_w, plank.darkened(0.45), 1.0)   # szpara
	# koleiny od wozów
	for sgn in [-1.0, 1.0]:
		_ci.draw_line(a + side * 9.0 * sgn, c + side * 9.0 * sgn, Color(plank.darkened(0.25), 0.6), 2.0)
	# poręcze: belka w świetle po stronie zwróconej do światła
	var light_side := -1.0 if (-side).dot(Vector2(-0.7, -0.7)) > 0.0 else 1.0
	for sgn in [-1.0, 1.0]:
		var e0: Vector2 = a + side * half_w * sgn
		var e1: Vector2 = c + side * half_w * sgn
		_ci.draw_line(e0, e1, outline, 5.0)
		_ci.draw_line(e0, e1, rail.lightened(0.2) if sgn == light_side else rail, 3.0)
		for k in range(0, n + 1, 4):
			var q: Vector2 = e0.lerp(e1, float(k) / n)
			_ci.draw_rect(Rect2(q - Vector2(2.5, 2.5), Vector2(5, 5)), outline)
			_ci.draw_rect(Rect2(q - Vector2(1.5, 1.5), Vector2(3, 3)), rail.lightened(0.3))
