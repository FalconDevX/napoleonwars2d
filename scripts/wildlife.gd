extends Node2D
## Dzikie zwierzęta na skraju lasu: sarny (z koźlętami) i króliki pasą się, przechadzają, podnoszą łby;
## spłoszone (wybuch, salwa) uciekają w las. Ptaki zrywają się z drzew i odlatują (osobny węzeł nad koronami).
## Rysowane proceduralnie z góry, w stylu malowanych sprite'ów: światło z góry-lewej, cień rzucany w prawo w dół.

enum { DEER, FAWN, RABBIT }
enum { GRAZE, WALK, ALERT, FLEE }

const LIGHT := Vector2(-0.7, -0.7)
const SHADOW_OFF := Vector2(2.2, 2.6)

var animals: Array = []   # słowniki: kind, pos, head (kierunek), state, t (licznik stanu), ph (faza animacji), vel, alpha, dir
var birds: BirdFlock = null
var shelter := Vector2.DOWN   # w którą stronę jest głąb lasu (tam się ucieka)


class BirdFlock extends Node2D:
	## Stado ptaków: siedzą niewidoczne w koronach, spłoszone wzbijają się i odlatują, machając skrzydłami.
	var birds: Array = []   # [pos, vel, phase, size, alive_t]

	func add(p: Vector2) -> void:
		birds.append([p, Vector2.ZERO, randf() * TAU, randf_range(0.8, 1.2), -1.0])

	func scatter(from: Vector2) -> void:
		for b in birds:
			if b[4] < 0.0:
				var away: Vector2 = ((b[0] as Vector2) - from).normalized().rotated(randf_range(-0.6, 0.6))
				b[1] = away * randf_range(55.0, 85.0)
				b[4] = randf_range(0.0, 0.5)   # krótka zwłoka: nie wszystkie zrywają się naraz

	func _process(dt: float) -> void:
		var any := false
		for b in birds:
			if b[4] < 0.0:
				continue
			b[4] += dt
			if b[4] < 0.3:
				continue
			any = true
			b[2] += dt * 22.0
			b[0] += (b[1] as Vector2) * dt * minf(1.0, b[4])
			b[1] = (b[1] as Vector2).rotated(sin(b[4] * 1.3 + b[3] * 5.0) * 0.4 * dt)
		if any:
			queue_redraw()

	func _draw() -> void:
		for b in birds:
			if b[4] < 0.3:
				continue
			var p: Vector2 = b[0]
			var v: Vector2 = b[1]
			var d := v.normalized()
			var s: float = b[3] * (1.0 + minf(b[4], 2.0) * 0.25)   # wznosząc się wydaje się większy
			var flap := sin(b[2])
			var side := d.orthogonal()
			var lift := minf(b[4] * 14.0, 26.0)
			# cień na ziemi oddala się od ptaka, im wyżej leci
			var sp := p + Vector2(lift * 0.6, lift)
			draw_line(sp - side * 3.5 * s, sp + side * 3.5 * s, Color(0, 0, 0, 0.18), 1.4 * s)
			var col := Color(0.12, 0.11, 0.1)
			var wing := side * 4.2 * s
			var tipb := -d * (1.2 + flap * 1.8) * s
			draw_line(p, p + wing + tipb, col, 1.3 * s)
			draw_line(p, p - wing + tipb, col, 1.3 * s)
			draw_circle(p, 1.1 * s, col)
			draw_line(p, p + d * 1.8 * s, col, 1.0 * s)


func setup_meadow(center: Vector2, forest_dir: Vector2, deer := 6, rabbits := 7) -> void:
	## Stadko na łące przy skraju lasu. forest_dir: kierunek w głąb lasu (ucieczka).
	shelter = forest_dir.normalized()
	var across := shelter.orthogonal()
	for k in deer:
		var kind := FAWN if k >= deer - 2 else DEER
		var p := center + across * randf_range(-150.0, 150.0) + shelter * randf_range(-60.0, 30.0)
		_add(kind, p)
	for k in rabbits:
		var p := center + across * randf_range(-200.0, 200.0) + shelter * randf_range(-20.0, 55.0)
		_add(RABBIT, p)


func add_birds(around: Vector2, n: int, spread: float) -> void:
	if birds == null:
		return
	for k in n:
		birds.add(around + Vector2(randf_range(-spread, spread), randf_range(-spread * 0.5, spread * 0.5)))


func _add(kind: int, p: Vector2) -> void:
	animals.append({"kind": kind, "pos": p, "head": randf() * TAU, "state": GRAZE, "t": randf_range(0.5, 4.0),
		"ph": randf() * TAU, "vel": Vector2.ZERO, "alpha": 1.0, "dir": Vector2.ZERO, "bob": 0.0, "seed": randi(), "buck": randf() < 0.35})


func startle(from: Vector2, radius := 900.0) -> void:
	## Huk w pobliżu: zwierzęta podrywają łby i (po chwili wahania) uciekają w las; ptaki się zrywają.
	for a in animals:
		if a["state"] == FLEE or (a["pos"] as Vector2).distance_to(from) > radius:
			continue
		var away: Vector2 = ((a["pos"] as Vector2) - from).normalized()
		a["dir"] = (away * 0.6 + shelter * 1.0).normalized().rotated(randf_range(-0.45, 0.45))
		a["state"] = ALERT
		a["t"] = randf_range(0.1, 0.5) if a["kind"] == RABBIT else randf_range(0.25, 0.7)
	if birds != null:
		birds.scatter(from)


func _process(dt: float) -> void:
	for a in animals:
		_tick(a, dt)
	queue_redraw()


func _speed(kind: int, state: int) -> float:
	if state == FLEE:
		return [95.0, 85.0, 70.0][kind]
	return [7.0, 6.0, 9.0][kind]


func _tick(a: Dictionary, dt: float) -> void:
	a["t"] -= dt
	var st: int = a["state"]
	var kind: int = a["kind"]
	match st:
		GRAZE:
			a["ph"] += dt * 2.0
			if a["t"] <= 0.0:
				var r := randf()
				if r < 0.45:
					a["state"] = WALK
					a["dir"] = Vector2.from_angle((a["head"] as float) + randf_range(-1.2, 1.2))
					a["t"] = randf_range(0.6, 1.8) if kind != RABBIT else randf_range(0.25, 0.6)
				elif r < 0.7:
					a["state"] = ALERT   # podniesiony łeb, nasłuchuje
					a["dir"] = Vector2.ZERO
					a["t"] = randf_range(0.8, 2.0)
				else:
					a["t"] = randf_range(1.5, 4.0)
		WALK, FLEE:
			var d: Vector2 = a["dir"]
			var want := d.angle()
			a["head"] = rotate_toward(a["head"], want, dt * (9.0 if st == FLEE else 3.0))
			var spd := _speed(kind, st)
			if kind == RABBIT:
				# królik kica: ruch zrywami
				var hop := maxf(0.0, sin(a["ph"]))
				a["ph"] += dt * (16.0 if st == FLEE else 9.0)
				a["bob"] = hop
				spd *= hop * 2.0
			else:
				a["ph"] += dt * (14.0 if st == FLEE else 5.0)
				a["bob"] = absf(sin(a["ph"])) if st == FLEE else 0.0
			a["pos"] += Vector2.from_angle(a["head"]) * spd * dt
			if st == FLEE:
				a["dir"] = d.rotated(sin(a["ph"] * 0.15) * 0.3 * dt)
				if a["t"] < -2.6:
					a["alpha"] = maxf(0.0, a["alpha"] - dt * 0.8)   # zniknęły w gęstwinie
			elif a["t"] <= 0.0:
				a["state"] = GRAZE
				a["bob"] = 0.0
				a["t"] = randf_range(1.5, 5.0)
		ALERT:
			if a["t"] <= 0.0:
				if (a["dir"] as Vector2) != Vector2.ZERO:
					a["state"] = FLEE   # spłoszone: w nogi
					a["t"] = 0.0
				else:
					a["state"] = GRAZE
					a["t"] = randf_range(1.5, 4.0)


# ------------------------------------------------------------------ rysowanie

func _ell(c: Vector2, rx: float, ry: float, ang: float, col: Color) -> void:
	draw_set_transform(c, ang, Vector2(rx, ry))
	draw_circle(Vector2.ZERO, 1.0, col)
	draw_set_transform(Vector2.ZERO)


func _draw() -> void:
	for a in animals:
		if a["alpha"] <= 0.01:
			continue
		match int(a["kind"]):
			DEER: _draw_deer(a, 1.0)
			FAWN: _draw_deer(a, 0.68)
			RABBIT: _draw_rabbit(a)




# Sylwetki z góry (oś +x = przód zwierzęcia): pary (x, połowa szerokości) wzdłuż ciała.
const DEER_BODY := [Vector2(-9.2, 0.0), Vector2(-8.9, 1.5), Vector2(-8.2, 2.7), Vector2(-7.0, 3.4), Vector2(-5.4, 3.5),
	Vector2(-3.6, 3.1), Vector2(-1.6, 2.85), Vector2(0.6, 3.05), Vector2(2.6, 3.3), Vector2(4.4, 3.1), Vector2(5.8, 2.4),
	Vector2(6.7, 1.4), Vector2(7.0, 0.0)]
const DEER_HEAD := [Vector2(-1.7, 0.0), Vector2(-1.5, 1.0), Vector2(-0.6, 1.45), Vector2(0.6, 1.3), Vector2(1.6, 0.95),
	Vector2(2.6, 0.6), Vector2(3.1, 0.35), Vector2(3.3, 0.0)]
const DEER_RUMP := [Vector2(-9.05, 0.0), Vector2(-8.8, 1.1), Vector2(-8.0, 1.45), Vector2(-7.3, 1.0), Vector2(-7.0, 0.0)]
const RAB_BODY := [Vector2(-3.0, 0.0), Vector2(-2.8, 1.3), Vector2(-2.0, 2.0), Vector2(-0.8, 2.1), Vector2(0.4, 1.8),
	Vector2(1.3, 1.35), Vector2(1.9, 0.8), Vector2(2.1, 0.0)]
const RAB_HEAD := [Vector2(-1.1, 0.0), Vector2(-0.9, 0.9), Vector2(0.0, 1.1), Vector2(0.8, 0.85), Vector2(1.3, 0.45), Vector2(1.45, 0.0)]


static func _prof(samples: Array, off := Vector2.ZERO, wk := 1.0, lk := 1.0) -> PackedVector2Array:
	## Obrys z profilu: lewa krawędź od tyłu do przodu, potem prawa z powrotem.
	var pts := PackedVector2Array()
	for v in samples:
		pts.append(off + Vector2(v.x * lk, -v.y * wk))
	for k in range(samples.size() - 2, 0, -1):
		var v: Vector2 = samples[k]
		pts.append(off + Vector2(v.x * lk, v.y * wk))
	return pts


func _shaded(samples: Array, off: Vector2, ll: Vector2, outline: Color, shade: Color, base: Color, hi: Color) -> void:
	## Bryła cieniowana jak sprite'y: ciemny obrys, strona cienia, główny kolor przesunięty do światła, odblask.
	draw_colored_polygon(_prof(samples, off, 1.12, 1.03), outline)
	draw_colored_polygon(_prof(samples, off), shade)
	draw_colored_polygon(_prof(samples, off + ll * 0.55, 0.8, 0.94), base)
	draw_colored_polygon(_prof(samples, off + ll * 1.15, 0.42, 0.8), hi)


func _leaf(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := (b - a).orthogonal().normalized() * w
	var m := a.lerp(b, 0.42)
	draw_colored_polygon(PackedVector2Array([a, m + n, b, m - n]), col)


func _draw_deer(a: Dictionary, s: float) -> void:
	var p: Vector2 = a["pos"]
	var h: float = a["head"]
	var al: float = a["alpha"]
	var st: int = a["state"]
	var fawn := s < 0.9
	var lift := float(a["bob"]) * 1.6 * s
	var ll := LIGHT.rotated(-h)   # kierunek światła w układzie zwierzęcia
	# łeb: pasąca się sarna sięga nisko przed siebie, czujna trzyma go wysoko (z góry szyja skrócona)
	var hx := 11.4
	if st == WALK:
		hx = 10.2
	elif st == ALERT:
		hx = 8.4
	elif st == FLEE:
		hx = 9.9
	var hy := 0.0
	var ha := 0.0
	if st == GRAZE:
		hy = sin(float(a["ph"]) * 0.7) * 0.9
		ha = sin(float(a["ph"]) * 0.7) * 0.25
	elif st == ALERT:
		ha = sin(float(a["t"]) * 1.7) * 0.5   # rozgląda się
		hy = ha * 1.2
	var hp := Vector2(hx, hy)
	var outline := Color(0.2, 0.12, 0.06, 0.85 * al)
	var shade := Color(0.43, 0.25, 0.12, al)
	var coat := Color(0.63, 0.38, 0.19, al) if not fawn else Color(0.66, 0.42, 0.22, al)
	var hi := Color(0.78, 0.53, 0.3, 0.75 * al)
	# cień rzucany: ta sama sylwetka, przesunięta na ziemi
	draw_set_transform(p + SHADOW_OFF * s * 1.2 + Vector2(lift, lift), h, Vector2(s, s))
	var shc := Color(0, 0, 0, 0.27 * al)
	draw_colored_polygon(_prof(DEER_BODY), shc)
	draw_line(Vector2(6.0, 0), hp, shc, 2.6)
	draw_colored_polygon(_prof(DEER_HEAD, hp), shc)
	draw_set_transform(p - Vector2(lift, lift), h, Vector2(s, s))
	# nogi: z góry widać je tylko w ruchu, gdy wysuwają się spod tułowia
	if st == WALK or st == FLEE:
		var ph := float(a["ph"])
		var amp := 4.2 if st == FLEE else 1.8
		var legs := [[Vector2(4.6, -1.9), 0.0], [Vector2(4.6, 1.9), PI if st == WALK else 0.3],
			[Vector2(-6.4, -2.2), PI], [Vector2(-6.4, 2.2), 0.0 if st == WALK else PI + 0.3]]
		for lg in legs:
			var root: Vector2 = lg[0]
			var sw := sin(ph + float(lg[1])) * amp
			var foot := root + Vector2(sw, signf(root.y) * 0.9)
			var lc := Color(0.36, 0.22, 0.11, al)
			draw_colored_polygon(PackedVector2Array([root + Vector2(0, -0.55), foot + Vector2(0, -0.28), foot + Vector2(0, 0.28),
				root + Vector2(0, 0.55)]), lc)
			draw_circle(foot, 0.42, Color(0.1, 0.07, 0.05, al))   # racica
	# szyja
	var nb := Vector2(5.6, 0.0)
	var nd := (hp - nb).normalized()
	var nn := nd.orthogonal()
	draw_colored_polygon(PackedVector2Array([nb - nn * 1.9, hp - nd * 0.8 - nn * 1.0, hp - nd * 0.8 + nn * 1.0, nb + nn * 1.9]), shade)
	# tułów
	_shaded(DEER_BODY, Vector2.ZERO, ll, outline, shade, coat, hi)
	draw_colored_polygon(PackedVector2Array([nb - nn * 1.5 + ll * 0.4, hp - nd * 0.8 - nn * 0.7 + ll * 0.3,
		hp - nd * 0.8 + nn * 0.7 + ll * 0.3, nb + nn * 1.5 + ll * 0.4]), coat)
	# ciemniejsza pręga grzbietu i sierść układająca się do tyłu
	draw_line(Vector2(-6.5, 0), Vector2(5.0, 0), Color(0.42, 0.24, 0.11, 0.55 * al), 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["seed"])
	for k in 22:
		var x := rng.randf_range(-7.8, 5.6)
		var half := 0.0
		for v in DEER_BODY:
			if v.x <= x:
				half = v.y
		var y := rng.randf_range(-half, half) * 0.85
		var lc := Color(0.3, 0.17, 0.08, 0.35 * al) if rng.randf() < 0.6 else Color(0.85, 0.6, 0.36, 0.3 * al)
		draw_line(Vector2(x, y), Vector2(x - rng.randf_range(0.8, 1.6), y * 1.04), lc, 0.32)
	# lustro na zadzie
	draw_colored_polygon(_prof(DEER_RUMP), Color(0.93, 0.89, 0.8, al))
	draw_colored_polygon(_prof(DEER_RUMP, Vector2(0.15, 0), 0.6, 1.0), Color(1.0, 0.98, 0.93, 0.6 * al))
	if fawn:
		# cętki koźlęcia: dwa rzędy po bokach grzbietu
		for k in 7:
			for sg in [-1.0, 1.0]:
				draw_circle(Vector2(-6.0 + k * 1.6, sg * (1.3 + 0.25 * (k % 2))), 0.42, Color(0.95, 0.88, 0.72, 0.9 * al))
	# łeb
	draw_set_transform_matrix(Transform2D(h, Vector2(s, s), 0.0, p - Vector2(lift, lift)) * Transform2D(ha, hp))
	_shaded(DEER_HEAD, Vector2.ZERO, ll.rotated(-ha), outline, shade, coat, hi)
	draw_circle(Vector2(3.0, 0), 0.5, Color(0.08, 0.06, 0.05, al))                  # nos
	draw_line(Vector2(2.3, -0.62), Vector2(2.3, 0.62), Color(0.92, 0.88, 0.8, 0.8 * al), 0.35)   # jasna broda
	for sg in [-1.0, 1.0]:
		draw_circle(Vector2(0.25, sg * 1.2), 0.32, Color(0.06, 0.04, 0.03, al))       # oko
		# uszy: przy nasłuchiwaniu postawione szeroko na boki, przy paszeniu położone do tyłu
		var e0 := Vector2(-1.0, sg * 0.9)
		var e1 := Vector2(-2.0, sg * 2.7) if st == ALERT else Vector2(-3.0, sg * 2.2)
		_leaf(e0, e1, 0.75, outline)
		_leaf(e0, e1, 0.6, coat)
		_leaf(e0.lerp(e1, 0.2), e1.lerp(e0, 0.15), 0.3, Color(0.86, 0.72, 0.58, 0.8 * al))
		if bool(a["buck"]) and not fawn:
			# krótkie różki kozła: tyka z odnogą
			var r0 := Vector2(-0.7, sg * 0.45)
			var r1 := Vector2(-2.4, sg * 0.75)
			draw_line(r0, r1, Color(0.28, 0.2, 0.12, al), 0.45)
			draw_line(r0.lerp(r1, 0.55), r0.lerp(r1, 0.55) + Vector2(0.5, sg * 0.6), Color(0.28, 0.2, 0.12, al), 0.35)
			draw_circle(r0, 0.4, Color(0.35, 0.27, 0.17, al))
	draw_set_transform(Vector2.ZERO)


func _draw_rabbit(a: Dictionary) -> void:
	var p: Vector2 = a["pos"]
	var h: float = a["head"]
	var al: float = a["alpha"]
	var st: int = a["state"]
	var hop := float(a["bob"])
	var s := 1.15
	var lift := hop * 2.4
	var ll := LIGHT.rotated(-h)
	var outline := Color(0.18, 0.14, 0.1, 0.85 * al)
	var shade := Color(0.36, 0.29, 0.21, al)
	var fur := Color(0.5, 0.42, 0.31, al)
	var hi := Color(0.65, 0.57, 0.45, 0.7 * al)
	var hp := Vector2(2.7 + hop * 0.5, 0.0)
	draw_set_transform(p + Vector2(1.2, 1.5) * s + Vector2(lift, lift) * 0.8, h, Vector2(s, s))
	draw_colored_polygon(_prof(RAB_BODY, Vector2.ZERO, 1.0, 1.0 + hop * 0.3), Color(0, 0, 0, 0.26 * al))
	draw_colored_polygon(_prof(RAB_HEAD, hp), Color(0, 0, 0, 0.26 * al))
	draw_set_transform(p - Vector2(lift, lift) * 0.5, h, Vector2(s, s))
	# skoki: tylne łapy wyrzucone do tyłu w locie, przy siedzeniu podwinięte wzdłuż boków
	for sg in [-1.0, 1.0]:
		var f0 := Vector2(-2.2, sg * 1.75)
		var f1 := Vector2(-0.5, sg * 1.95)
		if hop > 0.2:
			f0 = Vector2(-2.6, sg * 1.2)
			f1 = Vector2(-2.6 - 2.2 * hop, sg * 1.1)
		_leaf(f0, f1, 0.55, Color(0.4, 0.33, 0.24, al))
		draw_circle(Vector2(1.9 + hop * 0.8, sg * 0.75), 0.38, Color(0.42, 0.35, 0.26, al))   # przednie łapki
	_shaded(RAB_BODY, Vector2.ZERO, ll * 0.5, outline, shade, fur, hi)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["seed"])
	for k in 14:   # nakrapiana sierść (umaszczenie dzikie)
		draw_circle(Vector2(rng.randf_range(-2.4, 1.6), rng.randf_range(-1.4, 1.4)), rng.randf_range(0.12, 0.22),
			Color(0.2, 0.16, 0.12, 0.5 * al) if rng.randf() < 0.6 else Color(0.75, 0.68, 0.55, 0.5 * al))
	draw_circle(Vector2(-3.0, 0), 0.75, Color(0.96, 0.95, 0.92, al))   # biały ogonek
	_shaded(RAB_HEAD, hp, ll * 0.5, outline, shade, fur, hi)
	for sg in [-1.0, 1.0]:
		draw_circle(hp + Vector2(0.3, sg * 0.8), 0.22, Color(0.05, 0.04, 0.03, al))
		# uszy: położone na grzbiecie przy paszeniu, postawione (z góry krótkie) przy nasłuchiwaniu
		var e0 := hp + Vector2(-0.5, sg * 0.4)
		var e1 := hp + Vector2(-1.1, sg * 1.5) if st == ALERT else hp + Vector2(-3.2, sg * 0.95)
		_leaf(e0, e1, 0.55, outline)
		_leaf(e0, e1, 0.42, Color(0.47, 0.39, 0.29, al))
		draw_circle(e1.lerp(e0, 0.1), 0.25, Color(0.15, 0.12, 0.09, al))   # ciemne końce uszu
	draw_circle(hp + Vector2(1.35, 0), 0.25, Color(0.3, 0.2, 0.18, al))
	draw_set_transform(Vector2.ZERO)
