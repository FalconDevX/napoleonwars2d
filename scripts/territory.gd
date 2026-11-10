class_name Territory
extends Node2D
## Granice państw: każda osada ma swój region (ważony diagram Voronoja - teren najbliższy tej osadzie),
## regiony tej samej strony łączą się w jedno terytorium. Pułki w polu dodatkowo zajmują teren wokół siebie.
## Rysowane shaderem (gładkie granice + delikatne wypełnienie w kolorze strony).

const CELL := 100.0
const UPDATE_EVERY := 0.8
const K := 5              # ile najbliższych osad pamiętamy dla każdej komórki
const REACH := 2600.0     # dalej od osady teren jest niczyj
const SLOPE := 600.0      # jak szybko rośnie "pewność" przynależności od granicy
const CITY_WEIGHT := 1.35 # miasta mają większe regiony niż wsie

var battle: Battle
var gw := 0
var gh := 0
var _inf0 := PackedFloat32Array()
var _inf1 := PackedFloat32Array()
var _near_idx := PackedInt32Array()   # K najbliższych osad dla komórki (stałe - osady się nie ruszają)
var _near_d := PackedFloat32Array()   # ważone odległości do nich
var _bytes := PackedByteArray()
var _tex: ImageTexture        # bieżąca klatka pola wpływów
var _tex_prev: ImageTexture   # poprzednia (do płynnego przejścia)
var _img: Image
var _mat: ShaderMaterial
var _timer := 0.0

const SHADER := """
shader_type canvas_item;
// Dwie klatki pola wpływów (poprzednia i bieżąca) - przenikanie między przeliczeniami, żeby granice
// płynęły, a nie skakały. Próbkowanie bikubiczne (B-spline) zamiast liniowego: gładkie łuki zamiast łamanej.
uniform sampler2D infl_a : filter_linear;
uniform sampler2D infl_b : filter_linear;
uniform vec2 tex_size = vec2(64.0);
uniform float blend = 1.0;
uniform vec4 col0 : source_color;
uniform vec4 col1 : source_color;
uniform float fill = 0.12;

vec4 cubic_w(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

vec2 bicubic(sampler2D t, vec2 uv) {
	vec2 inv = 1.0 / tex_size;
	vec2 c = uv * tex_size - 0.5;
	vec2 f = fract(c);
	c -= f;
	vec4 xc = cubic_w(f.x);
	vec4 yc = cubic_w(f.y);
	vec4 cc = c.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 off = (cc + vec4(xc.yw, yc.yw) / s) * inv.xxyy;
	vec2 s0 = texture(t, off.xz).rg;
	vec2 s1 = texture(t, off.yz).rg;
	vec2 s2 = texture(t, off.xw).rg;
	vec2 s3 = texture(t, off.yw).rg;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	return mix(mix(s3, s2, sx), mix(s1, s0, sx), sy);
}

void fragment() {
	vec2 v = mix(bicubic(infl_a, UV), bicubic(infl_b, UV), smoothstep(0.0, 1.0, blend));
	float m = v.r;                       // siła wpływu (0.5 = granica terytorium)
	float side = v.g - 0.5;              // >0 = gracz, <0 = wróg
	float fm = max(fwidth(m), 0.0005);
	float fs = max(fwidth(side), 0.0005);
	float own = smoothstep(0.5 - fm, 0.5 + fm, m);
	float edge = 1.0 - smoothstep(0.0, fm * 1.6, abs(m - 0.5));
	float front = (1.0 - smoothstep(0.0, fs * 1.6, abs(side))) * own;
	vec3 c = side > 0.0 ? col0.rgb : col1.rgb;
	float a = own * fill + max(edge * own, edge * 0.6) * 0.7;
	c = mix(c, vec3(0.95, 0.9, 0.75), front * 0.6);
	a = max(a, front * 0.85);
	COLOR = vec4(c, a);
}
"""


func setup(p_battle: Battle) -> void:
	battle = p_battle
	gw = ceili(battle.map_size.x / CELL) + 1
	gh = ceili(battle.map_size.y / CELL) + 1
	_inf0.resize(gw * gh)
	_inf1.resize(gw * gh)
	_bytes.resize(gw * gh * 2)
	_build_nearest()
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("col0", Battle.owner_color(0))
	_mat.set_shader_parameter("col1", Battle.owner_color(1))
	material = _mat
	recompute()


func tick(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = UPDATE_EVERY
		recompute()
	_mat.set_shader_parameter("blend", clampf(1.0 - _timer / UPDATE_EVERY, 0.0, 1.0))
	# z bliska wypełnienie prawie niewidoczne, zostają same granice
	_mat.set_shader_parameter("fill", lerpf(0.16, 0.035, battle.soldier_alpha))


func _splat(arr: PackedFloat32Array, p: Vector2, radius: float, w: float) -> void:
	var cx := p.x / CELL
	var cy := p.y / CELL
	var rc := radius / CELL
	var x0 := maxi(0, floori(cx - rc))
	var x1 := mini(gw - 1, ceili(cx + rc))
	var y0 := maxi(0, floori(cy - rc))
	var y1 := mini(gh - 1, ceili(cy + rc))
	var inv := 1.0 / (rc * rc)
	for y in range(y0, y1 + 1):
		var dy := float(y) - cy
		var row := y * gw
		for x in range(x0, x1 + 1):
			var dx := float(x) - cx
			var q := 1.0 - (dx * dx + dy * dy) * inv
			if q > 0.0:
				arr[row + x] += q * q * w


func _build_nearest() -> void:
	var ss := battle.settlements
	var n := ss.size()
	_near_idx.resize(gw * gh * K)
	_near_d.resize(gw * gh * K)
	var bi := PackedInt32Array()
	var bd := PackedFloat32Array()
	bi.resize(K)
	bd.resize(K)
	for y in gh:
		for x in gw:
			var p := Vector2(x, y) * CELL
			bd.fill(INF)
			bi.fill(-1)
			for j in n:
				var d := p.distance_to(ss[j].position) / (CITY_WEIGHT if ss[j].is_city else 1.0)
				if d >= bd[K - 1]:
					continue
				var k := K - 1
				while k > 0 and bd[k - 1] > d:
					bd[k] = bd[k - 1]
					bi[k] = bi[k - 1]
					k -= 1
				bd[k] = d
				bi[k] = j
			var base := (y * gw + x) * K
			for k in K:
				_near_idx[base + k] = bi[k]
				_near_d[base + k] = bd[k]


func recompute() -> void:
	_inf0.fill(0.0)
	_inf1.fill(0.0)
	var fac := PackedInt32Array()
	for s in battle.settlements:
		fac.append(s.faction)
	# Pole ze znakiem dla każdej strony: 0.5 dokładnie na granicy jej regionów (dwusieczne Voronoja).
	for i in gw * gh:
		var base := i * K
		var own0 := INF
		var own1 := INF
		var not0 := INF
		var not1 := INF
		for k in K:
			var j := _near_idx[base + k]
			if j < 0:
				break
			var d := _near_d[base + k]
			var f := fac[j]
			if f == 0:
				own0 = minf(own0, d)
				not1 = minf(not1, d)
			elif f == 1:
				own1 = minf(own1, d)
				not0 = minf(not0, d)
			else:
				not0 = minf(not0, d)
				not1 = minf(not1, d)
		if own0 < INF:
			_inf0[i] = maxf(0.0, minf(0.5 + (minf(not0, own0 + SLOPE) - own0) / SLOPE, 0.5 + (REACH - own0) / SLOPE))
		if own1 < INF:
			_inf1[i] = maxf(0.0, minf(0.5 + (minf(not1, own1 + SLOPE) - own1) / SLOPE, 0.5 + (REACH - own1) / SLOPE))
	for r in battle.regiments:
		if r.dead or r.state == Regiment.State.ROUTING:
			continue
		var arr := _inf0 if r.team == 0 else _inf1
		var share := float(r.s_pos.size()) / maxf(1.0, r.initial_count)
		_splat(arr, r.center, 450.0 + 200.0 * share, 0.8 * share + 0.2)
	_drop_islands()
	for i in _inf0.size():
		var a := _inf0[i]
		var b := _inf1[i]
		var m := clampf(maxf(a, b), 0.0, 1.0)
		var side := 0.5
		if a + b > 0.001:
			side = a / (a + b)
		_bytes[i * 2] = int(m * 255.0)
		_bytes[i * 2 + 1] = int(side * 255.0)
	var img := Image.create_from_data(gw, gh, false, Image.FORMAT_RG8, _bytes)
	if _tex == null:
		_tex = ImageTexture.create_from_image(img)
		_tex_prev = ImageTexture.create_from_image(img)
		_mat.set_shader_parameter("infl_a", _tex_prev)
		_mat.set_shader_parameter("infl_b", _tex)
		_mat.set_shader_parameter("tex_size", Vector2(gw, gh))
	else:
		_tex_prev.update(_img)   # stara klatka staje się punktem startowym przejścia
		_tex.update(img)
		_mat.set_shader_parameter("blend", 0.0)
	_img = img
	queue_redraw()


func _drop_islands() -> void:
	## Terytorium musi łączyć się z własną osadą. Plamy wokół pułków odcięte od niej (w środku cudzego regionu)
	## wyglądały jak kotły, których nie ma - oddajemy je stronie, która je otacza.
	var n := gw * gh
	var win := PackedByteArray()
	win.resize(n)
	for i in n:
		var a := _inf0[i]
		var b := _inf1[i]
		win[i] = 0 if (a >= 0.5 and a >= b) else (1 if (b >= 0.5 and b > a) else 2)
	for side in 2:
		var arr := _inf0 if side == 0 else _inf1
		var other := _inf1 if side == 0 else _inf0
		var seen := PackedByteArray()
		seen.resize(n)
		var stack := PackedInt32Array()
		for s in battle.settlements:
			if s.faction != side:
				continue
			var cx := clampi(roundi(s.position.x / CELL), 0, gw - 1)
			var cy := clampi(roundi(s.position.y / CELL), 0, gh - 1)
			var c := cy * gw + cx
			if win[c] == side and seen[c] == 0:
				seen[c] = 1
				stack.append(c)
		while not stack.is_empty():
			var c := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var x := c % gw
			var y := c / gw
			for d in 4:
				var nx := x + (1 if d == 0 else (-1 if d == 1 else 0))
				var ny := y + (1 if d == 2 else (-1 if d == 3 else 0))
				if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
					continue
				var q := ny * gw + nx
				if seen[q] == 0 and win[q] == side:
					seen[q] = 1
					stack.append(q)
		for i in n:
			if win[i] == side and seen[i] == 0:
				var v := arr[i]
				arr[i] = minf(v, 0.45)
				if other[i] > 0.2:
					other[i] = maxf(other[i], v)   # wyspa w cudzym regionie -> należy do otaczającej strony


func _draw() -> void:
	if _tex != null:
		# siatka ma węzły w punktach k*CELL - próbki trafiają w środki tekseli
		draw_texture_rect(_tex, Rect2(Vector2(-CELL * 0.5, -CELL * 0.5), Vector2(gw, gh) * CELL), false)
