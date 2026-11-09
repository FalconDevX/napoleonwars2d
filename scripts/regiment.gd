class_name Regiment
extends Node2D
## Pułk: kilkadziesiąt żołnierzy w szyku. Żołnierze to lekkie dane (tablice), nie węzły.
## `center` = środek pierwszego szeregu w świecie. Węzeł stoi w (0,0), więc rysujemy w koordynatach świata.
## Rodzaje: "inf" (piechota), "cav" (kawaleria), "art" (artyleria — pierwszy szereg to działa).

enum State { IDLE, MOVING, CHARGING, MELEE, ROUTING }

static var battle: Battle

const SOLDIER_RADIUS := 2.7
const SOLDIER_ACCEL := 16.0     # jak szybko żołnierz rusza/hamuje (px/s²)
const SOLDIER_TURN := 4.0       # jak szybko obraca się ciało (rad/s)
const MELEE_REACH := 7.0
const FIRE_ARC := 1.15
const SOLDIER_ARC := 0.61     # pojedynczy żołnierz strzela najwyżej ~35° w bok od frontu swojego szeregu
const RELOAD_REAL := 1.9      # ładowanie muszkietu w ogniu bitwy: ~2 strzały na minutę (dane z arkusza x1.9)
const HIT_COMP := 1.85        # salwa rzadsza, ale skupiona — wyrównanie siły ognia (+~25% skuteczności)
const RANGE_MULT := 1.15      # wszystkie jednostki strzelają nieco dalej niż w arkuszu
const VOLLEY_READY := 0.75    # komenda "Fire!" gdy tyle strzelających jest załadowanych
const VOLLEY_WAIT := 5.0      # ...albo gdy pierwsi czekają już tyle sekund
const VOLLEY_WINDOW := 1.0    # salwa trwa ułamek sekundy-sekundę (nie wszyscy w tym samym momencie)
const HORSE_R := 9.0          # promień skrętu konia (jednostki świata)
const HORSE_PIVOT := 0.45     # rad/s — obrót stojącego konia
const HORSE_MAX_TURN := 2.4   # rad/s — górny limit w galopie
const DROWN_RATE := 0.035       # szansa na sekundę, że żołnierz w wodzie utonie
const ART_DEPLOY_TIME := 4.0

var team := 0
var reg_name := ""
var unit_key := "line"
var unit_type := ""
var kind := "inf"
var color := Color.BLUE
var base_files := 16
var _wide_files := 16                 # normalna szerokość szyku (most zwęża go tylko na czas przeprawy)
var accuracy := 1.0
var melee_skill := 1.0
var melee_def := 1.0               # obrona wręcz (arkusz Francji); inne nacje = melee_skill
var armor := 0.0                   # pancerz: ułamek trafień ogniem, które się nie liczą (kirasjerzy)
var heal_acc := 0.0                # leczenie przez ambulans Larreya (ułamki żołnierza)
var discipline := 1.0
var spacing := 9.0
var rank_spacing := 9.0
var walk_speed := 13.0
var run_speed := 28.0
var fire_range := 210.0
var reload_time := 9.0

var center := Vector2.ZERO
var facing := 0.0
var move_target := Vector2.ZERO
var move_facing := 0.0
var attack_target: Regiment = null
var fire_target: Regiment = null
var focus_target: Regiment = null
var officer_alive := true            # dowódca kieruje salwami; bez niego ogień nieregularny ("fire at will")
var _officer_back := 0.0             # sekundy do przejęcia komendy przez podoficera
var _volley_at := -100.0
var _make_ready := 3.0               # ile sekund po zatrzymaniu pułk gotuje broń przed pierwszą salwą             # czas ostatniej komendy "Fire!"
var _first_loaded := -1.0            # od kiedy pierwszy strzelający czeka załadowany
var wedge := false                   # jazda w klinie: ostrze na froncie, mocniejsze uderzenie szarży
var _flag_down := 0.0                # >0: chorąży padł, sztandar leży (sekundy do podniesienia)   # cel wskazany rozkazem ataku (artyleria strzela do niego, póki jest w zasięgu)
var melee_enemies: Array[Regiment] = []
var state := State.IDLE
var morale := 100.0
var initial_count := 0
var last_casualty_time := -100.0
var last_fire_time := -100.0
var selected := false
var dead := false
var fled := false
var flee_dir := Vector2.RIGHT
var in_water_ratio := 0.0
var army_id := -1        # numer armii gracza (-1 = rezerwa)
var garrisoned := false   # stoi we własnej osadzie → bez kosztów utrzymania

# --- dane żołnierzy (równoległe tablice) ---
var s_pos := PackedVector2Array()
var s_hp := PackedFloat32Array()
var s_reload := PackedFloat32Array()
var s_cool := PackedFloat32Array()
var s_aim := PackedFloat32Array()
var s_vel := PackedVector2Array()
var s_jit := PackedVector2Array()
var s_tgt_reg: Array = []
var s_tgt_idx := PackedInt32Array()
var _direct := false                # przejście na nową pozycję: każdy żołnierz idzie prosto na swoje miejsce
var _direct_t := 0.0
var _direct_best := INF
var _direct_stall := 0.0
var fire_at_will := true            # false = piechota strzela tylko do wskazanego celu (na rozkaz gracza)
var _leash_t := 0.0                   # jak długo środek pułku czeka na żołnierzy, którzy utknęli
var _wait_t := 0.0                    # ile już czekamy na maruderów (limit, żeby nigdy nie stać w miejscu)
var net_id := -1                      # identyfikator w grze sieciowej
var base_key := ""     # rodzaj ogólny (np. "lancers" dla ułanów i Kozaków) - mechanika i wygląd bazowy
var commander := 0                      # gracz, który dowodzi pułkiem (0 = AI / nikt)
var net_prev := PackedVector2Array()   # gość: położenia z poprzedniego snapshotu (interpolacja)
var net_next := PackedVector2Array()
var net_c0 := Vector2.ZERO
var net_c1 := Vector2.ZERO
var s_block := PackedFloat32Array()   # >0: żołnierz utknął na zboczu — przez chwilę idzie za środkiem pułku

var reg_vel := Vector2.ZERO        # prędkość całego bloku (żołnierze idą z nią krok w krok)
var _think_timer := 0.0
var _retarget := false
var _pending_files := -1           # szerokość szyku do przyjęcia po dojściu na miejsce
var _forming := false              # przed marszem oddział najpierw spokojnie ustawia szyk
var _form_time := 0.0
var _cohesion := 0.0               # średnia odległość żołnierzy od ich miejsc w szyku
var _disengage_until := -1.0
var _last_autoface := -100.0
var _idle_since := 0.0
var waypoints: Array[Vector2] = []  # trasa (ostatni punkt = cel rozkazu)
var march_mode := false            # bieżący rozkaz idzie drogami kolumną (wybierane automatycznie)
var _in_column := false
var limber_u := 0.0          # artyleria: 0 = działa rozłożone (mogą strzelać), 1 = złożone na przodkach (szybki marsz)
var _needs_limber := false   # rozkaz dalekiego marszu: najpierw złożyć działa
var _art_face := INF          # artyleria: kierunek, do którego bateria płynnie się obraca po dojechaniu
var square := false
var _gun_ang := PackedFloat32Array()   # kąt lufy każdego działa (obraca się powoli za celem)   # czworobok: piechota stoi pustym kwadratem, front na wszystkie strony (przeciw jeździe)
var _trail := PackedVector2Array()  # ślad prowadzącego kolumny (od czoła do tyłu)
var _path_trail := PackedVector2Array()  # ślad środka pułku w marszu (od najnowszego) — droga dla zablokowanych
var _final_facing := 0.0
var _rest_key := Vector3(INF, INF, INF)  # pułk stoi w gotowym szyku → szybka ścieżka symulacji
var _rest_n := -1
var _soldier_acc := 0.0
var _mt := PackedFloat32Array()          # mnożniki prędkości dla typów terenu (bez porównań stringów)
var surround_mask := 0             # 8 sektorów wokół pułku zajętych przez wroga
var flanked_until := -100.0        # do kiedy pokazujemy "oskrzydlony" (trafienie z boku/tyłu)
var _rout_since := -100.0
var stamina := 100.0              # kondycja: bieg, szarża i walka męczą; odpoczynek przywraca
var speed_cap := -1.0             # wspólne tempo dywizji (prędkość najwolniejszego pułku w rozkazie), -1 = brak
var _surrender_acc := 0.0         # ułamki żołnierzy, którzy już się poddają (kapitulacja stopniowa)
var _surrendering := false
var support := 0                  # ilu sojuszników stoi obok (wsparcie morale w szyku dywizji)


func setup(p_team: int, p_name: String, key: String, p_center: Vector2, p_facing: float, p_color: Color) -> void:
	var t: Dictionary = Battle.UNIT_TYPES[key]
	team = p_team
	reg_name = p_name
	color = p_color
	unit_key = key
	base_key = t.get("base", key)
	unit_type = t["name"]
	kind = t["kind"]
	base_files = men_files(t)
	_wide_files = base_files
	accuracy = t["accuracy"]
	melee_skill = t["melee"]
	melee_def = t.get("defense", melee_skill)
	armor = t.get("armor", 0.0)
	discipline = t["discipline"]
	spacing = t["spacing"] * (0.85 if kind == "inf" else (0.92 if kind == "cav" else 1.0))   # gęstszy, zwarty szyk
	rank_spacing = t["rank_spacing"]
	walk_speed = t["walk"]
	run_speed = t["run"]
	fire_range = float(t["range"]) * RANGE_MULT
	reload_time = t["reload"] * (RELOAD_REAL if kind == "inf" else 1.0)
	center = p_center
	facing = p_facing
	move_facing = p_facing
	move_target = p_center
	var count: int = men_count(t)
	# piechota gracza domyślnie strzela tylko na rozkaz; artyleria i AI — według uznania
	fire_at_will = kind != "inf" or (team == 1 and not Net.active()) or not GameSettings.hold_fire
	initial_count = count
	for i in count:
		s_jit.append(Vector2(randf_range(-0.9, 0.9), randf_range(-0.7, 0.7)))
	for i in count:
		s_pos.append(slot_pos(i, count))
		s_hp.append(100.0)
		s_reload.append(randf() * reload_time * 0.6)
		s_cool.append(0.0)
		s_aim.append(facing)
		s_vel.append(Vector2.ZERO)
		s_tgt_reg.append(null)
		s_tgt_idx.append(-1)
		s_block.append(0.0)


const MEN_MULT := 2   # liczebność piechoty i jazdy względem danych jednostek (front rośnie, szeregi zostają)


static func men_mult() -> float:
	## Wielkość pułków z ustawień (w grze sieciowej zawsze domyślna, żeby wszyscy mieli to samo).
	return float(MEN_MULT) if Net.active() else GameSettings.men_mult


static func men_count(t: Dictionary) -> int:
	return int(t["count"]) if t["kind"] == "art" else roundi(int(t["count"]) * men_mult())


static func men_files(t: Dictionary) -> int:
	return int(t["files"]) if t["kind"] == "art" else roundi(int(t["files"]) * men_mult())


func _trail_goal(p: Vector2) -> Vector2:
	## Najbliższy punkt śladu środka pułku, przesunięty trochę w stronę czoła — prowadzi dookoła przeszkody.
	var n := _path_trail.size()
	if n == 0:
		return center
	var best := 0
	var bd := INF
	for k in n:
		var d := p.distance_squared_to(_path_trail[k])
		if d < bd:
			bd = d
			best = k
	return _path_trail[maxi(0, best - 3)]


# ------------------------------------------------------------------ uzupełnianie w osadach

var _refill_acc := 0.0


func can_resupply() -> bool:
	## Odpoczynek we własnej osadzie: tylko bez walki (10 s bez strat, nie w zwarciu, nie w ucieczce).
	return state != State.MELEE and state != State.ROUTING and state != State.CHARGING \
		and battle.sim_time - last_casualty_time > 10.0


func resupply(dt: float, city: bool, can_pay: bool) -> bool:
	## Leczy rannych i co jakiś czas dokłada rekruta (do stanu początkowego). Zwraca true, gdy dodano żołnierza.
	var heal := (6.0 if city else 3.0) * dt
	for i in s_hp.size():
		if s_hp[i] < 100.0:
			s_hp[i] = minf(100.0, s_hp[i] + heal)
	morale = minf(100.0, morale + 2.0 * dt)
	if s_pos.size() >= initial_count:
		_refill_acc = 0.0
		return false
	_refill_acc += dt
	if _refill_acc < (1.2 if city else 3.0) / (men_mult() if kind != "art" else 1.0) or not can_pay:
		return false
	_refill_acc = 0.0
	add_recruit()
	return true


func add_recruit() -> void:
	## Dokłada jednego żołnierza na koniec szyku (uzupełnienie w osadzie, ambulans Larreya).
	if s_pos.size() >= initial_count:
		return
	var n := s_pos.size()
	s_jit.append(Vector2(randf_range(-0.9, 0.9), randf_range(-0.7, 0.7)))
	var p := slot_pos(n, n + 1) if kind != "art" else centroid() - forward() * 20.0
	s_pos.append(p + Vector2(randf_range(-3, 3), randf_range(-3, 3)))
	s_hp.append(100.0)
	s_reload.append(reload_time)
	s_cool.append(0.0)
	s_aim.append(facing)
	s_vel.append(Vector2.ZERO)
	s_tgt_reg.append(null)
	s_tgt_idx.append(-1)
	s_block.append(0.0)
	_rest_key = Vector3(INF, INF, INF)   # szyk się zmienił


# ------------------------------------------------------------------ szyk

func alive_count() -> int:
	return s_pos.size()


func health_frac() -> float:
	## Siła pułku względem stanu początkowego: suma zdrowia żołnierzy / (początkowa liczebność * 100).
	## Ranni też obniżają pasek; nigdy nie przekracza 100%.
	var sum := 0.0
	for hp in s_hp:
		sum += clampf(hp, 0.0, 100.0)
	return clampf(sum / (maxf(1.0, initial_count) * 100.0), 0.0, 1.0)


func gun_count() -> int:
	return art_gun_count(s_pos.size(), base_files) if kind == "art" else 0


func files_for(count: int) -> int:
	return files_for_base(count, base_files)


static func files_for_base(count: int, bf: int) -> int:
	# Linia nie zwęża się po każdej stracie (cały szereg przesuwałby się i przestawał strzelać):
	# drugi szereg może się przerzedzić do połowy, dopiero potem front skraca się — co 2 szeregi naraz.
	if count >= ceili(bf * 1.5):
		return bf
	return maxi(1, ceili(count / 2.0 / 2.0) * 2) if count > 6 else maxi(1, ceili(count / 2.0))


func formation_width() -> float:
	if wedge:
		return float(_wedge_rows(s_pos.size()) - 1) * 2.0 * spacing
	if square:
		return _square_half(s_pos.size()) * 2.0
	return (files_for(s_pos.size()) - 1) * spacing


func formation_depth() -> float:
	if wedge:
		return float(_wedge_rows(s_pos.size()) - 1) * rank_spacing
	if square:
		return _square_half(s_pos.size()) * 2.0
	var n := s_pos.size()
	return (ceili(float(n) / files_for(n)) - 1) * rank_spacing


# ------------------------------------------------------------------ czworobok

func _square_k(n: int) -> int:
	## Ilu żołnierzy na boku w jednym szeregu (dwa szeregi na każdy z 4 boków).
	return maxi(2, ceili(n / 8.0))


func _square_half(n: int) -> float:
	return (_square_k(n) - 1) * 0.5 * spacing + spacing


func square_side(i: int, n: int) -> int:
	var k := _square_k(n)
	return (i % (4 * k)) / k


func square_dir(i: int, n: int) -> float:
	## Kierunek, w który patrzy dany żołnierz czworoboku (na zewnątrz swojego boku).
	return facing + square_side(i, n) * PI * 0.5


func _square_slot(i: int, n: int) -> Vector2:
	var k := _square_k(n)
	var rank := mini(i / (4 * k), 1)
	var j := i % (4 * k)
	var along := (float(j % k) - (k - 1) * 0.5) * spacing
	var off := _square_half(n) - rank * rank_spacing
	var out := Vector2.from_angle(facing + (j / k) * PI * 0.5)
	return center + out * off + out.orthogonal() * along


func net_fit(n: int) -> void:
	## Gość: dopasowanie tablic żołnierzy do liczebności ze snapshotu (pozycje ustawia Net).
	var old := s_jit.size()
	s_jit.resize(n)
	for i in range(old, n):
		s_jit[i] = Vector2(randf_range(-0.9, 0.9), randf_range(-0.7, 0.7))
	s_hp.resize(n)
	s_reload.resize(n)
	s_cool.resize(n)
	s_aim.resize(n)
	s_vel.resize(n)
	s_block.resize(n)
	s_tgt_reg.resize(n)
	s_tgt_idx.resize(n)


# ------------------------------------------------------------------ klin (jazda)

static func _wedge_rows(n: int) -> int:
	return maxi(1, ceili(sqrt(float(n))))


func _wedge_slot(i: int, n: int) -> Vector2:
	## Rząd r ma 2r+1 jeźdźców (1, 3, 5...), ostrze klina na froncie; ostatni rząd wyśrodkowany.
	var r := int(floor(sqrt(float(i))))
	var k := i - r * r
	var in_row := mini(2 * r + 1, n - r * r)
	var x := (float(k) - float(in_row - 1) * 0.5) * spacing
	var depth := float(_wedge_rows(n) - 1) * rank_spacing
	var fwd := forward()
	return center + fwd.rotated(PI * 0.5) * x + fwd * (depth * 0.5 - float(r) * rank_spacing)


func order_wedge(on: bool) -> void:
	if Net.is_client():
		Net.inst.cmd(["wedge", net_id, on])
		return
	if kind != "cav" or dead or state == State.ROUTING or state == State.MELEE or wedge == on:
		return
	wedge = on
	_rest_key = Vector3(INF, INF, INF)
	_reform()


func order_square(on: bool) -> void:
	if Net.is_client():
		Net.inst.cmd(["square", net_id, on])
		return
	## Formowanie / rozwiązanie czworoboku (tylko piechota, nie w walce wręcz i nie w ucieczce).
	if kind != "inf" or dead or state == State.ROUTING or state == State.MELEE or square == on:
		return
	square = on
	_in_column = false
	waypoints.clear()
	attack_target = null
	if state != State.IDLE:
		_set_idle()
	move_facing = facing
	_rest_key = Vector3(INF, INF, INF)
	_reform()


func _reform_square() -> void:
	## Każdy żołnierz idzie na najbliższe kątowo miejsce w czworoboku (bez przechodzenia przez środek).
	var n := s_pos.size()
	var c := center
	var slots: Array = range(n)
	var sp: Array = []
	for k in n:
		sp.append((_square_slot(k, n) - c).angle())
	slots.sort_custom(func(a: int, b: int) -> bool: return sp[a] < sp[b])
	var men: Array = range(n)
	var pos := s_pos
	men.sort_custom(func(a: int, b: int) -> bool: return (pos[a] - c).angle() < (pos[b] - c).angle())
	var final: Array = []
	final.resize(n)
	for m in n:
		final[slots[m]] = men[m]
	_apply_order(final)


func forward() -> Vector2:
	return Vector2.from_angle(facing)


func slot_pos(i: int, count: int) -> Vector2:
	if wedge:
		return _wedge_slot(i, count) + _jit_world(i) * 0.3
	if square:
		return _square_slot(i, count) + _jit_world(i) * 0.3
	if kind == "art":
		return art_slot_for(i, count, center, facing, base_files, spacing) + _jit_world(i) * 0.5
	return slot_pos_for(i, count, center, facing, base_files, spacing, rank_spacing) + _jit_world(i)


# Obsługa działa rozstawiona wokół niego: (w prawo, do tyłu) względem osi działa.
const ART_CREW := [Vector2(0, 20), Vector2(-9, 3), Vector2(9, 3), Vector2(-7, 26), Vector2(7, 26), Vector2(0, 32)]


static func art_gun_count(count: int, bf: int) -> int:
	return clampi(ceili(count / 3.0), 1, bf)


static func art_gun_pos(g: int, guns: int, c: Vector2, f_angle: float, sp: float) -> Vector2:
	var fwd := Vector2.from_angle(f_angle)
	var x := (float(g) - float(guns - 1) * 0.5) * sp
	return c + fwd.rotated(PI * 0.5) * x


static func art_slot_for(i: int, count: int, c: Vector2, f_angle: float, bf: int, sp: float) -> Vector2:
	var guns := art_gun_count(count, bf)
	var g := i % guns
	var role := mini(i / guns, ART_CREW.size() - 1)
	var fwd := Vector2.from_angle(f_angle)
	var off: Vector2 = ART_CREW[role]
	return art_gun_pos(g, guns, c, f_angle, sp) + fwd.rotated(PI * 0.5) * off.x - fwd * off.y


func _jit_world(i: int) -> Vector2:
	var fwd := Vector2.from_angle(facing)
	return fwd.rotated(PI * 0.5) * s_jit[i].x - fwd * s_jit[i].y


static func slot_pos_for(i: int, count: int, c: Vector2, f_angle: float, bf: int, sp: float, rsp: float) -> Vector2:
	var f := files_for_base(count, bf)
	var rank := i / f
	var file := i % f
	var in_rank := mini(f, count - rank * f)
	var x := (float(file) - float(in_rank - 1) * 0.5) * sp
	var y := float(rank) * rsp
	var fwd := Vector2.from_angle(f_angle)
	return c + fwd.rotated(PI * 0.5) * x - fwd * y


func set_facing(f: float) -> void:
	## Zmiana kierunku: szyk nie obraca się jak bryła — żołnierze sami przechodzą na najbliższe nowe miejsca.
	facing = f
	_art_face = INF
	_reform()


func _reform() -> void:
	var n := s_pos.size()
	if n < 2 or kind == "art":
		return
	if square:
		_reform_square()
		return
	if wedge:
		# klin: każdy jeździec na najbliższe wolne miejsce (zachłannie, od ostrza)
		var taken := {}
		var final_w: Array = []
		final_w.resize(n)
		for slot in n:
			var sp := _wedge_slot(slot, n)
			var best := -1
			var bd := INF
			for m in n:
				if taken.has(m):
					continue
				var d := s_pos[m].distance_squared_to(sp)
				if d < bd:
					bd = d
					best = m
			taken[best] = true
			final_w[slot] = best
		_apply_order(final_w)
		return
	var f := files_for(n)
	var fwd := forward()
	var right := fwd.rotated(PI * 0.5)
	var order: Array = range(n)
	var pos := s_pos
	var c := center
	order.sort_custom(func(a: int, b: int) -> bool: return (pos[a] - c).dot(fwd) > (pos[b] - c).dot(fwd))
	var final: Array = []
	var start := 0
	while start < n:
		var chunk: Array = order.slice(start, mini(start + f, n))
		chunk.sort_custom(func(a: int, b: int) -> bool: return (pos[a] - c).dot(right) < (pos[b] - c).dot(right))
		final.append_array(chunk)
		start += f
	_apply_order(final)


func _apply_order(final: Array) -> void:
	## Przestawia dane żołnierzy wg nowej kolejności (miejsc w szyku).
	var n := s_pos.size()
	var np := PackedVector2Array()
	var nh := PackedFloat32Array()
	var nr := PackedFloat32Array()
	var nc := PackedFloat32Array()
	var na := PackedFloat32Array()
	var nv := PackedVector2Array()
	for k in final:
		np.append(s_pos[k])
		nh.append(s_hp[k])
		nr.append(s_reload[k])
		nc.append(s_cool[k])
		na.append(s_aim[k])
		nv.append(s_vel[k])
	s_pos = np
	s_hp = nh
	s_reload = nr
	s_cool = nc
	s_aim = na
	s_vel = nv
	for i in n:
		s_tgt_reg[i] = null
		s_tgt_idx[i] = -1
	_rest_n = -1


func centroid() -> Vector2:
	var c := Vector2.ZERO
	for p in s_pos:
		c += p
	return c / maxf(1.0, s_pos.size())


func anchor() -> Vector2:
	## Front-środek faktycznych ludzi. W przejściu na nową pozycję (_direct) `center` od razu stoi na celu,
	## a żołnierze dopiero tam idą — rysowanie, sztandar i cele szarży muszą trzymać się ludzi, nie celu.
	if _direct and state == State.MOVING and not s_pos.is_empty():
		return centroid() + forward() * formation_depth() * 0.5
	return center


func distance_to_soldiers(p: Vector2) -> float:
	var best := INF
	for sp in s_pos:
		best = minf(best, sp.distance_squared_to(p))
	return sqrt(best)


# ------------------------------------------------------------------ rozkazy

func final_target() -> Vector2:
	return waypoints.back() if not waypoints.is_empty() else move_target


func order_move(pos: Vector2, f: float, files := -1, cap := -1.0) -> void:
	if Net.is_client():
		Net.inst.cmd(["move", net_id, pos, f, files, cap])
		return

	if state == State.ROUTING or dead:
		return
	# rozkaz bez podanej szerokości = normalny szyk (nie ten zwężony na moście); podana szerokość staje się normalną
	if files > 0:
		_wide_files = files
	else:
		files = _wide_files
	if state == State.MELEE or battle.sim_time < _disengage_until:
		_disengage_until = battle.sim_time + 7.0   # odwrót z walki: przez chwilę nikt nas nie wiąże zwarciem
		center = centroid()
	_final_facing = f
	speed_cap = cap
	square = false   # w marszu czworobok się rozwiązuje
	# Trasa: prosto do celu. Jedyny wyjątek to rzeka — głęboki nurt da się przejść tylko w brodzie przy moście,
	# więc linia łamie się na przeprawie (most/bród) i dalej znów biegnie prosto.
	# Cel kliknięty w górach przesuwa się na najbliższe podnóże, w nurcie — na brzeg.
	pos = EdgeFog.clamp_inside(pos, battle.map_size)   # pas przy krawędzi mapy jest niedostępny
	var tgt := battle.terrain.bank_point(battle.terrain.free_point(pos))
	var half_w := float((files if files > 0 else base_files) - 1) * spacing * 0.5
	var r := battle.terrain.crossing_route(center, tgt, half_w, 0, kind != "art")
	# Ruch w pełni ręczny: oddział idzie tam, gdzie kazano, w szyku — tak samo po polu i po drodze.
	march_mode = false
	_in_column = false
	waypoints.assign(r["points"])
	if r["bridge"]:
		if files <= 0:
			files = base_files if _pending_files <= 0 else _pending_files
		var column := 6 if kind == "inf" else (4 if kind == "cav" else 2)
		base_files = mini(base_files, column)
	_pending_files = files
	pos = waypoints[0]
	if waypoints.size() > 1:
		f = (waypoints[1] - pos).angle()
	move_target = pos
	move_facing = f
	attack_target = null
	fire_target = null
	focus_target = null
	state = State.MOVING
	var to := pos - center
	if kind == "art":
		# daleki marsz: działa trzeba najpierw złożyć na przodki; krótki - przetaczają je ręcznie
		_needs_limber = to.length() >= 70.0 or limber_u > 0.0
	if to.length() < 70.0:
		_apply_pending_files()
		set_facing(f)  # krótki ruch: od razu docelowy szyk
	elif kind != "art" or limber_u >= 1.0:
		set_facing(to.angle())  # długi marsz: front w stronę marszu
	# Rusza od razu: żołnierze dobiegają na swoje miejsca w marszu (bez stania i równania szyku).
	_forming = false
	_wait_t = 0.0
	_form_time = 0.0
	# Przejście na pobliską pozycję (bez przeprawy): szyk "przenosi się" od razu na miejsce docelowe, a każdy
	# żołnierz idzie prosto na swoje nowe miejsce (najbliższe — bez krzyżowania), swoim tempem. Szybsi docierają
	# wcześniej i czekają w szeregu, aż dojdzie reszta. Nie ma sztywnego bloku ani obracania całości na końcu.
	_direct = false
	if kind != "art" and not wedge and waypoints.size() == 1 and not r["bridge"] and to.length() < 1100.0:
		_direct = true
		_direct_t = 0.0
		_direct_best = INF
		_direct_stall = 0.0
		_apply_pending_files()
		center = pos
		facing = f
		set_facing(f)


func col_gap() -> float:
	## Odstęp między kolejnymi rzędami kolumny marszowej.
	return 13.0 if kind == "cav" else (11.0 if kind == "art" else 7.0)


func col_width() -> int:
	## Ilu idzie obok siebie w kolumnie: piechota czwórkami, kawaleria dwójkami, działa pojedynczo.
	return 2 if kind == "cav" else (1 if kind == "art" else 4)


func col_lane() -> float:
	return 11.0 if kind == "cav" else 7.0


func _col_rows() -> int:
	return ceili(float(s_pos.size()) / col_width())


func _order_column_march(pos: Vector2, files: int, r: Dictionary) -> void:
	## Marsz drogami: oddział idzie kolumną (kilka rzędów obok siebie) po śladzie prowadzącego.
	## Rusza od razu — żołnierze dołączają do kolumny w marszu.
	waypoints.assign(r["points"])
	if files <= 0:
		files = base_files if _pending_files <= 0 else _pending_files
	_pending_files = files
	move_target = waypoints[0]
	move_facing = _final_facing
	attack_target = null
	fire_target = null
	state = State.MOVING
	var dir := (move_target - center)
	dir = dir.normalized() if dir.length() > 1.0 else forward()
	var right := dir.orthogonal()
	_in_column = true
	# Czoło kolumny: najbliżej celu stojący żołnierze; rzędy po `col_width`, w rzędzie od lewej do prawej.
	var order: Array = range(s_pos.size())
	var pos_arr := s_pos
	var c := center
	order.sort_custom(func(a: int, b: int) -> bool: return (pos_arr[a] - c).dot(dir) > (pos_arr[b] - c).dot(dir))
	var final: Array = []
	var w := col_width()
	var start := 0
	while start < order.size():
		var chunk: Array = order.slice(start, mini(start + w, order.size()))
		chunk.sort_custom(func(a: int, b: int) -> bool: return (pos_arr[a] - c).dot(right) > (pos_arr[b] - c).dot(right))
		final.append_array(chunk)
		start += w
	_apply_order(final)
	# Prowadzący startuje z czoła obecnego szyku; ślad startowy biegnie przez środek szyku do tyłu.
	center = center + dir * 4.0
	facing = dir.angle()
	_trail = PackedVector2Array()
	var length := _col_rows() * col_gap() + 80.0
	for k in int(length / 3.0) + 2:
		_trail.append(center - dir * k * 3.0)
	_forming = false
	_form_time = 0.0


func _column_slots(n: int) -> PackedVector2Array:
	## Pozycje w kolumnie: rząd co `col_gap` wzdłuż śladu, w rzędzie `col_width` ludzi obok siebie (prostopadle do śladu).
	var slots := PackedVector2Array()
	slots.resize(n)
	var w := col_width()
	var lane := col_lane()
	var rows := ceili(float(n) / w)
	var gap := col_gap()
	var acc := 0.0
	var row := 0
	var target := 0.0
	var last_p := center
	var last_t := forward()
	for k in _trail.size() - 1:
		var a := _trail[k]
		var b := _trail[k + 1]
		var seg := a.distance_to(b)
		if seg > 0.001:
			last_t = (a - b) / seg
		while row < rows and target <= acc + seg:
			var p := a.lerp(b, (target - acc) / maxf(seg, 0.001))
			_place_row(slots, row, w, n, p, last_t, lane)
			last_p = p
			row += 1
			target = row * gap
		acc += seg
		if row >= rows:
			break
	while row < rows:
		last_p -= last_t * gap
		_place_row(slots, row, w, n, last_p, last_t, lane)
		row += 1
	return slots


func _place_row(slots: PackedVector2Array, row: int, w: int, n: int, p: Vector2, tangent: Vector2, lane: float) -> void:
	var side := tangent.orthogonal()
	var in_row := mini(w, n - row * w)
	for l in in_row:
		var off := (float(l) - float(in_row - 1) * 0.5) * lane
		slots[row * w + l] = p + side * off


func _apply_pending_files() -> void:
	if _pending_files > 0:
		base_files = _pending_files
		_pending_files = -1


func order_attack(target: Regiment) -> void:
	if Net.is_client():
		if target != null:
			Net.inst.cmd(["attack", net_id, target.net_id])
		return
	if state == State.ROUTING or dead or target == null or target.dead:
		return
	if kind == "art":
		# Artyleria nie szarżuje. Cel już w zasięgu → bateria tylko obraca się frontem i ostrzeliwuje go;
		# poza zasięgiem → podjeżdża tylko na skraj zasięgu (nie pod nos wroga).
		focus_target = target
		var dir := (target.center - center).normalized()
		var d := center.distance_to(target.center)
		var reach := fire_range + target.formation_width() * 0.3
		if d <= reach * 0.97:
			if state == State.IDLE or state == State.MOVING:
				waypoints.clear()
				_set_idle()
			if absf(angle_difference(facing, dir.angle())) > FIRE_ARC * 0.5:
				move_facing = dir.angle()
				set_facing(dir.angle())
			return
		order_move(target.center - dir * fire_range * 0.92, dir.angle())
		focus_target = target
		return
	if kind == "inf" and focus_target != target and state != State.MELEE 			and center.distance_to(target.center) <= fire_range + target.formation_width() * 0.5:
		# wróg w zasięgu: pierwszy rozkaz = "ognia do nich!" (stoi i strzela), drugi = szarża na bagnety
		focus_target = target
		if state == State.MOVING or state == State.CHARGING:
			waypoints.clear()
			attack_target = null
			_set_idle()
		var fa := (target.center - center).angle()
		if not square and absf(angle_difference(facing, fa)) > FIRE_ARC * 0.6:
			move_facing = fa
			set_facing(fa)
		return
	_direct = false
	attack_target = target
	fire_target = null
	speed_cap = -1.0
	# Szarża przez rzekę: najpierw na przeprawę (wszystkie punkty trasy oprócz ostatniego = sam wróg).
	var r := battle.terrain.crossing_route(center, target.center, formation_width() * 0.5, 0, kind != "art")
	var pts: Array = r["points"]
	pts.pop_back()
	waypoints.assign(pts)
	_in_column = false
	square = false
	if state != State.MELEE:
		state = State.CHARGING


func order_fire_at_will(on: bool) -> void:
	if Net.is_client():
		Net.inst.cmd(["fire", net_id, on])
		return
	fire_at_will = on


func order_halt() -> void:
	if Net.is_client():
		Net.inst.cmd(["halt", net_id])
		return
	if state == State.ROUTING or state == State.MELEE or dead:
		return
	if _direct:
		# stój w trakcie przejścia: szyk staje tam, gdzie są teraz ludzie
		center = centroid() + forward() * formation_depth() * 0.5
		move_target = center
		_rest_key = Vector3(INF, INF, INF)
	_set_idle()
	move_facing = facing
	attack_target = null
	waypoints.clear()
	_in_column = false
	_apply_pending_files()


func gun_angle(g: int) -> float:
	return _gun_ang[g] if g < _gun_ang.size() else facing


func _update_gun_aim(dt: float) -> void:
	## Każde działo obsługa obraca powoli (drągiem za ogon lawety) w stronę celu, w granicach pola ostrzału.
	var guns := gun_count()
	if _gun_ang.size() != guns:
		var old := _gun_ang.size()
		_gun_ang.resize(guns)
		for g in range(old, guns):
			_gun_ang[g] = facing
	var rate := (0.55 if base_key == "horse_art" else 0.4) * dt
	for g in guns:
		var want := facing
		if limber_u > 0.0:
			rate = 3.0 * dt   # przy składaniu lufa wraca na wprost
		elif fire_target != null and not fire_target.dead:
			var a := (fire_target.center - gun_pos(g)).angle()
			if absf(angle_difference(facing, a)) < FIRE_ARC:
				want = a
		_gun_ang[g] = rotate_toward(_gun_ang[g], want, rate)


func limber_time() -> float:
	# zaprzęg musi zawrócić, przejechać obok działa i zajechać do haka (~130 j. kłusem/stępa)
	return 4.5 if base_key == "horse_art" else 7.0


func unlimber_time() -> float:
	return 5.0 if base_key == "horse_art" else 7.5


func move_mult() -> float:
	## Złożona artyleria jedzie zaprzęgiem: dużo szybciej niż przetaczane ręcznie działa
	## (piesza ~ tempo piechoty w marszu forsownym, konna ~ tempo jazdy).
	if kind == "art" and limber_u >= 1.0:
		var want := 36.0 if base_key == "horse_art" else 22.0
		return maxf(2.2 if base_key == "horse_art" else 1.9, want / maxf(walk_speed, 1.0))
	return 1.0


func is_limbering() -> bool:
	return kind == "art" and state == State.MOVING and _needs_limber and limber_u < 1.0


func is_unlimbering() -> bool:
	return kind == "art" and state != State.MOVING and limber_u > 0.0


func _set_idle() -> void:
	_rest_n = -1
	_direct = false
	if state != State.IDLE:
		_idle_since = battle.sim_time
		_make_ready = randf_range(2.5, 4.0) / maxf(discipline, 0.5)   # weterani szybciej
	state = State.IDLE


# ------------------------------------------------------------------ symulacja

func simulate(dt: float) -> void:
	if dead:
		return
	if _flag_down > 0.0:
		_flag_down -= dt   # ktoś z szeregu podnosi sztandar
	if not officer_alive:
		_officer_back -= dt
		if _officer_back <= 0.0:
			officer_alive = true   # podoficer przejmuje komendę — znów salwy
	_update_volley()
	if kind == "art" and state != State.MOVING and limber_u > 0.0:
		limber_u = maxf(0.0, limber_u - dt / unlimber_time())   # rozkładanie dział po zatrzymaniu
	if kind == "art" and _art_face != INF:
		if state == State.MOVING:
			_art_face = INF
		else:
			facing = rotate_toward(facing, _art_face, 1.1 * dt)   # cała bateria zawraca łukiem
			if absf(angle_difference(facing, _art_face)) < 0.005:
				facing = _art_face
				_art_face = INF
	if kind == "art":
		_update_gun_aim(dt)
	_remove_dead()
	if s_pos.is_empty():
		_die()
		return
	_think_timer -= dt
	if _think_timer <= 0.0:
		_think_timer = randf_range(0.2, 0.3)
		_think()
	_move(dt)
	# Pułki poza ekranem (lub przy dużym oddaleniu) liczą żołnierzy rzadziej — 20 razy/s.
	_soldier_acc += dt
	if visible or _soldier_acc >= 0.05:
		_update_soldiers(_soldier_acc)
		_soldier_acc = 0.0
	_update_morale(dt)
	_update_stamina(dt)


func stamina_f() -> float:
	return stamina / 100.0


func _update_stamina(dt: float) -> void:
	## Kondycja: marsz męczy lekko, bieg/szarża i walka wręcz mocno; stojąc odpoczywa (w kwaterach szybciej).
	## Zmęczony pułk wolniej biega, wolniej ładuje, słabiej walczy i szarżuje — nie da się wiecznie rzucać tych samych ludzi.
	var d := 0.0
	match state:
		State.IDLE:
			d = 4.0 if garrisoned else (1.2 if fire_target != null else 2.5)
		State.MOVING:
			d = -0.12 if (kind == "cav" or limber_u >= 1.0) else -0.2
			var c := battle.terrain.cell_at(center)
			if c == Terrain.FORD or c == Terrain.SWAMP or c == Terrain.WATER or c == Terrain.RAVINE:
				d -= 0.6
		State.CHARGING:
			if not waypoints.is_empty():
				d = -0.2
			else:
				d = -5.0 if kind == "cav" else -3.5
		State.MELEE:
			d = -1.6
		State.ROUTING:
			d = -1.5
	stamina = clampf(stamina + d * dt, 0.0, 100.0)


func fatigue_name() -> String:
	if stamina < 25.0:
		return "exhausted"
	if stamina < 55.0:
		return "tired"
	return ""


func _die() -> void:
	dead = true
	visible = false
	selected = false


func _remove_dead() -> void:
	# Martwego żołnierza zastępuje ostatni (z tylnego szeregu) — "zamykanie szeregów".
	var i := s_pos.size() - 1
	while i >= 0:
		if s_hp[i] <= 0.0:
			# dowódca też może paść: pułk traci rytm salw, dopóki komendy nie przejmie podoficer
			if kind == "inf" and officer_alive and randf() < 1.0 / maxf(s_pos.size(), 1.0):
				officer_alive = false
				_officer_back = randf_range(18.0, 32.0)
				morale -= 8.0 / discipline
				if team == 0:
					battle.message("%s: officer down - firing at will" % reg_name)
			# chorąży stoi za szykiem, ale też ginie: utrata sztandaru mocno uderza w morale
			if kind != "art" and _flag_down <= 0.0 and randf() < 1.0 / maxf(s_pos.size(), 1.0):
				_flag_down = randf_range(4.0, 8.0)
				morale -= 12.0 / discipline
			if not battle.terrain.is_water(s_pos[i]):
				battle.corpses.add_corpse(s_pos[i], _uniform()["coat"], s_aim[i], kind == "cav", sprite_key())
			var last := s_pos.size() - 1
			if i != last:
				s_pos[i] = s_pos[last]
				s_hp[i] = s_hp[last]
				s_reload[i] = s_reload[last]
				s_cool[i] = s_cool[last]
				s_aim[i] = s_aim[last]
				s_vel[i] = s_vel[last]
				s_jit[i] = s_jit[last]
				s_tgt_reg[i] = s_tgt_reg[last]
				s_tgt_idx[i] = s_tgt_idx[last]
				s_block[i] = s_block[last]
			s_pos.resize(last)
			s_hp.resize(last)
			s_reload.resize(last)
			s_cool.resize(last)
			s_aim.resize(last)
			s_vel.resize(last)
			s_jit.resize(last)
			s_tgt_reg.resize(last)
			s_tgt_idx.resize(last)
			s_block.resize(last)
		i -= 1


func _blocked_at(q: Vector2) -> bool:
	## Przeszkoda dla żołnierza: góry zawsze; głęboki nurt tylko dla artylerii (piechota i jazda przechodzą wpław).
	var t := battle.terrain
	if state != State.ROUTING:
		# krawędź mapy (mgła): tylko uciekający mogą tam wbiec i zniknąć
		var m: float = EdgeFog.NO_GO * 0.75
		var ms := battle.map_size
		if q.x < m or q.y < m or q.x > ms.x - m or q.y > ms.y - m:
			return true
	return t.is_mountain_fast(q) or (kind == "art" and t.is_deep_fast(q))


func to_slot_sq(i: int, goal: Vector2) -> float:
	return s_pos[i].distance_squared_to(goal)


func engage_dist() -> float:
	return 20.0 if kind == "cav" else 16.0


func _min_soldier_dist_sq(e: Regiment, limit_sq: float) -> float:
	var best := INF
	var n := s_pos.size()
	var step := 1 if n < 30 else 2
	for a in range(0, n, step):
		var p := s_pos[a]
		for q in e.s_pos:
			var d := p.distance_squared_to(q)
			if d < best:
				best = d
				if best < limit_sq:
					return best
	return best


func _nearest_enemy() -> Regiment:
	var best: Regiment = null
	var bd := INF
	for e in battle.regiments:
		if e.team == team or e.dead:
			continue
		var d := center.distance_squared_to(e.center)
		if d < bd:
			bd = d
			best = e
	return best


func _think() -> void:
	_retarget = true
	var now := battle.sim_time

	# Kontakt wręcz: którykolwiek z naszych żołnierzy blisko wrogiego.
	melee_enemies.clear()
	var my_r := formation_width() * 0.5 + formation_depth() + 20.0 + (_cohesion * 2.5 if _direct else 0.0)
	var ed := engage_dist()
	for e in battle.regiments:
		if e.team == team or e.dead:
			continue
		if e.state == State.ROUTING and not _pursues(e):
			continue
		if now < e._disengage_until and not (kind == "cav" and attack_target == e):
			continue   # wróg wycofuje się na rozkaz — nie gonimy go zwarciem (chyba że jazda szarżuje właśnie na niego)
		var their_r := e.formation_width() * 0.5 + e.formation_depth() + 20.0
		if anchor().distance_to(e.anchor()) > my_r + their_r + 20.0:
			continue
		if _min_soldier_dist_sq(e, ed * ed) < ed * ed:
			melee_enemies.append(e)

	_update_surround()
	_update_support()

	if state == State.ROUTING:
		_update_flee()
		return

	if not melee_enemies.is_empty() and now >= _disengage_until:
		if state != State.MELEE:
			if state == State.CHARGING:
				_charge_impact()
			state = State.MELEE
			fire_target = null
		return
	elif state == State.MELEE:
		_set_idle()
		center = centroid()
		move_facing = facing
		attack_target = null

	if state == State.CHARGING and (attack_target == null or attack_target.dead 			or (attack_target.state == State.ROUTING and not _pursues(attack_target))):
		_set_idle()
		attack_target = null
		waypoints.clear()
		move_facing = facing

	# Wybór celu ostrzału (tylko gdy pułk stoi).
	fire_target = null
	if state == State.IDLE and fire_range > 0.0:
		var best: Regiment = null
		var bd := INF
		for e in battle.regiments:
			if e.team == team or e.dead:
				continue
			if not fire_at_will and e != focus_target:
				continue   # ogień tylko na rozkaz: bez wskazanego celu pułk stoi z bronią gotową
			var d := center.distance_to(e.center)
			if d > fire_range + e.formation_width() * 0.5:
				continue
			if e.state == State.ROUTING:
				d += 250.0  # najpierw ci, którzy jeszcze walczą
			if d < bd:
				bd = d
				best = e
		if focus_target != null and not focus_target.dead and focus_target.state != State.ROUTING 				and center.distance_to(focus_target.center) <= fire_range + focus_target.formation_width() * 0.5:
			best = focus_target   # wskazany cel ma pierwszeństwo przed najbliższym
		elif focus_target != null and (focus_target.dead or focus_target.state == State.ROUTING):
			focus_target = null
		if best != null:
			var ang := (best.center - center).angle()
			if square:
				fire_target = best   # czworobok ma front z każdej strony
			elif absf(angle_difference(facing, ang)) < FIRE_ARC:
				fire_target = best
			elif now - _last_autoface > 4.0:
				# Wróg z boku/tyłu: żołnierze sami odwracają się frontem do niego.
				_last_autoface = now
				move_facing = ang
				set_facing(ang)
				_idle_since = now


func braced_against(from: Vector2) -> bool:
	## Czy piechota przyjmie szarżę na bagnety: stoi w szyku (nie w marszu/kolumnie), z dobrym morale,
	## a atak idzie od frontu.
	if kind != "inf" or _in_column:
		return false
	if state == State.MOVING or state == State.ROUTING or state == State.CHARGING:
		return false
	if square:
		return morale >= 30.0   # czworobok: bagnety z każdej strony
	if morale < 55.0:
		return false
	return hit_dir_mult(from) < 1.2


func _pursues(e: Regiment) -> bool:
	## Piechota nie goni uciekających; kawaleria ściga ich tylko przez chwilę.
	return kind == "cav" and battle.sim_time - e._rout_since < 8.0


func _charge_impact() -> void:
	## Uderzenie szarży: kawaleria zadaje straty i łamie morale, piechota tylko morale.
	for e in melee_enemies:
		var dm := e.hit_dir_mult(center)
		if kind == "cav":
			# zmęczone konie nie mają rozpędu — szarża z wyczerpania traci połowę siły
			var power := float(Battle.UNIT_TYPES[unit_key].get("charge", 1.6 if base_key == "lancers" else 1.0)) * dm \
				* lerpf(0.45, 1.0, stamina_f()) * (1.2 if wedge else 1.0)
			if e.braced_against(center):
				# Zwarta piechota od frontu: konie nie wchodzą na bagnety — szarża słabnie, jeźdźcy padają.
				power *= 0.2 if e.square else 0.4
				morale -= (18.0 if e.square else 12.0) / discipline
				var lost := int(randf_range(1.0, 3.0) * float(e.alive_count()) / maxf(1.0, e.initial_count) * 2.0)
				for k in lost:
					if s_pos.is_empty():
						break
					var mine := randi() % s_pos.size()
					damage(mine, randf_range(60.0, 130.0))
				battle.effects.add_spark(center)
			e.morale -= 20.0 * power / e.discipline
			var hits := int(randf_range(2, 5) * power * float(s_pos.size()) / initial_count)
			for k in hits:
				if e.s_pos.is_empty():
					break
				var j := randi() % e.s_pos.size()
				if e.s_pos[j].distance_to(center) < 60.0 + formation_width() * 0.5:
					e.damage(j, randf_range(60.0, 130.0))
		else:
			e.morale -= 10.0 * dm * discipline / e.discipline * lerpf(0.5, 1.0, stamina_f())


func _update_flee() -> void:
	var home := battle.home_dir(team, center)
	var e := _nearest_enemy()
	var away := home
	if e != null:
		away = (center - e.center).normalized()
	var want := (away + home * 0.7).normalized()
	# Uciekający nie wbiegają do rzek i jezior: spośród kierunków bliskich pożądanemu wybieramy taki,
	# na którym przez najbliższe ~350 j. nie ma wody ani gór (most/bród przez rzekę jest w porządku).
	var terrain := battle.terrain
	var best := want
	var best_score := -INF
	for k in 16:
		var d := want.rotated((k / 2) * 0.35 * (1.0 if k % 2 == 0 else -1.0))
		var score := d.dot(want) * 2.0
		for step in range(1, 8):
			var q := center + d * step * 50.0
			var c := terrain.cell_at(q)
			if c == Terrain.WATER or c == Terrain.MOUNTAIN:
				score -= 6.0 / step + 1.0
			elif c == Terrain.SWAMP:
				score -= 0.6
		if score > best_score:
			best_score = score
			best = d
	flee_dir = best


func _move(dt: float) -> void:
	var tmult := battle.terrain.speed_mult(center, kind)
	if tmult <= 0.0:
		tmult = 0.6   # środek szyku otarł się o zbocze — to punkt umowny, nie może utknąć (żołnierze sami omijają góry)
	var prev := center
	match state:
		State.IDLE:
			pass
		State.MOVING:
			var to := move_target - center
			var d := to.length()
			if _direct:
				_direct_t += dt
				# koniec przejścia: prawie wszyscy na miejscach (albo ktoś utknął na dobre)
				# pierwsze chwile: _cohesion to jeszcze stara wartość (0 = stał w szyku) — nie może być punktem odniesienia,
				# inaczej "nikt się nie przybliża" odpala po 4 s i pułk staje, zanim ludzie dojdą (sztandar na celu)
				if _direct_t < 0.3 or _cohesion < _direct_best - 0.5:
					_direct_best = _cohesion
					_direct_stall = 0.0
				else:
					_direct_stall += dt   # nikt się nie przybliża (np. ktoś utknął za zboczem)
				if (_cohesion < 2.0 and _direct_t > 0.5) or (_direct_stall > 4.0 and _direct_t > 3.0) or _direct_t > 90.0:
					_direct = false
					_set_idle()
					waypoints.clear()
			elif kind == "art" and _needs_limber and limber_u < 1.0:
				# składanie dział: obsługa podprowadza przodki z końmi i zaczepia lawety
				limber_u = minf(1.0, limber_u + dt / limber_time())   # bez obrotu w miejscu — zaprzęg skręca w marszu
			elif _forming:
				_form_time += dt
				if _cohesion < (4.0 if _in_column else 2.5) or _form_time > (10.0 if _in_column else 12.0):
					_forming = false
			elif waypoints.size() > 1 and d < 12.0:
				# punkt pośredni trasy → dalej, bez zatrzymywania
				waypoints.pop_front()
				move_target = waypoints[0]
				if waypoints.size() == 1:
					move_facing = _final_facing
				var nd := (move_target - center).angle()
				if _in_column:
					facing = nd
				elif kind == "art" and limber_u >= 1.0:
					pass   # złożona bateria skręca łukiem (niżej), nie obraca się w miejscu
				elif absf(angle_difference(facing, nd)) > 0.25:
					set_facing(nd)
			elif d > 0.5:
				var dir := to / d
				var base_spd := walk_speed * move_mult()
				if speed_cap > 0.0:
					base_spd = minf(base_spd, speed_cap)   # dywizja maszeruje razem — tempem najwolniejszego
				if battle.sim_time < _disengage_until:
					base_spd = maxf(base_spd, run_speed * 0.75)   # odwrót z walki biegiem
				var spd := base_spd * tmult * lerpf(0.8, 1.0, stamina / 100.0)
				if _in_column:
					# kolumna: na drodze dużo szybciej; czeka na ogon, gdy się rozciągnie
					spd = walk_speed * move_mult() * Terrain.mult_for(battle.terrain.cell_at(center), kind, true)
					spd *= clampf(1.4 - _cohesion / 25.0, 0.55, 1.0)  # tylko lekko czeka na dołączających
					facing = rotate_toward(facing, dir.angle(), 3.0 * dt)
				else:
					# W marszu szyk nie musi być idealny — zwalniamy dopiero, gdy ludzie mocno odstają.
					var wait := clampf(1.25 - _cohesion / 40.0, 0.6, 1.0)
					if _cohesion > 45.0 and _wait_t < 5.0:
						wait = 0.1   # część ludzi została za zboczem/przeszkodą — chwilę czekamy, aż dojdą
						_wait_t += dt
					elif _cohesion < 20.0:
						_wait_t = 0.0
					spd *= wait
				if not _in_column and kind != "art":
					# smycz: środek pułku nie odjeżdża od żołnierzy (np. gdy część utknęła przy górach) —
					# czeka na nich; gdy przez dłuższą chwilę nie da się dojść, pułk staje tam, gdzie są ludzie
					var lead := center.distance_to(centroid())
					var leash := maxf(45.0, formation_depth() + 30.0)
					if lead > leash:
						spd *= clampf(1.0 - (lead - leash) / 30.0, 0.0, 1.0)
						_leash_t += dt
						if _leash_t > 6.0:
							_leash_t = 0.0
							center = centroid()
							move_target = center
							waypoints.clear()
							waypoints.append(center)
							move_facing = facing
							_final_facing = facing
					else:
						_leash_t = maxf(0.0, _leash_t - dt)
				if waypoints.size() <= 1:
					spd = minf(spd, d * 0.6 + 1.5)               # łagodne zatrzymanie
				if kind == "art" and limber_u >= 1.0 and not _in_column:
					# zaprzęgi skręcają łukiem: bateria obraca się w ruchu, zwalniając na zakręcie
					var diff := angle_difference(facing, dir.angle())
					facing = rotate_toward(facing, dir.angle(), 1.3 * dt)
					if d > 40.0:
						spd *= clampf(cos(diff), 0.3, 1.0)
						dir = Vector2.from_angle(facing)
				center += dir * minf(d, spd * dt)
				if _path_trail.is_empty() or center.distance_to(_path_trail[0]) >= 10.0:
					_path_trail.insert(0, center)
					if _path_trail.size() > 250:
						_path_trail.resize(250)
				if _in_column and (_trail.is_empty() or center.distance_to(_trail[0]) >= 3.0):
					_trail.insert(0, center)
					var max_pts := int((_col_rows() * col_gap() + 100.0) / 3.0)
					if _trail.size() > max_pts:
						_trail.resize(max_pts)
			else:
				waypoints.clear()
				_needs_limber = false
				# Na miejscu: rozwinięcie w docelowy szyk (kierunek i szerokość).
				var was_column := _in_column
				_in_column = false
				_set_idle()
				var widen := _pending_files > 0 and _pending_files != base_files
				_apply_pending_files()
				if kind == "art" and not was_column:
					_art_face = move_facing   # bateria obraca się płynnie podczas rozkładania dział
				elif was_column:
					# czoło kolumny staje w środku nowej linii
					set_facing(move_facing)
				elif widen or absf(angle_difference(facing, move_facing)) > 0.05:
					set_facing(move_facing)
		State.CHARGING:
			# do celu prosto; przez rzekę — najpierw na przeprawę (punkty trasy), potem dalej na wroga
			# cel = faktyczni żołnierze wroga (nie jego punkt docelowy, gdy dopiero przechodzi na pozycję)
			var enemy_at := attack_target.centroid()
			var goal := enemy_at
			if not waypoints.is_empty():
				goal = waypoints[0]
				if center.distance_to(goal) < 20.0:
					waypoints.pop_front()
					goal = enemy_at if waypoints.is_empty() else waypoints[0]
			var to := goal - center
			var d := to.length()
			if d > 0.5:
				var diff := absf(angle_difference(facing, to.angle()))
				if diff > 1.2:
					set_facing(to.angle())   # duży zwrot: przestawienie szyku
				elif diff > 0.02:
					# drobne poprawki kursu za ruchomym celem: płynny skręt bez przetasowania jeźdźców
					facing = rotate_toward(facing, to.angle(), (1.2 if kind == "cav" else 0.8) * dt)
				# rozpędzanie: najpierw marsz, potem bieg/galop; zmęczeni biegną wolniej
				var accel := 30.0 if kind == "cav" else 8.0
				var top := run_speed * lerpf(0.6, 1.0, stamina / 100.0)
				if not waypoints.is_empty():
					top = walk_speed * 1.2   # dojście do przeprawy marszem, szarża dopiero na drugim brzegu
				var spd := minf(top, maxf(walk_speed * 0.5, reg_vel.length() / maxf(tmult, 0.1) + accel * dt))
				center += to / d * minf(d, spd * tmult * dt)
			move_facing = facing
		State.MELEE:
			center = center.lerp(centroid(), clampf(dt * 2.0, 0.0, 1.0))
		State.ROUTING:
			center = centroid()
			facing = flee_dir.angle()
			var m := battle.map_size
			if center.x < 20.0 or center.y < 20.0 or center.x > m.x - 20.0 or center.y > m.y - 20.0:
				fled = true
				_die()
	if state == State.MOVING or state == State.CHARGING:
		reg_vel = (center - prev) / maxf(dt, 0.0001)
		if visible:
			_kick_dust(dt)
	else:
		reg_vel = Vector2.ZERO


func _kick_dust(dt: float) -> void:
	## Kurz spod nóg i kopyt: najwięcej na drodze i pustyni, mało na trawie, nic w wodzie i bagnie.
	## Szarżująca jazda wzbija gęsty obłok, maszerująca piechota — delikatny pył przy stopach.
	var spd := reg_vel.length()
	var n := s_pos.size()
	if spd < 6.0 or n == 0 or dt <= 0.0:
		return
	var t := battle.terrain
	var cell := t.cell_at(center)
	var ground := 0.5
	match cell:
		Terrain.ROAD: ground = 2.2
		Terrain.FOREST: ground = 0.25
		Terrain.WATER, Terrain.SWAMP, Terrain.FORD: return
	if float(Terrain.tv("desert")) > 0.5:
		ground *= 2.4
	elif float(Terrain.tv("snow")) > 0.5:
		ground *= 1.2   # pył śnieżny
	elif float(Terrain.tv("mud")) > 0.2:
		ground *= 0.5   # mokra jesień — mało kurzu
	var cav := kind == "cav" or kind == "art"
	var rate := (0.05 if cav else 0.007) * float(n) * minf(spd / 30.0, 2.5) * ground * dt   # oczekiwana liczba kłębów
	var back := -reg_vel / spd
	while rate > 0.0:
		if randf() < rate:
			var i := randi() % n
			var q := s_pos[i] + back * (6.0 if cav else 2.5) + Vector2(randf_range(-2, 2), randf_range(-2, 2))
			if cav:
				battle.effects.add_dust(q, randf_range(2.5, 4.5), randf_range(3.5, 6.0), back * randf_range(4.0, 14.0), 0.32)
			else:
				battle.effects.add_dust(q, randf_range(1.8, 3.0), randf_range(2.0, 3.2), back * randf_range(2.0, 6.0), 0.2)
		rate -= 1.0


func _update_soldiers(dt: float) -> void:
	var n := s_pos.size()
	var files := files_for(n)
	var fire_slots := files * 2 if kind == "inf" else gun_count()
	var in_melee := state == State.MELEE
	var routing := state == State.ROUTING
	var retarget := _retarget
	_retarget = false
	var cohesion_sum := 0.0
	var wet := 0
	var terrain := battle.terrain
	var art_ready := kind == "art" and state == State.IDLE and limber_u <= 0.0
	var rout_speed := run_speed * 1.05
	# Maks. prędkość dochodzenia do miejsca w szyku (spokojny krok, przy szarży szybciej).
	var catch_up := walk_speed * move_mult() * (0.6 if state == State.CHARGING else (1.6 if state == State.MOVING else 1.25))
	if battle.sim_time < _disengage_until:
		catch_up = maxf(catch_up, run_speed * 0.75)
	var column := _in_column and state == State.MOVING
	var col_slots := _column_slots(n) if column else PackedVector2Array()
	# prędkość bloku w "jednostkach bez terenu" (teren pod każdym żołnierzem liczony osobno)
	var base_vel := reg_vel / maxf(Terrain.mult_for(terrain.cell_at(center), kind, column), 0.1)

	# Szybka ścieżka: pułk stoi w gotowym szyku — żołnierze tylko celują, ładują i strzelają.
	var rest_key := Vector3(center.x, center.y, facing)
	if state == State.IDLE and reg_vel == Vector2.ZERO and _cohesion < 0.4 and in_water_ratio == 0.0 			and rest_key == _rest_key and n == _rest_n:
		_update_resting(dt, n, fire_slots, art_ready)
		return
	_rest_key = rest_key
	_rest_n = n
	_mt.resize(8)
	for c in 8:
		_mt[c] = Terrain.mult_for(c, kind, column)
	var fwd := forward()
	var rgt := Vector2(-fwd.y, fwd.x)
	var is_art := kind == "art"
	var nfiles := files_for(n)
	var turn_rate := SOLDIER_TURN * (1.1 if kind == "cav" else 1.0) * dt

	for i in n:
		if s_hp[i] <= 0.0:
			continue
		s_reload[i] -= dt
		s_cool[i] -= dt
		var p := s_pos[i]
		var goal := p
		var spd := run_speed
		var aim := facing
		var free_move := true   # true = idzie samodzielnie do celu; false = trzyma miejsce w szyku
		var accel := SOLDIER_ACCEL * (3.0 if kind == "cav" else 1.0)

		if routing:
			var fd := flee_dir + s_jit[i] * 0.5
			if terrain.is_water(p + fd.normalized() * 24.0) and not terrain.is_water(p):
				# woda tuż przed nim: biegnie wzdłuż brzegu w stronę bliższą kierunkowi ucieczki
				var side := fd.orthogonal()
				fd = side if not terrain.is_water(p + side.normalized() * 24.0) else -side
			goal = p + fd * 40.0
			spd = rout_speed * (1.0 + s_jit[i].x * 0.1)
			aim = flee_dir.angle()
			accel *= 1.5
		elif in_melee:
			accel *= 2.0
			var er: Regiment = s_tgt_reg[i]
			var ei := s_tgt_idx[i]
			var valid := er != null and not er.dead and ei >= 0 and ei < er.s_pos.size() and er.s_hp[ei] > 0.0
			if retarget or not valid:
				_find_melee_target(i)
				er = s_tgt_reg[i]
				ei = s_tgt_idx[i]
				valid = er != null
			if valid:
				var ep := er.s_pos[ei]
				var d := p.distance_to(ep)
				aim = (ep - p).angle()
				var reach := MELEE_REACH + (4.0 if kind == "cav" else 0.0)
				if d > reach:
					goal = ep + (p - ep) / maxf(d, 0.001) * reach * 0.85   # podchodzi na długość broni, nie wchodzi we wroga
					spd = run_speed * 0.8
				elif s_cool[i] <= 0.0:
					# Walka wręcz jest długa: rzadkie ciosy, większość parowana, zwykle 2–3 trafienia do śmierci.
					s_cool[i] = randf_range(2.2, 3.8)
					var dm := er.hit_dir_mult(p)
					# zmęczenie: wyczerpani bronią się i atakują słabiej
					var chance := 0.2 * melee_skill / er.melee_def * dm \
						* lerpf(0.6, 1.0, stamina_f()) / lerpf(0.75, 1.0, er.stamina_f())
					if er.state == State.ROUTING:
						chance *= 2.0
					if randf() < chance:
						er.damage(ei, randf_range(30.0, 60.0))
						er.morale -= (dm - 1.0) * 0.6 / er.discipline
						battle.effects.add_spark((p + ep) * 0.5)
					elif randf() < 0.3:
						battle.effects.add_spark((p + ep) * 0.5)  # parada
			else:
				goal = slot_pos(i, n)
				spd = walk_speed
		else:
			free_move = false
			if column:
				goal = col_slots[i] + (rgt * s_jit[i].x - fwd * s_jit[i].y) * 0.4
			elif is_art or square or wedge:
				goal = slot_pos(i, n)
				if square:
					aim = square_dir(i, n)
			else:
				# inline slot_pos_for (gorąca pętla)
				var rank := i / nfiles
				var in_rank := mini(nfiles, n - rank * nfiles)
				var sx := (float(i % nfiles) - float(in_rank - 1) * 0.5) * spacing + s_jit[i].x
				var sy := float(rank) * rank_spacing + s_jit[i].y
				goal = center + rgt * sx - fwd * sy
			if state == State.IDLE and fire_target != null and (i < fire_slots or square):
				var ta := (fire_target.center - p).angle()
				aim += clampf(angle_difference(aim, ta), -SOLDIER_ARC, SOLDIER_ARC)   # tułów obraca się tylko trochę
				# drobne zamykanie szeregu po stratach nie przerywa ognia — strzela, kto stoi prawie w miejscu
				if s_reload[i] <= 0.0 and s_vel[i].length() < (6.0 if kind == "inf" else 2.0) and to_slot_sq(i, goal) < 64.0:
					if kind == "inf":
						if _may_fire(i):
							_fire(i)
							aim = s_aim[i]
					elif art_ready:
						_fire_cannon(i)

		if s_block[i] > 0.0:
			s_block[i] -= dt
			if not free_move:
				goal = _trail_goal(p)   # obejście zbocza: śladem, którym przeszedł środek pułku
		if _direct and state == State.MOVING and not free_move:
			free_move = true
			cohesion_sum += p.distance_to(goal)
			spd = walk_speed * move_mult() * lerpf(0.85, 1.0, stamina / 100.0)
			if battle.sim_time < _disengage_until:
				spd = maxf(spd, run_speed * 0.75)   # odwrót z walki: biegiem, żeby oderwać się od wroga
		var to := goal - p
		var dist := to.length()
		var desired: Vector2
		var personal := 1.0 + s_jit[i].x * (0.12 if state == State.MOVING else 0.05)
		if free_move:
			desired = Vector2.ZERO if dist < 0.5 else to / dist * minf(spd, dist * 1.5) * personal
		else:
			# Idzie razem z blokiem (ta sama prędkość co oddział) + spokojna korekta do swojego miejsca.
			cohesion_sum += dist
			var corr := to * 0.9
			if corr.length() > catch_up * personal:
				corr = corr.normalized() * catch_up * personal
			desired = base_vel + corr
			if dist < 0.4 and reg_vel == Vector2.ZERO:
				desired = Vector2.ZERO
		# Żołnierz chodzi tylko przodem: najpierw obraca się w kierunku ruchu, potem idzie.
		var heading := s_aim[i]
		var want_speed := desired.length()
		var want_heading := aim
		if want_speed > 1.5:
			want_heading = desired.angle()
		var cav := kind == "cav"
		# koń nie obraca się w miejscu jak bączek: w ruchu skręca łukiem, stojąc obraca się powoli na zadzie
		if cav:
			# koń nie obraca się wokół własnej osi: skręca łukiem o promieniu ~HORSE_R (ω = v / R),
			# a stojąc obraca się tylko powoli, krok po kroku na zadzie
			var omega := clampf(s_vel[i].length() / HORSE_R, HORSE_PIVOT, HORSE_MAX_TURN)
			heading = rotate_toward(heading, want_heading, omega * dt)
		else:
			heading = rotate_toward(heading, want_heading, turn_rate)
		var target_speed := 0.0
		if want_speed > 1.5:
			var align := cos(angle_difference(heading, want_heading))
			if cav:
				# w zakręcie koń idzie dalej naprzód (wolniej) zamiast zawracać w miejscu
				target_speed = want_speed * clampf((align + 0.6) / 1.6, 0.35, 1.0)
			else:
				target_speed = want_speed * clampf((align - 0.3) / 0.7, 0.0, 1.0)
		var speed_now := move_toward(s_vel[i].length(), target_speed, accel * dt)
		var v := Vector2.from_angle(heading) * speed_now
		s_vel[i] = v

		# Teren pod nogami: las spowalnia, woda bardzo spowalnia i topi.
		if speed_now < 0.01 and in_water_ratio == 0.0:
			s_vel[i] = Vector2.ZERO
			s_aim[i] = heading
			continue   # stoi na suchym — teren nie ma znaczenia
		var cell := terrain.cell_at(p)
		# Topi się tylko ten, kto wpadł w głęboki nurt rzeki (np. zepchnięty w walce). Jezioro to płytkie rozlewisko:
		# bardzo wolno, ale bez ofiar — trasy idą prosto, więc nie karzemy śmiercią za przejście przez wodę stojącą.
		if cell == Terrain.WATER and terrain.is_deep_fast(p):
			wet += 1
			# przeprawa wpław jest dozwolona; toną ci, którzy wpadli w nurt w panice albo zepchnięci w zwarciu
			if (routing or in_melee) and randf() < DROWN_RATE * (0.6 if kind == "cav" else 1.0) * dt:
				s_hp[i] = 0.0
				morale -= 1.0
				battle.stats["losses"][team] += 1
				battle.stats["drowned"][team] += 1
				battle.effects.add_splash(p)
		var step := v * _mt[cell] * dt
		var np := p + step
		if _blocked_at(np) and not _blocked_at(p):
			# góry i głęboki nurt nie do przejścia: ślizg wzdłuż przeszkody albo stój (kto już w niej jest, może wyjść)
			if not _blocked_at(p + Vector2(step.x, 0)):
				np = p + Vector2(step.x, 0)
			elif not _blocked_at(p + Vector2(0, step.y)):
				np = p + Vector2(0, step.y)
			else:
				np = p
				s_vel[i] = Vector2.ZERO
			s_block[i] = 1.5
		var hp := battle.house_push(np)
		if hp != Vector2.ZERO:
			np += hp   # budynek: ślizg wzdłuż ściany
		p = np
		s_pos[i] = p
		s_aim[i] = heading

	in_water_ratio = float(wet) / maxf(1.0, n)
	if not in_melee and not routing:
		_cohesion = cohesion_sum / maxf(1.0, n)
	if in_melee or routing or kind == "cav":
		_separate()   # konie nie wchodzą na siebie także w marszu i przy przestawianiu szyku


func _update_resting(dt: float, n: int, fire_slots: int, art_ready: bool) -> void:
	var turn_rate := SOLDIER_TURN * dt
	var has_target := fire_target != null
	for i in n:
		s_reload[i] -= dt
		s_cool[i] -= dt
		var aim := square_dir(i, n) if square else facing
		if has_target and (i < fire_slots or square):
			var ta := (fire_target.center - s_pos[i]).angle()
			aim += clampf(angle_difference(aim, ta), -SOLDIER_ARC, SOLDIER_ARC)   # tułów obraca się tylko trochę
			if s_reload[i] <= 0.0:
				if kind == "inf":
					if _may_fire(i):
						_fire(i)
						aim = s_aim[i]
				elif art_ready:
					_fire_cannon(i)
		s_aim[i] = rotate_toward(s_aim[i], aim, turn_rate)
		s_vel[i] = Vector2.ZERO


func _find_melee_target(i: int) -> void:
	var p := s_pos[i]
	var best_d := INF
	var best_r: Regiment = null
	var best_j := -1
	# ilu naszych już walczy z danym wrogiem — nie rzucamy się całą kupą na jednego (max ~2 na przeciwnika)
	var busy := {}
	for k in s_pos.size():
		if k != i and s_tgt_reg[k] != null:
			var key := Vector2i(s_tgt_reg[k].get_instance_id(), s_tgt_idx[k])
			busy[key] = busy.get(key, 0) + 1
	for e in melee_enemies:
		if e.dead:
			continue
		var arr := e.s_pos
		var eid := e.get_instance_id()
		for j in arr.size():
			if e.s_hp[j] <= 0.0:
				continue
			var d := p.distance_squared_to(arr[j])
			var crowd: int = busy.get(Vector2i(eid, j), 0)
			if crowd >= 2:
				d += 900.0 * crowd    # zajęty przeciwnik: szukaj wolnego obok
			if d < best_d:
				best_d = d
				best_r = e
				best_j = j
	s_tgt_reg[i] = best_r
	s_tgt_idx[i] = best_j


func _separate() -> void:
	var n := s_pos.size()
	var min_d := 12.0 if kind == "cav" else 7.0   # w zwarciu każdy potrzebuje miejsca na zamach bagnetem/szablą
	if kind == "cav" and state != State.MELEE and state != State.ROUTING:
		_separate_horses()
		return
	for i in n:
		for j in range(i + 1, n):
			var dv := s_pos[i] - s_pos[j]
			var d2 := dv.length_squared()
			if d2 < min_d * min_d and d2 > 0.0001:
				var d := sqrt(d2)
				var push := dv / d * (min_d - d) * 0.5
				s_pos[i] += push
				s_pos[j] -= push


func _update_volley() -> void:
	## Oficer czeka, aż większość pierwszych szeregów załaduje, i daje komendę — salwa.
	if kind != "inf" or not officer_alive or state != State.IDLE or fire_target == null:
		_first_loaded = -1.0
		return
	var now := battle.sim_time
	if now - _idle_since < _make_ready:
		return
	if now - _volley_at < VOLLEY_WINDOW:
		return
	var n := s_pos.size()
	var slots := n if square else mini(n, files_for(n) * 2)
	var loaded := 0
	for i in slots:
		if s_hp[i] > 0.0 and s_reload[i] <= 0.0:
			loaded += 1
	if loaded == 0:
		_first_loaded = -1.0
		return
	if _first_loaded < 0.0:
		_first_loaded = now
	if loaded >= ceili(slots * VOLLEY_READY) or now - _first_loaded > VOLLEY_WAIT:
		_volley_at = now
		_first_loaded = -1.0


func _may_fire(i: int) -> bool:
	## Piechota z dowódcą strzela tylko na komendę (każdy z małym opóźnieniem), bez dowódcy — kiedy załaduje.
	if kind != "inf":
		return true
	if battle.sim_time - _idle_since < _make_ready:
		return false   # po zatrzymaniu: "ładuj — gotuj broń — cel!" zanim padnie pierwszy strzał
	if not officer_alive:
		return battle.sim_time - _idle_since > _make_ready + (s_jit[i].x + 1.0) * 1.2   # bez komendy — rozproszone
	var since := battle.sim_time - _volley_at
	return since >= (s_jit[i].x + 1.0) * 0.22 and since < VOLLEY_WINDOW + 0.5


func _separate_horses() -> void:
	## Koń z góry to wydłużony owal (~15 x 6 j.): rozpychamy w układzie konia — mocno w bok, słabiej wzdłuż,
	## żeby szereg i kolumna (głowa za zadem) zostały, a konie nie zachodziły na siebie.
	var n := s_pos.size()
	const HALF_LEN := 7.5
	const HALF_W := 3.4
	for i in n:
		var fi := Vector2.from_angle(s_aim[i])
		var ci := s_pos[i] + fi * 3.0
		for j in range(i + 1, n):
			var cj := s_pos[j] + Vector2.from_angle(s_aim[j]) * 3.0
			var dv := ci - cj
			if dv.length_squared() > 16.0 * 16.0:
				continue
			var along := dv.dot(fi)
			var across := dv.dot(fi.orthogonal())
			var ox := HALF_LEN * 2.0 - absf(along)
			var oy := HALF_W * 2.0 - absf(across)
			if ox > 0.0 and oy > 0.0:
				# rozsuwamy wzdłuż osi o mniejszym nachodzeniu (jak prostokąty)
				var push: Vector2
				if oy < ox:
					push = fi.orthogonal() * signf(across if absf(across) > 0.01 else 1.0) * oy * 0.5
				else:
					push = fi * signf(along if absf(along) > 0.01 else 1.0) * ox * 0.5
				s_pos[i] += push * 0.5
				s_pos[j] -= push * 0.5


func _fire(i: int) -> void:
	var tgt := fire_target
	var m := tgt.s_pos.size()
	if m == 0:
		return
	# Każdy żołnierz celuje tylko w wycinku przed sobą (obrót tułowia z muszkietem ~±35° od frontu szeregu):
	# kilka prób znalezienia wroga w tym wycinku i zasięgu; jeśli nikogo — nie strzela (czeka na lepszy cel).
	var from := s_pos[i]
	var front := square_dir(i, s_pos.size()) if square else facing
	var j := -1
	var tp := Vector2.ZERO
	var dist := 0.0
	var ang := 0.0
	for attempt in 6:
		var c := randi() % m
		if tgt.s_hp[c] <= 0.0:
			continue
		var q := tgt.s_pos[c]
		var dq := from.distance_to(q)
		var aq := (q - from).angle()
		if dq <= fire_range and absf(angle_difference(front, aq)) <= SOLDIER_ARC:
			j = c
			tp = q
			dist = dq
			ang = aq
			break
	if j < 0:
		s_reload[i] = randf_range(0.3, 0.8)
		return
	s_reload[i] = reload_time * randf_range(0.85, 1.3) / discipline / lerpf(0.75, 1.0, stamina_f())
	if not officer_alive:
		s_reload[i] *= randf_range(0.8, 1.5)   # bez komendy każdy ładuje i strzela we własnym rytmie
	var dm := tgt.hit_dir_mult(from)
	var chance := lerpf(0.30, 0.05, dist / fire_range) * accuracy * lerpf(1.0, dm, 0.5) * HIT_COMP  # ogień wzdłuż szeregów
	if battle.terrain.is_forest(tp):
		chance *= 0.55
	elif tgt.kind == "inf" and battle.in_town(tp):
		chance *= 0.6   # piechota za murami i w domach
	if tgt.kind == "cav":
		chance *= 1.25  # koń to duży cel
	if tgt.square:
		chance *= 1.4   # zbity czworobok - łatwy cel
	chance *= 1.0 - tgt.armor   # kirasy zatrzymują część kul
	var hit := randf() < chance
	var muzzle := from + Vector2.from_angle(ang) * 7.0
	var end := tp
	if not hit:
		end = tp + Vector2.from_angle(ang + randf_range(-0.25, 0.25)) * randf_range(5.0, 40.0)
	battle.effects.add_shot(muzzle, end)
	battle.sfx.musket(muzzle)
	Net.record([8, muzzle])
	s_aim[i] = ang
	last_fire_time = battle.sim_time
	tgt.morale -= 0.12 * dm / tgt.discipline
	if hit:
		tgt.damage(j, randf_range(60.0, 130.0))


func _fire_cannon(i: int) -> void:
	## Działo strzela kulą: leci do punktu upadku, potem toczy się i kosi szeregi.
	var tgt := fire_target
	if tgt.s_pos.is_empty():
		return
	var tp := tgt.s_pos[randi() % tgt.s_pos.size()]
	var gun := gun_pos(i)
	var dist := gun.distance_to(tp)
	if dist > fire_range:
		s_reload[i] = 1.0
		return
	if absf(angle_difference(gun_angle(i), (tgt.center - gun).angle())) > 0.12:
		s_reload[i] = 0.25   # działo jeszcze się obraca w stronę celu
		return
	s_reload[i] = reload_time * randf_range(0.9, 1.25) / discipline
	if dist < CANISTER_RANGE:
		_fire_canister(i, gun, tp, dist)
		return
	var spread := dist * 0.06 / accuracy
	var impact := tp + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * spread
	var dir := (impact - gun).normalized()
	battle.spawn_ball(gun + dir * 17.0, impact, team, float(Battle.UNIT_TYPES[unit_key].get("shell", 0.3)), float(Battle.UNIT_TYPES[unit_key].get("power", 1.0)))
	battle.effects.add_cannon_smoke(gun + dir * 17.0, dir)
	battle.sfx.cannon(gun)
	Net.record([9, gun])
	_recoil[i % _recoil.size()] = 1.0
	last_fire_time = battle.sim_time


const CANISTER_RANGE := 260.0


func _fire_canister(i: int, gun: Vector2, tp: Vector2, dist: float) -> void:
	## Kartacze: z bliska działo sieje gradem kulek w stożku — kilka trafień naraz, mocny cios w morale.
	var tgt := fire_target
	var dir := (tp - gun).normalized()
	var cone := 0.16 + dist / CANISTER_RANGE * 0.1
	var hits := 0
	var cover := 0.65 if tgt.kind == "inf" and battle.in_town(tgt.center) else 1.0
	for j in tgt.s_pos.size():
		var q := tgt.s_pos[j]
		var to := q - gun
		if to.length() > dist + 40.0 or absf(angle_difference(dir.angle(), to.angle())) > cone:
			continue
		if randf() < 0.32 * accuracy * lerpf(1.3, 0.7, dist / CANISTER_RANGE) * cover * (1.0 - tgt.armor):
			tgt.damage(j, randf_range(80.0, 160.0))
			hits += 1
			if hits >= 9:
				break
	for k in 6:
		var a := dir.angle() + randf_range(-cone, cone)
		battle.effects.add_shot(gun + dir * 17.0, gun + Vector2.from_angle(a) * (dist + randf_range(-20.0, 30.0)))
	tgt.morale -= 4.0 * tgt.hit_dir_mult(gun) / tgt.discipline
	battle.effects.add_cannon_smoke(gun + dir * 17.0, dir)
	battle.sfx.cannon(gun)
	Net.record([9, gun])
	_recoil[i % _recoil.size()] = 1.0
	last_fire_time = battle.sim_time


func gun_pos(g: int) -> Vector2:
	if _in_column and state == State.MOVING and not s_pos.is_empty():
		var idx := mini(g * 4 + 1, s_pos.size() - 1)
		return s_pos[idx] - Vector2.from_angle(s_aim[idx]) * 6.0
	return art_gun_pos(g, gun_count(), center, facing, spacing)


func surround_count() -> int:
	var c := 0
	for k in 8:
		if surround_mask & (1 << k):
			c += 1
	return c


func is_surrounded() -> bool:
	return surround_count() >= 5


func is_flanked() -> bool:
	return battle.sim_time < flanked_until


func hit_dir_mult(from: Vector2) -> float:
	## Mnożnik skuteczności ataku zależnie od kierunku: przód 1.0, bok 1.5, tył 2.2.
	## Kolumna marszowa jest wrażliwa z każdej strony. Czworobok nie ma flanek.
	if square:
		return 1.0
	var mid := center - forward() * formation_depth() * 0.5
	var rel := absf(angle_difference(facing, (from - mid).angle()))
	var m := 1.0
	if rel > 2.1:
		m = 2.2
	elif rel > 1.1:
		m = 1.5
	if _in_column and state == State.MOVING:
		m = maxf(m, 1.6)
	if m > 1.0:
		flanked_until = battle.sim_time + 3.0
	return m


func _update_surround() -> void:
	## Które z 8 kierunków wokół pułku są zajęte przez (nieuciekające) oddziały wroga.
	surround_mask = 0
	var mid := center - forward() * formation_depth() * 0.5
	var reach := 230.0 + formation_width() * 0.5
	for e in battle.regiments:
		if e.team == team or e.dead or e.state == State.ROUTING:
			continue
		var ew := e.formation_width() * 0.5
		if mid.distance_squared_to(e.center) > (reach + ew) * (reach + ew):
			continue
		var rt := e.forward().orthogonal() * ew
		for pt in [e.center, e.center + rt, e.center - rt, e.center + rt * 0.5, e.center - rt * 0.5]:
			if mid.distance_to(pt) < reach:
				var sec := posmod(roundi((pt - mid).angle() / TAU * 8.0), 8)
				surround_mask |= 1 << sec


func _update_support() -> void:
	## Sąsiedzi w szyku dywizji: pułk ze wsparciem obok trzyma morale, osamotniony się chwieje.
	support = 0
	var my_w := formation_width() * 0.5
	for f in battle.regiments:
		if f == self or f.team != team or f.dead or f.state == State.ROUTING:
			continue
		var reach := 220.0 + my_w + f.formation_width() * 0.5
		if center.distance_squared_to(f.center) < reach * reach:
			support += 1
			if support >= 3:
				return


func _disband(prisoners: bool) -> void:
	## Kapitulacja (okrążony) lub rozproszenie (rozbite resztki).
	var n := s_pos.size()
	battle.stats["losses"][team] += n
	if prisoners:
		battle.stats["prisoners"][1 - team] += n
	if team == 0:
		battle.message(("%s surrendered - %d taken prisoner" if prisoners else "%s has scattered (%d men lost)") % [reg_name, n])
	elif prisoners:
		battle.message("%s surrendered to us! %d prisoners" % [reg_name, n])
	for arr in [s_pos, s_hp, s_reload, s_cool, s_aim, s_vel, s_jit, s_tgt_idx, s_block]:
		arr.resize(0)
	s_tgt_reg.clear()
	_die()


func _surrender_step(dt: float) -> void:
	## Okrążeni uciekinierzy składają broń stopniowo: ~20% stanu na sekundę (od tylnych szeregów).
	var n := s_pos.size()
	if n == 0:
		return
	if not _surrendering:
		_surrendering = true
		if team == 0:
			battle.message("%s is surrounded and laying down arms!" % reg_name)
		else:
			battle.message("%s is surrendering to us!" % reg_name)
	_surrender_acc += dt * maxf(1.5, float(n) * 0.2)
	var k := mini(int(_surrender_acc), n)
	if k <= 0:
		return
	_surrender_acc -= k
	battle.stats["losses"][team] += k
	battle.stats["prisoners"][1 - team] += k
	var left := n - k
	for arr in [s_pos, s_hp, s_reload, s_cool, s_aim, s_vel, s_jit, s_tgt_idx, s_block]:
		arr.resize(left)
	s_tgt_reg.resize(left)
	if left == 0:
		_die()


func damage(j: int, dmg: float) -> void:
	if j < 0 or j >= s_hp.size() or s_hp[j] <= 0.0:
		return
	s_hp[j] -= dmg
	battle.effects.add_hit_blood(s_pos[j], s_hp[j] <= 0.0, kind == "cav")
	if s_hp[j] <= 0.0:
		battle.stats["losses"][team] += 1
		battle.stats["kills"][1 - team] += 1
		morale -= 160.0 / initial_count / discipline
		last_casualty_time = battle.sim_time


func _update_morale(dt: float) -> void:
	var now := battle.sim_time
	var ratio := float(s_pos.size()) / initial_count
	var cap := 35.0 + 65.0 * ratio

	var surrounded := is_surrounded()
	if surrounded and state != State.ROUTING:
		morale -= 2.5 * dt / discipline   # okrążenie: brak drogi odwrotu łamie ducha
	elif surround_count() >= 3 and (surround_mask & _rear_bits()) != 0 and state == State.MELEE:
		morale -= 1.0 * dt / discipline   # wróg na tyłach

	if now - last_casualty_time > 4.0 and in_water_ratio < 0.1 and not surrounded:
		var rate := 2.0 * discipline
		if state == State.ROUTING:
			var e := _nearest_enemy()
			if e == null or e.center.distance_to(center) > 300.0:
				rate = 5.0 * discipline
		else:
			rate *= 1.0 + 0.25 * mini(support, 2)   # wsparcie sąsiadów: szybciej odzyskują ducha
			rate *= 1.0 + battle.aura_at(self)      # Napoleon, marszałek, żandarmeria w pobliżu
			if stamina < 25.0:
				rate *= 0.5                         # wyczerpani dochodzą do siebie wolniej
		morale = minf(morale + rate * dt, maxf(cap, morale))

	# Osamotniona piechota/artyleria pod ogniem lub w zwarciu: bez wsparcia duch słabnie.
	if support == 0 and kind != "cav" and state != State.ROUTING and surround_count() >= 1 \
			and now - last_casualty_time < 6.0:
		morale -= 0.5 * dt / discipline

	if in_water_ratio > 0.3:
		morale -= 1.2 * dt / discipline

	if state == State.MELEE:
		var enemy_n := 0
		for e in melee_enemies:
			enemy_n += e.s_pos.size()
		var r := float(enemy_n) / maxf(1.0, s_pos.size())
		if r > 1.3:
			morale -= (r - 1.0) * 1.2 * dt / discipline
	morale = clampf(morale, 0.0, 100.0)

	var break_at := 30.0 if stamina < 20.0 else 22.0   # wyczerpani pękają szybciej
	var min_ratio := 0.2
	if Battle.UNIT_TYPES[unit_key].get("steadfast", false):
		break_at = 6.0      # Grenadierzy Pieszy Gwardii: "Gwardia umiera, ale się nie poddaje"
		min_ratio = 0.3
	if state != State.ROUTING and (morale < break_at or ratio < min_ratio):
		_start_rout()
	elif state == State.ROUTING:
		var e := _nearest_enemy()
		var ed := INF if e == null else e.distance_to_soldiers(center)
		if surrounded and ed < 160.0:
			_surrender_step(dt)   # nie ma dokąd uciec — ludzie poddają się grupkami, nie cały pułk w jednej chwili
			return
		if ratio < 0.2 and now - _rout_since > 12.0 and ed > 400.0:
			_disband(false)  # resztki rozbitego pułku rozchodzą się do domów
			return
		if morale > 55.0 and ratio >= 0.25:
			_try_rally(e)


func _rear_bits() -> int:
	## Bity sektorów za plecami pułku (3 z 8).
	var back := posmod(roundi((facing + PI) / TAU * 8.0), 8)
	return (1 << back) | (1 << posmod(back + 1, 8)) | (1 << posmod(back - 1, 8))


func _try_rally(e: Regiment) -> void:
	if e == null or e.center.distance_to(center) > 300.0:
		_set_idle()
		center = centroid()
		move_facing = (e.center - center).angle() if e != null else facing
		facing = move_facing
		move_target = center


func _start_rout() -> void:
	state = State.ROUTING
	_rout_since = battle.sim_time
	_in_column = false
	waypoints.clear()
	attack_target = null
	fire_target = null
	_update_flee()
	# Panika udziela się sąsiednim pułkom.
	for f in battle.regiments:
		if f != self and f.team == team and not f.dead and f.center.distance_to(center) < 260.0:
			f.morale -= 6.0 / f.discipline


# ------------------------------------------------------------------ rysowanie

func on_screen(view: Rect2) -> bool:
	return view.grow(formation_width() + formation_depth() + 60.0).has_point(center)


func _draw() -> void:
	if _bake:
		_draw_bake()
		return
	var n := s_pos.size()
	if n == 0:
		return
	var body := color
	var dark := color.darkened(0.6)
	var fwd := forward()
	var right := fwd.rotated(PI * 0.5)

	var show_all := battle.show_all
	if (selected or show_all) and _in_column and state == State.MOVING:
		# kolumna marszowa: poświata pod każdym żołnierzem
		var oc2 := Color(1, 1, 0.6, 0.45) if selected else (Color(0.6, 0.8, 1, 0.35) if team == 0 else Color(1, 0.5, 0.45, 0.35))
		var rr := 7.0 if kind == "cav" else 4.6
		for p in s_pos:
			draw_circle(p, rr, oc2)
	elif (selected or show_all) and state != State.ROUTING and state != State.MELEE and not _direct:
		var hw := formation_width() * 0.5 + 6.0
		var front := 14.0 if kind == "art" else 6.0
		var back := formation_depth() + 6.0
		if square:
			front = hw
			back = hw
		var pts := PackedVector2Array([
			center - right * hw + fwd * front,
			center + right * hw + fwd * front,
			center + right * hw - fwd * back,
			center - right * hw - fwd * back,
			center - right * hw + fwd * front,
		])
		var oc := Color(1, 1, 0.7, 0.8) if selected else (Color(0.6, 0.8, 1, 0.6) if team == 0 else Color(1, 0.5, 0.45, 0.6))
		draw_colored_polygon(pts, Color(oc, 0.12))
		draw_polyline(pts, oc, 1.4 if selected else 1.0)
	if selected and fire_range > 0.0 and state != State.ROUTING:
		_draw_range(fwd)

	var tex: Texture2D = sprite_tex.get(sprite_key())
	if tex != null:
		# szybka ścieżka: cały pułk jednym poleceniem (MultiMesh z wypalonym sprite'em żołnierza)
		if kind == "art":
			_draw_artillery(n, body, dark, false)
		_draw_sprites(tex)
	else:
		match kind:
			"cav":
				_draw_cavalry(n, body, dark)
			"art":
				_draw_artillery(n, body, dark)
			_:
				_draw_infantry(n, body, dark)

	# Chorąży ze sztandarem za szykiem: prawdziwy żołnierz tego pułku z drzewcem i flagą w barwach narodowych.
	if state != State.ROUTING and kind != "art" and n > 0:
		var fp := anchor() - fwd * (formation_depth() + rank_spacing * 1.3) if state != State.MELEE else centroid()
		_draw_standard(fp, tex)


func _draw_standard(fp: Vector2, tex: Texture2D) -> void:
	var S := SPRITE_WORLD
	var cav := kind == "cav"
	if tex != null:
		draw_set_transform(fp, facing, Vector2(1.0, -1.0))   # sprite odwrócony w osi Y (QuadMesh)
		draw_texture_rect(tex, Rect2(-S * 0.5, -S * 0.5, S, S), false)
		draw_set_transform(Vector2.ZERO)
	if _flag_down > 0.0:
		# chorąży padł: sztandar leży na ziemi, aż ktoś go podniesie
		var d := Vector2.from_angle(facing + 2.2)
		draw_line(fp, fp + d * 13.0, Color(0.25, 0.17, 0.09), 1.0)
		_flag_cloth_wind(fp + d * 12.0, d, 7.0, 5.0, 0.0)   # płachta leży płasko na ziemi
		return
	# Sztandar jak w menu: pikselowa flaga narodowa (proporcje 2:1) falująca kratka po kratce,
	# na pionowym drzewcu nad chorążym, z grotem/orłem na szczycie.
	var fwd := forward()
	var hand := fp + fwd * 1.0 + fwd.orthogonal() * 1.2
	var plen := 13.0 if cav else 15.0
	var top := hand + Vector2(0.0, -plen)
	draw_line(hand + Vector2(0.6, 0.8), top + Vector2(0.6, 0.8), Color(0, 0, 0, 0.22), 0.9)   # cień
	draw_line(hand, top, Color(0.16, 0.10, 0.05), 0.9)
	var nat := Battle.nation(team)
	if nat == 0:
		draw_rect(Rect2(top + Vector2(-1.2, -2.0), Vector2(2.4, 1.8)), Color(0.92, 0.75, 0.28))   # orzeł
	else:
		draw_rect(Rect2(top + Vector2(-0.5, -1.8), Vector2(1.0, 1.8)), Color(0.86, 0.82, 0.62))   # grot
	var w := 9.0 if cav else 11.0
	_pixel_standard(top + Vector2(0.45, 0.2), w, w * 0.5, battle.sim_time * 2.6 + float(net_id) * 0.9, nat, cav)


func _pixel_standard(o: Vector2, w: float, h: float, t: float, nat: int, swallow: bool) -> void:
	## Kratki ułożone równo (piksele), fala przesuwa kolumny o całe kratki, cieniowanie progowe.
	const C := 16
	const R := 8
	var cw := w / C
	var ch := h / R
	for c in C:
		var u := (c + 0.5) / C
		var ph := t - u * 7.0
		var dy := roundf(sin(ph) * 1.4 * u / ch) * ch
		var shade := 1.0 + roundf(cos(ph) * u * 2.0) * 0.08
		for r in R:
			var v := (r + 0.5) / R
			if swallow and c >= C - 4 and absf(v - 0.5) < 0.09 * float(c - C + 5):
				continue   # jaskółczy ogon proporca jazdy
			var col := _flag_color(nat, u, v)
			draw_rect(Rect2(Vector2(o.x + c * cw, o.y + r * ch + dy), Vector2(cw + 0.05, ch + 0.05)), Color(col * shade, 1.0))


func _flag_cloth_wind(top: Vector2, wind: Vector2, w: float, h: float, t: float) -> void:
	## Płachta jako siatka: krawędź przy drzewcu nieruchoma, wolny koniec faluje mocniej i lekko opada.
	var nat := Battle.nation(team)
	const C := 9
	const R := 6
	var down := Vector2.DOWN
	var across := wind.orthogonal()
	var verts := PackedVector2Array()
	verts.resize((C + 1) * (R + 1))
	for c in C + 1:
		var u := float(c) / C
		var ripple := sin(t - u * 5.0) * 1.1 * u
		for r in R + 1:
			var v := float(r) / R
			verts[c * (R + 1) + r] = top + wind * (u * w) + down * (v * h + u * u * 0.9) + across * ripple * (0.6 + 0.4 * v)
	var fringe := Color(0.93, 0.76, 0.28)
	for c in C:
		var u := (c + 0.5) / C
		var slope := cos(t - u * 5.0) * u
		var shade := 1.0 + clampf(roundf(slope * 2.0) * 0.1, -0.22, 0.16)   # progi jasności (pixel-art)
		for r in R:
			var v := (r + 0.5) / R
			var col := _flag_color(nat, u, v)
			if c == C - 1 and nat == 0:
				col = fringe if r % 2 == 0 else fringe.darkened(0.2)
			var i0 := c * (R + 1) + r
			var quad := PackedVector2Array([verts[i0], verts[i0 + R + 1], verts[i0 + R + 2], verts[i0 + 1]])
			var qc := Color(col * shade, 1.0)
			draw_primitive(quad, PackedColorArray([qc, qc, qc, qc]), PackedVector2Array())   # bez triangulacji (zgniecione fałdy nie sypią błędami)
	# delikatnie ciemniejsza krawędź przy drzewcu (cień fałdy), bez ramki dookoła
	draw_line(verts[0], verts[R], Color(0, 0, 0, 0.25), 0.5)


const EAGLE := [
	"X.X.........X.X",
	"XXX...XX....XXX",
	".XXX.XXX...XXX.",
	".XXXXXXXX.XXXX.",
	"..XXXXXXXXXXX..",
	"...XXXXXXXXX...",
	"....XXXXXXX....",
	".....XXXXX.....",
	"......XXX......",
	".....XXXXX.....",
	"....X.XXX.X....",
	"...X..X.X..X...",
	"......X.X......",
]


static func _eagle_at(u: float, v: float) -> bool:
	## Pikselowy orzeł heraldyczny (15x13) na środku płachty: u 0.30-0.70, v 0.10-0.90.
	var ex := (u - 0.30) / 0.40
	var ey := (v - 0.10) / 0.80
	if ex < 0.0 or ex >= 1.0 or ey < 0.0 or ey >= 1.0:
		return false
	var row: String = EAGLE[int(ey * EAGLE.size())]
	return row[int(ex * row.length())] == "X"


static func _union_flag(u: float, v: float) -> Color:
	## Union Flag: niebieskie pole, biały skośny krzyż (św. Andrzeja), na nim przesunięty czerwony (św. Patryka)
	## — w każdym ramieniu po lewej stronie patrząc od środka ku narożnikowi ("wiatraczek") — oraz czerwony
	## krzyż św. Jerzego z białym obramowaniem. Wymiary wg wzoru 60 x 30.
	const RED := Color(0.78, 0.07, 0.12)
	const WHITE := Color(0.96, 0.96, 0.95)
	const BLUE := Color(0.0, 0.14, 0.42)
	var x := u * 60.0
	var y := v * 30.0
	if absf(x - 30.0) < 3.0 or absf(y - 15.0) < 3.0:
		return RED
	if absf(x - 30.0) < 5.0 or absf(y - 15.0) < 5.0:
		return WHITE
	const L := 67.082   # sqrt(60^2 + 30^2)
	var d1 := (x * 30.0 - y * 60.0) / L            # przekątna lewy-górny → prawy-dolny (ujemne = pod nią)
	var d2 := (x * 30.0 + y * 60.0 - 1800.0) / L   # przekątna lewy-dolny → prawy-górny (dodatnie = pod nią)
	if absf(d1) < 3.0:
		if (x < 30.0 and d1 > -2.0 and d1 < 0.0) or (x >= 30.0 and d1 > 0.0 and d1 < 2.0):
			return RED
		return WHITE
	if absf(d2) < 3.0:
		if (x >= 30.0 and d2 > -2.0 and d2 < 0.0) or (x < 30.0 and d2 > 0.0 and d2 < 2.0):
			return RED
		return WHITE
	return BLUE


static func _flag_color(nat: int, u: float, v: float) -> Color:
	match nat:
		0:   # Francja: trójkolor pionowy
			return Color(0.12, 0.2, 0.62) if u < 0.34 else (Color(0.95, 0.95, 0.92) if u < 0.67 else Color(0.82, 0.12, 0.12))
		1:   # Wielka Brytania: Union Flag z 1801 r. (proporcje 60x30)
			return _union_flag(u, v)
		2:   # Austria: barwy habsburskie z 1804 r. — czarny nad żółtym
			return Color(0.06, 0.06, 0.06) if v < 0.5 else Color(0.98, 0.80, 0.10)
		3:   # Rosja: biało-niebiesko-czerwona (poziomo)
			if v < 1.0 / 3.0:
				return Color(0.97, 0.97, 0.96)
			return Color(0.05, 0.22, 0.62) if v < 2.0 / 3.0 else Color(0.80, 0.10, 0.12)
		_:   # Prusy: biała z czarnym orłem o rozpostartych skrzydłach
			return Color(0.06, 0.06, 0.06) if _eagle_at(u, v) else Color(0.97, 0.97, 0.95)


func _draw_range(fwd: Vector2) -> void:
	## Pole ostrzału zaznaczonego pułku: suma stożków ognia wszystkich żołnierzy — od całej szerokości frontu
	## rozchodzi się na boki pod kątem ostrzału pojedynczego strzelca. Ciepły gradient (mocniejszy przy pułku),
	## cienka złota obwódka i linia skutecznego dystansu. W czworoboku — pełne koło.
	var cam := get_viewport().get_camera_2d()
	var z := maxf(cam.zoom.x if cam else 1.0, 0.05)
	var lw := 1.5 / z
	var fill := Color(0.86, 0.42, 0.14)
	var edge := Color(1.0, 0.82, 0.38)
	var R := fire_range
	if square:
		for k in 5:
			draw_circle(center, R * (0.2 + 0.2 * k), Color(fill, 0.055))
		draw_arc(center, R, 0.0, TAU, 64, Color(edge, 0.6), lw)
		draw_arc(center, R * 0.5, 0.0, TAU, 48, Color(edge, 0.25), lw * 0.7)
		return
	var right := fwd.orthogonal() * -1.0
	var hw := formation_width() * 0.5
	var arc := 0.32 if kind == "art" else SOLDIER_ARC
	var front := center + fwd * (14.0 if kind == "art" else 4.0)
	var L := front - right * hw
	var Rr := front + right * hw
	var bands := 6
	for k in range(bands, 0, -1):
		draw_colored_polygon(_range_shape(L, Rr, fwd, arc, R * float(k) / bands), Color(fill, 0.05 + 0.012 * (bands - k)))
	var outline := _range_shape(L, Rr, fwd, arc, R)
	outline.append(outline[0])
	draw_polyline(outline, Color(edge, 0.7), lw)
	var mid := _range_shape(L, Rr, fwd, arc, R * 0.5)
	draw_polyline(mid.slice(1, mid.size() - 1), Color(edge, 0.3), lw * 0.7)


static func _range_shape(L: Vector2, Rr: Vector2, fwd: Vector2, arc: float, r: float) -> PackedVector2Array:
	## Otoczka stożków ognia z odcinka frontu L–Rr: lewy łuk wokół L, prosta krawędź, prawy łuk wokół Rr.
	var pts := PackedVector2Array([L])
	var a0 := fwd.angle()
	var n := 10
	# Godot: oś y w dół, więc "lewo" frontu to obrót o -arc
	var lsign := 1.0 if (Rr - L).cross(fwd) > 0.0 else -1.0
	for k in n + 1:
		pts.append(L + Vector2.from_angle(a0 + lsign * arc * (1.0 - float(k) / n)) * r)
	for k in n + 1:
		pts.append(Rr + Vector2.from_angle(a0 - lsign * arc * float(k) / n) * r)
	pts.append(Rr)
	return pts


# ------------------------------------------------------------------ mundury (widok z góry)

const DETAIL_ZOOM := 1.1        # od tego zbliżenia żołnierze mają mundury; dalej proste kropki
const BLACK_HAT := Color(0.08, 0.08, 0.09)
const FUR := Color(0.13, 0.10, 0.08)
const BRASS := Color(0.85, 0.68, 0.28)
const STEEL := Color(0.78, 0.80, 0.86)
const WHITE_BELT := Color(0.93, 0.92, 0.86)

var _style := {}


func _uniform() -> Dictionary:
	## Wygląd munduru danego typu i strony: płaszcz, wyłogi, nakrycie głowy, pióropusz, oporządzenie.
	if not _style.is_empty():
		return _style
	var nat := Battle.nation(team)
	var fr := nat == 0
	var coat: Color = Battle.NATION_COATS[nat]
	var st := {"coat": coat, "facing": Battle.NATION_FACINGS[nat], "hat": "shako",
		"hat_col": BLACK_HAT, "plume": Color(0, 0, 0, 0), "belts": true, "pack": true, "civil": false, "big": 1.0}
	if nat == 2 and kind == "inf":
		st["hat"] = "helmet"            # austriacki skórzany kask z grzebieniem
		st["hat_col"] = Color(0.12, 0.1, 0.08)
	match base_key:
		"line":
			st["plume"] = Color(0.95, 0.95, 0.95) if fr else Color(0.95, 0.95, 0.9)
		"light":
			st["plume"] = Color(0.3, 0.75, 0.25) if fr else Color(0.25, 0.55, 0.2)
			st["facing"] = Color(0.95, 0.85, 0.3) if fr else Color(0.25, 0.55, 0.2)
		"rifles":
			if fr:
				st["plume"] = Color(0.95, 0.85, 0.2)
				st["facing"] = Color(0.95, 0.85, 0.2)
			else:
				st["coat"] = Color(0.13, 0.30, 0.16).lerp(coat, 0.12)   # zielone kurtki strzelców
				st["facing"] = Color(0.08, 0.08, 0.08)
				st["plume"] = Color(0.05, 0.05, 0.05)
			st["belts"] = false
		"grenadier":
			st["hat"] = "bearskin"
			st["hat_col"] = FUR
			st["plume"] = Color(0.9, 0.1, 0.1) if fr else Color(0.95, 0.95, 0.95)
		"guard":
			st["hat"] = "bearskin"
			st["hat_col"] = FUR
			st["big"] = 1.2
			st["coat"] = coat.darkened(0.2)
			st["plume"] = Color(0.9, 0.1, 0.1) if fr else Color(0.95, 0.95, 0.95)
			st["facing"] = Color(0.98, 0.98, 0.98)
		"militia":
			st["hat"] = "bicorne" if fr else "round"
			st["civil"] = true
			st["pack"] = false
		"hussars":
			st["hat"] = "busby"
			st["hat_col"] = FUR
			st["plume"] = Color(0.95, 0.85, 0.3) if fr else Color(0.95, 0.95, 0.95)
			st["coat"] = coat.lightened(0.15)
			st["facing"] = Color(0.98, 0.9, 0.5)          # szamerowanie
		"dragoons":
			st["hat"] = "helmet"
			st["hat_col"] = BRASS if fr else BLACK_HAT     # francuski mosiężny / brytyjski tarleton
			st["plume"] = Color(0.08, 0.06, 0.05)
		"cuirassiers":
			st["hat"] = "helmet"
			st["hat_col"] = STEEL
			st["plume"] = Color(0.08, 0.06, 0.05)
			st["cuirass"] = true
		"lancers":
			st["hat"] = "czapka"
			st["hat_col"] = coat.darkened(0.3) if not fr else Color(0.85, 0.15, 0.12)
			st["plume"] = Color(0.95, 0.95, 0.95)
		"artillery", "horse_art":
			st["coat"] = coat.darkened(0.3)
			st["plume"] = Color(0.85, 0.15, 0.12)
			st["pack"] = false
			st["belts"] = false
			if base_key == "horse_art":
				st["hat"] = "busby" if fr else "helmet"
				st["hat_col"] = FUR if fr else BLACK_HAT
	# --- oddziały unikalne nacji
	match unit_key:
		"grenzer":
			st["coat"] = Color(0.42, 0.30, 0.19)          # brązowe kurtki pograniczników
			st["facing"] = Color(0.75, 0.15, 0.15)
			st["hat"] = "shako"
			st["plume"] = Color(0.25, 0.45, 0.2)
			st["belts"] = false
		"hun_grenadier":
			st["hat"] = "bearskin"
			st["hat_col"] = FUR
			st["facing"] = Color(0.2, 0.3, 0.7)
			st["plume"] = Color(0.95, 0.85, 0.3)
		"uhlans":
			st["coat"] = Color(0.18, 0.34, 0.22)
			st["hat"] = "czapka"
			st["hat_col"] = Color(0.95, 0.8, 0.2)
			st["facing"] = Color(0.9, 0.15, 0.15)
		"opolchenie":
			st["coat"] = Color(0.45, 0.42, 0.37)          # szare kaftany pospolitego ruszenia
			st["hat"] = "round"
			st["hat_col"] = Color(0.3, 0.27, 0.22)
			st["civil"] = true
			st["pack"] = false
			st["belts"] = false
			st["plume"] = Color(0, 0, 0, 0)
		"pavlov":
			st["hat"] = "bearskin"                        # mitra z mosiężną blachą
			st["hat_col"] = Color(0.82, 0.66, 0.26)
			st["plume"] = Color(0.8, 0.12, 0.12)
			st["big"] = 1.2
		"cossacks":
			st["coat"] = Color(0.14, 0.17, 0.36)
			st["hat"] = "busby"                           # futrzany kołpak
			st["hat_col"] = Color(0.12, 0.1, 0.09)
			st["plume"] = Color(0.8, 0.12, 0.12)
			st["facing"] = Color(0.8, 0.12, 0.12)
			st["civil"] = true
			st["belts"] = false
		"unicorns":
			st["coat"] = Color(0.10, 0.22, 0.14)
			st["plume"] = Color(0.1, 0.1, 0.1)
		"landwehr":
			st["coat"] = Color(0.12, 0.12, 0.2)
			st["hat"] = "round"                           # miękka czapka Landwehry
			st["hat_col"] = Color(0.12, 0.12, 0.2)
			st["facing"] = Color(0.85, 0.2, 0.18)
			st["civil"] = false
			st["pack"] = false
		"fusiliers":
			st["belts"] = false
			st["facing"] = Color(0.1, 0.1, 0.1)
			st["plume"] = Color(0.1, 0.1, 0.1)
		"black_hussars":
			st["coat"] = Color(0.08, 0.08, 0.09)          # czarne dolmany, srebrne szamerowanie, trupia główka
			st["facing"] = Color(0.85, 0.85, 0.88)
			st["hat"] = "busby"
			st["hat_col"] = Color(0.06, 0.06, 0.07)
			st["plume"] = Color(0.92, 0.92, 0.92)
		"garde_pr":
			st["big"] = 1.15
			st["facing"] = Color(0.95, 0.95, 0.95)
			st["plume"] = Color(0.95, 0.95, 0.95)
	# --- wygląd jednostek z arkusza Francji (klucz "look" w UNIT_TYPES)
	var look: Dictionary = Battle.UNIT_TYPES[unit_key].get("look", {})
	for k in look:
		st[k] = look[k]
	# --- historyczne mundury (data/uniforms.json): nakładane na końcu — realizm ważniejszy niż barwa strony
	var hist := _uniforms_db().get(unit_key, {}) as Dictionary
	for src in [hist.get("look", {}), (hist.get("look_by_nation", {}) as Dictionary).get(Battle.NATION_DIRS[nat], {})]:
		for k in src:
			var v = src[k]
			if v is Array:
				v = Color(v[0], v[1], v[2], v[3] if v.size() > 3 else 1.0)
			st[k] = v
	_style = st
	return st


static var _udb: Dictionary = {}


static func _uniforms_db() -> Dictionary:
	if _udb.is_empty():
		var f := FileAccess.open("res://data/uniforms.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			_udb = parsed if parsed is Dictionary else {"_": {}}
		else:
			_udb = {"_": {}}
	return _udb


func _figure(p: Vector2, dir: Vector2, st: Dictionary, jit: Vector2, sc := 1.0) -> void:
	## Żołnierz z góry: plecak, ramiona w kolorze płaszcza, pasy, kołnierz, nakrycie głowy z pióropuszem.
	var side := dir.orthogonal()
	var coat: Color = st["coat"]
	if st["civil"]:
		# milicja: każdy w czym innym
		coat = coat.lerp([Color(0.42, 0.32, 0.22), Color(0.35, 0.36, 0.38), Color(0.5, 0.45, 0.35)][int((jit.x + 1.0) * 7.3) % 3], 0.45)
	var outline := coat.darkened(0.6)
	var sleeve := coat.darkened(0.12)
	var skin := Color(0.86, 0.68, 0.52)
	var ls := p - side * 1.55 * sc     # lewy bark
	var rs := p + side * 1.55 * sc     # prawy bark
	if st["pack"]:
		# tornister z kocem na wierzchu
		draw_line(p - dir * 1.9 * sc - side * 1.15 * sc, p - dir * 1.9 * sc + side * 1.15 * sc, Color(0.30, 0.22, 0.14), 1.6 * sc)
		draw_line(p - dir * 1.3 * sc - side * 1.2 * sc, p - dir * 1.3 * sc + side * 1.2 * sc, Color(0.55, 0.5, 0.45), 0.6 * sc)
	# ręce wysunięte do przodu (trzymają broń / wodze) — pod tułowiem
	var lh := p + side * 0.5 * sc + dir * 2.5 * sc
	var rh := p + side * 1.45 * sc + dir * 2.0 * sc
	draw_line(ls, lh, outline, 1.3 * sc)
	draw_line(rs, rh, outline, 1.3 * sc)
	draw_line(ls, lh, sleeve, 0.85 * sc)
	draw_line(rs, rh, sleeve, 0.85 * sc)
	draw_circle(lh, 0.5 * sc, skin)
	draw_circle(rh, 0.5 * sc, skin)
	# tułów z góry: zaokrąglone barki (kapsuła) z obrysem
	draw_circle(ls, 1.3 * sc, outline)
	draw_circle(rs, 1.3 * sc, outline)
	draw_line(ls, rs, outline, 2.6 * sc)
	draw_circle(ls, 0.92 * sc, coat)
	draw_circle(rs, 0.92 * sc, coat)
	draw_line(ls, rs, coat, 1.85 * sc)
	if st.get("cuirass", false):
		draw_line(p - side * 1.2 * sc, p + side * 1.2 * sc, st.get("cuirass_col", STEEL), 1.6 * sc)
		draw_line(p - side * 0.9 * sc + dir * 0.3 * sc, p + side * 0.9 * sc + dir * 0.3 * sc, Color(1, 1, 1, 0.5), 0.4 * sc)
	elif st["belts"]:
		var belt: Color = st.get("belt_col", WHITE_BELT)   # białe, płowe (buff) albo czarne pasy
		draw_line(ls + dir * 0.4 * sc, rs - dir * 0.7 * sc, belt, 0.45 * sc)
		draw_line(rs + dir * 0.4 * sc, ls - dir * 0.7 * sc, belt, 0.45 * sc)
	# epolety w kolorze wyłogów
	draw_circle(ls, 0.5 * sc, st["facing"])
	draw_circle(rs, 0.5 * sc, st["facing"])
	var hc: Color = st["hat_col"]
	var plume: Color = st["plume"]
	var big: float = st["big"]
	match st["hat"]:
		"bearskin":
			draw_circle(p, 1.75 * big * sc, hc)
			draw_circle(p + dir * 0.3 * sc, 1.15 * big * sc, hc.lightened(0.12))
			draw_circle(p - side * 1.2 * sc, 0.5 * sc, plume)
		"bicorne":
			draw_line(p - side * 2.0 * sc, p + side * 2.0 * sc, hc, 1.4 * sc)
			if plume.a > 0.0:
				draw_line(p - side * 1.4 * sc, p + side * 1.4 * sc, plume, 0.5 * sc)   # obszycie / pióra
			draw_circle(p, 0.95 * sc, Color(0.85, 0.7, 0.55))
			draw_circle(p + side * 1.1 * sc, 0.5 * sc, Color(0.85, 0.15, 0.12))
		"round":
			var rc: Color = st.get("round_col", Color(0.22, 0.17, 0.12))   # kapelusz okrągły / turban
			draw_circle(p, 1.55 * sc, rc)
			draw_circle(p, 0.9 * sc, rc.lightened(0.12))
		"busby":
			draw_circle(p, 1.5 * sc, hc)
			draw_line(p, p - side * 1.7 * sc - dir * 0.6 * sc, coat, 0.8 * sc)
			draw_circle(p + dir * 0.4 * sc, 0.45 * sc, plume)
		"helmet":
			draw_circle(p, 1.4 * sc, hc)
			draw_line(p - dir * 2.2 * sc, p + dir * 0.6 * sc, plume, 0.8 * sc)
		"czapka":
			var a := (dir + side) * 0.9 * sc
			var b := (dir - side) * 0.9 * sc
			draw_colored_polygon(PackedVector2Array([p + a, p + b, p - a, p - b]), hc)
			draw_circle(p - side * 0.9 * sc, 0.5 * sc, plume)
		_:
			draw_circle(p + dir * 0.35 * sc, 1.3 * sc, hc)                           # daszek
			draw_circle(p, 1.15 * sc, hc.lightened(0.08))
			draw_circle(p + dir * 0.15 * sc, 0.5 * sc, plume if plume.a > 0.0 else hc.lightened(0.3))


# ------------------------------------------------------------------ sprite'y (wypalane raz, rysowane MultiMeshem)

const SPRITE_WORLD := 34.0          # bok kwadratu sprite'a w jednostkach świata (mieści lancę i ogon konia)
static var sprite_tex := {}         # "key/team" -> Texture2D
static var _quad_mesh: QuadMesh
var _bake := false                  # tryb wypalania: rysuje jednego żołnierza w (0,0) twarzą w prawo
var _mm: MultiMesh
var _mm_buf := PackedFloat32Array()


func sprite_key() -> String:
	return "%s/%d" % [unit_key, Battle.nation(team)]


const ART_WORLD := 72.0   # bok sprite'a działa / zaprzęgu w jednostkach świata


func _team_off(pairs: int) -> float:
	## Środek sprite'a zaprzęgu względem zaczepu przodka (wzdłuż kierunku jazdy).
	return (-6.5 + 15.0 + float(pairs - 1) * 12.0 + 10.0) * 0.5


func _art_pairs() -> int:
	return Battle.UNIT_TYPES[unit_key].get("gun", {}).get("pairs", 3 if base_key == "horse_art" else 2)


func _set_art_wood() -> void:
	var fr_wood := Battle.nation(team) == 0
	_wood = Color(0.33, 0.36, 0.20) if fr_wood else LIMBER_WOOD          # francuskie lawety: oliwkowe
	_wood_dark = Color(0.19, 0.21, 0.11) if fr_wood else LIMBER_DARK


func _blit(tex: Texture2D, p: Vector2, ang: float, alpha := 1.0) -> void:
	## Pikselowy sprite działa/zaprzęgu (wypalony twarzą w prawo, odwrócony w osi Y jak dla QuadMesh).
	draw_set_transform(p, ang, Vector2(1.0, -1.0))
	draw_texture_rect(tex, Rect2(-ART_WORLD * 0.5, -ART_WORLD * 0.5, ART_WORLD, ART_WORLD), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO)


func _draw_bake() -> void:
	var st := _uniform()
	var j := Vector2(0.15, 0.05)
	if bake_pose >= 10:
		_set_art_wood()
		match bake_pose:
			10: _draw_gun(Vector2.ZERO, Vector2.RIGHT)
			11, 12: _draw_team(Vector2(-_team_off(_art_pairs()), 0.0), Vector2.RIGHT, _art_pairs(), bake_pose - 11, st)
			13: _horse_top(Vector2(-0.5, 0.0), Vector2.RIGHT, HORSE_COLORS[0])
		return
	match kind:
		"cav":
			_cav_one(Vector2.ZERO, Vector2.RIGHT, j, 0.0, st)
		"art":
			draw_circle(Vector2(0.6, 0.8), 2.4, Color(0, 0, 0, 0.22))
			_figure(Vector2.ZERO, Vector2.RIGHT, st, j, 0.9)
		_:
			_inf_one(Vector2.ZERO, Vector2.RIGHT, st, j)


func _draw_sprites(tex: Texture2D) -> void:
	## Cały pułk kilkoma draw_multimesh: każdy żołnierz = obrócony kwadrat z teksturą, lekko zróżnicowany odcieniem.
	## Piechota ma 3 pozy: gotowy do strzału, ładowanie (muszkiet pionowo, stempel w lufie), ubijanie (stempel w górze).
	var n := s_pos.size()
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1, 1)
	var texs: Array = [tex, tex, tex, tex]
	var inf := kind == "inf"
	if inf:
		texs[1] = sprite_tex.get(sprite_key() + "#r1", tex)
		texs[2] = sprite_tex.get(sprite_key() + "#r2", tex)
		texs[3] = sprite_tex.get(sprite_key() + "#sh", tex)
	var groups: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var t := battle.sim_time
	for i in n:
		groups[_reload_pose(i, t) if inf else 0].append(i)
	var S := SPRITE_WORLD
	var posed := kind == "art" and _pose_pos.size() == n
	var horse := kind == "cav"
	while _mms.size() < 4:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = _quad_mesh
		_mms.append(mm)
		_mm_bufs.append(PackedFloat32Array())
	for g in 4:
		var idx: PackedInt32Array = groups[g]
		var mm: MultiMesh = _mms[g]
		if idx.is_empty():
			continue
		if mm.instance_count != idx.size():
			mm.instance_count = idx.size()
			_mm_bufs[g].resize(idx.size() * 12)
		var buf: PackedFloat32Array = _mm_bufs[g]
		var k := 0
		for i in idx:
			var a := _pose_aim[i] if posed else s_aim[i]
			var c := cos(a) * S
			var sn := sin(a) * S
			var p := _pose_pos[i] if posed else s_pos[i]
			if horse:
				p += Vector2(cos(a), sin(a)) * 3.0   # koń obraca się na zadzie, nie wokół środka
			var shade := 0.92 + clampf(s_jit[i].x, -1.0, 1.0) * 0.08
			buf[k] = c
			buf[k + 1] = -sn
			buf[k + 2] = 0.0
			buf[k + 3] = p.x
			buf[k + 4] = sn
			buf[k + 5] = c
			buf[k + 6] = 0.0
			buf[k + 7] = p.y
			buf[k + 8] = shade
			buf[k + 9] = shade
			buf[k + 10] = shade
			buf[k + 11] = 1.0
			k += 12
		_mm_bufs[g] = buf
		mm.buffer = buf
		draw_multimesh(mm, texs[g])


var _mms: Array = []
var _mm_bufs: Array = []


func _reload_pose(i: int, t: float) -> int:
	## Ładowanie muszkietu: odgryzienie ładunku, podsypka, stempel w lufę i ubijanie (2-3 ruchy), potem broń do ramienia.
	## Tylko strzelający (przednie szeregi) i tylko gdy faktycznie ładują po strzale.
	if state == State.MELEE or state == State.ROUTING:
		return 0
	if not square and not wedge and i >= files_for(s_pos.size()) * 2:
		return 3                              # tylne szeregi nie strzelają — broń na ramieniu
	if s_reload[i] <= 0.7 or s_vel[i].length() > 6.0:
		return 0
	if s_reload[i] > reload_time * 0.5:
		return 1                              # ładunek do lufy, stempel wsunięty
	var ph := fposmod(t * 1.6 + s_jit[i].x * 3.0, 1.0)
	return 2 if ph < 0.45 else 1              # ubijanie: stempel w górę i w dół


var bake_pose := 0   # wypalanie: 0 = gotowy, 1 = ładuje (stempel w lufie), 2 = ubija (stempel w górze)


func _inf_one(p: Vector2, dir: Vector2, st: Dictionary, j: Vector2) -> void:
	var musket := Color(0.28, 0.18, 0.1)
	var steel := Color(0.82, 0.82, 0.88)
	var rifle := base_key == "rifles"
	var side := dir.orthogonal()
	draw_circle(p + Vector2(0.6, 0.8), 2.6, Color(0, 0, 0, 0.22))
	if bake_pose == 3:
		# "na ramię broń": muszkiet pionowo przy lewym barku — z góry widać kolbę, krótki skrót lufy i bagnet
		var s0 := p - side * 1.6 - dir * 0.4
		var s1 := p - side * 1.9 + dir * 1.5
		_figure(p, dir, st, j)
		draw_line(s0, s1, musket, 1.0)
		draw_circle(s1, 0.45, steel)
		if base_key != "rifles":
			draw_line(s1, s1 + dir * 0.9 - side * 0.3, steel, 0.4)   # bagnet sterczy w górę
		return
	if bake_pose > 0:
		# muszkiet postawiony kolbą na ziemi przy prawej nodze, lufa przy barku — z góry widać krótki skrót
		var b0 := p + side * 2.1 + dir * 0.9
		var b1 := p + side * 1.7 + dir * 2.3
		_figure(p, dir, st, j)
		draw_line(b0, b1, musket, 1.0)
		draw_circle(b1, 0.45, steel)                                # wylot lufy
		if bake_pose == 2:
			draw_line(b1, b1 + dir * 1.4 - side * 2.6, steel, 0.4)   # stempel wyciągnięty w górę
		else:
			draw_line(b1, b1 - side * 0.6, steel, 0.4)                # stempel w lufie
		return
	# Muszkiet z góry: kolba (szersza, ciemny orzech) przy prawym barku, łoże, stalowa lufa z mosiężnymi
	# obręczami, a na wylocie bagnet na tulei — długie, wąskie ostrze ze stali z jasnym odblaskiem.
	var m0 := p + side * 1.35 - dir * 1.2          # stopka kolby
	var m1 := p + side * 0.95 + dir * (5.4 if rifle else 6.4)   # wylot lufy
	var md := (m1 - m0).normalized()
	var mside := md.orthogonal()
	draw_line(m0 - md * 0.1, m0 + md * 1.6, musket.darkened(0.25), 1.15)            # kolba
	draw_line(m0 + md * 1.4, m1 - md * 1.0, musket, 0.7)                             # łoże
	draw_line(m0 + md * 2.2 + mside * 0.12, m1, Color(0.36, 0.37, 0.40), 0.32)     # lufa (stal)
	for band in [0.45, 0.72]:                                                       # obręcze
		var bp := m0.lerp(m1, band)
		draw_line(bp - mside * 0.4, bp + mside * 0.4, BRASS if rifle else Color(0.6, 0.6, 0.62), 0.25)
	if not rifle:
		var b0 := m1 + mside * 0.35                    # tuleja z boku lufy
		var b1 := b0 + md * 3.2                        # ostrze ~45 cm
		draw_line(m1, b0, steel.darkened(0.2), 0.35)
		draw_line(b0, b1, steel.darkened(0.25), 0.45)
		draw_line(b0 + md * 0.4 - mside * 0.08, b1 - md * 0.3 - mside * 0.08, Color(0.97, 0.97, 1.0), 0.18)   # odblask
	_figure(p, dir, st, j)


func _cav_one(p: Vector2, dir: Vector2, j: Vector2, sway: float, st: Dictionary) -> void:
	var lancer := base_key == "lancers"
	var heavy := base_key == "cuirassiers" or base_key == "dragoons"
	var side := dir.orthogonal()
	var hc: Color = HORSE_COLORS[int((j.y + 0.7) * 2.8) % 4]
	if base_key == "cuirassiers" or (base_key == "dragoons" and Battle.nation(team) == 1):
		hc = HORSE_COLORS[1]
	var hd := hc.darkened(0.35)
	var hb := 1.1 if heavy else 1.0
	draw_line(p - dir * 5.0 + Vector2(0.8, 1.1), p + dir * 6.0 + Vector2(0.8, 1.1), Color(0, 0, 0, 0.25), 4.6 * hb)
	draw_line(p - dir * 4.6, p - dir * 7.4 + side * sway * 2.0, hd.darkened(0.3), 0.9)
	draw_circle(p - dir * 3.6, 2.0 * hb, hd)
	draw_line(p - dir * 3.6, p + dir * 2.4, hd, 4.0 * hb)
	draw_circle(p + dir * 2.4, 1.9 * hb, hd)
	draw_circle(p - dir * 3.6, 1.6 * hb, hc)
	draw_line(p - dir * 3.6, p + dir * 2.4, hc, 3.2 * hb)
	draw_circle(p + dir * 2.4, 1.5 * hb, hc)
	var nk := p + dir * 4.6 + side * sway
	draw_line(p + dir * 2.6, nk, hc, 1.9)
	draw_line(nk, nk + dir * 2.4 + side * sway * 0.5, hd, 1.5)
	draw_circle(nk + dir * 2.4 + side * sway * 0.5, 0.7, hd.darkened(0.2))
	draw_line(p - dir * 1.9 - side * 1.9, p - dir * 1.9 + side * 1.9, (st["coat"] as Color).darkened(0.35), 1.4)
	if lancer:
		var lp := p + side * 1.9
		draw_line(lp - dir * 4.0, lp + dir * 13.5, Color(0.40, 0.30, 0.18), 0.65)
		draw_line(lp + dir * 11.5, lp + dir * 13.0, Color(0.92, 0.92, 0.95), 0.5)
		draw_line(lp + dir * 10.6 + side * 0.1, lp + dir * 11.6 - side * 1.3, Color(0.9, 0.15, 0.15), 0.9)
		draw_line(lp + dir * 10.6 + side * 0.1, lp + dir * 11.0 - side * 1.5, Color(0.97, 0.97, 0.97), 0.55)
	else:
		var curve := 0.0 if heavy else 0.5
		draw_line(p + side * 2.1, p + side * 2.4 + dir * 3.5, STEEL, 0.6)
		draw_line(p + side * 2.4 + dir * 3.5, p + side * (2.4 + curve) + dir * 5.6, STEEL, 0.5)
	_figure(p - dir * 0.6, dir, st, j, 0.85)


func _draw_infantry(n: int, body: Color, dark: Color) -> void:
	var musket := Color(0.28, 0.18, 0.1)
	var steel := Color(0.82, 0.82, 0.88)
	if battle.cam.zoom.x < DETAIL_ZOOM:
		for i in n:
			var p := s_pos[i]
			var dir := Vector2.from_angle(s_aim[i])
			var side := dir.rotated(PI * 0.5) * 1.4
			draw_line(p + side - dir * 1.5, p + side + dir * 6.5, musket, 0.9)
			draw_line(p + side + dir * 6.5, p + side + dir * 8.2, steel, 0.6)
			draw_circle(p, SOLDIER_RADIUS, dark)
			draw_circle(p, SOLDIER_RADIUS - 0.7, body)
		return
	var st := _uniform()
	var rifle := base_key == "rifles"
	for i in n:
		var p := s_pos[i]
		var dir := Vector2.from_angle(s_aim[i])
		var side := dir.orthogonal()
		# muszkiet przy prawym ramieniu (karabin strzelców krótszy, bez bagnetu)
		draw_circle(p + Vector2(0.8, 1.0), 2.6, Color(0, 0, 0, 0.22))
		var m0 := p + side * 1.3 - dir * 1.0
		var m1 := p + side * 0.9 + dir * (5.6 if rifle else 6.6)
		draw_line(m0, m1, musket, 0.85)
		if not rifle:
			draw_line(m1, m1 + (m1 - m0).normalized() * 2.0, steel, 0.5)
		_figure(p, dir, st, s_jit[i])


const HORSE_COLORS := [Color(0.36, 0.22, 0.12), Color(0.22, 0.14, 0.08), Color(0.5, 0.33, 0.18), Color(0.15, 0.12, 0.1)]


func _draw_cavalry(n: int, body: Color, dark: Color) -> void:
	var lancer := base_key == "lancers"
	if battle.cam.zoom.x >= DETAIL_ZOOM:
		_draw_cavalry_detail(n, lancer)
		return
	for i in n:
		var dir := Vector2.from_angle(s_aim[i])
		var p := s_pos[i] + dir * 3.0   # koń obraca się na zadzie, nie wokół środka tułowia
		var side := dir.rotated(PI * 0.5)
		var hc: Color = HORSE_COLORS[int((s_jit[i].y + 0.7) * 2.8) % 4]
		# koń: tułów + szyja + głowa
		draw_line(p - dir * 5.0, p + dir * 4.0, Color(0, 0, 0, 0.35), 4.6)
		draw_line(p - dir * 4.5, p + dir * 3.5, hc, 3.8)
		draw_line(p + dir * 3.0, p + dir * 6.5, hc, 2.0)
		draw_circle(p + dir * 6.8, 1.3, hc.darkened(0.2))
		# jeździec
		if lancer:
			draw_line(p + side * 1.8 - dir * 3.0, p + side * 1.8 + dir * 13.0, Color(0.35, 0.25, 0.15), 0.7)
			draw_rect(Rect2(p + side * 1.8 + dir * 11.0, Vector2(1.6, 1.2)), Color(0.9, 0.15, 0.15))
		else:
			draw_line(p + side * 2.0, p + side * 2.0 + dir * 5.0, Color(0.85, 0.85, 0.9), 0.6)
		draw_circle(p, 2.4, dark)
		draw_circle(p, 1.7, body)


func _draw_cavalry_detail(n: int, lancer: bool) -> void:
	## Koń z góry: zad, tułów, pierś, szyja, łeb, ogon; na nim jeździec w mundurze typu.
	var st := _uniform()
	var heavy := base_key == "cuirassiers" or base_key == "dragoons"
	var t := battle.sim_time
	for i in n:
		var dir := Vector2.from_angle(s_aim[i])
		var p := s_pos[i] + dir * 3.0   # obrót na zadzie (punkt obrotu = tylne nogi)
		var side := dir.orthogonal()
		var j := s_jit[i]
		var hc: Color = HORSE_COLORS[int((j.y + 0.7) * 2.8) % 4]
		if base_key == "cuirassiers" or (base_key == "dragoons" and Battle.nation(team) == 1):
			hc = HORSE_COLORS[1 + int((j.x + 1.0) * 3.0) % 2 * 2]   # ciężka jazda: ciemne konie
		elif base_key == "lancers" and unit_key != "cossacks" and Battle.nation(team) != 0 and int((j.x + 1.0) * 5.0) % 3 == 0:
			hc = Color(0.72, 0.72, 0.7)                                # siwki
		var hd := hc.darkened(0.35)
		var moving := s_vel[i].length() > 4.0
		var sway := sin(t * (9.0 if moving else 1.5) + j.x * 10.0) * (0.35 if moving else 0.15)
		var hb := 1.1 if heavy else 1.0
		# cień
		draw_line(p - dir * 5.0 + Vector2(1.2, 1.6), p + dir * 6.0 + Vector2(1.2, 1.6), Color(0, 0, 0, 0.25), 4.6 * hb)
		# ogon
		draw_line(p - dir * 4.6, p - dir * 7.4 + side * sway * 2.0, hd.darkened(0.3), 0.9)
		# tułów: zad, korpus, pierś (zaokrąglone kółkami)
		draw_circle(p - dir * 3.6, 2.0 * hb, hd)
		draw_line(p - dir * 3.6, p + dir * 2.4, hd, 4.0 * hb)
		draw_circle(p + dir * 2.4, 1.9 * hb, hd)
		draw_circle(p - dir * 3.6, 1.6 * hb, hc)
		draw_line(p - dir * 3.6, p + dir * 2.4, hc, 3.2 * hb)
		draw_circle(p + dir * 2.4, 1.5 * hb, hc)
		# szyja i łeb (lekko kołysze się w marszu)
		var nk := p + dir * 4.6 + side * sway
		draw_line(p + dir * 2.6, nk, hc, 1.9)
		draw_line(nk, nk + dir * 2.4 + side * sway * 0.5, hd, 1.5)
		draw_circle(nk + dir * 2.4 + side * sway * 0.5, 0.7, hd.darkened(0.2))
		# czaprak w kolorze strony
		draw_line(p - dir * 1.9 - side * 1.9, p - dir * 1.9 + side * 1.9, (st["coat"] as Color).darkened(0.35), 1.4)
		# broń
		if lancer:
			var lp := p + side * 1.9
			draw_line(lp - dir * 4.0, lp + dir * 13.5, Color(0.40, 0.30, 0.18), 0.65)
			draw_line(lp + dir * 11.5, lp + dir * 13.0, Color(0.92, 0.92, 0.95), 0.5)
			draw_line(lp + dir * 10.6 + side * 0.1, lp + dir * 11.6 - side * 1.3 + side * sway, Color(0.9, 0.15, 0.15), 0.9)
			draw_line(lp + dir * 10.6 + side * 0.1, lp + dir * 11.0 - side * 1.5 + side * sway, Color(0.97, 0.97, 0.97), 0.55)
		else:
			var curve := 0.0 if heavy else 0.5   # lekka jazda: zakrzywiona szabla
			draw_line(p + side * 2.1, p + side * 2.4 + dir * 3.5, STEEL, 0.6)
			draw_line(p + side * 2.4 + dir * 3.5, p + side * (2.4 + curve) + dir * 5.6, STEEL, 0.5)
		# jeździec
		_figure(p - dir * 0.6, dir, st, j, 0.85)


var _recoil := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _pose_pos := PackedVector2Array()   # artyleria: pozy obsługi w tej klatce (ładowanie, jazda wierzchem)
var _pose_aim := PackedFloat32Array()


func _quad(c: Vector2, ax: Vector2, ay: Vector2, hx0: float, hx1: float, y0: float, y1: float, col: Color) -> void:
	## Czworokąt wzdłuż osi `ay` (od y0 do y1), szerokość hx0 na początku i hx1 na końcu.
	draw_colored_polygon(PackedVector2Array([
		c + ay * y0 - ax * hx0, c + ay * y0 + ax * hx0, c + ay * y1 + ax * hx1, c + ay * y1 - ax * hx1]), col)


const LIMBER_WOOD := Color(0.36, 0.25, 0.13)
const LIMBER_DARK := Color(0.22, 0.15, 0.08)
const IRON := Color(0.17, 0.17, 0.19)
const BRONZE := Color(0.66, 0.53, 0.26)
const BRONZE_DARK := Color(0.38, 0.30, 0.14)
const LEATHER := Color(0.16, 0.10, 0.06)
var _wood := LIMBER_WOOD
var _wood_dark := LIMBER_DARK


func _wheel(c: Vector2, ax: Vector2, along: Vector2, half_len: float, out: float) -> void:
	## Koło widziane z góry: obręcz (wąski prostokąt) + piasta wystająca na zewnątrz.
	_quad(c, ax, along, 1.4, 1.4, -half_len, half_len, _wood_dark)
	_quad(c, ax, along, 0.75, 0.75, -half_len + 0.6, half_len - 0.6, _wood)
	draw_line(c - along * half_len, c + along * half_len, IRON, 0.45)
	draw_circle(c + ax * out * 1.9, 1.15, IRON)
	draw_circle(c + ax * out * 1.9, 0.5, _wood.lightened(0.2))


func _draw_gun(gp: Vector2, gd: Vector2) -> void:
	## Działo polowe: lufa w kierunku gd, laweta (dwie belki) zwężająca się do tyłu, skrzynka, koła, ucha.
	var ax := gd.orthogonal()
	var bk := -gd
	# cień
	_quad(gp + Vector2(3, 4), ax, bk, 7.5, 2.2, -16.0, 19.0, Color(0, 0, 0, 0.28))
	# laweta: dwie belki zbiegające się ku końcowi + poprzeczki
	for sd in [-1.0, 1.0]:
		var a0: Vector2 = gp + ax * 2.8 * sd
		var a1: Vector2 = gp + bk * 16.0 + ax * 0.9 * sd
		draw_line(a0, a1, _wood_dark, 2.0)
		draw_line(a0 + bk * 0.3, a1, _wood, 1.1)
	for k in [4.0, 9.0]:
		draw_line(gp + bk * k - ax * (2.8 - k * 0.12), gp + bk * k + ax * (2.8 - k * 0.12), _wood_dark, 1.0)
	# skrzynka amunicyjna między belkami + koniec lawety z drągiem do kierowania
	_quad(gp, ax, bk, 1.7, 1.5, 10.0, 14.0, Color(0.30, 0.22, 0.12))
	draw_line(gp + bk * 12.0 - ax * 1.5, gp + bk * 12.0 + ax * 1.5, _wood_dark, 0.5)
	draw_circle(gp + bk * 16.5, 1.3, IRON)
	draw_line(gp + bk * 16.5 - ax * 0.4, gp + bk * 20.0 + ax * 1.6, Color(0.45, 0.33, 0.2), 0.8)
	# oś i koła
	draw_line(gp - ax * 7.2, gp + ax * 7.2, IRON, 1.5)
	for sd in [-1.0, 1.0]:
		_wheel(gp + ax * 6.4 * sd, ax, gd, 5.6, sd)
	# lufa wg typu działa: długość (6/8/12-funt.), kaliber, haubica = krótka i gruba, Gwardia = polerowany brąz
	var spec: Dictionary = Battle.UNIT_TYPES[unit_key].get("gun", {})
	var L: float = spec.get("len", 1.0)
	var B: float = spec.get("bore", 1.0)
	var how: bool = spec.get("how", false)
	var br := BRONZE.lightened(0.22) if spec.get("polish", false) else BRONZE
	var bd := BRONZE_DARK.lightened(0.1) if spec.get("polish", false) else BRONZE_DARK
	var mz := 1.3 if how else 1.0
	var e := 13.4 * L
	draw_circle(gp - gd * (4.6 + 1.0 * B), 1.1 * B, bd)
	_quad(gp, ax, gd, 2.9 * B, 2.3 * B, -4.6, 2.0, bd)
	_quad(gp, ax, gd, 2.4 * B, 1.8 * B, -4.2, 1.8, br)
	_quad(gp, ax, gd, 2.2 * B, 1.5 * B * mz, 1.6, e, bd)
	_quad(gp, ax, gd, 1.7 * B, 1.15 * B * mz, 1.8, e - 0.2, br)
	for k in [-4.4, 1.8, 1.8 + (e - 1.8) * 0.45]:
		var w: float = (2.6 - (k + 4.4) * 0.09 / maxf(L, 0.5)) * B
		draw_line(gp + gd * k - ax * w, gp + gd * k + ax * w, bd, 0.7)
	_quad(gp, ax, gd, 1.9 * B * mz, 1.9 * B * mz, e - 0.4, e + 2.2, bd)
	_quad(gp, ax, gd, 1.4 * B * mz, 1.4 * B * mz, e - 0.1, e + 1.9, br)
	draw_circle(gp + gd * (e + 2.2), 0.95 * B * mz, Color(0.04, 0.04, 0.04))
	if spec.get("polish", false):
		draw_line(gp - ax * 3.0 * B + gd * 0.2, gp + ax * 3.0 * B + gd * 0.2, Color(0.95, 0.8, 0.35), 0.6)   # mosiężne okucia Gwardii
	# czopy na lawecie
	draw_line(gp - ax * 3.2, gp + ax * 3.2, BRONZE_DARK, 1.1)
	# odblask na lufie
	draw_line(gp - gd * 3.5 - ax * 1.0 * B, gp + gd * (e - 1.0) - ax * 0.6 * B, Color(1, 0.95, 0.75, 0.45 if spec.get("polish", false) else 0.38), 0.6)


func _horse_top(p: Vector2, d: Vector2, hc: Color) -> void:
	## Koń z góry: zad, tułów, pierś, szyja z grzywą, łeb, ogon; chomąto na karku.
	var sd := d.orthogonal()
	draw_line(p - d * 6.2 + Vector2(2.2, 3.0), p + d * 8.0 + Vector2(2.2, 3.0), Color(0, 0, 0, 0.26 * hc.a), 4.8)
	draw_line(p - d * 8.6, p - d * 5.4, hc.darkened(0.55), 1.3)   # ogon
	draw_line(p - d * 5.0, p + d * 3.4, hc.darkened(0.25), 4.8)
	draw_line(p - d * 4.8, p + d * 3.2, hc, 4.0)
	draw_circle(p - d * 4.6, 2.2, hc)
	draw_circle(p + d * 3.0, 2.0, hc)
	draw_line(p + d * 3.2, p + d * 7.0, hc, 2.3)                  # szyja
	draw_line(p + d * 3.4, p + d * 6.8, hc.darkened(0.5), 0.8)    # grzywa
	draw_line(p + d * 6.8, p + d * 9.6, hc.darkened(0.12), 1.8)   # łeb
	draw_circle(p + d * 9.6, 0.8, hc.darkened(0.3))
	draw_line(p + d * 2.6 - sd * 2.3, p + d * 2.6 + sd * 2.3, LEATHER, 1.0)   # chomąto
	draw_line(p + d * 0.5 - sd * 2.0, p + d * 0.5 + sd * 2.0, LEATHER, 0.6)   # popręg


func _draw_team(anchor: Vector2, td: Vector2, pairs: int, g: int, st: Dictionary) -> void:
	## Przodek (dwukołowy wózek ze skrzynią amunicyjną) + dyszel + pary koni; woźnica na lewym koniu każdej pary.
	var ax := td.orthogonal()
	# przodek
	_quad(anchor + Vector2(2.5, 3.5), ax, td, 6.5, 6.5, -6.0, 5.0, Color(0, 0, 0, 0.25))
	draw_line(anchor - ax * 7.0, anchor + ax * 7.0, IRON, 1.3)
	for sd in [-1.0, 1.0]:
		_wheel(anchor + ax * 6.2 * sd, ax, td, 5.0, sd)
	_quad(anchor, ax, td, 4.4, 4.4, -3.6, 3.6, _wood_dark)
	_quad(anchor, ax, td, 3.8, 3.8, -3.0, 3.0, Color(0.34, 0.30, 0.20))
	draw_line(anchor - ax * 3.8, anchor + ax * 3.8, _wood_dark, 0.6)          # wieko skrzyni
	draw_line(anchor - td * 3.6, anchor - td * 6.5, IRON, 0.9)                  # hak na lawetę
	# dyszel i postronki
	var front := anchor + td * (10.0 + pairs * 12.0)
	draw_line(anchor + td * 3.6, anchor + td * 22.0, _wood, 1.0)
	for sd in [-1.0, 1.0]:
		draw_line(anchor + td * 4.0 + ax * 2.5 * sd, front - td * 6.0 + ax * 4.2 * sd, LEATHER, 0.45)
	for k in pairs:
		var c := anchor + td * (15.0 + k * 12.0)
		for sd in [-1.0, 1.0]:
			var hc: Color = HORSE_COLORS[(g * 3 + k * 2 + (1 if sd > 0.0 else 0)) % HORSE_COLORS.size()]
			_horse_top(c + ax * 4.4 * sd, td, hc)
		_figure(c - ax * 4.4 - td * 0.8, td, st, Vector2.ZERO, 0.8)   # woźnica na lewym koniu


const GUN_CLEAR := 10.5      # odstęp od osi działa, poza kołami
const GUN_SPAN := Vector2(-22.0, 18.0)   # od końca drąga za lawetą do wylotu lufy (wzdłuż osi)


static func _crew_path(home: Vector2, tgt: Vector2, gp: Vector2, gd: Vector2, k: float) -> Vector2:
	## Pozycja na trasie home→tgt omijającej działo: odejście w bok poza koło, wzdłuż działa, podejście na miejsce.
	if k <= 0.0:
		return home
	var sd := gd.orthogonal()
	var ah := (home - gp).dot(gd)
	var ch := (home - gp).dot(sd)
	var at := (tgt - gp).dot(gd)
	var ct := (tgt - gp).dot(sd)
	var side := signf(ch) if absf(ch) > 0.5 else (signf(ct) if absf(ct) > 0.5 else 1.0)
	var pts := PackedVector2Array([home])
	var inside_h := ah > GUN_SPAN.x and ah < GUN_SPAN.y
	var inside_t := at > GUN_SPAN.x and at < GUN_SPAN.y
	if inside_h or inside_t or signf(ct) != side:
		var aa := clampf(ah, GUN_SPAN.x - 2.0, GUN_SPAN.y + 2.0) if inside_h else ah
		var ab := clampf(at, GUN_SPAN.x - 2.0, GUN_SPAN.y + 2.0) if inside_t else at
		pts.append(gp + gd * aa + sd * side * maxf(absf(ch) if signf(ch) == side else 0.0, GUN_CLEAR))
		pts.append(gp + gd * ab + sd * side * maxf(absf(ct) if signf(ct) == side else 0.0, GUN_CLEAR))
	pts.append(tgt)
	var total := 0.0
	for m in pts.size() - 1:
		total += pts[m].distance_to(pts[m + 1])
	if total < 0.01:
		return tgt
	var want := clampf(k, 0.0, 1.0) * total
	for m in pts.size() - 1:
		var seg := pts[m].distance_to(pts[m + 1])
		if want <= seg:
			return pts[m].lerp(pts[m + 1], want / maxf(seg, 0.001))
		want -= seg
	return tgt


const CREW_SPEED := 12.0     # krok obsługi działa (jednostki świata / s, ~1.5 m/s)
var _crew_cur := PackedVector2Array()
var _crew_dir := PackedFloat32Array()


var _limbering := true     # kierunek: składanie (true) albo rozkładanie (false)
var _last_limber_u := 0.0


static func _bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var m := 1.0 - t
	return p0 * m * m * m + p1 * 3.0 * m * m * t + p2 * 3.0 * m * t * t + p3 * t * t * t


static func _bez_tan(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var m := 1.0 - t
	var d := (p1 - p0) * 3.0 * m * m + (p2 - p1) * 6.0 * m * t + (p3 - p2) * 3.0 * t * t
	return d.normalized() if d.length() > 0.001 else (p3 - p0).normalized()


static func _team_pose(u: float, limbering: bool, gp: Vector2, f: Vector2, r: Vector2) -> Array:
	## [zaczep przodka, kierunek koni, obrót działa 0..1] dla postępu składania u (0 rozłożone, 1 zaczepione).
	## Rozłożone: zaprzęg stoi za działem (S), konie od frontu. Zaczepione: przodek przed działem (E), konie w stronę marszu.
	## Zaprzęg jedzie jak pojazd (półkola, proste, łuki; konie zawsze przodem), a działo obraca się na kołach
	## tylko wtedy, gdy zaprzęg jest w bocznej "alei" dalej niż długość lawety — nic się nie zderza.
	const R := 14.0
	const LANE := 28.0
	var S := gp - f * 48.0
	var E := gp + f * 22.0
	if limbering:
		var swing := smoothstep(0.32, 0.62, u)
		if u < 0.3:   # zawrót półkolem za działem: z kierunku -f na +f, na prawą aleję
			var t := smoothstep(0.0, 1.0, u / 0.3)
			var c := S + r * R
			return [c + (-r).rotated(-PI * t) * R, (-r).rotated(-PI * t - PI * 0.5), swing]
		var lane0 := S + r * LANE
		var lane1 := gp + r * LANE - f * 4.0
		if u < 0.62:   # prosto aleją obok działa (w tym czasie obsługa przerzuca ogon lawety)
			var t2 := (u - 0.3) / 0.32
			return [lane0.lerp(lane1, t2), f, swing]
		var t3 := smoothstep(0.0, 1.0, (u - 0.62) / 0.38)   # łuk przed działo, przodek do haka
		var c1 := lane1 + f * 22.0
		var c2 := E - f * 10.0 + r * 4.0
		return [_bez(lane1, c1, c2, E, t3), _bez_tan(lane1, c1, c2, E, t3), swing]
	var w := 1.0 - u
	var swing2 := 1.0 - smoothstep(0.45, 0.75, w)
	var F := E + f * 20.0
	if w < 0.2:   # odczepienie i odjazd do przodu
		return [E.lerp(F, smoothstep(0.0, 1.0, w / 0.2)), f, swing2]
	if w < 0.45:   # zawrót w lewo przed baterią
		var t4 := smoothstep(0.0, 1.0, (w - 0.2) / 0.25)
		var cc := F - r * R
		return [cc + r.rotated(-PI * t4) * R, f.rotated(-PI * t4), swing2]
	var lane2 := F - r * LANE
	var lane3 := gp - r * LANE - f * 10.0
	if w < 0.75:   # z powrotem lewą aleją (działo obraca się z powrotem)
		return [lane2.lerp(lane3, (w - 0.45) / 0.3), -f, swing2]
	var t5 := smoothstep(0.0, 1.0, (w - 0.75) / 0.25)   # łuk na miejsce za działem
	var d1 := lane3 - f * 18.0
	var d2 := S + f * 12.0 - r * 6.0
	return [_bez(lane3, d1, d2, S, t5), _bez_tan(lane3, d1, d2, S, t5), swing2]


static func _crew_post(role: int, mz: float) -> Vector2:
	## Stanowiska obsługi względem działa: (w prawo, do tyłu od osi kół). Wylot lufy jest mz przed osią.
	match role:
		1: return Vector2(5.5, -(mz + 1.0))     # wyciorowy — prawa strona wylotu
		2: return Vector2(-5.5, -(mz + 1.0))    # ładowniczy — lewa strona wylotu
		3: return Vector2(4.8, 6.0)             # przy zapale — za prawym kołem
		4: return Vector2(-9.0, 8.5)            # kanonier z lontem — z tyłu po lewej
		5: return Vector2(-3.0, 34.0)           # amunicyjny — przy skrzyni z tyłu
	return Vector2(0.0, 20.5)                   # celowniczy — przy ogonie lawety


static func _stroke(t: float, n: int) -> float:
	## Płynny ruch tam i z powrotem (n razy) z zatrzymaniem w głębi lufy — bez szarpania.
	var x := clampf(t, 0.0, 1.0) * n
	var k := x - floorf(x)
	return smoothstep(0.0, 0.45, k) * (1.0 - smoothstep(0.55, 1.0, k))


static func _phase(f: float, a: float, b: float) -> float:
	## Płynne wejście/wyjście w fazę musztry [a, b] (0 poza nią, 1 w środku).
	var ramp := 0.09
	return smoothstep(a, a + ramp, f) * (1.0 - smoothstep(b - ramp, b, f))


func _crew_tool_rammer(p: Vector2, dir: Vector2, muzzle: Vector2, gd: Vector2, depth: float, L: float, rammer_end: bool) -> void:
	## Wycior (gąbka) albo stempel: drzewce od rąk do wylotu, w lufie na głębokość depth.
	var tip := muzzle - gd * (depth * 11.0 * L)
	var hand := p + dir * 1.5
	draw_line(hand, tip, Color(0.45, 0.33, 0.2), 0.8)
	draw_line(hand, hand + (hand - tip).normalized() * 3.0, Color(0.45, 0.33, 0.2), 0.8)
	draw_circle(tip, 0.9, Color(0.30, 0.22, 0.12) if rammer_end else Color(0.18, 0.16, 0.15))   # stempel / mokra gąbka


func _draw_artillery(n: int, body: Color, dark: Color, crew := true) -> void:
	## Bateria z góry: działa (laweta, koła, lufa z brązu) + przodki z zaprzęgami koni i woźnicami.
	## limber_u: 0 = działa rozłożone, zaprzęgi stoją z tyłu; 1 = działa zaczepione lufą do tyłu, konie ciągną.
	var fwd := forward()
	var right := fwd.rotated(PI * 0.5)
	var guns := gun_count()
	var u := limber_u
	if limber_u > _last_limber_u + 0.0001:
		_limbering = true
	elif limber_u < _last_limber_u - 0.0001:
		_limbering = false
	_last_limber_u = limber_u
	var spec: Dictionary = Battle.UNIT_TYPES[unit_key].get("gun", {})
	var pairs: int = spec.get("pairs", 3 if base_key == "horse_art" else 2)
	var st := _uniform()
	var fr_wood := Battle.nation(team) == 0
	_wood = Color(0.33, 0.36, 0.20) if fr_wood else LIMBER_WOOD          # francuskie lawety: oliwkowe
	_wood_dark = Color(0.19, 0.21, 0.11) if fr_wood else LIMBER_DARK
	for g in guns:
		var rec: float = _recoil[g % _recoil.size()]
		_recoil[g % _recoil.size()] = maxf(0.0, rec - 0.04)
		var gd := Vector2.from_angle(gun_angle(g))
		var gp := gun_pos(g) - gd * rec * 4.0
		# zaprzęg jedzie jak pojazd (łukami, przodem w kierunku jazdy), a działo obraca się na kołach dopiero,
		# gdy przodek stoi przed nim — ogon lawety przerzucany stroną z dala od koni (bez obrotów w miejscu)
		var pose := _team_pose(u, _limbering, gp, fwd, right)
		var anchor: Vector2 = pose[0]
		var tdir: Vector2 = pose[1]
		var swing: float = pose[2]
		var ttex: Texture2D = sprite_tex.get(sprite_key() + "#team%d" % (g % 2))
		var gtex: Texture2D = sprite_tex.get(sprite_key() + "#gun")
		if ttex != null:
			_blit(ttex, anchor + tdir * _team_off(pairs), tdir.angle())
		else:
			_draw_team(anchor, tdir, pairs, g, st)
		if gtex != null:
			_blit(gtex, gp, gd.rotated(-PI * swing).angle())   # lufa w lewo, ogon przez prawą stronę
		else:
			_draw_gun(gp, gd.rotated(-PI * swing))

	var detail := battle.cam.zoom.x >= DETAIL_ZOOM
	var L: float = spec.get("len", 1.0)
	var firing := limber_u <= 0.01 and battle.sim_time - last_fire_time < reload_time * 1.6
	var mounted := base_key == "horse_art" and u > 0.02
	_pose_pos.resize(n)
	_pose_aim.resize(n)
	var crew_dt := 0.0 if battle.paused else clampf(get_process_delta_time(), 0.0, 0.1) * battle.time_scale
	for i in n:
		var p := s_pos[i]
		var dir := Vector2.from_angle(s_aim[i])
		var g := i % guns
		var role := i / guns
		var tool := 0          # narzędzie w rękach: 0 brak, 1 wycior/stempel, 2 nabój, 3 drąg, 4 lont
		var f := 1.0           # postęp ładowania tego działa (1 = gotowe)
		var ammo_go := 0.0     # amunicyjny: 0 przy skrzyni, 1 przy ładowniczym
		var deployed := limber_u <= 0.01 and g < guns
		if deployed:
			# Musztra przy dziale: każdy ma stałe stanowisko, rusza głównie rękami i narzędziem.
			# Chodzi tylko amunicyjny (nr 5) — nosi nabój od skrzyni do ładowniczego i wraca.
			var gd2 := Vector2.from_angle(gun_angle(g))
			var sd2 := gd2.orthogonal()
			var gp2 := gun_pos(g)
			var mz := 13.4 * L + 3.5
			var reloading := s_reload[g] > 0.0 and battle.sim_time - last_fire_time < reload_time * 1.6
			if reloading:
				f = 1.0 - clampf(s_reload[g] / maxf(reload_time, 0.1), 0.0, 1.0)
			var post := _crew_post(role, mz)
			var look := gd2
			match role:
				1:   # nr 1, wyciorowy: przy wylocie po prawej, twarzą do lufy
					look = -sd2
					if reloading and f > 0.08 and f < 0.7:
						tool = 1
				2:   # nr 2, ładowniczy: przy wylocie po lewej; bierze nabój od amunicyjnego i wkłada do lufy
					look = sd2
					if reloading and f > 0.36 and f < 0.46:
						tool = 2
				3:   # nr 3, przy zapale: kciuk na zapale podczas czyszczenia, potem przebija nabój
					look = gd2
				4:   # nr 4, kanonier z lontem: z tyłu po lewej, na koniec przykłada lont do zapału
					tool = 4
					look = (gp2 - gd2 * 3.0 - (gp2 + sd2 * post.x - gd2 * post.y)).normalized()
					if reloading and f > 0.9:
						post = post.lerp(Vector2(-4.5, 4.0), smoothstep(0.9, 0.97, f))
				0:   # nr 6, celowniczy przy ogonie lawety: drąg w rękach przy celowaniu
					look = gd2
					if reloading and f > 0.66 and f < 0.88:
						tool = 3
						post.x += sin((f - 0.66) / 0.22 * PI) * 1.5   # lekko przesuwa ogon lawety
				5:   # nr 5, amunicyjny: skrzynia z tyłu -> ładowniczy -> z powrotem (dookoła koła, nie przez nie)
					ammo_go = smoothstep(0.12, 0.36, f) * (1.0 - smoothstep(0.46, 0.7, f)) if reloading else 0.0
					if reloading and f > 0.1 and f < 0.38:
						tool = 2
			p = gp2 + sd2 * post.x - gd2 * post.y
			if role == 5:
				var front := Vector2(-9.5, -(mz - 3.0))
				p = _crew_path(p, gp2 + sd2 * front.x - gd2 * front.y, gp2, gd2, ammo_go)
			dir = look
			if detail:
				var muzzle := gp2 + gd2 * mz
				var vent := gp2 - gd2 * 3.0
				match tool:
					1:
						var depth := 0.0
						if f > 0.12 and f < 0.32:
							depth = _stroke((f - 0.12) / 0.2, 2)      # czyszczenie: 2 spokojne ruchy wycioru
						elif f > 0.48 and f < 0.68:
							depth = _stroke((f - 0.48) / 0.2, 2)      # ubijanie: 2 ruchy stempla
						_crew_tool_rammer(p, dir, muzzle, gd2, depth, L, f > 0.4)
					2:
						var hand := p + dir * 2.2
						draw_rect(Rect2(hand - Vector2(1.0, 1.0), Vector2(2.0, 2.0)), Color(0.85, 0.80, 0.62))
						draw_circle(hand + dir * 1.1, 0.8, Color(0.12, 0.12, 0.13))
					3:
						draw_line(p + dir * 1.2, gp2 - gd2 * 19.0 + sd2 * 1.5, Color(0.40, 0.29, 0.17), 0.9)
					4:
						var tip := p + dir * 5.0
						if f > 0.94 and f < 1.0:
							tip = vent
						draw_line(p + dir * 1.0, tip, Color(0.33, 0.24, 0.14), 0.7)
						draw_rect(Rect2(tip - Vector2(0.8, 0.8), Vector2(1.6, 1.6)), Color(1.0, 0.55 + 0.3 * sin(battle.sim_time * 9.0), 0.15))
		if mounted:
			# artyleria konna: obsługa jedzie wierzchem; przy rozkładaniu zsiada, a konie odprowadzane są do tyłu
			var hp := p - fwd * (1.0 - u) * 34.0
			var hc: Color = HORSE_COLORS[(i * 3) % HORSE_COLORS.size()]
			hc.a = clampf(u * 1.6, 0.0, 1.0)
			var hdir := dir if u > 0.5 else fwd
			var htex: Texture2D = sprite_tex.get(sprite_key() + "#horse")
			if htex != null:
				_blit(htex, hp - hdir * 1.0, hdir.angle(), hc.a)
			elif detail:
				_horse_top(hp - hdir * 1.5, hdir, hc)
			else:
				draw_line(hp - hdir * 4.5, hp + hdir * 4.0, hc, 3.6)
			if u > 0.5:
				p = hp
				dir = hdir
		# obsługa chodzi normalnym krokiem: pozycja dochodzi do wyznaczonej z prędkością marszu (bez teleportów)
		if _crew_cur.size() != n:
			_crew_cur = _pose_pos.duplicate() if _pose_pos.size() == n else s_pos.duplicate()
			_crew_dir.resize(n)
			for c in n:
				_crew_dir[c] = s_aim[c]
		var cur := _crew_cur[i]
		if cur.distance_to(p) > 80.0:
			cur = p   # nowa pozycja baterii (przemarsz) — bez biegu przez pół mapy
		var walked := cur.move_toward(p, CREW_SPEED * crew_dt)
		if walked.distance_to(cur) > 0.05 and walked.distance_to(p) > 3.0:
			dir = (walked - cur).normalized()   # idąc dłuższy kawałek patrzy przed siebie
		_crew_cur[i] = walked
		_crew_dir[i] = rotate_toward(_crew_dir[i], dir.angle(), 2.6 * crew_dt)   # spokojny obrót
		p = walked
		dir = Vector2.from_angle(_crew_dir[i])
		_pose_pos[i] = p
		_pose_aim[i] = dir.angle()
		if not crew:
			continue   # postacie narysuje szybka ścieżka (sprite'y) w pozach z _pose_pos
		if detail:
			var side := dir.orthogonal()
			draw_circle(p + Vector2(0.8, 1.0), 2.3, Color(0, 0, 0, 0.22))
			if i % 4 == 0 and tool == 0:
				draw_line(p - side * 1.5 - dir * 3.5, p - side * 1.5 + dir * 6.5, Color(0.45, 0.33, 0.2), 0.7)
				draw_circle(p - side * 1.5 + dir * 6.5, 0.7, Color(0.15, 0.12, 0.1))
			_figure(p, dir, st, s_jit[i], 0.9)
			continue
		draw_line(p + dir.rotated(PI * 0.5) * 1.4, p + dir.rotated(PI * 0.5) * 1.4 + dir * 5.0, Color(0.4, 0.3, 0.2), 0.7)
		draw_circle(p, SOLDIER_RADIUS * 0.9, dark)
		draw_circle(p, SOLDIER_RADIUS * 0.9 - 0.7, body)

