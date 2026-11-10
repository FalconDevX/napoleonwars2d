class_name Effects
extends Node2D
## Efekty: smugi strzałów, błyski z luf, dym prochowy, iskry walki wręcz, kule armatnie, plusk wody.

const SHOT_LIFE := 0.14
const MAX_SMOKE := 1400

var shots: Array = []   # [from, to, age]
var smoke: Array = []   # [pos, age, life, radius, drift, jet, rot, spin, tex]
const WIND := Vector2(3.5, -1.2)   # wspólny powiew: dym całej bitwy odpływa w jedną stronę
const JET_DECAY := 5.0             # jak szybko gaśnie wyrzut dymu z lufy
var _puffs: Array[ImageTexture] = []
var sparks: Array = []  # [pos, age]
var gore: Array = []    # [pos, vel, age, size] - krople krwi lecące po trafieniu
const GORE_LIFE := 0.45
var splashes: Array = []  # [pos, age]
var dust: Array = []    # [pos, age, size]
var flashes: Array = [] # [pos, age, size]
var blasts: Array = []  # [pos, age, size]          - wybuch: błysk, kula ognia, fala uderzeniowa
var debris: Array = []  # [pos, vel, z, vz, age, size, col] - grudy ziemi wyrzucone w powietrze
var leaves: Array = []  # [pos, vel, z, age, col, phase] - liście opadające z trafionego drzewa
var fires: Array = []   # [pos, dir, age, seed] - ogień z lufy muszkietu
const FIRE_LIFE := 0.11
const LEAF_LIFE := 2.6
const BLAST_LIFE := 0.55
const GRAVITY := 260.0
var pellets: Array = [] # [from, to, age, life] - kule kartacza: jasne smugi rozchodzące się wachlarzem
var blazes: Array = []  # [pos, dir, age, size, wide, seed] - płomień wylotowy działa: wąski jęzor ognia w osi lufy
const BLAZE_LIFE := 0.13
var dusts: Array = []   # [pos, age, life, radius, drift, jet, rot, spin, tex, col, alpha] - kurz: miękkie kłęby jak dym, w kolorze gruntu
const MAX_DUST := 700


func _ready() -> void:
	_build_puffs()


func _build_puffs() -> void:
	## Miękkie, poszarpane kłęby dymu (kilka wariantów): suma przesuniętych gaussów + szum na brzegu.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for v in 4:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var blobs := []
		for k in 5:
			blobs.append([Vector2(rng.randf_range(-0.22, 0.22), rng.randf_range(-0.22, 0.22)), rng.randf_range(0.18, 0.3)])
		for y in n:
			for x in n:
				var q := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5)
				var a := 0.0
				for b in blobs:
					var d: float = (q - b[0]).length() / b[1]
					a = maxf(a, exp(-d * d * 1.6))
				a *= clampf(1.0 - (q.length() - 0.38) / 0.12, 0.0, 1.0)
				var shade := 0.88 + 0.12 * clampf(0.5 - q.y, 0.0, 1.0)   # jaśniejszy od góry
				img.set_pixel(x, y, Color(shade, shade, shade * 0.98, a))
		_puffs.append(ImageTexture.create_from_image(img))


func add_shot(from: Vector2, to: Vector2) -> void:
	Net.record([0, from, to])
	shots.append([from, to, 0.0])
	fires.append([from, (to - from).normalized(), 0.0, randf()])
	# wystrzał muszkietu: 3 kłęby wyrzucone z lufy do przodu, potem puchną i odpływają z wiatrem
	var dir := (to - from).normalized()
	for k in 3:
		var jet := dir.rotated(randf_range(-0.35, 0.35)) * randf_range(18.0, 46.0) * (1.0 - k * 0.25)
		_add_smoke(from + Vector2(randf_range(-1, 1), randf_range(-1, 1)), randf_range(3.5, 6.0), randf_range(2.2, 3.4),
			WIND * randf_range(0.6, 1.2) + Vector2(randf_range(-1.0, 1.0), randf_range(-1.5, 0.5)), jet)


func add_cannon_smoke(p: Vector2, dir: Vector2) -> void:
	if Regiment.battle != null and Regiment.battle.cam != null:
		Regiment.battle.cam.shake(p, 1.6)
	Net.record([1, p, dir])
	blazes.append([p, dir, 0.0, 1.0, 1.0, randf()])
	for k in 11:
		var jet := dir.rotated(randf_range(-0.4, 0.4)) * randf_range(30.0, 110.0)
		_add_smoke(p + dir * randf_range(0, 10) + Vector2(randf_range(-4, 4), randf_range(-4, 4)),
			randf_range(6.0, 11.0), randf_range(5.0, 9.0), WIND * randf_range(0.6, 1.1) + Vector2(randf_range(-2, 2), randf_range(-2, 0)), jet)


func add_canister(p: Vector2, dir: Vector2, cone: float, reach: float) -> void:
	## Kartacz = strzelba wielkości działa: szeroki jęzor ognia, kilkadziesiąt kul lecących wachlarzem,
	## pas wzbitej ziemi tam, gdzie spadają, i dym rozlany na cały stożek.
	add_cannon_smoke(p, dir)
	if Regiment.battle != null and Regiment.battle.cam != null:
		Regiment.battle.cam.shake(p, 3.2)
	# kartacz: płomień krótszy i szerszy niż przy kuli (ładunek rozchodzi się od razu za wylotem)
	blazes[blazes.size() - 1][3] = 1.05
	blazes[blazes.size() - 1][4] = 1.3
	var base := dir.angle()
	for k in 46:
		# gęściej w osi, rzadziej na skrajach - jak rozrzut śrutu
		var a := base + (randf() + randf() - 1.0) * cone * 1.15
		var d := reach * randf_range(0.55, 1.08)
		var to := p + Vector2.from_angle(a) * d
		pellets.append([p + Vector2.from_angle(a) * randf_range(0.0, 6.0), to, -randf() * 0.03, 0.2 + d / 1500.0])
		if k % 3 == 0:
			# kule ryją ziemię: fontanny kurzu w pasie upadku
			add_dust(to, randf_range(1.6, 2.8), randf_range(2.0, 3.6), Vector2.from_angle(a) * randf_range(10.0, 34.0), 0.6)
		if k % 9 == 0:
			_throw_earth(to, 2, 2, 0.3, Vector2.from_angle(a))
	for k in 14:
		var a2 := base + randf_range(-cone, cone) * 1.3
		_add_smoke(p + Vector2.from_angle(a2) * randf_range(4.0, 22.0), randf_range(5.0, 9.0), randf_range(4.5, 8.0),
			WIND * randf_range(0.6, 1.1), Vector2.from_angle(a2) * randf_range(60.0, 170.0))


func add_impact(p: Vector2) -> void:
	Net.record([2, p])
	## Kula odbija się / sunie po ziemi: kilka grud i źdźbeł trawy, niski obłok kurzu.
	_throw_earth(p, 4, 3, 0.45)
	for k in 2:
		add_dust(p + Vector2(randf_range(-3, 3), randf_range(-3, 3)), randf_range(3.5, 5.5), randf_range(3.2, 4.8),
			Vector2.from_angle(randf() * TAU) * randf_range(6.0, 18.0), 0.65)


static func ground_dust_col() -> Color:
	## Kolor kurzu dla bieżącego teatru: pył drogi / piasek / pył śnieżny.
	if float(Terrain.tv("snow")) > 0.5:
		return Color(0.93, 0.95, 0.99)
	if float(Terrain.tv("desert")) > 0.5:
		return (Terrain.tv("sand") as Color).lightened(0.12)
	var rc: Array = Terrain.tv("road")
	return (rc[1] as Color).lerp(Color(0.72, 0.66, 0.54), 0.35)


func add_dust(p: Vector2, life: float, radius: float, jet: Vector2, alpha := 0.5, col := Color(0, 0, 0, 0)) -> void:
	## Kłąb kurzu: jak dym (miękka tekstura, puchnie, odpływa z wiatrem), ale ciężki - nisko, wolniej i krócej.
	var c := col if col.a > 0.0 else ground_dust_col()
	c = c.lerp(c.darkened(0.15), randf() * 0.5)
	dusts.append([p, 0.0, life, radius, WIND * randf_range(0.3, 0.7) + Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 0.3)),
		jet, randf() * TAU, randf_range(-0.4, 0.4), randi() % 4, c, alpha])
	if dusts.size() > MAX_DUST:
		dusts.remove_at(0)


func _throw_earth(p: Vector2, clods: int, blades: int, size: float, dir := Vector2.ZERO) -> void:
	## Grudy ziemi (kwadratowe piksele, z cieniem) i wyrwane kępki trawy (źdźbła wirujące w locie).
	var snow := float(Terrain.tv("snow")) > 0.5
	var desert := float(Terrain.tv("desert")) > 0.5
	var dirt: Color = Terrain.tv("dirt")
	var gc: Array = Terrain.tv("grass")
	for k in clods:
		var a := randf() * TAU
		var v := Vector2.from_angle(a) * randf_range(20.0, 70.0) * (0.6 + size)
		if dir != Vector2.ZERO:
			v = (v + dir * randf_range(20.0, 60.0))
		var c := dirt.darkened(randf_range(0.0, 0.35))
		if snow and randf() < 0.6:
			c = Color(0.90, 0.92, 0.96).darkened(randf() * 0.1)
		debris.append([p, v, 0.0, randf_range(50.0, 120.0) * (0.6 + size), 0.0, randf_range(0.7, 1.6) * (0.7 + size * 0.6), c, 0, randf() * TAU])
	if desert:
		return
	for k in blades:
		var v2 := Vector2.from_angle(randf() * TAU) * randf_range(15.0, 55.0) * (0.6 + size)
		var g := (gc[randi() % gc.size()] as Color).lightened(randf_range(0.0, 0.25))
		if snow:
			g = Color(0.40, 0.42, 0.30)
		debris.append([p, v2, 0.0, randf_range(40.0, 100.0) * (0.6 + size), 0.0, randf_range(1.6, 2.8), g, 1, randf() * TAU])


func add_explosion(p: Vector2, size := 1.0) -> void:
	if Regiment.battle != null and Regiment.battle.cam != null:
		Regiment.battle.cam.shake(p, 3.0 * size)
	Net.record([3, p, size])
	## Wybuch przy uderzeniu kuli: błysk, kula ognia, fala uderzeniowa, grudy ziemi, kłęby dymu, lej.
	blasts.append([p, 0.0, size])
	_throw_earth(p, int(14 * size), int(9 * size), size)
	# słup kurzu i ziemi: kilka kłębów wyrzuconych na boki + gęsty środek, osiada powoli
	for k in int(4 + 5 * size):
		var jd := Vector2.from_angle(randf() * TAU) * randf_range(8.0, 34.0) * size
		add_dust(p + Vector2(randf_range(-3, 3), randf_range(-3, 3)) * size, randf_range(4.5, 8.0), randf_range(5.0, 8.5) * maxf(size, 0.8), jd, 0.75)
	for k in (5 if size > 0.9 else 0):
		var jet := Vector2.from_angle(randf() * TAU) * randf_range(10.0, 40.0) * size
		_add_smoke(p + Vector2(randf_range(-3, 3), randf_range(-3, 3)), randf_range(3.5, 6.0), randf_range(4.0, 7.0) * size,
			WIND * randf_range(0.6, 1.1) + Vector2(0, randf_range(-3.0, -1.0)), jet)
	if debris.size() > 900:
		debris = debris.slice(debris.size() - 900)
	Regiment.battle.corpses.add_crater(p, size)


func _add_smoke(p: Vector2, life: float, radius: float, drift: Vector2, jet := Vector2.ZERO) -> void:
	smoke.append([p, 0.0, life, radius, drift, jet, randf() * TAU, randf_range(-0.5, 0.5), randi() % 4])
	if smoke.size() > MAX_SMOKE:
		smoke.remove_at(0)


func add_tree_hit(p: Vector2, dir: Vector2, fell: bool, leaf_col: Color) -> void:
	## Kula w drzewie: drzazgi wyrzucone w kierunku lotu (spadają z grawitacją) i opadające, kołyszące się liście.
	var d := dir.normalized()
	for k in (10 if fell else 6):
		var v := d.rotated(randf_range(-0.9, 0.9)) * randf_range(35.0, 95.0)
		var wood := Color(0.55, 0.40, 0.24) if randf() < 0.6 else Color(0.80, 0.68, 0.48)   # kora / jasne drewno
		debris.append([p + Vector2(randf_range(-2, 2), randf_range(-2, 2)), v, randf_range(6.0, 14.0), randf_range(40.0, 95.0), 0.0, randf_range(0.5, 0.9), wood])
	for k in (26 if fell else 12):
		var c := leaf_col.lerp(Color(0.62, 0.58, 0.22), randf() * 0.35)
		leaves.append([p + Vector2(randf_range(-7, 7), randf_range(-7, 7)), d.rotated(randf_range(-1.6, 1.6)) * randf_range(4.0, 16.0),
			randf_range(10.0, 22.0), 0.0, c, randf() * TAU])


func add_spark(p: Vector2) -> void:
	Net.record([4, p])
	sparks.append([p, 0.0])


func add_splash(p: Vector2) -> void:
	Net.record([5, p])
	splashes.append([p, 0.0])


func add_blood(p: Vector2, size := 1.0) -> void:
	Regiment.battle.corpses.add_blood(p, size)


func add_hit_blood(p: Vector2, fatal: bool, big := false) -> void:
	Net.record([6, p, fatal, big])
	## Trafienie: rozprysk kropli krwi + plama na ziemi (przy śmierci większa kałuża).
	var drops := randi_range(5, 9) if fatal else randi_range(2, 5)
	for k in drops:
		var v := Vector2.from_angle(randf() * TAU) * randf_range(12.0, 45.0)
		gore.append([p + Vector2(randf_range(-1, 1), randf_range(-1, 1)), v, 0.0, randf_range(0.5, 1.2)])
	if gore.size() > 1500:
		gore = gore.slice(gore.size() - 1500)
	var sz := (1.5 if big else 1.2) if fatal else 0.55
	if fatal or randf() < 0.6:
		add_blood(p + Vector2(randf_range(-2, 2), randf_range(-2, 2)), sz)
	if fatal:
		for k in 2:
			add_blood(p + Vector2.from_angle(randf() * TAU) * randf_range(3.0, 7.0), randf_range(0.3, 0.6))


func update(dt: float) -> void:
	shots = _age(shots, 2, dt, SHOT_LIFE)
	sparks = _age(sparks, 1, dt, 0.25)
	var ng: Array = []
	for g in gore:
		g[2] += dt
		if g[2] < GORE_LIFE:
			g[0] += g[1] * dt
			g[1] *= 0.86
			ng.append(g)
	gore = ng
	splashes = _age(splashes, 1, dt, 1.2)
	fires = _age(fires, 2, dt, FIRE_LIFE)
	blazes = _age(blazes, 2, dt, BLAZE_LIFE)
	var np: Array = []
	for s in pellets:
		s[2] += dt
		if s[2] < s[3]:
			np.append(s)
	pellets = np
	var nl: Array = []
	for l in leaves:
		l[3] += dt
		if l[2] > 0.0:
			l[0] += (l[1] + Vector2(sin(l[3] * 5.0 + l[5]) * 7.0, 0.0)) * dt + WIND * dt   # kołysanie i wiatr
			l[1] *= 0.97
			l[2] = maxf(0.0, l[2] - dt * randf_range(6.0, 10.0))
		if l[3] < LEAF_LIFE:
			nl.append(l)
	leaves = nl
	dust = _age(dust, 1, dt, 1.6)
	flashes = _age(flashes, 1, dt, 0.12)
	blasts = _age(blasts, 1, dt, BLAST_LIFE)
	var nd: Array = []
	for d in debris:
		d[4] += dt
		if d[2] > 0.0 or d[3] > 0.0:
			d[0] += d[1] * dt
			d[3] -= GRAVITY * dt
			d[2] = maxf(0.0, d[2] + d[3] * dt)
			if d[2] <= 0.0:
				d[3] = 0.0
				d[1] *= 0.0
		if d.size() > 8 and d[2] > 0.0:
			d[8] += dt * 12.0   # źdźbło / gruda wiruje w locie
		if d[4] < 2.2:
			nd.append(d)
	debris = nd
	var nu: Array = []
	for s in dusts:
		s[1] += dt
		if s[1] < s[2]:
			nu.append(s)
	dusts = nu
	var nm: Array = []
	for s in smoke:
		s[1] += dt
		if s[1] < s[2]:
			nm.append(s)
	smoke = nm


func _age(arr: Array, idx: int, dt: float, life: float) -> Array:
	var out: Array = []
	for s in arr:
		s[idx] += dt
		if s[idx] < life:
			out.append(s)
	return out


func _draw() -> void:
	for s in dust:
		var t: float = s[1] / 1.6
		draw_circle(s[0], s[2] * (1.0 + t * 1.5), Color(0.55, 0.47, 0.35, 0.55 * (1.0 - t)))
	for s in dusts:
		var age: float = s[1]
		var t: float = age / s[2]
		var jdec := 3.5   # ciężki pył szybko traci rozpęd
		var pos: Vector2 = s[0] + s[5] * ((1.0 - exp(-age * jdec)) / jdec) + s[4] * age
		var grow := 1.0 + 1.8 * (1.0 - exp(-age * 3.0)) + 0.9 * t   # buch kurzu rozchodzi się od razu, potem powoli rzednie
		var r: float = s[3] * grow
		var a: float = s[10] * minf(age / 0.06, 1.0) * pow(1.0 - t, 1.6)
		var col: Color = s[9]
		col.a = a
		var tex: ImageTexture = _puffs[s[8]] if not _puffs.is_empty() else null
		if tex == null:
			draw_circle(pos, r, col)
			continue
		draw_set_transform(pos, s[6] + s[7] * age, Vector2(1.0, 0.8))   # spłaszczony - ściele się przy ziemi
		draw_texture_rect(tex, Rect2(-r * 1.25, -r * 1.25, r * 2.5, r * 2.5), false, col)
	draw_set_transform(Vector2.ZERO)
	for s in splashes:
		var t: float = s[1] / 1.2
		draw_arc(s[0], 3.0 + t * 10.0, 0, TAU, 16, Color(0.85, 0.92, 1.0, 0.8 * (1.0 - t)), 0.8)
		draw_arc(s[0], 1.0 + t * 5.0, 0, TAU, 12, Color(0.85, 0.92, 1.0, 0.6 * (1.0 - t)), 0.6)
	for s in smoke:
		var age: float = s[1]
		var t: float = age / s[2]
		# wyrzut z lufy wygasa wykładniczo, potem tylko wiatr
		var pos: Vector2 = s[0] + s[5] * ((1.0 - exp(-age * JET_DECAY)) / JET_DECAY) + s[4] * age
		var grow := 1.0 + 2.8 * (1.0 - pow(1.0 - minf(t * 1.6, 1.0), 2.0))   # szybko puchnie, potem wolno
		var r: float = s[3] * grow
		var fade_in := minf(age / 0.04, 1.0)
		var a := 0.68 * fade_in * pow(1.0 - t, 1.4)
		var col := Color(1.0, 0.86, 0.62).lerp(Color(0.95, 0.95, 0.92), clampf(age / 0.18, 0.0, 1.0))
		col = col.lerp(Color(0.78, 0.78, 0.76), t)
		col.a = a
		var tex: ImageTexture = _puffs[s[8]] if not _puffs.is_empty() else null
		if tex == null:
			draw_circle(pos, r, col)
			continue
		draw_set_transform(pos, s[6] + s[7] * age, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-r * 1.25, -r * 1.25, r * 2.5, r * 2.5), false, col)
	draw_set_transform(Vector2.ZERO)
	for s in shots:
		var t: float = s[2] / SHOT_LIFE
		# realistycznie: krótki płomień z lufy + ledwo widoczna kulka w locie (bez "lasera" przez całe pole)
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		var dir := (e - a).normalized()
		var nrm := dir.orthogonal()
		if t < 0.35:
			var k := 1.0 - t / 0.35
			var tip := a + dir * (4.0 + 5.0 * k)
			if k > 0.03 and dir.is_finite() and dir.length_squared() > 0.5 and a.is_finite():   # zdegenerowany trójkąt psuje triangulację
				# trójkąt rysowany wprost (bez triangulacji - przy wąskim płomieniu potrafiła zawieść)
				var fc := Color(1.0, 0.75, 0.25, 0.85 * k)
				draw_primitive(PackedVector2Array([a + nrm * 1.3 * k, tip, a - nrm * 1.3 * k]), PackedColorArray([fc, fc, fc]), PackedVector2Array())
			draw_circle(a, 1.6 * k + 0.4, Color(1.0, 0.95, 0.75, 0.9 * k))
		var bp := a.lerp(e, t)
		draw_line(bp - dir * 5.0, bp, Color(0.85, 0.82, 0.72, 0.28 * (1.0 - t * 0.5)), 0.7)
	for s in blazes:
		# Płomień wylotowy czarnego prochu: jęzor ognia w osi lufy - biało-żółty rdzeń, pomarańczowa otoczka,
		# ciemnoczerwone, postrzępione brzegi. Wyskakuje w ułamku sekundy i gaśnie w dymie; nie jest kulą.
		var t: float = s[2] / BLAZE_LIFE
		var o: Vector2 = s[0]
		var d: Vector2 = s[1]
		if not d.is_finite() or d.length_squared() < 0.5:
			continue
		var nrm := d.orthogonal()
		var sz: float = s[3]
		var wide: float = s[4]
		var sd: float = s[5]
		var k := pow(1.0 - t, 1.3)
		var reach := (0.55 + 0.45 * minf(t / 0.22, 1.0)) * (0.85 + 0.3 * sd)   # wyskakuje, potem kurczy się
		var layers := [
			[44.0, 4.0, Color(0.62, 0.16, 0.06, 0.45 * k)],
			[35.0, 2.9, Color(0.95, 0.42, 0.10, 0.70 * k)],
			[25.0, 1.9, Color(1.0, 0.74, 0.30, 0.85 * k)],
			[15.0, 1.0, Color(1.0, 0.97, 0.88, 0.95 * k)],
		]
		for li in layers.size():
			var ln: float = float(layers[li][0]) * sz * reach / sqrt(wide)
			var hw: float = float(layers[li][1]) * sz * wide * (0.75 + 0.25 * k)
			if ln < 3.0 or hw < 0.6:
				continue
			# kształt płomienia: wąski przy wylocie, najszerszy w 1/3, ostro zakończony; brzeg lekko postrzępiony
			var prof := [[0.0, 0.28], [0.14, 0.82], [0.36, 1.0], [0.62, 0.62], [0.84, 0.26], [1.0, 0.0]]
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			for q in prof.size():
				var u: float = prof[q][0]
				var jag := 1.0 + 0.22 * sin(sd * 40.0 + q * 2.4 + li * 1.3)
				var w2: float = hw * float(prof[q][1]) * (jag if li < 2 else 1.0)
				var c := o + d * (ln * u)
				left.append(c + nrm * w2)
				if q > 0 and q < prof.size() - 1:
					right.append(c - nrm * w2)
			right.reverse()
			var pts := left
			pts.append_array(right)
			pts.append(o - nrm * hw * 0.28)
			draw_colored_polygon(pts, layers[li][2])
		# poświata przy samym wylocie i iskry niedopalonego prochu wzdłuż płomienia
		draw_circle(o + d * 1.5 * sz, 1.2 * sz * k, Color(1.0, 0.95, 0.8, 0.7 * k))
		for q in 5:
			var u2 := fposmod(sd * 7.0 + q * 0.37, 1.0)
			var sp := o + d * (10.0 + 30.0 * u2 + 40.0 * t) * sz + nrm * (fposmod(sd * 13.0 + q * 0.61, 1.0) - 0.5) * 9.0 * wide
			draw_circle(sp, 0.45, Color(1.0, 0.6, 0.2, 0.8 * k))
	for s in pellets:
		# kul kartacza prawie nie widać w locie - tylko blade, krótkie smugi; widać za to, gdzie ryją ziemię
		if s[2] < 0.0:
			continue
		var t: float = s[2] / s[3]
		var a: Vector2 = s[0]
		var e: Vector2 = s[1]
		var head := a.lerp(e, t)
		var tail := a.lerp(e, maxf(0.0, t - 0.1))
		draw_line(tail, head, Color(0.88, 0.86, 0.80, 0.42 * (1.0 - t * 0.6)), 0.55)
	for g in gore:
		var t: float = g[2] / GORE_LIFE
		draw_circle(g[0], g[3] * (1.0 - t * 0.4), Color(0.55, 0.02, 0.02, 0.9 * (1.0 - t)))
	for s in flashes:
		var t: float = s[1] / 0.12
		draw_circle(s[0], s[2] * (1.0 - t * 0.5), Color(1.0, 0.8, 0.3, 0.9 * (1.0 - t)))
	for s in blasts:
		var t: float = s[1] / BLAST_LIFE
		var p: Vector2 = s[0]
		var sz: float = s[2]
		# fala uderzeniowa
		draw_arc(p, (6.0 + 46.0 * sqrt(t)) * sz, 0, TAU, 32, Color(1.0, 0.95, 0.85, 0.5 * (1.0 - t)), 1.6 * (1.0 - t) + 0.4)
		# kula ognia: biały środek -> żółty -> pomarańczowy -> ciemnoczerwony, kurczy się i gaśnie
		if t < 0.6:
			var ft := t / 0.6
			var r := (7.0 + 9.0 * sqrt(ft)) * sz
			var fire := Color(1.0, 0.75, 0.25).lerp(Color(0.55, 0.12, 0.05), ft)
			fire.a = 0.85 * (1.0 - ft)
			var tex: ImageTexture = _puffs[0] if not _puffs.is_empty() else null
			if tex != null:
				draw_texture_rect(tex, Rect2(p - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), false, fire)
			else:
				draw_circle(p, r, fire)
			draw_circle(p, r * 0.55 * (1.0 - ft), Color(1.0, 0.95, 0.7, 0.9 * (1.0 - ft)))
		# pierwszy błysk
		if t < 0.15:
			draw_circle(p, 16.0 * sz * (1.0 - t / 0.15 * 0.6), Color(1.0, 1.0, 0.85, 0.75 * (1.0 - t / 0.15)))
	for d in debris:
		var a := clampf((2.2 - d[4]) / 0.6, 0.0, 1.0)
		var z: float = d[2]
		var pos: Vector2 = d[0]
		var sz: float = d[5]
		if d.size() > 8 and d[7] == 1:
			# źdźbła trawy: krótka kreska obracająca się w locie; na ziemi leży
			var bd := Vector2.from_angle(d[8]) * sz * 0.5
			var bp := pos - Vector2(0, z * 0.5)
			if z > 0.5:
				draw_line(pos + Vector2(z * 0.25, z * 0.35) - bd, pos + Vector2(z * 0.25, z * 0.35) + bd, Color(0, 0, 0, 0.18 * a), 0.6)
			draw_line(bp - bd, bp + bd, Color(d[6], a), 0.7)
			draw_rect(Rect2(bp + bd - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), Color((d[6] as Color).darkened(0.3), a))   # grudka korzeni
			continue
		if z > 0.5:
			draw_rect(Rect2(pos + Vector2(z * 0.25, z * 0.35) - Vector2(sz, sz) * 0.45, Vector2(sz, sz) * 0.9), Color(0, 0, 0, 0.25 * a))   # cień
		var q := pos - Vector2(0, z * 0.5)
		var w := sz * (1.0 + z * 0.006) * 1.5
		draw_rect(Rect2(q - Vector2(w, w) * 0.5, Vector2(w, w)), Color(d[6], a))
		draw_rect(Rect2(q - Vector2(w, w) * 0.5, Vector2(w * 0.5, w * 0.5)), Color((d[6] as Color).lightened(0.18), a))   # oświetlona krawędź
	for l in leaves:
		var la := clampf((LEAF_LIFE - l[3]) / 0.6, 0.0, 1.0)
		var lz: float = l[2]
		var lp: Vector2 = l[0] - Vector2(0, lz * 0.5)
		var flip := absf(sin(l[3] * 9.0 + l[5]))   # liść obraca się w locie - migocze
		if lz > 0.5:
			draw_rect(Rect2(l[0] + Vector2(lz * 0.25, lz * 0.35), Vector2(0.9, 0.6)), Color(0, 0, 0, 0.2 * la))
		draw_rect(Rect2(lp, Vector2(1.1, 0.4 + 0.6 * flip)), Color((l[4] as Color) * (0.8 + 0.3 * flip), la))
	for fr in fires:
		# język ognia z lufy: jasny rdzeń i pomarańczowe kratki wzdłuż strzału, kilka iskier
		var ft: float = fr[2] / FIRE_LIFE
		var fa := 1.0 - ft
		var fp: Vector2 = fr[0]
		var fd: Vector2 = fr[1]
		var fs := fd.orthogonal()
		draw_rect(Rect2(fp + fd * 0.6 - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), Color(1.0, 0.97, 0.75, fa))
		for k in 5:
			var along := 1.6 + k * 1.15 * (1.0 + 0.4 * ft)
			var wob := sin(float(k) * 2.3 + float(fr[3]) * 9.0) * 0.5
			var sz := (1.5 - k * 0.22) * (1.0 - ft * 0.5)
			var fc := Color(1.0, 0.82, 0.30).lerp(Color(0.95, 0.30, 0.08), float(k) / 4.0)
			draw_rect(Rect2(fp + fd * along + fs * wob - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(fc, fa * (1.0 - k * 0.12)))
		for k in 3:
			var sp := fp + fd.rotated((float(k) - 1.0) * 0.5 + float(fr[3])) * (3.0 + ft * 6.0 + k)
			draw_rect(Rect2(sp, Vector2(0.5, 0.5)), Color(1.0, 0.75, 0.3, fa))
	for s in sparks:
		var t: float = s[1] / 0.25
		var p: Vector2 = s[0]
		var c := Color(1, 1, 0.85, 1.0 - t)
		draw_line(p + Vector2(-2, -2), p + Vector2(2, 2), c, 0.6)
		draw_line(p + Vector2(-2, 2), p + Vector2(2, -2), c, 0.6)
	# kule armatnie
	for b in Regiment.battle.balls:
		var p: Vector2 = b["pos"]
		var lift: float = b["lift"]
		draw_circle(p + Vector2(2, 3), 2.2, Color(0, 0, 0, 0.35))
		draw_circle(p - Vector2(0, lift), 2.4, Color(0.12, 0.12, 0.12))
