class_name EdgeFog
extends Node2D
## Krawędź mapy: szeroki, miękki pas mgły (nieregularny brzeg, od przezroczystego do pełnego) — świat
## nie kończy się ostrą linią. W pasie EDGE wojska nie mogą stanąć (rozkazy są przesuwane do środka).

const EDGE := 520.0        # szerokość mgły (jednostki świata)
const NO_GO := 380.0       # bliżej krawędzi nie da się wejść (poza uciekającymi)
const STEP := 48.0

var map_size := Vector2(4000, 4000)
var fog_col := Color(0.12, 0.13, 0.12)


static func clamp_inside(p: Vector2, size: Vector2, margin := NO_GO) -> Vector2:
	return Vector2(clampf(p.x, margin, size.x - margin), clampf(p.y, margin, size.y - margin))


func _ready() -> void:
	z_index = 50
	# mgła w kolorze pasującym do teatru (zima jaśniejsza, pustynia piaskowa)
	if float(Terrain.tv("snow")) > 0.5:
		fog_col = Color(0.80, 0.84, 0.90)
	elif float(Terrain.tv("desert")) > 0.5:
		fog_col = Color(0.62, 0.55, 0.42)
	queue_redraw()


func _depth(t: float, seed_v: float) -> float:
	## Nieregularna szerokość mgły wzdłuż brzegu (kilka nałożonych fal).
	return EDGE * (0.82 + 0.10 * sin(t * 0.0041 + seed_v) + 0.06 * sin(t * 0.0113 + seed_v * 2.3) + 0.04 * sin(t * 0.031 + seed_v * 5.1))


func _draw() -> void:
	var far := 6000.0
	var solid := Color(fog_col, 1.0)
	# poza mapą — pełna mgła
	draw_rect(Rect2(-far, -far, map_size.x + far * 2.0, far), solid)
	draw_rect(Rect2(-far, map_size.y, map_size.x + far * 2.0, far), solid)
	draw_rect(Rect2(-far, 0, far, map_size.y), solid)
	draw_rect(Rect2(map_size.x, 0, far, map_size.y), solid)
	# 4 brzegi: pas od krawędzi (alfa 1) przez środek (0.55) do brzegu mgły (0)
	var sides := [
		[Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), map_size.x, 0.0],    # góra
		[Vector2(0, map_size.y), Vector2(1, 0), Vector2(0, -1), map_size.x, 1.7],   # dół
		[Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), map_size.y, 3.1],    # lewo
		[Vector2(map_size.x, 0), Vector2(0, 1), Vector2(-1, 0), map_size.y, 4.6],   # prawo
	]
	var c0 := Color(fog_col, 1.0)
	var c1 := Color(fog_col, 0.55)
	var c2 := Color(fog_col, 0.0)
	for sd in sides:
		var o: Vector2 = sd[0]
		var along: Vector2 = sd[1]
		var inward: Vector2 = sd[2]
		var length: float = sd[3]
		var sv: float = sd[4]
		var n := int(ceil(length / STEP))
		for k in n:
			var t0 := k * STEP
			var t1 := minf((k + 1) * STEP, length)
			var d0 := _depth(t0, sv)
			var d1 := _depth(t1, sv)
			var a0 := o + along * t0
			var a1 := o + along * t1
			var m0 := a0 + inward * d0 * 0.45
			var m1 := a1 + inward * d1 * 0.45
			var e0 := a0 + inward * d0
			var e1 := a1 + inward * d1
			draw_polygon(PackedVector2Array([a0, a1, m1, m0]), PackedColorArray([c0, c0, c1, c1]))
			draw_polygon(PackedVector2Array([m0, m1, e1, e0]), PackedColorArray([c1, c1, c2, c2]))
