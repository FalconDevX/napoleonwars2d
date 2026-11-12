class_name Regiment
extends Node2D
## Pułk: kilkadziesiąt żołnierzy w szyku. Żołnierze to lekkie dane (tablice), nie węzły.
## `center` = środek pierwszego szeregu w świecie. Węzeł stoi w (0,0), więc rysujemy w koordynatach świata.
## Rodzaje: "inf" (piechota), "cav" (kawaleria), "art" (artyleria - pierwszy szereg to działa).

enum State { IDLE, MOVING, CHARGING, MELEE, ROUTING }

static var battle: Battle

const SOLDIER_RADIUS := 2.7
const SOLDIER_ACCEL := 16.0     # jak szybko żołnierz rusza/hamuje (px/s²)
const SOLDIER_TURN := 4.0       # jak szybko obraca się ciało (rad/s)
const MELEE_REACH := 7.0
const FIRE_ARC := 1.15
const SOLDIER_ARC := 0.61     # pojedynczy żołnierz strzela najwyżej ~35° w bok od frontu swojego szeregu
const RELOAD_REAL := 1.9      # ładowanie muszkietu w ogniu bitwy: ~2 strzały na minutę (dane z arkusza x1.9)
const HIT_COMP := 1.85        # salwa rzadsza, ale skupiona - wyrównanie siły ognia (+~25% skuteczności)
const RANGE_MULT := 1.15      # wszystkie jednostki strzelają nieco dalej niż w arkuszu
const VOLLEY_READY := 0.75    # komenda "Fire!" gdy tyle strzelających jest załadowanych
const VOLLEY_WAIT := 5.0      # ...albo gdy pierwsi czekają już tyle sekund
const VOLLEY_WINDOW := 1.0    # salwa trwa ułamek sekundy-sekundę (nie wszyscy w tym samym momencie)
const HORSE_R := 9.0          # promień skrętu konia (jednostki świata)
const HORSE_PIVOT := 0.75     # rad/s - najciaśniejszy zwrot (koń nie kręci się jak bączek, tylko zawraca woltą)
const HORSE_VOLTE := 6.5      # stęp, którym koń idzie do przodu, gdy musi zawrócić stojąc
const HORSE_MAX_TURN := 2.6   # rad/s - górny limit w galopie
const HORSE_DRESS := 11.0     # tak blisko swojego miejsca koń już nie zatacza łuku, tylko dochodzi krokiem
const HORSE_DRESS_SPEED := 8.0
const DROWN_RATE := 0.035       # szansa na sekundę, że żołnierz w wodzie utonie
const ART_DEPLOY_TIME := 4.0
const STEP_CYCLE := 16.0            # droga, na której piechur robi dwa kroki (lewa + prawa)
const GALLOP_CYCLE := 22.0          # droga jednego skoku konia w marszu/kłusie
const GALLOP_CYCLE_CHARGE := 13.0   # ...i w szarży: szybka praca nóg
const SQUARE_READY_COH := 5.0   # średnia odległość od miejsc, przy której czworobok uznajemy za zwarty
const DIRECT_MAX := 240.0     # do tej odległości pułk tylko "przestawia się"; dalej maszeruje zwartym szykiem

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
var jitter_scale := 1.0   # rozrzut ludzi wokół miejsc w szyku: 1 = musztra, więcej = bezład (np. jazda w bitewnym chaosie)
# Szarża jazdy: po pierwszym kontakcie blok jeszcze pędzi, każdy koń uderza osobno, część przebija się przez szereg.
const CHARGE_THROUGH_T := 2.2      # s: tyle najdłużej trwa przejazd szarży po pierwszym kontakcie
const CHARGE_MIN_MOMENTUM := 0.3   # poniżej tego ułamka koni w pędzie szarża zamienia się w zwykłe zwarcie
const RIDER_STUCK := 0.3           # s_cool jeźdźca powyżej tej wartości = ugrzązł w szeregu wroga (stoi i walczy)
var _charge_contact_t := -1.0      # czas pierwszego kontaktu szarży (-1 = jeszcze nie uderzyła)
static var _old_charge := OS.get_cmdline_user_args().has("--oldcharge")   # test: stara szarża (porównanie)
const PROC_DRAW_MAX_REGS := 24     # powyżej tylu pułków żołnierze bez gotowego sprite'a rysują się jako kropki
const CONTACT_PIN := 4             # tylu stykających się żołnierzy wiąże pułk walką, gdy nikt nikogo nie atakuje
var melee_enemies_prev: Array[Regiment] = []
var _momentum := 1.0               # ułamek jeźdźców, którzy wciąż pędzą (liczone w _update_soldiers)
var s_tgt_reg: Array = []
var s_tgt_idx := PackedInt32Array()
var _direct := false                # przejście na nową pozycję: każdy żołnierz idzie prosto na swoje miejsce
var _direct_t := 0.0
var _direct_best := INF
var _direct_stall := 0.0
var fire_at_will := true            # false = piechota strzela tylko do wskazanego celu (na rozkaz gracza)
var _step := PackedFloat32Array()      # faza kroku każdego żołnierza (cykle; rośnie tylko, gdy idzie)
var _tmult := 1.0                     # mnożnik terenu, z jakim porusza się środek pułku
static var cannon_shots := [0, 0]     # licznik wystrzałów dział każdej strony (statystyka / testy)
const AMMO_NAMES := ["Auto", "Round shot", "Shell", "Canister"]
var ammo := 0                         # amunicja baterii: 0 = według odległości, 1 = kule, 2 = granaty, 3 = kartacze
var _resquare := false                # po dojściu na miejsce wrócić do czworoboku
var _melee_pt := Vector2.INF          # najbliższy wróg w zwarciu (linia napiera w jego stronę)
var _blocked_n := 0                   # ilu żołnierzy stoi teraz na przeszkodzie terenowej (zbocze, głęboki nurt)
var _leash_t := 0.0                   # jak długo środek pułku czeka na żołnierzy, którzy utknęli
var _wait_t := 0.0                    # ile już czekamy na maruderów (limit, żeby nigdy nie stać w miejscu)
var net_id := -1                      # identyfikator w grze sieciowej
var base_key := ""     # rodzaj ogólny (np. "lancers" dla ułanów i Kozaków) - mechanika i wygląd bazowy
var commander := 0                      # gracz, który dowodzi pułkiem (0 = AI / nikt)
var net_prev := PackedVector2Array()   # gość: położenia z poprzedniego snapshotu (interpolacja)
var net_next := PackedVector2Array()
var net_c0 := Vector2.ZERO
var net_c1 := Vector2.ZERO
var s_block := PackedFloat32Array()   # >0: żołnierz utknął na zboczu - przez chwilę idzie za środkiem pułku

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
const RIG_HOOK := 22.0        # zaczep przodka przed osią zaczepionego działa
const RIG_LANE := 18.0        # zaprzęg stoi i jeździ własnym pasem obok działa - nic się nie krzyżuje
var _gun_p := PackedVector2Array()     # faktyczne położenie każdego działa (toczy się, nie przeskakuje)
var _team_p := PackedVector2Array()    # zaczep przodka każdego zaprzęgu
var _team_ang := PackedFloat32Array()  # kierunek jazdy zaprzęgu
var _gun_swing := 0.0                  # 0 = lufa do przodu (stanowisko), 1 = ogon lawety na haku przodka
var _line_ang := INF                   # kierunek, w którym stoi linia dział (zmienia się tylko przy marszu / dużym zwrocie)
var _rig_lag := 0.0                    # o ile zaprzęgi jadą za linią baterii (ustawiają się w marszu)
var square := false
var _disorder_until := -1.0         # do kiedy szyk jest rozbity szarżą (słabsza walka wręcz, łatwiejszy cel)
var _square_ok := false              # czworobok faktycznie stoi (ludzie na miejscach), a nie tylko dostał rozkaz
var _gun_ang := PackedFloat32Array()   # kąt lufy każdego działa (obraca się powoli za celem)   # czworobok: piechota stoi pustym kwadratem, front na wszystkie strony (przeciw jeździe)
var _trail := PackedVector2Array()  # ślad prowadzącego kolumny (od czoła do tyłu)
var _path_trail := PackedVector2Array()  # ślad środka pułku w marszu (od najnowszego) - droga dla zablokowanych
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
	# piechota gracza domyślnie strzela tylko na rozkaz; artyleria i AI - według uznania
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
	## Najbliższy punkt śladu środka pułku, przesunięty trochę w stronę czoła - prowadzi dookoła przeszkody.
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
	# drugi szereg może się przerzedzić do połowy, dopiero potem front skraca się - co 2 szeregi naraz.
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
	return _square_slot_at(i, n, center, facing)


func _square_slot_at(i: int, n: int, c: Vector2, f: float) -> Vector2:
	var k := _square_k(n)
	var rank := mini(i / (4 * k), 1)
	var j := i % (4 * k)
	var along := (float(j % k) - (k - 1) * 0.5) * spacing
	var off := _square_half(n) - rank * rank_spacing
	var out := Vector2.from_angle(f + (j / k) * PI * 0.5)
	return c + out * off + out.orthogonal() * along


func preview_slot(i: int, n: int, pos: Vector2, f: float, files: int) -> Vector2:
	## Miejsce i-tego żołnierza w podglądzie rozkazu - w tym samym szyku, w jakim pułk stanie u celu.
	if wedge:
		return _wedge_slot_at(i, n, pos, f)
	if square:
		return _square_slot_at(i, n, pos, f)
	if kind == "art":
		return art_slot_for(i, n, pos, f, files, spacing)
	return slot_pos_for(i, n, pos, f, files, spacing, rank_spacing)


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
	return _wedge_slot_at(i, n, center, facing)


func _wedge_slot_at(i: int, n: int, c: Vector2, f: float) -> Vector2:
	## Rząd r ma 2r+1 jeźdźców (1, 3, 5...), ostrze klina na froncie; ostatni rząd wyśrodkowany.
	var r := int(floor(sqrt(float(i))))
	var k := i - r * r
	var in_row := mini(2 * r + 1, n - r * r)
	var x := (float(k) - float(in_row - 1) * 0.5) * spacing
	var depth := float(_wedge_rows(n) - 1) * rank_spacing
	var fwd := Vector2.from_angle(f)
	return c + fwd.rotated(PI * 0.5) * x + fwd * (depth * 0.5 - float(r) * rank_spacing)


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
	_square_ok = false
	_cohesion = 99.0   # do pierwszego przeliczenia: szyk w rozsypce (ludzie dopiero biegną na miejsca)
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
		return _wedge_slot(i, count) + _jit_world(i) * 0.3 * jitter_scale
	if square:
		return _square_slot(i, count) + _jit_world(i) * 0.3
	if kind == "art":
		# obsługa trzyma się SWOJEGO działa (tam, gdzie ono faktycznie jest), nie umownej linii baterii
		var guns := art_gun_count(count, base_files)
		var fw := Vector2.from_angle(facing)
		var off: Vector2 = ART_CREW[mini(i / guns, ART_CREW.size() - 1)]
		var g := i % guns
		if _manhandled(g):
			# działo jest toczone: obsługa staje przy kołach i ogonie lawety i idzie razem z nim
			var gdv := Vector2.from_angle(gun_angle(g) - PI * smoothstep(0.0, 1.0, _gun_swing))
			var hp: Vector2 = ART_HANDLE[mini(i / guns, ART_HANDLE.size() - 1)]
			return gun_pos(g) + gdv.rotated(PI * 0.5) * hp.x - gdv * hp.y
		return gun_pos(g) + fw.rotated(PI * 0.5) * off.x - fw * off.y + _jit_world(i) * 0.5
	return slot_pos_for(i, count, center, facing, base_files, spacing, rank_spacing) + _jit_world(i)


# Obsługa działa rozstawiona wokół niego: (w prawo, do tyłu) względem osi działa.
const ART_CREW := [Vector2(0, 20), Vector2(-9, 3), Vector2(9, 3), Vector2(-7, 26), Vector2(7, 26), Vector2(0, 32)]
# Przetaczanie działa rękami: dwóch przy kołach (pchają za szprychy), reszta przy ogonie lawety.
const ART_HANDLE := [Vector2(1.8, 21.5), Vector2(-9.4, 1.5), Vector2(9.4, 1.5), Vector2(-3.6, 13.0), Vector2(3.6, 13.0), Vector2(-1.8, 22.5)]
const RIG_AWAY := 46.0        # po odczepieniu działa zaprzęg odjeżdża jeszcze tyle dalej na tyły
var _handle_wait := 0.0       # jak długo działa czekają na ludzi przy kołach (łącznie, od ostatniego marszu)
var _await_load := false      # bateria była w marszu: po rozstawieniu obsługa musi najpierw naładować działa


func _off_guns(q: Vector2, goal: Vector2, stepl: float) -> Vector2:
	## Obsługa nie chodzi po działach: punkt wypychany w bok poza koła, lufę i ogon lawety własnej baterii.
	for g in _gun_p.size():
		var gp := _gun_p[g]
		if q.distance_squared_to(gp) > 500.0:
			continue
		var d := Vector2.from_angle(gun_angle(g) - PI * smoothstep(0.0, 1.0, _gun_swing))
		var sd := d.rotated(PI * 0.5)
		var rel := q - gp
		var along := rel.dot(d)
		var lat := rel.dot(sd)
		var hw := 0.0
		if absf(along) < 6.0:
			hw = 8.4                      # koła i oś
		elif along > -19.0 and along < 17.0:
			hw = 2.7                      # lufa z przodu, ogon lawety z tyłu
		if hw > 0.0 and absf(lat) < hw:
			q += sd * ((hw if lat >= 0.0 else -hw) - lat)
			# cel po drugiej stronie działa: idzie wzdłuż niego do bliższego końca i obchodzi dookoła
			var glat := (goal - gp).dot(sd)
			if absf(glat) > 1.0 and (glat >= 0.0) != (lat >= 0.0):
				q += d * (stepl if along > 0.0 else -stepl)
	return q


func _manhandled(g: int) -> bool:
	## Działo jest właśnie toczone / obracane przez obsługę (nie stoi na stanowisku i nie wisi na haku).
	if limber_u >= 1.0 or state == State.ROUTING or g >= _gun_p.size():
		return false
	return _gun_swing > 0.04 or _gun_p[g].distance_squared_to(gun_base(g)) > 9.0


func _handlers_ready(g: int) -> bool:
	## Czy ludzie od kół doszli już do działa (bez nich działo się nie toczy).
	var guns := gun_count()
	var n := s_pos.size()
	for role in [1, 2]:
		var idx: int = g + guns * role
		if idx < n and s_pos[idx].distance_squared_to(slot_pos(idx, n)) > 64.0:
			return false
	return true


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


static func file_x(k: int, f: int) -> float:
	## Miejsce w szeregu liczone od środka na boki (0, +1, -1, +2, ...). Dzięki temu ten sam numer w każdym
	## szeregu to ten sam plik (żołnierz z tyłu stoi dokładnie za tym z przodu), a po stratach ubywa
	## skrajnych miejsc ostatniego szeregu - reszta pułku stoi, gdzie stała.
	if f % 2 == 1:
		return float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
	return (0.5 + float(k / 2)) if k % 2 == 1 else (-0.5 - float(k / 2))


static func slot_pos_for(i: int, count: int, c: Vector2, f_angle: float, bf: int, sp: float, rsp: float) -> Vector2:
	var f := files_for_base(count, bf)
	var x := file_x(i % f, f) * sp
	var y := float(i / f) * rsp
	var fwd := Vector2.from_angle(f_angle)
	return c + fwd.rotated(PI * 0.5) * x - fwd * y


func set_facing(f: float) -> void:
	## Zmiana kierunku: szyk nie obraca się jak bryła - żołnierze sami przechodzą na najbliższe nowe miejsca.
	facing = f
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
		# miejsca w szeregu są numerowane od środka - k-ty od lewej żołnierz dostaje k-te od lewej miejsce
		var m := chunk.size()
		var ks: Array = range(m)
		ks.sort_custom(func(a: int, b: int) -> bool: return file_x(a, f) < file_x(b, f))
		var placed: Array = []
		placed.resize(m)
		for j in m:
			placed[ks[j]] = chunk[j]
		final.append_array(placed)
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
	## a żołnierze dopiero tam idą - rysowanie, sztandar i cele szarży muszą trzymać się ludzi, nie celu.
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
	if kind == "art" and state == State.MELEE:
		if team == 0:
			battle.message("%s: the gunners are fighting for their lives - the battery cannot move" % reg_name)
		return   # obsługa walczy przy działach: nie zaprzęgnie ich ani nie przetoczy pod szablami
	# rozkaz bez podanej szerokości = normalny szyk (nie ten zwężony na moście); podana szerokość staje się normalną
	if files > 0:
		_wide_files = files
	else:
		files = _wide_files
	if _direct and state == State.MOVING:
		# nowy rozkaz w trakcie przejścia: `center` stoi już na starym celu, a ludzie dopiero tam idą -
		# trasa i szyk muszą wyjść z miejsca, gdzie pułk faktycznie jest, inaczej najpierw szedłby na stary cel
		center = anchor()
		_direct = false
	if state == State.MELEE or battle.sim_time < _disengage_until:
		_disengage_until = battle.sim_time + 7.0   # odwrót z walki: przez chwilę nikt nas nie wiąże zwarciem
		center = centroid()
	_final_facing = f
	speed_cap = cap
	if square:
		_resquare = true   # u celu pułk znów stanie w czworoboku (tak jak pokazuje podgląd)
	square = false   # w marszu czworobok się rozwiązuje
	# Trasa: prosto do celu. Jedyny wyjątek to rzeka - głęboki nurt da się przejść tylko w brodzie przy moście,
	# więc linia łamie się na przeprawie (most/bród) i dalej znów biegnie prosto.
	# Cel kliknięty w górach przesuwa się na najbliższe podnóże, w nurcie - na brzeg.
	pos = EdgeFog.clamp_inside(pos, battle.map_size)   # pas przy krawędzi mapy jest niedostępny
	var tgt := battle.terrain.bank_point(battle.terrain.free_point(pos))
	var half_w := float((files if files > 0 else base_files) - 1) * spacing * 0.5
	var r := battle.terrain.crossing_route(center, tgt, half_w, 0, kind != "art")
	# Ruch w pełni ręczny: oddział idzie tam, gdzie kazano, w szyku - tak samo po polu i po drodze.
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
	# żołnierz idzie prosto na swoje nowe miejsce (najbliższe - bez krzyżowania), swoim tempem. Szybsi docierają
	# wcześniej i czekają w szeregu, aż dojdzie reszta. Nie ma sztywnego bloku ani obracania całości na końcu.
	_direct = false
	if kind != "art" and not wedge and waypoints.size() == 1 and not r["bridge"] and to.length() < DIRECT_MAX:
		_begin_direct(pos, f)


func _can_flow_in() -> bool:
	## Czy pułk może zakończyć marsz przejściem wprost na miejsca (nie bateria, nie klin, nie kolumna, nie w wodzie).
	return kind != "art" and not wedge and not _in_column and not _forming and in_water_ratio < 0.02 		and battle.sim_time >= _disengage_until


func _begin_direct(pos: Vector2, f: float) -> void:
	_direct = true
	_direct_t = 0.0
	_direct_best = INF
	_direct_stall = 0.0
	_apply_pending_files()
	center = pos
	move_target = pos
	move_facing = f
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
	## Rusza od razu - żołnierze dołączają do kolumny w marszu.
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
	if kind == "inf" and fire_mode == FIRE_SHOOT and state != State.MELEE:
		# tryb "tylko ogień": pułk podchodzi na zasięg, staje frontem do celu i strzela - bez szarży
		focus_target = target
		_shout_fire = Battle.nation(team) == 0
		var sdir := (target.center - center).normalized()
		if center.distance_to(target.center) <= fire_range * 0.95 + target.formation_width() * 0.3:
			if state == State.MOVING or state == State.CHARGING:
				waypoints.clear()
				attack_target = null
				_set_idle()
			if not square and absf(angle_difference(facing, sdir.angle())) > FIRE_ARC * 0.6:
				move_facing = sdir.angle()
				set_facing(sdir.angle())
			return
		order_move(target.center - sdir * fire_range * 0.85, sdir.angle())
		focus_target = target
		return
	# Wróg już związany walką wręcz: nie ma do czego strzelać (trafialibyśmy swoich) - rozkaz ataku to od razu
	# szarża na bagnety, żeby drugi i trzeci pułk dołączały do starcia jednym kliknięciem.
	if kind == "inf" and fire_mode != FIRE_MELEE and focus_target != target and state != State.MELEE and target.state != State.MELEE 			and center.distance_to(target.center) <= fire_range + target.formation_width() * 0.5:
		# wróg w zasięgu: pierwszy rozkaz = "ognia do nich!" (stoi i strzela), drugi = szarża na bagnety
		focus_target = target
		_shout_fire = Battle.nation(team) == 0
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
	_resquare = false
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
		_charge_contact_t = -1.0   # nowa szarża: rozpęd od zera, przejazd po pierwszym kontakcie liczony od nowa
		if Battle.nation(team) == 0:
			battle.sfx.voice("charge", center)   # sygnał do szarży (jazda i piechota na bagnety)


func order_ammo(a: int) -> void:
	## Rodzaj pocisków baterii. Kule: daleko i celnie, koszą szeregi. Granaty: wybuchają u celu (rażą obszar),
	## ale są mniej celne i wolniej się je ładuje. Kartacze: tylko z bliska, grad kul w stożku.
	if kind != "art":
		return
	ammo = clampi(a, 0, AMMO_NAMES.size() - 1)
	if Net.is_client():
		Net.inst.cmd(["ammo", net_id, ammo])


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
		var r := rate
		if limber_u >= 1.0 and g < _team_p.size():
			# działo na haku: jedzie za przodkiem jak przyczepa
			var tv := _team_p[g] - _gun_p[g]
			if tv.length_squared() > 1.0:
				want = tv.angle()
			r = 4.0 * dt
		elif limber_u > 0.0 or _gun_swing > 0.01:
			r = 1.0 * dt   # przy składaniu/rozkładaniu lufa spokojnie wraca na wprost
		elif fire_target != null and not fire_target.dead:
			var a := (fire_target.center - gun_pos(g)).angle()
			if absf(angle_difference(facing, a)) < FIRE_ARC:
				want = a
		_gun_ang[g] = rotate_toward(_gun_ang[g], want, r)


func _rig_park() -> float:
	## Jak daleko za linią dział stoją zaprzęgi (zaczep przodka), gdy bateria jest rozłożona.
	return 40.0 + float(_art_pairs()) * 6.0


func guns_settled() -> bool:
	## Działa stoją na stanowiskach lufami do przodu (można strzelać).
	if _gun_swing > 0.05:
		return false
	var guns := gun_count()
	if _gun_p.size() != guns:
		return true
	for g in guns:
		if _gun_p[g].distance_squared_to(gun_base(g)) > 36.0:
			return false
	return true


func _update_guns(dt: float) -> void:
	## Ruch dział i zaprzęgów bez "baletu": nic nie przeskakuje i nic nie kręci się w kółko.
	##  - rozłożone: działo stoi na stanowisku; po zmianie frontu obsługa PRZETACZA je na nowe miejsce
	##  - składanie: obsługa odwraca działo ogonem do przodu, zaprzęg podjeżdża PROSTO swoim pasem obok działa,
	##    działo dotaczane jest na hak
	##  - marsz: zaprzęg ciągnie działo jak przyczepę
	##  - rozkładanie: zaprzęg zostaje, gdzie stanął; obsługa wytacza działo do przodu na stanowisko
	var guns := gun_count()
	# Linia dział: w marszu i przy składaniu idzie za frontem baterii; rozłożona stoi, jak stanęła.
	# Dopiero gdy front odwróci się naprawdę mocno (ponad ~80°), obsługa przetacza działa na nową linię.
	if _line_ang == INF or state == State.MOVING or limber_u > 0.0 or absf(angle_difference(_line_ang, facing)) > 1.4:
		_line_ang = facing
	var fwd := Vector2.from_angle(_line_ang)
	var rgt := fwd.rotated(PI * 0.5)
	var park := _rig_park()
	if _gun_p.size() != guns:
		var old := _gun_p.size()
		_gun_p.resize(guns)
		_team_p.resize(guns)
		_team_ang.resize(guns)
		for g in range(old, guns):
			var b0 := gun_base(g)
			_gun_p[g] = b0
			_team_p[g] = b0 - fwd * park + rgt * RIG_LANE
			_team_ang[g] = facing
	if limber_u > _last_limber_u + 0.00001:
		if _last_limber_u <= 0.0:
			_rig_lag = 0.0
		_limbering = true
	elif limber_u < _last_limber_u - 0.00001:
		_limbering = false
	_last_limber_u = limber_u
	var limbered := limber_u >= 1.0
	var packing := limber_u > 0.0 and not limbered and _limbering
	if limbered and state == State.MOVING and reg_vel.length_squared() > 9.0:
		_rig_lag = move_toward(_rig_lag, park + RIG_HOOK, 10.0 * dt)   # w marszu zaprzęgi zostają nieco za linią
	var horse := base_key == "horse_art"
	var far := 0.0
	for g in guns:
		var base := gun_base(g)
		var tp := _team_p[g]
		var gp := _gun_p[g]
		if tp.distance_squared_to(base) > 360000.0 or gp.distance_squared_to(base) > 360000.0:
			# bateria znalazła się gdzie indziej (np. dane z sieci) - bez jazdy przez pół mapy
			gp = base
			tp = base - fwd * park + rgt * RIG_LANE
			_team_ang[g] = facing
		if limbered:
			var tt := base + fwd * (RIG_HOOK - _rig_lag) + rgt * RIG_LANE
			var before := tp
			tp = tp.move_toward(tt, 90.0 * dt)
			var mv := tp - before
			if mv.length() > 0.08:
				_team_ang[g] = rotate_toward(_team_ang[g], mv.angle(), 2.2 * dt)
			gp = gp.move_toward(tp - Vector2.from_angle(_team_ang[g]) * RIG_HOOK, 45.0 * dt)
		elif packing:
			var tt2 := base + fwd * RIG_HOOK + rgt * RIG_LANE
			if limber_u > 0.2:
				var d := tp.distance_to(tt2)
				if d > 6.0:
					_team_ang[g] = rotate_toward(_team_ang[g], (tt2 - tp).angle(), 1.5 * dt)
				tp = tp.move_toward(tt2, (park + RIG_AWAY + RIG_HOOK) / (limber_time() * 0.5) * dt)
				if d < 1.0:
					gp = gp.move_toward(tp - Vector2.from_angle(_team_ang[g]) * RIG_HOOK, (22.0 if horse else 16.0) * dt)
		else:
			# zaprzęg stoi; działo wraca/idzie na stanowisko - najpierw w bok z pasa zaprzęgu, potem prosto
			var push := (26.0 if horse else 17.0) if _gun_swing > 0.01 else maxf(10.0, walk_speed * 1.4)
			if state != State.ROUTING and not _handlers_ready(g):
				_handle_wait += dt
				if _handle_wait < 3.0 * float(guns):
					push *= 0.12   # działo rusza dopiero, gdy obsługa złapie za koła (ale nie czeka w nieskończoność)
			if _gun_swing < 0.5 and state != State.MOVING:
				# odczepione: woźnice odprowadzają zaprzęg łukiem dalej za baterię, żeby konie nie stały pod ogniem
				var away := base - fwd * (park + RIG_AWAY) + rgt * RIG_LANE
				var to_away := away - tp
				if to_away.length() > 7.0:
					_team_ang[g] = rotate_toward(_team_ang[g], to_away.angle(), 1.1 * dt)
					tp += Vector2.from_angle(_team_ang[g]) * 16.0 * maxf(0.25, cos(angle_difference(_team_ang[g], to_away.angle()))) * dt
			var rel := gp - base
			var lat := rel.dot(rgt)
			var along := rel.dot(fwd)
			if _gun_swing > 0.5 and absf(lat) > 1.0 and along < -30.0:
				gp = gp.move_toward(gp - rgt * lat, push * dt)
			else:
				gp = gp.move_toward(base, push * dt)
			far = maxf(far, gp.distance_to(base))
		_team_p[g] = tp
		_gun_p[g] = gp
	if limbered:
		_gun_swing = move_toward(_gun_swing, 1.0, dt / 1.5)
		_handle_wait = 0.0
		_await_load = true
	elif packing:
		_gun_swing = move_toward(_gun_swing, 1.0, dt / (limber_time() * 0.35))
	elif far < 30.0:
		_gun_swing = move_toward(_gun_swing, 0.0, dt / (2.2 if horse else 3.2))   # "action front": obsługa obraca działo lufą na wroga
	if _await_load and limber_u <= 0.0 and guns_settled():
		# działa stoją na stanowiskach, ale są puste: pierwsza salwa dopiero po pełnej musztrze ładowania
		_await_load = false
		for g in mini(guns, s_reload.size()):
			s_reload[g] = maxf(s_reload[g], reload_time * randf_range(0.8, 0.95))
		last_fire_time = battle.sim_time


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
	_charge_contact_t = -1.0
	if _resquare and state == State.MOVING and kind == "inf":
		_resquare = false
		state = State.IDLE
		_idle_since = battle.sim_time
		order_square(true)
		return
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
			officer_alive = true   # podoficer przejmuje komendę - znów salwy
	_update_rank_swap()
	_update_volley()
	if kind == "art" and state != State.MOVING and limber_u > 0.0:
		limber_u = maxf(0.0, limber_u - dt / unlimber_time())   # rozkładanie dział po zatrzymaniu
	if kind == "art":
		_update_guns(dt)
		_update_gun_aim(dt)
	_remove_dead()
	if s_pos.is_empty():
		_die()
		return
	_think_timer -= dt
	var t0 := Time.get_ticks_usec() if Battle.PROF else 0
	if _think_timer <= 0.0:
		_think_timer = randf_range(0.2, 0.3)
		_think()
		if Battle.PROF:
			Battle.pf("r_think", t0)
	_move(dt)
	# Żołnierze liczeni najwyżej raz na klatkę (z sumowanym czasem): gdy klatka trwa długo i symulacja robi kilka
	# kroków naraz, pośrednie i tak nie są widoczne - to zatrzymuje spiralę spowolnienia w wielkich bitwach.
	# Widoczne pułki co klatkę (min. 20 razy/s), pułki poza ekranem 10 razy/s.
	_soldier_acc += dt
	if (visible and (battle.last_step or _soldier_acc >= 0.05)) or _soldier_acc >= 0.1:
		if Battle.PROF:
			t0 = Time.get_ticks_usec()
		_update_soldiers(_soldier_acc)
		_soldier_acc = 0.0
		if Battle.PROF:
			Battle.pf("r_soldiers", t0)
	if kind == "cav" and state == State.CHARGING and not _old_charge:
		if Battle.PROF:
			t0 = Time.get_ticks_usec()
		_charge_contacts()
		if Battle.PROF:
			Battle.pf("r_charge", t0)
	_update_morale(dt)
	_update_stamina(dt)


func stamina_f() -> float:
	return stamina / 100.0


func _update_stamina(dt: float) -> void:
	## Kondycja: marsz męczy lekko, bieg/szarża i walka wręcz mocno; stojąc odpoczywa (w kwaterach szybciej).
	## Zmęczony pułk wolniej biega, wolniej ładuje, słabiej walczy i szarżuje - nie da się wiecznie rzucać tych samych ludzi.
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
	# Martwego żołnierza zastępuje ten zza jego pleców - "zamykanie szeregów".
	var removed := false
	var files0 := files_for(s_pos.size())
	var i := s_pos.size() - 1
	while i >= 0:
		if s_hp[i] <= 0.0:
			# dowódca też może paść: pułk traci rytm salw, dopóki komendy nie przejmie podoficer
			if kind == "inf" and officer_alive and randf() < 1.0 / maxf(s_pos.size(), 1.0):
				officer_alive = false
				_officer_back = randf_range(18.0, 32.0)
				morale -= 5.0 / discipline
				if team == 0:
					battle.message("%s: officer down - firing at will" % reg_name)
			# chorąży stoi za szykiem, ale też ginie: utrata sztandaru mocno uderza w morale
			if kind != "art" and _flag_down <= 0.0 and randf() < 1.0 / maxf(s_pos.size(), 1.0):
				_flag_down = randf_range(4.0, 8.0)
				morale -= 7.0 / discipline
			if not battle.terrain.is_water(s_pos[i]):
				battle.corpses.add_corpse(s_pos[i], _uniform()["coat"], s_aim[i], kind == "cav", sprite_key())
			var last := s_pos.size() - 1
			var hole := i
			if kind != "art" and not square and not wedge and state != State.ROUTING:
				# Zamykanie szeregu: na miejsce poległego wchodzi ten, kto stał ZA nim (ten sam plik), za niego
				# następny... Rusza się tylko jeden plik o krok do przodu - szereg nie przesuwa się w bok.
				var cf := files_for(last + 1)
				while hole + cf <= last:
					_copy_soldier(hole + cf, hole)
					hole += cf
			if hole != last:
				_copy_soldier(last, hole)   # lukę w ostatnim szeregu zajmuje skrajny żołnierz tego szeregu
			removed = true
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
	if removed and kind != "art" and not square and not wedge and state != State.ROUTING 			and not s_pos.is_empty() and files_for(s_pos.size()) != files0:
		_reform()   # front się skrócił: każdy na najbliższe miejsce w nowym szyku (raz na wiele strat)


func _copy_soldier(from: int, to: int) -> void:
	s_pos[to] = s_pos[from]
	s_hp[to] = s_hp[from]
	s_reload[to] = s_reload[from]
	s_cool[to] = s_cool[from]
	s_aim[to] = s_aim[from]
	s_vel[to] = s_vel[from]
	s_tgt_reg[to] = s_tgt_reg[from]
	s_tgt_idx[to] = s_tgt_idx[from]
	s_block[to] = s_block[from]


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


func _disengage_pace() -> float:
	## Tempo odrywania się od wroga (ułamek biegu): jazda odjeżdża pełnym galopem, piechota biegiem.
	return 1.0 if kind == "cav" else 0.75


func _contact_count(e: Regiment, limit_sq: float, enough: int) -> int:
	## Ilu naszych żołnierzy stoi w zasięgu ciosu od kogoś z pułku e (liczenie przerwane po `enough`).
	var c := 0
	for a in s_pos.size():
		if s_hp[a] <= 0.0:
			continue
		var p := s_pos[a]
		for q in e.s_pos:
			if p.distance_squared_to(q) < limit_sq:
				c += 1
				if c >= enough:
					return c
				break
	return c


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
	melee_enemies_prev.assign(melee_enemies)
	melee_enemies.clear()
	var my_r := formation_width() * 0.5 + formation_depth() + 20.0 + (_cohesion * 2.5 if _direct else 0.0)
	var ed := engage_dist()
	var my_box := Rect2()
	for e in battle.regiments:
		if e.team == team or e.dead:
			continue
		if e.state == State.ROUTING and not _pursues(e):
			continue
		if now < e._disengage_until and e.kind != "art" and not (kind == "cav" and attack_target == e):
			continue   # wróg wycofuje się na rozkaz - nie gonimy go zwarciem (chyba że jazda szarżuje właśnie na niego)
		var their_r := e.formation_width() * 0.5 + e.formation_depth() + 20.0
		if anchor().distance_to(e.anchor()) > my_r + their_r + 20.0:
			continue
		# zwarcie jest wzajemne: liczy się większy z zasięgów (jazda sięga dalej). Inaczej jazda już walczyła
		# z piechotą, a piechota - "jeszcze nie w zwarciu" - stała i strzelała do niej salwami z przyłożenia.
		var ed2 := maxf(ed, e.engage_dist())
		if my_box.size == Vector2.ZERO:
			my_box = soldier_rect(ed2 + 2.0)
		if not my_box.intersects(e.soldier_rect(2.0)):
			continue   # prostokąty pułków się nie stykają - nie ma czego liczyć żołnierz po żołnierzu
		if _min_soldier_dist_sq(e, ed2 * ed2) < ed2 * ed2:
			# Zwarcie, gdy ktoś naprawdę atakuje (rozkaz ataku/szarża na ten pułk) albo gdy styka się już kilku ludzi.
			# Samo musnięcie skrzydłem w przemarszu nie wiąże pułku walką.
			var intent := attack_target == e or e.attack_target == self or state == State.MELEE and melee_enemies_prev.has(e) 				or e.state == State.CHARGING or state == State.CHARGING
			if intent or _contact_count(e, ed2 * ed2, CONTACT_PIN) >= CONTACT_PIN:
				melee_enemies.append(e)

	_update_surround()
	_update_support()

	if state == State.ROUTING:
		_update_flee()
		return

	if not melee_enemies.is_empty() and now >= _disengage_until:
		if state == State.CHARGING and kind == "cav" and not _old_charge:
			# Jazda nie staje w miejscu, gdy pierwszy koń dotknie wroga: blok jeszcze przez chwilę pędzi naprzód,
			# każdy jeździec uderza osobno (_charge_contacts). Zwarcie dopiero, gdy konie stracą rozpęd.
			if _charge_contact_t < 0.0:
				_charge_contact_t = now
				_charge_impact(true)   # morale i bezład u wroga od samego uderzenia; straty liczą konie osobno
			if now - _charge_contact_t < CHARGE_THROUGH_T and _momentum > CHARGE_MIN_MOMENTUM:
				return
		# punkt nacisku: najbliższy wrogi żołnierz względem środka naszego frontu
		var bd2 := INF
		for e in melee_enemies:
			for q in e.s_pos:
				var d2 := center.distance_squared_to(q)
				if d2 < bd2:
					bd2 = d2
					_melee_pt = q
		if state != State.MELEE:
			if _direct:
				center = anchor()   # w trakcie przestawiania: szyk staje tam, gdzie faktycznie są ludzie
				_direct = false
			if state == State.CHARGING and (kind != "cav" or _old_charge):
				_charge_impact()
			_charge_contact_t = -1.0
			state = State.MELEE
			fire_target = null
			waypoints.clear()
			move_target = center
		return
	elif state == State.MELEE:
		_set_idle()
		_melee_pt = Vector2.INF
		move_target = center
		move_facing = facing
		attack_target = null

	if state == State.CHARGING and _charge_contact_t >= 0.0 and melee_enemies.is_empty() \
			and (now - _charge_contact_t >= CHARGE_THROUGH_T or _momentum <= CHARGE_MIN_MOMENTUM):
		# szarża przeszła na wylot i nikogo już nie dotyka: jeźdźcy zawracają i szarżują od nowa na ten sam cel
		_charge_contact_t = -1.0
	if state == State.CHARGING and (attack_target == null or attack_target.dead 			or (attack_target.state == State.ROUTING and not _pursues(attack_target))):
		_set_idle()
		attack_target = null
		waypoints.clear()
		move_facing = facing

	# Wybór celu ostrzału (tylko gdy pułk stoi).
	var prev_target := fire_target
	fire_target = null
	if state == State.IDLE and fire_range > 0.0 and not (kind == "inf" and fire_mode == FIRE_MELEE):
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
		if kind == "art" and best != null and prev_target != null and prev_target != best and best != focus_target \
				and not prev_target.dead and prev_target.state != State.ROUTING and (fire_at_will or prev_target == focus_target):
			# Działa nie przeskakują z celu na cel: obracanie lufy trwa, więc bateria strzela do tego, kogo już
			# ma na celowniku, póki jest w zasięgu - chyba że ktoś inny podszedł wyraźnie bliżej.
			var pd := center.distance_to(prev_target.center)
			if pd <= fire_range + prev_target.formation_width() * 0.5 and pd < bd * 1.6 + 60.0 \
					and absf(angle_difference(facing, (prev_target.center - center).angle())) < FIRE_ARC:
				best = prev_target
		if best != null:
			var ang := (best.center - center).angle()
			if square:
				fire_target = best   # czworobok ma front z każdej strony
			elif absf(angle_difference(facing, ang)) < FIRE_ARC:
				fire_target = best
			elif now - _last_autoface > (9.0 if kind == "art" else 4.0):
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
		# czworobok: bagnety z każdej strony - ale dopiero, gdy naprawdę stoi; formowany w ostatniej chwili
		# to tłum biegnący na miejsca, a nie mur bagnetów
		return morale >= 30.0 and square_ready() >= 0.6
	if morale < 55.0:
		return false
	return hit_dir_mult(from) < 1.2


func square_ready() -> float:
	## 0..1: na ile czworobok jest już uformowany (sam rozkaz nie wystarcza - ludzie muszą dojść na miejsca).
	if not square:
		return 0.0
	if _square_ok:
		return 1.0
	return clampf(1.0 - (_cohesion - SQUARE_READY_COH) / 15.0, 0.0, 1.0)


func rank_count() -> int:
	## Głębokość szyku w szeregach (cienka, rozciągnięta linia = 1-2 szeregi).
	var n := s_pos.size()
	if n == 0:
		return 0
	if square:
		return 2
	return ceili(float(n) / float(maxi(1, files_for(n))))


func _pursues(e: Regiment) -> bool:
	## Piechota nie goni uciekających; kawaleria ściga ich tylko przez chwilę.
	return kind == "cav" and battle.sim_time - e._rout_since < 8.0


func _charge_impact(morale_only := false) -> void:
	## Uderzenie szarży: kawaleria zadaje straty i łamie morale, piechota tylko morale.
	## morale_only: jazda - straty zadają konie pojedynczo (_charge_contacts), tu tylko wstrząs, morale i bezład.
	for e in melee_enemies:
		var dm := e.hit_dir_mult(center)
		if kind == "cav":
			# zmęczone konie nie mają rozpędu - szarża z wyczerpania traci połowę siły
			var power := float(Battle.UNIT_TYPES[unit_key].get("charge", 1.6 if base_key == "lancers" else 1.0)) * dm \
				* lerpf(0.45, 1.0, stamina_f()) * (1.2 if wedge else 1.0)
			# Cienka linia (1-2 szeregi) nie zatrzyma koni: jazda przebija ją na wylot. Okrążony pułk nie ma
			# jak zewrzeć szeregów w każdą stronę naraz - szarża wchodzi w niego prawie jak w nieprzygotowany.
			var ranks := e.rank_count()
			var thin := 0.0
			if e.kind == "inf" and not e.square:
				thin = 1.0 if ranks <= 2 else 0.0
			var ringed := clampf((e.sectors_held_by_others(self) - 2) / 4.0, 0.0, 1.0) * (0.5 if e.square else 1.0)
			var open := maxf(thin, ringed)   # 0 = zwarty szyk, 1 = nie ma czym przyjąć szarży
			var braced := e.braced_against(center)
			# rozbicie szyku: szarża, której piechota nie miała czym przyjąć (z boku, z tyłu, w marszu, w trakcie
			# formowania czworoboku, cienka linia, okrążenie), rozrywa szeregi - więcej ofiar i chwila bezładu
			var shock := open if braced else 1.0
			if e.kind == "cav":
				shock = 0.0   # jazda z jazdą: zwykłe starcie
			if braced:
				# Zwarta piechota od frontu: konie nie wchodzą na bagnety - szarża słabnie, jeźdźcy padają.
				var hold := 0.2 if e.square else (0.4 if ranks >= 4 else 0.5)
				power *= lerpf(hold, 1.0, open)
				morale -= (18.0 if e.square else 12.0) / discipline * (1.0 - open)
				var lost := int(randf_range(1.0, 3.0) * float(e.alive_count()) / maxf(1.0, e.initial_count) * 2.0 * (1.0 - open))
				if morale_only:
					lost = 0   # konie, które wpadną na bagnety, giną pojedynczo w _charge_contacts
				for k in lost:
					if s_pos.is_empty():
						break
					var mine := randi() % s_pos.size()
					damage(mine, randf_range(60.0, 130.0))
				battle.effects.add_spark(center)
			if e.kind == "art":
				# bateria nie ma czym przyjąć szarży; złożona na przodkach albo w trakcie rozkładania jest bezbronna
				power *= 2.6 if e.limber_u > 0.0 or e.state == State.MOVING else 1.9
			if e.kind == "inf":
				power *= 1.0 + 0.3 * thin   # przebita linia: konie przechodzą przez szereg i sieką z obu stron
			e.morale -= 13.0 * power * (1.0 + 0.6 * shock) / e.discipline
			if shock > 0.3:
				e._disorder_until = maxf(e._disorder_until, battle.sim_time + 15.0 * shock)
			_charge_shock(e, power, maxf(open, shock), morale_only)
			if morale_only:
				continue
			var hits := int(randf_range(3, 6) * power * (1.0 + 2.5 * shock) * float(s_pos.size()) / initial_count)
			var near := 60.0 + formation_width() * 0.5
			for k in hits:
				if e.s_pos.is_empty():
					break
				# trafia tych, na których szarża faktycznie wpadła (kilka prób, żeby cios nie przepadał w dużym pułku)
				for attempt in 4:
					var j := randi() % e.s_pos.size()
					if e.s_pos[j].distance_to(center) < near:
						# w rozbity szyk konie wpadają pełnym pędem - stratowany rzadko wstaje
						e.damage(j, randf_range(60.0, 130.0) + 40.0 * shock)
						break
		else:
			e.morale -= 6.5 * dm * discipline / e.discipline * lerpf(0.5, 1.0, stamina_f())


func _charge_contacts() -> void:
	## Szarża koń po koniu: każdy jeździec w pędzie, który wpadnie na wrogiego żołnierza, uderza go sam.
	## Skutek zależy od prędkości konia (energia ~ v²), siły szarży, klina i od tego, czy wróg trzyma szyk:
	## rozpędzony koń tratuje i przebija się przez szereg (wróg odepchnięty w bok, koń jedzie dalej wolniej),
	## a na zwartych bagnetach czy w czworoboku zwykle grzęźnie - i sam może paść.
	var foes: Array[Regiment] = []
	var reach := formation_width() * 0.5 + formation_depth() + 60.0
	for e in battle.regiments:
		if e.team == team or e.dead or e.s_pos.is_empty():
			continue
		if e.state == State.ROUTING and not _pursues(e):
			continue
		if center.distance_to(e.centroid()) < reach + e.formation_width() * 0.5 + e.formation_depth():
			foes.append(e)
	if foes.is_empty():
		return
	var base_power := float(Battle.UNIT_TYPES[unit_key].get("charge", 1.6 if base_key == "lancers" else 1.0)) \
		* lerpf(0.55, 1.0, stamina_f()) * (1.2 if wedge else 1.0)
	var now := battle.sim_time
	var hits := 0
	# tylko wrodzy żołnierze w zasięgu naszego pułku (zwykle pierwsze szeregi), nie cały pułk wroga
	var box := soldier_rect(14.0)
	var c_pos := PackedVector2Array()
	var c_reg: Array[Regiment] = []
	var c_j := PackedInt32Array()
	for e in foes:
		for j in e.s_pos.size():
			if e.s_hp[j] > 0.0 and box.has_point(e.s_pos[j]):
				c_pos.append(e.s_pos[j])
				c_reg.append(e)
				c_j.append(j)
	if c_pos.is_empty():
		return
	for i in s_pos.size():
		if s_hp[i] <= 0.0 or s_cool[i] > 0.0:
			continue
		var v := s_vel[i].length()
		if v < run_speed * 0.35:
			continue   # stępa nie ma uderzenia - ten koń walczy już zwyczajnie
		var dir := s_vel[i] / v
		var p := s_pos[i]
		var hit_e: Regiment = null
		var hit_j := -1
		for c in c_pos.size():
			var rel := c_pos[c] - p
			var ahead := rel.dot(dir)
			if ahead < -2.0 or ahead > 10.0 or absf(rel.cross(dir)) > 6.5:
				continue
			if c_reg[c].s_hp[c_j[c]] <= 0.0:
				continue
			hit_e = c_reg[c]
			hit_j = c_j[c]
			break
		if hit_e == null:
			continue
		var e := hit_e
		var j := hit_j
		var sp := clampf(v / run_speed, 0.0, 1.25)
		var energy := sp * sp * base_power
		# opór trafionego: zwarta piechota frontem/czworobok > jazda (masa na masę) > rozbita linia > artyleria
		var res := 0.2
		var braced := false
		if e.kind == "cav":
			res = 0.5 if e.state == State.CHARGING else 0.4
		elif e.kind == "art":
			res = 0.1
		elif e.braced_against(p):
			braced = true
			res = 0.88 if e.square else (0.75 if e.rank_count() >= 4 else 0.62)
		if now < e._disorder_until:
			res *= 0.55
		# tratowany/cięty: szansa i siła rosną z prędkością konia
		if randf() < clampf(0.72 * energy * (1.0 - res * 0.8), 0.04, 0.9):
			e.damage(j, randf_range(55.0, 120.0) * (0.6 + 0.5 * sp))
		e.morale -= 0.4 * energy * (1.0 - res * 0.5) / e.discipline
		# jeździec też ryzykuje: koń wpadający na bagnety, zderzenie z innym koniem
		var back := 0.0
		if braced:
			back = 0.45 * res * (0.5 + 0.5 * sp)
		elif e.kind == "cav":
			back = 0.22 * res * (0.5 + 0.5 * sp)
		if randf() < back:
			damage(i, randf_range(50.0, 120.0))
		# przebicie: rozpędzony koń przechodzi przez szereg, wolny albo na zwartych bagnetach grzęźnie
		var through_p := clampf(1.15 * sp * base_power * (1.0 - res), 0.0, 0.9)
		var rel := e.s_pos[j] - p
		var side := signf(rel.cross(dir))
		if side == 0.0:
			side = 1.0 if randf() < 0.5 else -1.0
		if randf() < through_p:
			e.s_pos[j] += dir.orthogonal() * -side * randf_range(6.0, 11.0) + dir * randf_range(1.5, 5.0)   # odepchnięty na bok
			s_vel[i] *= randf_range(0.6, 0.85)
			s_cool[i] = 0.25   # krótka chwila, zanim ten sam koń znów uderzy
		else:
			e.s_pos[j] += dir * randf_range(1.0, 4.0) * sp   # szereg się ugina, ale trzyma
			s_vel[i] *= 0.12
			s_cool[i] = randf_range(0.9, 1.6)   # ugrzązł: staje i walczy wręcz
		hits += 1
		if randf() < 0.35:
			battle.effects.add_dust(p + dir * 6.0, randf_range(2.0, 3.5), randf_range(4.0, 7.0), dir * randf_range(5.0, 14.0), 0.35)
	if hits > 0:
		e_rest_reset(foes)
		battle.cam.shake(center, minf(1.0 + hits * 0.25, 3.5))


static func e_rest_reset(regs: Array[Regiment]) -> void:
	## Pułki potrącone przez konie muszą przeliczyć szyk (wyjść z szybkiej ścieżki "stoi w miejscu").
	for e in regs:
		e._rest_n = -1


func _charge_shock(e: Regiment, power: float, open := 0.0, light := false) -> void:
	## Fizyczne uderzenie szarży: pierwsze szeregi wroga zostają odrzucone w kierunku natarcia,
	## spod kopyt bucha kurz, ziemia drży. Zwarty czworobok/bagnety trzymają (mała siła = mały odrzut).
	## light: jazda - resztę odrzutu robią pojedyncze konie, tu tylko lekkie zachwianie szeregu.
	var dir := forward()
	var reach := 26.0 + 30.0 * open   # przebicie cienkiej linii: uderzenie sięga przez cały szyk
	var push := clampf(power, 0.2, 2.2) * 5.0 * (1.0 + 0.6 * open) * (0.35 if light else 1.0)
	var hit := 0
	for j in e.s_pos.size():
		var q := e.s_pos[j]
		var rel := q - center
		var ahead := rel.dot(dir)
		if ahead < -6.0 or ahead > reach or absf(rel.dot(dir.orthogonal())) > formation_width() * 0.5 + 6.0:
			continue
		var k := 1.0 - clampf(ahead / reach, 0.0, 1.0)
		e.s_pos[j] = q + dir * push * k + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * push * 0.25 * k
		hit += 1
	e._rest_n = -1
	if hit == 0:
		return
	var hw := formation_width() * 0.5
	for k in clampi(int(hw / 9.0), 4, 22):
		var p := center + dir.orthogonal() * randf_range(-hw, hw) + dir * randf_range(-4.0, 10.0)
		battle.effects.add_dust(p, randf_range(2.5, 4.5), randf_range(5.0, 9.0), dir * randf_range(6.0, 18.0), 0.4)
	battle.cam.shake(center, 2.0 + power)
	if e.kind != "cav":
		battle.sfx.ball_impact(center)   # starcie jazdy z jazdą - bez dźwięku


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
		tmult = 0.6   # środek szyku otarł się o zbocze - to punkt umowny, nie może utknąć (żołnierze sami omijają góry)
	if in_water_ratio > 0.08:
		# przeprawa wpław: dopóki część ludzi brodzi, cały pułk idzie ich tempem (nie zostawia ich w rzece)
		tmult = minf(tmult, Terrain.mult_for(Terrain.WATER, kind))
	_tmult = tmult
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
				# pierwsze chwile: _cohesion to jeszcze stara wartość (0 = stał w szyku) - nie może być punktem odniesienia,
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
				limber_u = minf(1.0, limber_u + dt / limber_time())   # bez obrotu w miejscu - zaprzęg skręca w marszu
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
			elif d < DIRECT_MAX and waypoints.size() <= 1 and _can_flow_in():
				# Ostatni odcinek: pułk nie dochodzi blokiem, żeby dopiero na miejscu się obracać - szyk "staje"
				# od razu w docelowym miejscu i kierunku, a każdy żołnierz idzie prosto na swoje najbliższe miejsce.
				# Bliżsi stają pierwsi, reszta dochodzi.
				_begin_direct(move_target, _final_facing)
			elif d > 0.5:
				var dir := to / d
				var base_spd := walk_speed * move_mult()
				if speed_cap > 0.0:
					base_spd = minf(base_spd, speed_cap)   # dywizja maszeruje razem - tempem najwolniejszego
				if battle.sim_time < _disengage_until:
					base_spd = maxf(base_spd, run_speed * _disengage_pace())   # odwrót z walki biegiem (jazda galopem)
				var spd := base_spd * tmult * lerpf(0.8, 1.0, stamina / 100.0)
				if _in_column:
					# kolumna: na drodze dużo szybciej; czeka na ogon, gdy się rozciągnie
					spd = walk_speed * move_mult() * Terrain.mult_for(battle.terrain.cell_at(center), kind, true)
					spd *= clampf(1.4 - _cohesion / 25.0, 0.55, 1.0)  # tylko lekko czeka na dołączających
					facing = rotate_toward(facing, dir.angle(), 3.0 * dt)
				else:
					# W marszu szyk nie musi być idealny - zwalniamy dopiero, gdy ludzie mocno odstają.
					var wait := clampf(1.25 - _cohesion / 40.0, 0.6, 1.0)
					if _cohesion > 45.0 and _wait_t < 5.0:
						wait = 0.1   # część ludzi została za zboczem/przeszkodą - chwilę czekamy, aż dojdą
						_wait_t += dt
					elif _cohesion < 20.0:
						_wait_t = 0.0
					spd *= wait
				if not _in_column and kind != "art":
					# smycz: środek pułku nie odjeżdża od żołnierzy (np. gdy część utknęła przy górach) -
					# czeka na nich; gdy przez dłuższą chwilę nie da się dojść, pułk staje tam, gdzie są ludzie
					var lead := center.distance_to(centroid())
					var leash := maxf(45.0, formation_depth() + 30.0)
					if lead > leash:
						spd *= clampf(1.0 - (lead - leash) / 30.0, 0.0, 1.0)
						# Rozkaz przepada TYLKO wtedy, gdy ludzie naprawdę utknęli na przeszkodzie terenowej (skały).
						# Zwykłe opóźnienie - przeprawa, omijanie sojuszników, zamykanie szyku - to tylko postój:
						# środek czeka, ludzie dochodzą i pułk idzie dalej tam, gdzie mu kazano.
						if in_water_ratio < 0.02 and _blocked_n * 5 > s_pos.size():
							_leash_t += dt
						if _leash_t > 8.0:
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
					facing = move_facing   # nowa linia baterii; każde działo obsługa przetacza na swoje stanowisko
					_rest_n = -1
				elif was_column:
					# czoło kolumny staje w środku nowej linii
					set_facing(move_facing)
				elif widen or absf(angle_difference(facing, move_facing)) > 0.05:
					set_facing(move_facing)
		State.CHARGING when kind == "cav" and _charge_contact_t >= 0.0:
			# przejazd szarży: blok pędzi dalej prosto przed siebie, tym wolniej, im więcej koni ugrzęzło w szeregu wroga
			var spd := run_speed * lerpf(0.6, 1.0, stamina / 100.0) * clampf(_momentum, 0.0, 1.0)
			center += forward() * spd * tmult * dt
			move_facing = facing
		State.CHARGING:
			# do celu prosto; przez rzekę - najpierw na przeprawę (punkty trasy), potem dalej na wroga
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
			# Linia napiera: front podchodzi do najbliższego wroga i tam się trzyma. Walczą ci, którzy mają
			# przeciwnika przed sobą; reszta stoi w szeregach i wchodzi w luki po poległych.
			if _melee_pt != Vector2.INF and not square:
				var tm := _melee_pt - center
				var dm := tm.length()
				if dm > 10.0:
					center += tm / dm * minf(dm - 10.0, walk_speed * 0.45 * tmult * dt)
					var da := angle_difference(facing, tm.angle())
					if absf(da) < 0.9 and dm > 18.0:
						facing = rotate_toward(facing, tm.angle(), 0.25 * dt)   # drobne równanie frontu do wroga
					_rest_n = -1
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
	## Szarżująca jazda wzbija gęsty obłok, maszerująca piechota - delikatny pył przy stopach.
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
		ground *= 0.5   # mokra jesień - mało kurzu
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
	var fire_slots := files if kind == "inf" else gun_count()   # piechota: ogień szeregami - strzela pierwszy szereg
	var in_melee := state == State.MELEE
	_mt_ready = false   # kandydaci do walki wręcz liczeni raz na przebieg, przy pierwszej potrzebie
	var routing := state == State.ROUTING
	var retarget := _retarget
	_retarget = false
	var cohesion_sum := 0.0
	var blocked := 0
	var wet := 0
	var terrain := battle.terrain
	var art_ready := kind == "art" and state == State.IDLE and limber_u <= 0.0
	var rout_speed := run_speed * 1.05
	# Maks. prędkość dochodzenia do miejsca w szyku (spokojny krok, przy szarży szybciej).
	var catch_up := walk_speed * move_mult() * (0.6 if state == State.CHARGING else (1.6 if state == State.MOVING else 1.25))
	if battle.sim_time < _disengage_until:
		catch_up = maxf(catch_up, run_speed * _disengage_pace())
	var column := _in_column and state == State.MOVING
	var col_slots := _column_slots(n) if column else PackedVector2Array()
	# prędkość bloku w "jednostkach bez terenu" (teren pod każdym żołnierzem liczony osobno)
	var base_vel := reg_vel / maxf(_tmult, 0.1)

	# Szybka ścieżka: pułk stoi w gotowym szyku - żołnierze tylko celują, ładują i strzelają.
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
	if _step.size() != n:
		_step.resize(n)
	var reg_block_still := reg_vel.length_squared() < 1.0   # pułk jako całość stoi (albo przestawia się w miejscu)
	var through := kind == "cav" and state == State.CHARGING and _charge_contact_t >= 0.0   # przejazd szarży
	var disengaging := battle.sim_time < _disengage_until and state == State.MOVING
	var fast := 0
	var alive := 0

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
				if not _mt_ready:
					_melee_prep()
				_find_melee_target(i)
				er = s_tgt_reg[i]
				ei = s_tgt_idx[i]
				valid = er != null
			if not valid:
				# nikogo w zasięgu: trzyma miejsce w szeregu (linia jako całość napiera na wroga)
				free_move = false
				if square or wedge or is_art:
					goal = slot_pos(i, n)
				else:
					goal = center + rgt * (file_x(i % nfiles, nfiles) * spacing + s_jit[i].x * jitter_scale) \
						- fwd * (float(i / nfiles) * rank_spacing + s_jit[i].y * jitter_scale)
			else:
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
					# szyk rozbity szarżą: ludzie walczą pojedynczo, bez sąsiadów po bokach
					if battle.sim_time < er._disorder_until:
						chance *= 2.0
					if battle.sim_time < _disorder_until:
						chance *= 0.4
					if er.kind == "art":
						# kanonierzy z wyciorami nie mają szans z szablą i bagnetem; w trakcie zaprzęgania tym bardziej
						chance *= 3.2 if er.limber_u > 0.0 or er.state == State.MOVING else 2.4
						s_cool[i] = minf(s_cool[i], randf_range(1.2, 2.0))
					elif kind == "art":
						chance *= 0.45
					if randf() < chance:
						er.damage(ei, randf_range(30.0, 60.0))
						er.morale -= (dm - 1.0) * 0.6 / er.discipline
						battle.effects.add_spark((p + ep) * 0.5)
					elif randf() < 0.3:
						battle.effects.add_spark((p + ep) * 0.5)  # parada
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
				var sx := file_x(i % nfiles, nfiles) * spacing + s_jit[i].x * jitter_scale
				var sy := float(i / nfiles) * rank_spacing + s_jit[i].y * jitter_scale
				goal = center + rgt * sx - fwd * sy
			if state == State.IDLE and fire_target != null and (i < fire_slots or square):
				var ta := (fire_target.center - p).angle()
				aim += clampf(angle_difference(aim, ta), -SOLDIER_ARC, SOLDIER_ARC)   # tułów obraca się tylko trochę
				# drobne zamykanie szeregu po stratach nie przerywa ognia - strzela, kto stoi prawie w miejscu
				if s_reload[i] <= 0.0 and s_vel[i].length() < (6.0 if kind == "inf" else 2.0) and to_slot_sq(i, goal) < 64.0:
					if kind == "inf":
						if _may_fire(i):
							_fire(i)
							aim = s_aim[i]
					elif art_ready:
						_fire_cannon(i)

		if through and s_cool[i] > RIDER_STUCK:
			# koń ugrzązł w szeregu wroga: nie wraca na miejsce w szyku, staje tam, gdzie uderzył
			free_move = true
			goal = p
		if s_block[i] > 0.0:
			blocked += 1
			s_block[i] -= dt
			if not free_move:
				goal = _trail_goal(p)   # obejście zbocza: śladem, którym przeszedł środek pułku
		if _direct and state == State.MOVING and not free_move:
			free_move = true
			cohesion_sum += p.distance_to(goal)
			spd = walk_speed * move_mult() * lerpf(0.85, 1.0, stamina / 100.0)
			if battle.sim_time < _disengage_until:
				spd = maxf(spd, run_speed * _disengage_pace())   # odwrót z walki: biegiem (jazda galopem), żeby oderwać się od wroga
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
		var speed_now := 0.0
		var v := Vector2.ZERO
		if cav and not routing and dist < HORSE_DRESS and reg_block_still and absf(angle_difference(heading, aim)) < 0.7:
			# Równanie szeregu: koń tuż przy swoim miejscu dochodzi do niego krokiem (także w bok i w tył),
			# a łeb trzyma w stronę frontu. Bez tego jeździec krążyłby wokół miejsca, w które nie umie skręcić.
			var dress := desired.limit_length(HORSE_DRESS_SPEED)
			if dist < 0.8:
				dress = Vector2.ZERO   # już na miejscu: stoi, nie drepcze
			v = s_vel[i].move_toward(dress, accel * dt)
			speed_now = v.length()
			heading = rotate_toward(heading, aim, 1.6 * dt)
		else:
			if cav:
				# koń skręca łukiem (ω = v / R), a stojąc obraca się na zadzie
				var omega := clampf(s_vel[i].length() / HORSE_R, HORSE_PIVOT, HORSE_MAX_TURN)
				if disengaging:
					omega = maxf(omega, 3.2)   # odwrót z walki: jeździec zawraca konia w miejscu, nie kręci wolty między wrogami
				heading = rotate_toward(heading, want_heading, omega * dt)
			else:
				heading = _human_turn(i, heading, want_heading, turn_rate, dt, not routing and not in_melee and state != State.CHARGING)
			var target_speed := 0.0
			if want_speed > 1.5:
				var align := cos(angle_difference(heading, want_heading))
				if cav:
					# im mocniej koń musi skręcić, tym bardziej zwalnia - ciasny zwrot zamiast szerokiego koła
					target_speed = want_speed * clampf((align + 0.15) / 1.15, 0.12, 1.0)
				else:
					target_speed = want_speed * clampf((align - 0.3) / 0.7, 0.0, 1.0)
			if cav and not routing and absf(angle_difference(heading, want_heading)) > 0.35:
				target_speed = maxf(target_speed, HORSE_VOLTE)   # zwrot w ruchu: mała wolta zamiast obrotu wokół własnej osi
			speed_now = move_toward(s_vel[i].length(), target_speed, accel * dt)
			v = Vector2.from_angle(heading) * speed_now
		s_vel[i] = v
		if speed_now > 1.0:
			# rytm kroku rośnie z prędkością łagodnie (marsz ~1.8 kroku/s, bieg ~2.7), faza narasta płynnie -
			# nogi nie przyspieszają skokowo, gdy żołnierz na chwilę zwolni albo dogania szereg
			# Faza kroku = przebyta droga / długość cyklu. Stopa wysunięta w przód "stoi" na ziemi, dopóki ciało
			# nie przejdzie nad nią - dlatego jeden krok piechura to ~8 j. drogi (cykl dwóch kroków = 16 j.).
			# Koń: cykl galopu ~22 j., w szarży krótszy (konie wyciągają nogi szybciej).
			var cycle := STEP_CYCLE
			if cav:
				cycle = GALLOP_CYCLE_CHARGE if state == State.CHARGING else GALLOP_CYCLE
			_step[i] += speed_now * dt / cycle

		# Teren pod nogami: las spowalnia, woda bardzo spowalnia i topi.
		if speed_now < 0.01 and in_water_ratio == 0.0:
			s_vel[i] = Vector2.ZERO
			s_aim[i] = heading
			continue   # stoi na suchym - teren nie ma znaczenia
		var cell := terrain.cell_at(p)
		# Topi się tylko ten, kto wpadł w głęboki nurt rzeki (np. zepchnięty w walce). Jezioro to płytkie rozlewisko:
		# bardzo wolno, ale bez ofiar - trasy idą prosto, więc nie karzemy śmiercią za przejście przez wodę stojącą.
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
		# Zabudowa nie blokuje żołnierzy: szyki przechodzą przez osadę swobodnie (domy bledną, gdy są w niej wojska).
		if kind == "art":
			np = _off_guns(np, goal, maxf(speed_now, 7.0) * dt)   # obsługa obchodzi działa, nie przechodzi po lawetach
		p = np
		s_pos[i] = p
		s_aim[i] = heading

	if through:
		for i in n:
			if s_hp[i] > 0.0:
				alive += 1
				if s_vel[i].length() > run_speed * 0.45 and s_cool[i] <= RIDER_STUCK:
					fast += 1
		_momentum = float(fast) / maxf(1.0, alive)
	else:
		_momentum = 1.0
	in_water_ratio = float(wet) / maxf(1.0, n)
	_blocked_n = blocked
	if not in_melee and not routing:
		_cohesion = cohesion_sum / maxf(1.0, n)
		if square and _cohesion < SQUARE_READY_COH:
			_square_ok = true
	# stojąca w szyku jazda się nie rozpycha - konie stoją spokojnie na swoich miejscach
	if in_melee or routing or (kind == "cav" and (state != State.IDLE or _cohesion > 2.0)):
		var ts := Time.get_ticks_usec() if Battle.PROF else 0
		_separate()   # konie nie wchodzą na siebie także w marszu i przy przestawianiu szyku
		if Battle.PROF:
			Battle.pf("r_separate", ts)


var _react := PackedFloat32Array()   # zwrot żołnierza: 0 = stoi równo, < 0 = jeszcze nie zareagował (czas do ruchu), 1 = obraca się


func _human_turn(i: int, heading: float, want: float, rate: float, dt: float, calm: bool) -> float:
	## Zwrot po ludzku zamiast jednoczesnego obrotu całego szyku jak w zegarku: każdy żołnierz reaguje na komendę
	## z własnym opóźnieniem (ułamek sekundy), obraca się we własnym tempie i wyhamowuje pod koniec zwrotu.
	## W szarży, walce i ucieczce (calm = false) nikt nie zwleka.
	if _react.size() != s_pos.size():
		_react.resize(s_pos.size())
	var diff := absf(angle_difference(heading, want))
	if diff < 0.06:
		_react[i] = 0.0
		return rotate_toward(heading, want, rate)
	var j := s_jit[i]
	var pace := 0.72 + 0.56 * fposmod(j.y * 5.31 + j.x * 1.7, 1.0)          # jedni zwinniejsi, drudzy ociężali
	if not calm:
		_react[i] = 1.0
		return rotate_toward(heading, want, rate * pace)
	if _react[i] == 0.0 and diff > 0.4:
		_react[i] = -(0.03 + fposmod(j.x * 7.31 + j.y * 3.17, 1.0) * 0.6)   # refleks: od razu albo po chwili
	if _react[i] < 0.0:
		_react[i] += dt
		if _react[i] < 0.0:
			return heading
		_react[i] = 1.0
	return rotate_toward(heading, want, rate * pace * clampf(diff / 0.55, 0.3, 1.0))


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
		s_aim[i] = _human_turn(i, s_aim[i], aim, turn_rate, dt, kind != "cav")
		s_vel[i] = Vector2.ZERO


var _mt_pos := PackedVector2Array()   # wrogowie w zasięgu pułku (migawka na ten przebieg)
var _mt_reg: Array = []
var _mt_j := PackedInt32Array()
var _mt_busy := {}                    # (wróg, żołnierz) -> ilu naszych go atakuje
var _mt_reach_sq := 484.0
var _mt_ready := false


func soldier_rect(pad := 0.0) -> Rect2:
	## Prostokąt obejmujący żywych żołnierzy pułku (powiększony o pad).
	if s_pos.is_empty():
		return Rect2(center, Vector2.ZERO)
	var mn := s_pos[0]
	var mx := mn
	for q in s_pos:
		mn = mn.min(q)
		mx = mx.max(q)
	return Rect2(mn - Vector2(pad, pad), mx - mn + Vector2(pad, pad) * 2.0)


func _melee_prep() -> void:
	## Raz na przebieg: lista wrogich żołnierzy w zasięgu ciosu od naszego pułku (zwykle pierwsze szeregi)
	## i licznik, kogo już atakują nasi. Dawniej każdy żołnierz liczył to sam od nowa - kwadratowo na pułk.
	_mt_ready = true
	_mt_pos.clear()
	_mt_reg.clear()
	_mt_j.clear()
	_mt_busy.clear()
	var reach := 30.0 if kind == "cav" else 22.0
	for e in melee_enemies:
		if e.kind == "art":
			reach = 95.0 if kind == "cav" else 60.0   # między działami każdy znajdzie swojego kanoniera
			break
	_mt_reach_sq = reach * reach
	var box := soldier_rect(reach + 2.0)
	for e in melee_enemies:
		if e.dead:
			continue
		var arr := e.s_pos
		for j in arr.size():
			if e.s_hp[j] > 0.0 and box.has_point(arr[j]):
				_mt_pos.append(arr[j])
				_mt_reg.append(e)
				_mt_j.append(j)
	for k in s_pos.size():
		if s_tgt_reg[k] != null:
			var key := Vector2i(s_tgt_reg[k].get_instance_id(), s_tgt_idx[k])
			_mt_busy[key] = int(_mt_busy.get(key, 0)) + 1


func _find_melee_target(i: int) -> void:
	var p := s_pos[i]
	var best_d := INF
	var best_r: Regiment = null
	var best_j := -1
	var old_key := Vector2i(-1, -1)
	if s_tgt_reg[i] != null:
		old_key = Vector2i(s_tgt_reg[i].get_instance_id(), s_tgt_idx[i])
	# ilu naszych już walczy z danym wrogiem - nie rzucamy się całą kupą na jednego (max ~2 na przeciwnika)
	for c in _mt_pos.size():
		var d := p.distance_squared_to(_mt_pos[c])
		if d > _mt_reach_sq:
			continue              # za daleko: ten żołnierz zostaje w szeregu, nie przebija się przez swoich
		var e: Regiment = _mt_reg[c]
		var j := _mt_j[c]
		if j >= e.s_hp.size() or e.s_hp[j] <= 0.0:
			continue
		var key := Vector2i(e.get_instance_id(), j)
		var crowd: int = int(_mt_busy.get(key, 0)) - (1 if key == old_key else 0)
		if crowd >= 2:
			d += 900.0 * crowd    # zajęty przeciwnik: szukaj wolnego obok
		if d < best_d:
			best_d = d
			best_r = e
			best_j = j
	if old_key.x >= 0:
		_mt_busy[old_key] = int(_mt_busy.get(old_key, 1)) - 1
	if best_r != null:
		var nk := Vector2i(best_r.get_instance_id(), best_j)
		_mt_busy[nk] = int(_mt_busy.get(nk, 0)) + 1
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


# --- tryb walki piechoty, zamiana szeregów, ogień własny
const FIRE_AUTO := 0      # strzela, a na rozkaz ataku: najpierw ogień, drugi rozkaz - szarża na bagnety
const FIRE_SHOOT := 1     # tylko ogień: rozkaz ataku = podejść na zasięg i strzelać, bez szarży
const FIRE_MELEE := 2     # tylko walka wręcz: nie strzela, rozkaz ataku = od razu szarża na bagnety
const FIRE_MODE_NAMES := ["Auto", "Fire at will", "Melee only"]
const RANK_SWAP_TIME := 1.8   # tyle trwa zamiana szeregów, zanim nowy pierwszy szereg może dać ognia
const FF_HOLD_DIST := 70.0    # swój tak blisko na linii strzału: żołnierz nie strzela
const FF_CHANCE := 0.5        # dalej stojący swój na linii strzału dostaje kulę z takim prawdopodobieństwem
var fire_mode := FIRE_AUTO
var _swap_at := -100.0
var _shout_fire := false   # gracz dał rozkaz ognia: przy najbliższej salwie oficer krzyknie komendę


func order_fire_mode(mode: int) -> void:
	fire_mode = clampi(mode, 0, 2)
	if Net.is_client():
		Net.inst.cmd(["fmode", net_id, fire_mode])
		return
	if fire_mode == FIRE_SHOOT:
		fire_at_will = true
	elif fire_mode == FIRE_MELEE:
		fire_target = null
		focus_target = null


func _swap_soldiers(a: int, b: int) -> void:
	## Dwaj żołnierze zamieniają się miejscami w szyku (każdy idzie potem na miejsce drugiego).
	var p := s_pos[a]
	s_pos[a] = s_pos[b]
	s_pos[b] = p
	var hp := s_hp[a]
	s_hp[a] = s_hp[b]
	s_hp[b] = hp
	var rl := s_reload[a]
	s_reload[a] = s_reload[b]
	s_reload[b] = rl
	var cl := s_cool[a]
	s_cool[a] = s_cool[b]
	s_cool[b] = cl
	var am := s_aim[a]
	s_aim[a] = s_aim[b]
	s_aim[b] = am
	var vl := s_vel[a]
	s_vel[a] = s_vel[b]
	s_vel[b] = vl
	var tr = s_tgt_reg[a]
	s_tgt_reg[a] = s_tgt_reg[b]
	s_tgt_reg[b] = tr
	var ti = s_tgt_idx[a]
	s_tgt_idx[a] = s_tgt_idx[b]
	s_tgt_idx[b] = ti
	var bl := s_block[a]
	s_block[a] = s_block[b]
	s_block[b] = bl
	var jt := s_jit[a]
	s_jit[a] = s_jit[b]
	s_jit[b] = jt
	if a < _step.size() and b < _step.size():
		var st := _step[a]
		_step[a] = _step[b]
		_step[b] = st
	if a < _react.size() and b < _react.size():
		_react[a] = 0.0
		_react[b] = 0.0


func _update_rank_swap() -> void:
	## Ogień szeregami: strzela tylko pierwszy szereg. Gdy wystrzelił, a drugi ma już nabite, szeregi zamieniają się
	## miejscami - drugi wychodzi do przodu i daje salwę, pierwszy ładuje z tyłu. I tak na zmianę.
	if kind != "inf" or square or wedge or state != State.IDLE or fire_target == null:
		return
	var now := battle.sim_time
	if now - _swap_at < RANK_SWAP_TIME + 0.6 or now - _volley_at < VOLLEY_WINDOW + 0.4:
		return
	var n := s_pos.size()
	var files := files_for(n)
	var back := mini(files, n - files)
	if back <= 0:
		return
	var fired := 0
	var ready := 0
	for i in back:
		if s_reload[i] > 0.6:
			fired += 1
		if s_reload[i + files] <= 0.0:
			ready += 1
	if fired < ceili(back * 0.6) or ready < ceili(back * VOLLEY_READY):
		return
	for i in back:
		_swap_soldiers(i, i + files)
	_swap_at = now
	_first_loaded = -1.0
	_cohesion = 9.0      # wyjście z "szybkiej ścieżki" stojącego szyku: ludzie muszą przejść na nowe miejsca
	_rest_n = -1


func _friend_in_line(from: Vector2, to: Vector2, dist: float) -> Array:
	## Najbliższy swój (z innego pułku) stojący na linii strzału: [pułk, indeks żołnierza, odległość] albo [].
	var dir := (to - from) / maxf(dist, 0.001)
	var best: Array = []
	var bd := dist - 8.0
	for r in battle.regiments:
		if r.team != team or r.dead or r == self:
			continue
		var m := r.s_pos.size()
		if m == 0:
			continue
		var rel := r.center - from
		var t := clampf(rel.dot(dir), 0.0, dist)
		if (rel - dir * t).length() > r.formation_width() * 0.5 + r.formation_depth() + 14.0:
			continue
		for k in mini(12, m):
			var idx := randi() % m
			if r.s_hp[idx] <= 0.0:
				continue
			var q: Vector2 = r.s_pos[idx] - from
			var along := q.dot(dir)
			if along < 5.0 or along > bd:
				continue
			if absf(q.cross(dir)) < 2.4:
				bd = along
				best = [r, idx, along]
	return best


func _update_volley() -> void:
	## Oficer czeka, aż większość pierwszych szeregów załaduje, i daje komendę - salwa.
	if kind != "inf" or not officer_alive or state != State.IDLE or fire_target == null:
		_first_loaded = -1.0
		return
	var now := battle.sim_time
	if now - _idle_since < _make_ready:
		return
	if now - _volley_at < VOLLEY_WINDOW:
		return
	var n := s_pos.size()
	var slots := n if square else mini(n, files_for(n))
	if now - _swap_at < RANK_SWAP_TIME:
		return   # szeregi właśnie się zamieniają
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
		if _shout_fire:
			_shout_fire = false
			battle.sfx.voice("fire", center)
		_first_loaded = -1.0


func _may_fire(i: int) -> bool:
	## Piechota z dowódcą strzela tylko na komendę (każdy z małym opóźnieniem), bez dowódcy - kiedy załaduje.
	if kind != "inf":
		return true
	if battle.sim_time - _swap_at < RANK_SWAP_TIME:
		return false   # zamiana szeregów: nikt nie strzela w biegu
	if battle.sim_time - _idle_since < _make_ready:
		return false   # po zatrzymaniu: "ładuj - gotuj broń - cel!" zanim padnie pierwszy strzał
	if not officer_alive:
		return battle.sim_time - _idle_since > _make_ready + (s_jit[i].x + 1.0) * 1.2   # bez komendy - rozproszone
	var since := battle.sim_time - _volley_at
	return since >= (s_jit[i].x + 1.0) * 0.22 and since < VOLLEY_WINDOW + 0.5


func _separate_horses() -> void:
	## Koń z góry to wydłużony owal (~15 x 6 j.): rozpychamy w układzie konia - mocno w bok, słabiej wzdłuż,
	## żeby szereg i kolumna (głowa za zadem) zostały, a konie nie zachodziły na siebie.
	var n := s_pos.size()
	const HALF_LEN := 6.6
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
	# kilka prób znalezienia wroga w tym wycinku i zasięgu; jeśli nikogo - nie strzela (czeka na lepszy cel).
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
	# swoi na linii strzału: kolega tuż przed lufą - żołnierz wstrzymuje ogień; dalej stojący może dostać kulę
	var ff := _friend_in_line(from, tp, dist)
	if not ff.is_empty():
		if float(ff[2]) < FF_HOLD_DIST:
			s_reload[i] = randf_range(0.8, 1.8)
			return
		if randf() < FF_CHANCE:
			var fr: Regiment = ff[0]
			var fq: Vector2 = fr.s_pos[int(ff[1])]
			var fmz := from + Vector2.from_angle(ang) * 7.0
			battle.effects.add_shot(fmz, fq)
			battle.sfx.musket(fmz)
			Net.record([8, fmz])
			s_aim[i] = ang
			last_fire_time = battle.sim_time
			fr.morale -= 0.5 / fr.discipline
			if randf() < 0.45:
				fr.damage(int(ff[1]), randf_range(60.0, 130.0))
			return
	var dm := tgt.hit_dir_mult(from)
	var chance := lerpf(0.30, 0.05, dist / fire_range) * accuracy * lerpf(1.0, dm, 0.5) * HIT_COMP  # ogień wzdłuż szeregów
	if battle.terrain.is_forest(tp):
		chance *= 0.55
	elif tgt.kind == "inf" and battle.in_town(tp):
		chance *= 0.6   # piechota za murami i w domach
	if tgt.kind == "cav":
		# koń to duży cel - ale w pełnym galopie szarży trafić trudno, a strzelcom drżą ręce
		chance *= 0.7 if tgt.state == State.CHARGING else 1.25
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
	if _gun_swing > 0.05 or gun.distance_squared_to(gun_base(i)) > 64.0:
		s_reload[i] = 0.5    # działo jeszcze toczone na stanowisko
		return
	if absf(angle_difference(gun_angle(i), (tgt.center - gun).angle())) > 0.12:
		s_reload[i] = 0.25   # działo jeszcze się obraca w stronę celu
		return
	if ammo == 3 and dist > CANISTER_RANGE * 1.2:
		s_reload[i] = 1.0    # kartacze nie doniosą - bateria czeka, aż wróg podejdzie
		return
	s_reload[i] = reload_time * randf_range(0.9, 1.25) / discipline * (1.15 if ammo == 2 else 1.0)
	cannon_shots[team] += 1
	if ammo == 3 or (ammo == 0 and dist < CANISTER_RANGE):
		_fire_canister(i, gun, tp, dist)
		return
	var shell_chance := float(Battle.UNIT_TYPES[unit_key].get("shell", 0.3))
	var spread := dist * 0.06 / accuracy
	if ammo == 1:
		shell_chance = 0.0
	elif ammo == 2:
		shell_chance = 1.0
		spread *= 1.35       # lont granatu przycinany na oko - większy rozrzut
	var impact := tp + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * spread
	var dir := (impact - gun).normalized()
	battle.spawn_ball(gun + dir * 17.0, impact, team, shell_chance, float(Battle.UNIT_TYPES[unit_key].get("power", 1.0)))
	battle.effects.add_cannon_smoke(gun + dir * 17.0, dir)
	battle.sfx.cannon(gun)
	Net.record([9, gun])
	_recoil[i % _recoil.size()] = 1.0
	last_fire_time = battle.sim_time


const CANISTER_RANGE := 260.0


func _fire_canister(i: int, gun: Vector2, tp: Vector2, dist: float) -> void:
	## Kartacze: z bliska działo sieje gradem kulek w stożku - kilka trafień naraz, mocny cios w morale.
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
			if hits >= 12:
				break
	tgt.morale -= 4.0 * tgt.hit_dir_mult(gun) / tgt.discipline
	battle.effects.add_canister(gun + dir * 17.0, dir, cone, dist + 35.0)
	battle.sfx.cannon(gun)
	Net.record([9, gun])
	_recoil[i % _recoil.size()] = 1.0
	last_fire_time = battle.sim_time


func gun_pos(g: int) -> Vector2:
	if g < _gun_p.size():
		return _gun_p[g]
	return gun_base(g)


func gun_base(g: int) -> Vector2:
	## Stanowisko działa w linii baterii. Linia nie obraca się przy każdej zmianie celu - działa celują lufami.
	return art_gun_pos(g, gun_count(), center, facing if _line_ang == INF else _line_ang, spacing)


func surround_count() -> int:
	var c := 0
	for k in 8:
		if surround_mask & (1 << k):
			c += 1
	return c


func sectors_held_by_others(skip: Regiment) -> int:
	## Ile z 8 kierunków wokół pułku zajmują wrogowie INNI niż `skip` (szarżujący nie okrąża sam siebie).
	var mask := 0
	var mid := center - forward() * formation_depth() * 0.5
	var reach := 230.0 + formation_width() * 0.5
	for e in battle.regiments:
		if e == skip or e.team == team or e.dead or e.state == State.ROUTING:
			continue
		var ew := e.formation_width() * 0.5
		if mid.distance_squared_to(e.center) > (reach + ew) * (reach + ew):
			continue
		var rt := e.forward().orthogonal() * ew
		for pt in [e.center, e.center + rt, e.center - rt, e.center + rt * 0.5, e.center - rt * 0.5]:
			if mid.distance_to(pt) < reach:
				mask |= 1 << posmod(roundi((pt - mid).angle() / TAU * 8.0), 8)
	var c := 0
	for k in 8:
		if mask & (1 << k):
			c += 1
	return c


func is_surrounded() -> bool:
	return surround_count() >= 6


func is_flanked() -> bool:
	return battle.sim_time < flanked_until


func hit_dir_mult(from: Vector2) -> float:
	## Mnożnik skuteczności ataku zależnie od kierunku: przód 1.0, bok 1.5, tył 2.2.
	## Kolumna marszowa jest wrażliwa z każdej strony. Czworobok nie ma flanek.
	if square:
		# uformowany czworobok nie ma flanek; złapany w trakcie formowania jest w rozsypce z każdej strony
		var sm := lerpf(1.6, 1.0, square_ready())
		if sm > 1.2:
			flanked_until = battle.sim_time + 3.0
		return sm
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
		morale -= 118.0 / initial_count / discipline
		last_casualty_time = battle.sim_time


func _update_morale(dt: float) -> void:
	var now := battle.sim_time
	var ratio := float(s_pos.size()) / initial_count
	var cap := 40.0 + 60.0 * ratio

	var surrounded := is_surrounded()
	if surrounded and state != State.ROUTING:
		morale -= 1.6 * dt / discipline   # okrążenie: brak drogi odwrotu łamie ducha
	elif surround_count() >= 3 and (surround_mask & _rear_bits()) != 0 and state == State.MELEE:
		morale -= 1.0 * dt / discipline   # wróg na tyłach

	if state != State.ROUTING and now - last_casualty_time <= 3.0 and not surrounded and stamina >= 25.0:
		# pod ogniem: oficerowie i sąsiedzi podtrzymują szyk - duch wraca powoli nawet w trakcie strat
		morale = minf(morale + (0.35 + 0.2 * mini(support, 2)) * discipline * dt, maxf(cap, morale))
	if now - last_casualty_time > 3.0 and in_water_ratio < 0.1 and not surrounded:
		var rate := 3.0 * discipline
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
		morale -= 0.3 * dt / discipline

	if in_water_ratio > 0.3:
		morale -= 1.2 * dt / discipline

	if state == State.MELEE:
		var enemy_n := 0
		for e in melee_enemies:
			enemy_n += e.s_pos.size()
			if kind == "art":
				morale -= (5.0 if e.kind == "cav" else 2.5) * dt / discipline   # wróg między działami: obsługa pęka szybko
		var r := float(enemy_n) / maxf(1.0, s_pos.size())
		if r > 1.5:
			morale -= minf(r - 1.0, 2.0) * 0.7 * dt / discipline
	morale = clampf(morale, 0.0, 100.0)

	var break_at := 25.0 if stamina < 20.0 else 18.0   # wyczerpani pękają szybciej
	var min_ratio := 0.18
	if Battle.UNIT_TYPES[unit_key].get("steadfast", false):
		break_at = 6.0      # Grenadierzy Pieszy Gwardii: "Gwardia umiera, ale się nie poddaje"
		min_ratio = 0.3
	if state != State.ROUTING and (morale < break_at or ratio < min_ratio):
		_start_rout()
	elif state == State.ROUTING:
		var e := _nearest_enemy()
		var ed := INF if e == null else e.distance_to_soldiers(center)
		if surrounded and ed < 160.0:
			_surrender_step(dt)   # nie ma dokąd uciec - ludzie poddają się grupkami, nie cały pułk w jednej chwili
			return
		if ratio < 0.2 and now - _rout_since > 12.0 and ed > 400.0:
			_disband(false)  # resztki rozbitego pułku rozchodzą się do domów
			return
		if morale > 42.0 and ratio >= 0.2:
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
			f.morale -= 3.5 / f.discipline


# ------------------------------------------------------------------ rysowanie

func on_screen(view: Rect2) -> bool:
	## Czy pułk trzeba rysować. Liczy się to, gdzie FAKTYCZNIE są żołnierze: przy przestawianiu szyku `center`
	## stoi już na celu, a ludzie dopiero tam idą; w zwarciu i w ucieczce szyk też bywa daleko od środka.
	var grown := view.grow(formation_width() + formation_depth() + 90.0)
	if grown.has_point(center):
		return true
	if s_pos.is_empty() or (state == State.IDLE and not _direct):
		return false
	return grown.has_point(s_pos[0]) or grown.has_point(s_pos[s_pos.size() - 1]) or grown.has_point(s_pos[s_pos.size() / 2])


func _draw() -> void:
	var _pt := Time.get_ticks_usec() if Battle.PROF else 0
	_draw_impl()
	if Battle.PROF:
		Battle.pf("d_regiments", _pt)


func _draw_impl() -> void:
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
	elif battle.regiments.size() > PROC_DRAW_MAX_REGS:
		# sprite'y jeszcze się wypalają (pierwsze klatki): przy dużej bitwie rysowanie każdego żołnierza kształt po
		# kształcie przepełnia bufor karty i zamraża grę - wystarczą kropki w barwach pułku, za chwilę będą sprite'y
		for p in s_pos:
			draw_circle(p, 3.0 if kind == "cav" else 2.0, body)
		return
	else:
		match kind:
			"cav":
				_draw_cavalry(n, body, dark)
			"art":
				_draw_artillery(n, body, dark)
			_:
				_draw_infantry(n, body, dark)

	# Sztab pułku za szykiem: chorąży ze sztandarem w środku, oficer z jednej strony, dobosz z drugiej
	# (w czworoboku - w jego środku; w zwarciu sztandar zostaje pośród walczących).
	if state != State.ROUTING and kind != "art" and n > 0:
		if state == State.MELEE:
			_draw_standard(centroid(), tex)
		else:
			var base := anchor() - fwd * (formation_depth() + rank_spacing * 1.3)
			var gap := 11.0 if kind == "inf" else 16.0
			if square:
				base = center
				gap = 8.0
			# sztandar zawsze wznosi się w górę ekranu: postać stojąca nad chorążym odsuwa się dalej, poza drzewiec i płachtę
			var g_off := gap + (10.0 if right.y < -0.5 else 0.0)
			var g_dr := gap + (10.0 if -right.y < -0.5 else 0.0)
			if officer_alive:
				_draw_officer(base + right * g_off + fwd * 1.5, tex)
			_draw_drummer(base - right * g_dr - fwd * 0.5, tex)
			_draw_standard(base, tex)


func _fig_ell(c: Vector2, rx: float, ry: float, ang: float, col: Color) -> void:
	## Elipsa obrócona o kąt (figury sztabu pułku rysowane z góry).
	var pts := PackedVector2Array()
	var ax := Vector2.from_angle(ang) * rx
	var ay := Vector2.from_angle(ang + PI * 0.5) * ry
	for k in 16:
		var a := float(k) / 16.0 * TAU
		pts.append(c + ax * cos(a) + ay * sin(a))
	draw_colored_polygon(pts, col)


func _fig_body(p: Vector2, coat: Color, hat: int) -> void:
	## Pieszy z góry: cień, ramiona w płaszczu (światło z lewej-góry), głowa i nakrycie głowy.
	## hat: 0 = czako, 1 = bikorn (oficer, noszony w poprzek), 2 = futrzana czapa grenadierska.
	var f := facing
	var fwd := Vector2.from_angle(f)
	var light := Vector2(-0.5, -0.5)
	_fig_ell(p + Vector2(1.3, 1.6), 1.9, 3.4, f, Color(0, 0, 0, 0.25))           # cień
	_fig_ell(p, 2.1, 3.4, f, coat.darkened(0.55))                                   # obrys
	_fig_ell(p, 1.8, 3.1, f, coat.darkened(0.15))
	_fig_ell(p + light * 0.5, 1.3, 2.4, f, coat.lightened(0.12))                  # ramiona w słońcu
	var hp := p + fwd * 0.3
	match hat:
		1:
			_fig_ell(hp, 1.25, 3.0, f, Color(0.06, 0.05, 0.05))                   # bikorn w poprzek
			_fig_ell(hp + light * 0.35, 0.7, 2.3, f, Color(0.2, 0.18, 0.17))
			draw_circle(hp + fwd * 0.6 + fwd.orthogonal() * 1.4, 0.45, Color(0.9, 0.85, 0.3) if Battle.nation(team) != 0 else Color(0.85, 0.15, 0.15))
		2:
			_fig_ell(hp, 1.9, 1.9, f, Color(0.07, 0.06, 0.06))
			_fig_ell(hp + light * 0.5, 1.1, 1.1, f, Color(0.2, 0.18, 0.17))
		_:
			_fig_ell(hp, 1.45, 1.45, f, Color(0.08, 0.08, 0.1))
			_fig_ell(hp + light * 0.4, 0.8, 0.8, f, Color(0.25, 0.25, 0.3))
			draw_circle(hp + fwd * 1.0, 0.45, Color(0.9, 0.85, 0.75))               # pompon/kokarda z przodu


func _draw_officer(p: Vector2, tex: Texture2D) -> void:
	## Oficer: bikorn, złote epolety, szabla - w spoczynku na ramieniu, w natarciu wzniesiona przed siebie.
	var fwd := forward()
	var side := fwd.orthogonal()
	var gold := Color(0.95, 0.78, 0.3)
	var attack := state == State.CHARGING or (state == State.MOVING and attack_target != null)
	if kind == "cav":
		if tex != null:
			draw_set_transform(p, facing, Vector2(1.0, -1.0))
			draw_texture_rect(tex, Rect2(-SPRITE_WORLD * 0.5, -SPRITE_WORLD * 0.5, SPRITE_WORLD, SPRITE_WORLD), false)
			draw_set_transform(Vector2.ZERO)
		# pióropusz i epolety jeźdźca - widać, kto dowodzi szwadronem
		draw_circle(p + fwd * 0.4 - side * 0.3, 1.25, Color(0.95, 0.95, 0.92))
		draw_circle(p + fwd * 0.6 - side * 0.3, 0.7, Color(0.85, 0.1, 0.12) if Battle.nation(team) == 0 else Color(0.95, 0.95, 0.95))
		for sg in [-1.0, 1.0]:
			draw_circle(p + side * sg * 2.6 - fwd * 0.6, 0.65, gold)
		if attack:
			draw_line(p + side * 2.8, p + side * 3.2 + fwd * 8.0, Color(0.85, 0.87, 0.9), 0.6)
		return
	var ot: Texture2D = sprite_tex.get(sprite_key() + ("#of2" if attack else "#of1"))
	if ot != null:
		_blit_staff(p, ot)   # wypalony oficer - ten sam styl i szczegóły co szeregowi
		return
	var coat: Color = Battle.NATION_COATS[Battle.nation(team)]
	var hand := p + side * 2.7 + fwd * 0.6
	if attack:
		draw_line(hand, hand + fwd * 7.5 + side * 0.8, Color(0.82, 0.84, 0.88), 0.55)   # szabla w górę, ku wrogowi
	else:
		draw_line(hand, hand - fwd * 2.0 + side * 3.6, Color(0.82, 0.84, 0.88), 0.5)    # na ramieniu
	_fig_body(p, coat, 1)
	for sg in [-1.0, 1.0]:
		draw_circle(p + side * sg * 2.7 - fwd * 0.2, 0.75, gold)                      # epolety
		draw_circle(p + side * sg * 2.7 - fwd * 0.2 + Vector2(-0.2, -0.2), 0.35, Color(1, 0.95, 0.7))
	draw_circle(hand, 0.55, Color(0.95, 0.85, 0.7))                                   # dłoń / rękojeść


func _draw_drummer(p: Vector2, tex: Texture2D) -> void:
	## Dobosz: werbel u boku (mosiężny korpus, biała skóra, barwne obręcze) i dwie pałki. W marszu pałki biją
	## na zmianę; w miejscu - spoczywają na bębnie. Jazda: kotły po obu stronach konia.
	var fwd := forward()
	var side := fwd.orthogonal()
	var t := battle.sim_time * 9.0 + float(net_id)
	var beating := state == State.MOVING or state == State.CHARGING
	var hoop := Color(0.75, 0.12, 0.12) if Battle.nation(team) != 0 else Color(0.15, 0.25, 0.7)
	if kind == "cav":
		if tex != null:
			draw_set_transform(p, facing, Vector2(1.0, -1.0))
			draw_texture_rect(tex, Rect2(-SPRITE_WORLD * 0.5, -SPRITE_WORLD * 0.5, SPRITE_WORLD, SPRITE_WORLD), false)
			draw_set_transform(Vector2.ZERO)
		for sg in [-1.0, 1.0]:
			var kc: Vector2 = p + fwd * 3.2 + side * sg * 3.6
			draw_circle(kc + Vector2(0.5, 0.6), 2.1, Color(0, 0, 0, 0.25))
			draw_circle(kc, 2.1, Color(0.55, 0.4, 0.18))
			draw_circle(kc, 1.6, Color(0.92, 0.88, 0.78))
			var hit: float = 0.6 * maxf(0.0, sin(t + (0.0 if sg < 0.0 else PI))) if beating else 0.0
			draw_line(kc - fwd * (2.6 + hit * 2.0), kc + fwd * 0.2 * (1.0 - hit), Color(0.35, 0.22, 0.1), 0.45)
		return
	# wypalony dobosz: bije pałkami tylko wtedy, gdy jego werbel faktycznie słychać (patrz Sfx), inaczej pałki leżą na bębnie
	var drumming := battle.sfx != null and battle.sfx.is_drumming(self)
	var frame := "#dr0"
	if drumming:
		frame = "#dr1" if int(battle.sim_time * 7.0 + float(net_id)) % 2 == 0 else "#dr2"
	var dt2: Texture2D = sprite_tex.get(sprite_key() + frame)
	if dt2 != null:
		_blit_staff(p, dt2)
		return
	var coat: Color = Battle.NATION_COATS[Battle.nation(team)]
	if Battle.nation(team) == 0:
		coat = Color(0.25, 0.42, 0.85).lerp(Color(0.95, 0.8, 0.35), 0.15)   # doboszy w odwróconych, jaśniejszych barwach
	var dc := p + fwd * 2.4 + side * 1.9
	_fig_body(p, coat, 0)
	# werbel
	draw_circle(dc + Vector2(0.6, 0.8), 2.0, Color(0, 0, 0, 0.25))
	draw_circle(dc, 2.05, hoop.darkened(0.3))
	draw_circle(dc, 1.75, Color(0.78, 0.6, 0.28))
	draw_circle(dc, 1.45, Color(0.95, 0.93, 0.86))
	draw_circle(dc + Vector2(-0.4, -0.4), 0.6, Color(1, 1, 1, 0.6))
	# pałki: w marszu na zmianę uderzają w skórę, w miejscu leżą na bębnie
	for k in 2:
		var sg := -1.0 if k == 0 else 1.0
		var hand := p + fwd * 1.3 + side * sg * 2.3
		var lift := 0.0
		if beating:
			lift = maxf(0.0, sin(t + float(k) * PI))
		var tip := dc + side * sg * 0.5 - fwd * (0.2 + lift * 1.6)
		draw_line(hand, tip, Color(0.4, 0.26, 0.12), 0.45)
		draw_circle(hand, 0.5, Color(0.95, 0.85, 0.7))


func _blit_staff(p: Vector2, t: Texture2D) -> void:
	## Postać sztabu pułku z wypalonego sprite'a (obrócona frontem pułku; QuadMesh ma oś Y odwróconą).
	draw_set_transform(p, facing, Vector2(1.0, -1.0))
	draw_texture_rect(t, Rect2(-SPRITE_WORLD * 0.5, -SPRITE_WORLD * 0.5, SPRITE_WORLD, SPRITE_WORLD), false)
	draw_set_transform(Vector2.ZERO)


func _draw_standard(fp: Vector2, tex: Texture2D) -> void:
	var S := SPRITE_WORLD
	var cav := kind == "cav"
	if kind == "inf":
		tex = sprite_tex.get(sprite_key() + "#col", tex)   # chorąży bez muszkietu, z drzewcem w dłoniach
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
	## - w każdym ramieniu po lewej stronie patrząc od środka ku narożnikowi ("wiatraczek") - oraz czerwony
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
		2:   # Austria: barwy habsburskie z 1804 r. - czarny nad żółtym
			return Color(0.06, 0.06, 0.06) if v < 0.5 else Color(0.98, 0.80, 0.10)
		3:   # Rosja: biało-niebiesko-czerwona (poziomo)
			if v < 1.0 / 3.0:
				return Color(0.97, 0.97, 0.96)
			return Color(0.05, 0.22, 0.62) if v < 2.0 / 3.0 else Color(0.80, 0.10, 0.12)
		_:   # Prusy: biała z czarnym orłem o rozpostartych skrzydłach
			return Color(0.06, 0.06, 0.06) if _eagle_at(u, v) else Color(0.97, 0.97, 0.95)


func _draw_range(fwd: Vector2) -> void:
	## Pole ostrzału zaznaczonego pułku: suma stożków ognia wszystkich żołnierzy - od całej szerokości frontu
	## rozchodzi się na boki pod kątem ostrzału pojedynczego strzelca. Ciepły gradient (mocniejszy przy pułku),
	## cienka złota obwódka i linia skutecznego dystansu. W czworoboku - pełne koło.
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
	# --- historyczne mundury (data/uniforms.json): nakładane na końcu - realizm ważniejszy niż barwa strony
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


# ------------------------------------------------------------------ styl malowany: warstwy, obrys, detal
# Sprite żołnierza wypalany jest warstwami (cień, nogi/oporządzenie, broń, ręce, tornister, tułów, broń na ramieniu,
# nakrycie głowy). Każda warstwa dostaje przy wypalaniu własne światło i cień (shader w Battle._bake_sprites).
# Układ lokalny postaci: _v(s, f) = s w prawo żołnierza, f do przodu.

const LY_SHADOW := 0
const LY_UNDER := 1
const LY_WEAPON := 2
const LY_ARMS := 3
const LY_PACK := 4
const LY_TORSO := 5
const LY_HIGH := 6
const LY_HAT := 7
const LAYERS := 8
const OL := Color(0.05, 0.05, 0.09)
const SKIN := Color(0.86, 0.68, 0.52)
var bake_layer := -1     # wypalanie: która warstwa jest rysowana (-1 = wszystkie naraz, np. rysowanie bez sprite'ów)
var _lay := 0
var _fo := Vector2.ZERO
var _fF := Vector2.RIGHT
var _fR := Vector2.DOWN
var _fs := 1.0


func _frame(p: Vector2, dir: Vector2, sc := 1.0) -> void:
	_fo = p
	_fF = dir * sc
	_fR = Vector2(-dir.y, dir.x) * sc
	_fs = sc


func _v(s: float, f: float) -> Vector2:
	return _fo + _fR * s + _fF * f


func _dl(a: Vector2, b: Vector2, col: Color, w := 1.0) -> void:
	if bake_layer < 0 or bake_layer == _lay:
		draw_line(a, b, col, w)


func _dc(c: Vector2, r: float, col: Color) -> void:
	if bake_layer < 0 or bake_layer == _lay:
		draw_circle(c, r, col)


func _dp(pts: PackedVector2Array, col: Color) -> void:
	if (bake_layer < 0 or bake_layer == _lay) and pts.size() >= 3 and is_finite(pts[0].x + pts[0].y + pts[2].x + pts[2].y):
		if not _bake and Geometry2D.triangulate_polygon(pts).is_empty():
			return   # rysowanie bez sprite'ów daleko od (0,0): zdegenerowany wielokąt pomijamy zamiast sypać błędami
		draw_colored_polygon(pts, col)


func _ln(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	_dl(a, b, col, w * _fs)


func _ci(c: Vector2, r: float, col: Color) -> void:
	_dc(c, r * _fs, col)


func _cap(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	## Odcinek z zaokrąglonymi końcami.
	if bake_layer >= 0 and bake_layer != _lay:
		return
	if a.distance_squared_to(b) > 0.00001:
		draw_line(a, b, col, w * _fs)
	draw_circle(a, w * _fs * 0.5, col)
	draw_circle(b, w * _fs * 0.5, col)


func _tp(a: Vector2, b: Vector2, w0: float, w1: float, col: Color, flat := false) -> void:
	## Zwężający się człon (ręka, noga): szerokość w0 przy a, w1 przy b; flat = prosty koniec zamiast zaokrąglenia.
	if (bake_layer >= 0 and bake_layer != _lay) or not is_finite(a.x + a.y + b.x + b.y):
		return
	var d := b - a
	if d.length_squared() > 0.0001:
		var n := d.normalized().orthogonal() * 0.5 * _fs
		# dwa trójkąty zamiast wielokąta: krótkie, szerokie czworokąty daleko od (0,0) nie przechodzą triangulacji
		var cols := PackedColorArray([col, col, col])
		var uvs := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		draw_primitive(PackedVector2Array([a + n * w0, b + n * w1, b - n * w1]), cols, uvs)
		draw_primitive(PackedVector2Array([a + n * w0, b - n * w1, a - n * w0]), cols, uvs)
	draw_circle(a, w0 * _fs * 0.5, col)
	if not flat:
		draw_circle(b, w1 * _fs * 0.5, col)


func _pg(pts: Array, col: Color) -> void:
	_dp(PackedVector2Array(pts), col)


func _rr(s0: float, f0: float, s1: float, f1: float, r: float, col: Color) -> void:
	## Zaokrąglony prostokąt w układzie postaci.
	_pg([_v(s0 + r, f0), _v(s1 - r, f0), _v(s1 - r, f1), _v(s0 + r, f1)], col)
	_pg([_v(s0, f0 + r), _v(s1, f0 + r), _v(s1, f1 - r), _v(s0, f1 - r)], col)
	for c in [_v(s0 + r, f0 + r), _v(s1 - r, f0 + r), _v(s1 - r, f1 - r), _v(s0 + r, f1 - r)]:
		_ci(c, r, col)


func _ell(c: Vector2, ax: Vector2, ay: Vector2, col: Color) -> void:
	## Elipsa o półosiach ax, ay (miękkie cienie pod końmi, działami).
	var pts := PackedVector2Array()
	for k in 24:
		var a := float(k) / 24.0 * TAU
		pts.append(c + ax * cos(a) + ay * sin(a))
	_dp(pts, col)


func _soft_ell(c: Vector2, ax: Vector2, ay: Vector2, alpha := 0.035) -> void:
	_lay = LY_SHADOW
	for k in 8:
		var f := 1.0 - float(k) * 0.075
		_ell(c, ax * f, ay * f, Color(0, 0, 0, alpha))


static func _h(k: float) -> float:
	return fposmod(sin(k * 12.9898) * 43758.5453, 1.0)


func _legs(p: Vector2, dir: Vector2, st: Dictionary, stride: float, sc := 1.0) -> void:
	## Nogi widziane z góry. stride = 0: stoi (stopy pod tułowiem, niewidoczne);
	## +1 / -1: krok - jedna noga wyrzucona w przód, druga zostaje z tyłu.
	if absf(stride) < 0.05:
		return
	_frame(p, dir, sc)
	_lay = LY_UNDER
	var tr: Color = st.get("trousers", Color(0.87, 0.86, 0.80))
	var boot := Color(0.09, 0.08, 0.08)
	for sgn in [-1.0, 1.0]:
		var hip := _v(0.85 * sgn, 0.0)
		var lead: float = -sgn * stride
		var foot: Vector2
		if lead > 0.0:
			foot = _v(0.95 * sgn, 1.5 + 1.5 * lead)
		else:
			foot = _v(0.85 * sgn, -(2.4 + 1.3 * -lead))
		var toe := foot + _fF * 0.55
		_tp(hip, foot, 1.5, 1.2, OL)
		_cap(foot, toe, OL, 1.14)
		_tp(hip, foot, 1.06, 0.8, tr)
		_cap(foot, toe, boot, 0.74)
		_ci(toe, 0.2, boot.lightened(0.2))


func _stride() -> float:
	## Faza kroku dla wypalanej pozy: 4/7 = lewa noga w przód, 5/8 = prawa.
	if bake_pose == 4 or bake_pose == 7:
		return 1.0
	if bake_pose == 5 or bake_pose == 8:
		return -1.0
	return 0.0


func _arm(sh: Vector2, hand: Vector2, out: Vector2, sleeve: Color, cuff: Color, piping: Color, buttons: bool) -> void:
	## Ręka: dłoń pod rękawem, ramię i przedramię zwężające się do nadgarstka, prosty koniec mankietu.
	var d := hand - sh
	var dist := d.length()
	var half := 1.85 * _fs
	var bend := sqrt(maxf(half * half - dist * dist * 0.25, 0.0)) * 0.55
	var el := sh + d * 0.42 + out.normalized() * bend
	var fd := (hand - el).normalized() if hand.distance_squared_to(el) > 0.0001 else _fF.normalized()
	var wr := hand - fd * 0.3 * _fs
	var n := fd.orthogonal() * _fs
	fd *= _fs
	_ci(hand, 0.47, OL)
	_ci(hand, 0.33, SKIN)
	_tp(sh, el, 1.52, 1.42, OL)
	_tp(el, wr + fd * 0.2, 1.42, 1.0, OL, true)
	_tp(sh, el, 1.12, 1.02, sleeve)
	_tp(el, wr, 1.02, 0.62, sleeve, true)
	if el.distance_to(wr) > 1.6 * _fs:
		_ln(el + fd * 0.5 + n * 0.2, wr - fd * 0.9 + n * 0.14, sleeve.lightened(0.14), 0.16)
	if el.distance_to(wr) > 0.85 * _fs:
		_pg([wr - fd * 0.8 + n * 0.39, wr + n * 0.32, wr - n * 0.32, wr - fd * 0.8 - n * 0.39], cuff)
		_ln(wr - fd * 0.86, wr - fd * 0.74, piping, 0.79)
		if buttons:
			for k in [-1.0, 1.0]:
				_ci(wr - fd * 0.45 + n * 0.19 * k, 0.07, BRASS)


func _fur(hc: Vector2, rx: float, ry: float, col: Color, seed_k: float) -> void:
	## Futrzana czapa z góry: postrzępiony obrys + kosmyki.
	var ring: Array = []
	var ring_o: Array = []
	for k in 40:
		var ang := float(k) / 40.0 * TAU
		var r := 1.0 + (0.055 if k % 2 == 1 else -0.045) + (_h(seed_k + float(k)) - 0.5) * 0.06
		var off := _fR * (rx * r * cos(ang)) + _fF * (ry * r * sin(ang))
		ring.append(hc + off)
		ring_o.append(hc + off * 1.11)
	_pg(ring_o, OL)
	_pg(ring, col)
	_dc(hc + _fR * -0.3 + _fF * 0.45, 0.85 * minf(rx, ry) / 1.5 * _fs, col.lightened(0.07))
	for k in 46:
		var ang := _h(seed_k + 100.0 + float(k)) * TAU
		var r := 0.25 + _h(seed_k + 200.0 + float(k)) * 0.67
		var z := hc + _fR * (rx * r * cos(ang)) + _fF * (ry * r * sin(ang))
		var dd := (z - hc).normalized() * _fs
		var c := col.lightened(0.1 + _h(seed_k + 300.0 + float(k)) * 0.14) if k % 5 < 3 else col.darkened(0.45)
		_ln(z, z + dd * (0.18 + _h(seed_k + 400.0 + float(k)) * 0.14), c, 0.09)


func _plume(z: Vector2, r: float, col: Color) -> void:
	## Pióropusz / pompon z góry: kula z piórami.
	_ci(z, r + 0.16, OL)
	_ci(z, r, col.darkened(0.12))
	for k in 6:
		var ang := float(k) / 6.0 * TAU + 0.3
		_ci(z + (_fR * cos(ang) + _fF * sin(ang)) * r * 0.54, r * 0.4, col.lightened(0.12) if k % 2 == 1 else col)
	_ci(z + _fR * -0.18 * r + _fF * 0.2 * r, r * 0.32, col.lightened(0.35))


func _figure(p: Vector2, dir: Vector2, st: Dictionary, jit: Vector2, sc := 1.0, lh := Vector2.INF, rh := Vector2.INF) -> void:
	## Żołnierz z góry: poły munduru, oporządzenie, ręce, tornister, barki z pasami i epoletami, nakrycie głowy.
	## lh / rh - położenie dłoni (domyślnie wysunięte w przód: broń / wodze).
	_frame(p, dir, sc)
	var coat: Color = st["coat"]
	var civil: bool = st["civil"]
	if civil:
		# milicja: każdy w czym innym
		coat = coat.lerp([Color(0.42, 0.32, 0.22), Color(0.35, 0.36, 0.38), Color(0.5, 0.45, 0.35)][int((jit.x + 1.0) * 7.3) % 3], 0.45)
	var facing: Color = st["facing"]
	var white: Color = st.get("belt_col", WHITE_BELT)
	var fr := Battle.nation(team) == 0
	var foot := sc >= 0.89 and kind != "cav"
	var inf := kind == "inf" and foot
	var elite := base_key == "grenadier" or base_key == "guard" or base_key == "light"
	var black := Color(0.07, 0.07, 0.08)

	# 1. poły munduru, tasak, ładownica
	_lay = LY_UNDER
	if foot:
		var cd := coat.darkened(0.18)
		for sg in [-1.0, 1.0]:
			_pg([_v(1.42 * sg, -0.8), _v(-0.1 * sg, -0.8), _v(0.02 * sg, -4.0), _v(1.0 * sg, -3.92)], OL)
		for sg in [-1.0, 1.0]:
			_pg([_v(1.25 * sg, -0.8), _v(0.0, -0.8), _v(0.14 * sg, -3.85), _v(0.85 * sg, -3.75)], cd)
			if not civil:
				_ln(_v(0.95 * sg, -2.8), _v(0.62 * sg, -3.7), facing, 0.36)
				_ci(_v(0.6 * sg, -3.5), 0.18, white)
	if inf and elite:
		_cap(_v(-1.75, -0.8), _v(-2.3, -3.5), OL, 0.72)
		_cap(_v(-1.75, -0.8), _v(-2.3, -3.5), Color(0.16, 0.13, 0.11), 0.42)
		_cap(_v(-2.24, -3.2), _v(-2.3, -3.5), BRASS, 0.42)
		_ci(_v(-1.72, -0.7), 0.36, BRASS)
		_ci(_v(-2.02, -0.5), 0.24, facing)
	if inf and st["belts"]:
		_rr(0.75, -2.95, 2.3, -1.7, 0.2, OL)
		_rr(0.9, -2.8, 2.15, -1.85, 0.15, black)
		_ci(_v(1.75, -2.32), 0.22, BRASS)

	# 2. ręce
	_lay = LY_ARMS
	if lh == Vector2.INF:
		lh = _v(-0.25, 2.4) if kind == "cav" else _v(-0.9, 2.3)
	if rh == Vector2.INF:
		rh = _v(1.85, 1.7) if kind == "cav" else _v(1.3, 2.2)
	var sleeve := coat.darkened(0.06)
	var cuff := coat.darkened(0.25) if civil else facing
	_arm(_v(-1.8, 0.3), lh, -_fR - _fF * 0.3, sleeve, cuff, white, not civil)
	_arm(_v(1.95, 0.2), rh, _fR * 0.6 - _fF, sleeve, cuff, white, not civil)

	# 3. tornister z cielęcej skóry + zrolowany płaszcz
	_lay = LY_PACK
	if st["pack"] and foot:
		var hide := Color(0.47, 0.33, 0.20)
		var roll := Color(0.62, 0.58, 0.50)
		_rr(-1.5, -3.2, 1.5, -1.25, 0.4, OL)
		_rr(-1.32, -3.02, 1.32, -1.4, 0.3, hide)
		for k in 7:
			var z := _v(-1.0 + _h(float(k) + 3.0) * 2.0, -2.85 + _h(float(k) + 17.0) * 0.75)
			_ci(z, 0.2 + _h(float(k) + 31.0) * 0.16, Color(0.80, 0.74, 0.62) if k % 2 == 0 else Color(0.30, 0.20, 0.12))
		for sg in [-1.0, 1.0]:
			_ln(_v(0.72 * sg, -3.02), _v(0.72 * sg, -1.4), white, 0.26)
			_ci(_v(0.72 * sg, -2.75), 0.17, BRASS)
		_cap(_v(-1.6, -1.6), _v(1.6, -1.6), OL, 1.42)
		_cap(_v(-1.6, -1.6), _v(1.6, -1.6), roll, 1.06)
		_ln(_v(-1.55, -1.42), _v(1.55, -1.42), roll.lightened(0.2), 0.22)
		for sx in [-1.05, 0.0, 1.05]:
			_ln(_v(sx, -2.13), _v(sx, -1.07), white, 0.24)
		for sg in [-1.0, 1.0]:
			_ci(_v(1.78 * sg, -1.6), 0.3, roll.darkened(0.3))

	# 4. tułów: barki, wyłogi, pasy krzyżowe / kirys, epolety
	_lay = LY_TORSO
	var ls := _v(-1.6, 0.0)
	var rs := _v(1.6, 0.0)
	_cap(ls, rs, OL, 2.9)
	_cap(ls, rs, coat, 2.46)
	_cap(_v(-1.7, 0.35), _v(1.7, 0.35), coat.lightened(0.1), 0.6)
	if not civil:
		_pg([_v(-0.75, 0.75), _v(0.75, 0.75), _v(0.55, 1.26), _v(-0.55, 1.26)], WHITE_BELT if fr else facing)
	if st.get("cuirass", false):
		var steel: Color = st.get("cuirass_col", STEEL)
		_cap(_v(-1.25, 0.0), _v(1.25, 0.0), OL, 2.5)
		_cap(_v(-1.25, 0.0), _v(1.25, 0.0), steel, 2.1)
		_cap(_v(-1.0, 0.4), _v(0.6, 0.4), steel.lightened(0.5), 0.36)
		for sg in [-1.0, 1.0]:
			_ln(_v(1.45 * sg, 1.0), _v(1.45 * sg, -1.0), BRASS, 0.3)
	elif st["belts"]:
		for sg in [-1.0, 1.0]:
			_ln(_v(1.72 * sg, 1.2), _v(1.15 * sg, -1.25), white.darkened(0.45), 0.72)
			_ln(_v(1.72 * sg, 1.2), _v(1.15 * sg, -1.25), white, 0.5)
	for sg in [-1.0, 1.0]:
		if elite and not civil:
			# epolet z frędzlami
			var e := _v(2.4 * sg, 0.0)
			var eo := _v(2.52 * sg, 0.0)
			for k in 2:
				var g := 0.18 if k == 0 else 0.0
				var c := OL if k == 0 else facing.darkened(0.22)
				_tp(eo - _fF * 0.26, eo + _fF * 0.26, 1.24 + g * 2.0, 1.24 + g * 2.0, c)
			for k in range(-3, 4):
				var ang := float(k) * 0.36
				_ln(e + _fR * 0.2 * sg, e + _fR * 0.7 * sg * cos(ang) + _fF * 0.78 * sin(ang), facing.lightened(0.08), 0.13)
			_cap(_v(1.3 * sg, 0.0), _v(2.2 * sg, 0.0), facing, 0.78)
			_tp(_v(2.28 * sg, -0.25), _v(2.28 * sg, 0.25), 0.56, 0.56, facing.lightened(0.2))
		else:
			# zwykły naramiennik
			_cap(_v(1.35 * sg, 0.0), _v(2.3 * sg, 0.0), OL, 0.86)
			_cap(_v(1.35 * sg, 0.0), _v(2.3 * sg, 0.0), coat.darkened(0.2) if civil else facing, 0.56)

	# 5. nakrycie głowy
	_lay = LY_HAT
	var hcol: Color = st["hat_col"]
	var plume: Color = st["plume"]
	var big: float = st["big"]
	var hc := _v(0.0, 0.3)
	match st["hat"]:
		"bearskin":
			# bermyca: futro, mosiężna blacha z przodu, denko, kordon z chwastami, pióropusz z lewej
			var rx := 1.5 * big
			var ry := 1.7 * big
			_fur(hc, rx, ry, hcol.lightened(0.08), 7.0)
			var pc := hc + _fF * 1.68 * big
			_pg([pc + _fR * -0.9 - _fF * 0.33, pc + _fR * 0.9 - _fF * 0.33, pc + _fR * 0.63 + _fF * 0.34, pc + _fR * -0.63 + _fF * 0.34], OL)
			_pg([pc + _fR * -0.72 - _fF * 0.26, pc + _fR * 0.72 - _fF * 0.26, pc + _fR * 0.5 + _fF * 0.27, pc + _fR * -0.5 + _fF * 0.27], BRASS)
			_ln(pc + _fR * -0.5 - _fF * 0.12, pc + _fR * 0.5 - _fF * 0.12, BRASS.lightened(0.45), 0.12)
			if fr:
				var cal := hc - _fF * 0.72 * big
				_ci(cal, 0.66, OL)
				_ci(cal, 0.52, plume if plume.a > 0.0 else facing)
				_ln(cal - _fR * 0.36, cal + _fR * 0.36, WHITE_BELT, 0.16)
				_ln(cal - _fF * 0.36, cal + _fF * 0.36, WHITE_BELT, 0.16)
				var prev := Vector2.ZERO
				for k in 13:
					var ang := deg_to_rad(165.0 - float(k) * 12.5)
					var z := hc + _fR * (rx * 0.86 * cos(ang)) + _fF * (ry * 0.86 * sin(ang) - 0.25 * sin(float(k) / 12.0 * PI))
					if k > 0:
						_cap(prev, z, WHITE_BELT, 0.16)
					prev = z
				for z in [hc + _fR * rx + _fF * 0.15, hc + _fR * (rx + 0.12) - _fF * 0.38]:
					_ci(z, 0.36, OL)
					_ci(z, 0.25, WHITE_BELT)
			if plume.a > 0.0:
				_plume(hc + _fR * -1.3 * big + _fF * 0.85, 0.56, plume)
		"bicorne":
			# kapelusz stosowany w poprzek: dwa rogi na boki, główka, kokarda
			_tp(hc - _fF * 0.2, hc + _fR * 2.5 - _fF * 0.2, 1.9, 0.6, OL)
			_tp(hc - _fF * 0.2, hc + _fR * -2.5 - _fF * 0.2, 1.9, 0.6, OL)
			_tp(hc - _fF * 0.2, hc + _fR * 2.4 - _fF * 0.2, 1.5, 0.3, hcol.lightened(0.05))
			_tp(hc - _fF * 0.2, hc + _fR * -2.4 - _fF * 0.2, 1.5, 0.3, hcol.lightened(0.05))
			if plume.a > 0.0:
				_ln(hc + _fR * -2.0 + _fF * 0.2, hc + _fR * 2.0 + _fF * 0.2, plume, 0.2)
			_ci(hc - _fF * 0.2, 1.0, hcol.lightened(0.14))
			_ci(hc + _fR * 1.0 + _fF * 0.5, 0.42, Color(0.85, 0.15, 0.12))
			_ci(hc + _fR * 1.0 + _fF * 0.5, 0.26, WHITE_BELT)
			_ci(hc + _fR * 1.0 + _fF * 0.5, 0.12, Color(0.15, 0.25, 0.6))
		"round":
			var rc: Color = st.get("round_col", Color(0.22, 0.17, 0.12))   # kapelusz okrągły / turban
			_ci(hc, 1.85, OL)
			_ci(hc, 1.65, rc)
			_ci(hc, 1.08, rc.darkened(0.35))
			_ci(hc, 0.92, rc.lightened(0.12))
		"busby":
			# kołpak: futro, bączek z boku w barwie munduru, kita z przodu
			_tp(hc, hc + _fR * 2.0 - _fF * 0.7, 1.3, 0.6, OL)
			_fur(hc, 1.5, 1.5, hcol.lightened(0.08), 11.0)
			_tp(hc + _fR * 0.3, hc + _fR * 1.95 - _fF * 0.68, 0.95, 0.3, facing if base_key == "hussars" else coat)
			if plume.a > 0.0:
				_plume(hc + _fF * 1.25, 0.45, plume)
		"helmet":
			# kask z grzebieniem i końskim włosiem spływającym do tyłu, daszek z przodu
			_ci(hc + _fF * 0.75, 1.15, OL)
			_ci(hc + _fF * 0.75, 0.95, Color(0.1, 0.09, 0.09))
			_ci(hc, 1.62, OL)
			_ci(hc, 1.42, hcol)
			_ci(hc + _fR * -0.4 + _fF * 0.5, 0.6, hcol.lightened(0.3))
			var crest := plume if plume.a > 0.0 else hcol.darkened(0.4)
			_tp(hc + _fF * 1.1, hc - _fF * 2.9, 0.95, 0.75, OL)
			_tp(hc + _fF * 1.0, hc - _fF * 2.8, 0.6, 0.42, crest)
			_ln(hc + _fF * 0.9 + _fR * -0.08, hc - _fF * 2.5 + _fR * -0.08, crest.lightened(0.25), 0.12)
			_cap(hc + _fF * 1.0, hc + _fF * 0.2, BRASS, 0.4)
		"czapka":
			# rogatywka: kwadratowe denko ustawione rogiem do przodu, wypustki, kita z lewej
			for k in 2:
				var s := 1.78 if k == 0 else 1.5
				_pg([hc + _fF * s, hc + _fR * s, hc - _fF * s, hc - _fR * s], OL if k == 0 else hcol)
			_ln(hc - _fF * 1.4, hc + _fF * 1.4, WHITE_BELT, 0.14)
			_ln(hc - _fR * 1.4, hc + _fR * 1.4, WHITE_BELT, 0.14)
			_ci(hc, 0.3, BRASS)
			if plume.a > 0.0:
				_plume(hc + _fR * -1.15 + _fF * 0.75, 0.48, plume)
		_:
			# czako: daszek z przodu, płaskie denko, blacha, pompon / kita
			_ci(hc + _fF * 0.85, 1.22, OL)
			_ci(hc + _fF * 0.85, 1.02, Color(0.1, 0.1, 0.11))
			_ci(hc, 1.55, OL)
			_ci(hc, 1.35, hcol.lightened(0.05))
			_ci(hc, 1.08, hcol.lightened(0.16))
			_ci(hc + _fR * -0.3 + _fF * 0.3, 0.5, hcol.lightened(0.26))
			_cap(hc + _fR * -0.4 + _fF * 1.32, hc + _fR * 0.4 + _fF * 1.32, BRASS, 0.3)
			if elite and fr:
				_cap(hc + _fR * -1.2 + _fF * 0.5, hc + _fR * 1.2 + _fF * 0.5, WHITE_BELT if base_key != "light" else plume, 0.14)
			_plume(hc + _fF * 1.05, 0.44, plume if plume.a > 0.0 else hcol.lightened(0.3))


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
	if bake_pose >= 10 and bake_pose <= 13:
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
			_soft_shadow(Vector2(-0.7, 0.0), 4.4)
			_legs(Vector2.ZERO, Vector2.RIGHT, st, _stride(), 0.9)
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
	const POSES := 9
	var texs: Array = []
	var groups: Array = []
	var sk := sprite_key()
	for g in POSES:
		texs.append(sprite_tex.get(sk + String(Battle.POSE_SUFFIX[g]), tex) if g > 0 else tex)
		groups.append(PackedInt32Array())
	var inf := kind == "inf"
	var t := battle.sim_time
	for i in n:
		groups[_anim_pose(i, t)].append(i)
	var S := SPRITE_WORLD
	var posed := kind == "art" and _pose_pos.size() == n
	var horse := kind == "cav"
	while _mms.size() < POSES:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = _quad_mesh
		_mms.append(mm)
		_mm_bufs.append(PackedFloat32Array())
	for g in POSES:
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


func _anim_pose(i: int, t: float) -> int:
	## Klatka animacji żołnierza: krok (nogi na zmianę, tempo zależne od prędkości), bieg z bronią na rękę
	## w szarży, a w miejscu - kolejne czynności ładowania.
	var sp := s_vel[i].length()
	var ph := fposmod(_step[i] if i < _step.size() else t * 0.9 + s_jit[i].y, 1.0)
	if kind == "cav":
		if sp < 4.0:
			return 0
		return 4 if ph < 0.5 else 5
	if sp > 3.5:
		# cykl kroku w 4 klatkach: lewa w przód - nogi razem - prawa w przód - nogi razem
		var q := int(ph * 4.0)
		var run := kind == "inf" and (state == State.CHARGING or state == State.MELEE)
		if q == 0:
			return 7 if run else 4
		if q == 2:
			return 8 if run else 5
		return 0 if run else (3 if kind == "inf" else 0)
	if kind != "inf":
		return 0
	return _reload_pose(i, t)


func _reload_pose(i: int, t: float) -> int:
	## Ładowanie muszkietu: odgryzienie ładunku, podsypka, stempel w lufę i ubijanie (2-3 ruchy), potem broń do ramienia.
	## Tylko strzelający (przednie szeregi) i tylko gdy faktycznie ładują po strzale.
	if state == State.MELEE or state == State.ROUTING:
		return 0
	if not square and not wedge and i >= files_for(s_pos.size()) * 2:
		return 3                              # tylne szeregi nie strzelają - broń na ramieniu
	if s_reload[i] <= 0.7 or s_vel[i].length() > 6.0:
		return 0
	var fr := s_reload[i] / maxf(reload_time, 0.1)
	if fr > 0.74:
		return 6                              # odgryzienie ładunku i podsypanie panewki
	if fr > 0.62 or fr < 0.2:
		return 1                              # ładunek do lufy, stempel wsunięty / broń do nogi
	var ph := fposmod(t * 1.3 + s_jit[i].x * 3.0, 1.0)
	return 2 if ph < 0.45 else 1              # ubijanie: stempel w górę i w dół


var bake_pose := 0   # wypalanie: 0 = gotowy, 1 = ładuje (stempel w lufie), 2 = ubija (stempel w górze)


func _musket(m0: Vector2, m1: Vector2, bayonet: bool) -> void:
	## Muszkiet z góry: kolba, łoże, lufa z obręczami, zamek, pas nośny; bagnet tulejowy z wygiętą szyjką.
	_lay = LY_WEAPON
	var ln := m0.distance_to(m1) / _fs
	var md := (m1 - m0).normalized() * _fs
	var ms := Vector2(-md.y, md.x)
	var wood := Color(0.28, 0.18, 0.10)
	_cap(m0 - md * 0.25, m0 + md * ln * 0.24, OL, 1.55)
	_ln(m0 + md * ln * 0.2, m1, OL, 1.05)
	_ln(m0 - md * 0.1, m0 + md * ln * 0.22, wood.darkened(0.1), 1.2)
	_ln(m0 + md * ln * 0.2, m1 - md * 0.9, wood.lightened(0.12), 0.72)
	_ln(m0 + md * ln * 0.13 - ms * 0.42, m0 + md * ln * 0.74 - ms * 0.4, WHITE_BELT, 0.2)          # pas nośny
	_ln(m0 + md * ln * 0.37 + ms * 0.08, m1, Color(0.40, 0.41, 0.45), 0.34)
	_ln(m0 + md * ln * 0.39 + ms * 0.14, m1 - md * 0.2 + ms * 0.14, Color(0.72, 0.73, 0.78), 0.1)
	for band in [0.5, 0.68, 0.85]:
		var bp := m0.lerp(m1, band)
		_ln(bp - ms * 0.42, bp + ms * 0.42, BRASS, 0.26)
	var lk := m0 + md * ln * 0.36 + ms * 0.38
	_ci(lk, 0.34, BRASS)
	_ln(lk, lk + md * 0.55 + ms * 0.15, Color(0.55, 0.56, 0.6), 0.22)
	if not bayonet:
		return
	var st_d := Color(0.44, 0.45, 0.50)
	var st_m := Color(0.66, 0.67, 0.73)
	var st_l := Color(0.88, 0.89, 0.94)
	var s0 := m1 - md * 0.62
	var s1 := m1 + md * 0.14
	var b0 := m1 + md * 0.62 + ms * 0.38
	var b1 := b0 + md * 3.9
	var neck := [m1 - md * 0.1 + ms * 0.22, m1 + md * 0.3 + ms * 0.42, b0 + md * 0.05]
	var blade := [b0 - ms * 0.11, b0 + md * 0.28 - ms * 0.19, b0 + md * 2.9 - ms * 0.15, b1,
		b0 + md * 2.9 + ms * 0.15, b0 + md * 0.28 + ms * 0.19, b0 + ms * 0.11]
	_ln(s0 - md * 0.1, s1 + md * 0.1, OL, 0.9)
	for k in 2:
		_cap(neck[k], neck[k + 1], OL, 0.5)
	for k in blade.size():
		_cap(blade[k], blade[(k + 1) % blade.size()], OL, 0.22)
	_ln(s0, s1, st_m, 0.56)
	_ln(s0 + md * 0.2, s1 - md * 0.05, st_l, 0.14)
	_ln(s0 + md * 0.02, s0 + md * 0.17, st_l, 0.68)
	_ln(s0 + md * 0.17, s0 + md * 0.23, st_d, 0.68)
	for k in 2:
		_cap(neck[k], neck[k + 1], st_d, 0.24)
	_pg([blade[0], blade[1], blade[2], b1, b0], st_l)
	_pg([b0, b1, blade[4], blade[5], blade[6]], st_d)
	_ln(b0 + md * 0.15, b1 - md * 0.2, Color(0.98, 0.98, 1.0), 0.06)


func _soft_shadow(c: Vector2, r: float) -> void:
	## Miękki, symetryczny cień pod postacią (sprite obraca się razem z żołnierzem, więc cień nie ma kierunku).
	_lay = LY_SHADOW
	for k in 10:
		_dc(c, r * (1.0 - float(k) * 0.085), Color(0, 0, 0, 0.032))


func _drum_top(c: Vector2, r: float, hoop: Color) -> void:
	## Werbel z góry, lekko przechylony na udzie: obrys, obręcz w barwie wyłogów, mosiężne napinacze, jasna skóra.
	_lay = LY_WEAPON
	_ci(c + _fR * 0.25 - _fF * 0.2, r + 0.35, OL)
	_ci(c + _fR * 0.2 - _fF * 0.16, r + 0.1, BRASS.darkened(0.25))       # widoczny skraj mosiężnego korpusu
	_ci(c, r + 0.22, OL)
	_ci(c, r, hoop)
	for k in 8:
		var a := float(k) / 8.0 * TAU
		_ci(c + (_fR * cos(a) + _fF * sin(a)) * (r - 0.12), 0.16, BRASS)    # napinacze
	_ci(c, r * 0.78, Color(0.90, 0.86, 0.74))
	_ci(c - _fR * r * 0.22 + _fF * r * 0.22, r * 0.38, Color(0.98, 0.96, 0.9))   # odblask na skórze


func _staff_one(p: Vector2, dir: Vector2, st: Dictionary, j: Vector2) -> void:
	## Sztab pułku w tym samym stylu co szeregowi: dobosz (14-16), oficer (17-18), chorąży (19).
	_soft_shadow(p - dir * 0.8, 5.0)
	_legs(p, dir, st, _stride())
	_frame(p, dir)
	var steel := Color(0.80, 0.81, 0.87)
	var wood := Color(0.40, 0.26, 0.13)
	if bake_pose <= 16:
		# dobosz: werbel przed lewym udem na pasie przez prawe ramię, pałki w obu dłoniach
		var dc := _v(-0.95, 2.75)
		var facing: Color = st["facing"]
		_drum_top(dc, 1.6, facing if facing.get_luminance() < 0.85 else Color(0.75, 0.15, 0.15))
		_lay = LY_WEAPON
		_ln(dc + _fR * 1.2 - _fF * 0.6, _v(1.75, -0.4), OL, 0.5)
		_ln(dc + _fR * 1.2 - _fF * 0.6, _v(1.75, -0.4), WHITE_BELT, 0.3)            # pas bębna
		var lh := _v(-1.95, 1.6)
		var rh := _v(0.45, 1.75)
		_figure(p, dir, st, j, 1.0, lh, rh)
		var tips := [dc + _fR * -0.45 + _fF * 0.15, dc + _fR * 0.5 + _fF * -0.05]
		var hands := [lh, rh]
		for k in 2:
			var up := (bake_pose == 14 and k == 1) or (bake_pose == 15 and k == 0)
			var tip: Vector2 = tips[k]
			if bake_pose == 16:
				tip = dc + _fR * (0.9 if k == 0 else -0.9) + _fF * 0.6       # pałki skrzyżowane na skórze
			elif up:
				tip = (hands[k] as Vector2).lerp(tip, 0.55) + _fF * 1.1       # pałka uniesiona do uderzenia
			_lay = LY_HIGH
			_cap(hands[k], tip, OL, 0.42)
			_cap(hands[k], tip, wood.lightened(0.15 if up else 0.0), 0.24)
			_ci(tip, 0.26, OL)
			_ci(tip, 0.17, wood.lightened(0.35))
		return
	if bake_pose <= 18:
		# oficer: bikorn, bez tornistra i pasów krzyżowych, złote epolety i ryngraf, szabla w prawej dłoni
		var so := st.duplicate()
		so["hat"] = "bicorne"
		so["hat_col"] = Color(0.07, 0.06, 0.06)
		so["plume"] = Color(0, 0, 0, 0)
		so["pack"] = false
		so["belts"] = false
		var rh := _v(1.55, 2.1) if bake_pose == 18 else _v(1.75, 0.9)
		var tip := _v(1.05, 7.4) if bake_pose == 18 else _v(2.3, -2.6)
		_lay = LY_WEAPON
		_cap(rh, tip, OL, 0.5)
		_cap(rh, tip, steel, 0.26)
		_ln(rh.lerp(tip, 0.1), tip, Color(0.95, 0.96, 1.0), 0.08)
		_figure(p, dir, so, j, 1.0, _v(-1.35, 0.7), rh)
		_lay = LY_HIGH
		var gold := Color(0.96, 0.8, 0.32)
		for sg in [-1.0, 1.0]:
			var e: Vector2 = _v(2.3 * sg, 0.0)
			_ci(e, 0.82, OL)
			_ci(e, 0.66, gold)
			_ci(e + _fF * 0.18 - _fR * 0.15, 0.3, Color(1.0, 0.95, 0.7))
			for k in range(-2, 3):
				_ln(e + _fR * 0.55 * sg, e + _fR * 0.95 * sg + _fF * 0.3 * float(k), gold.darkened(0.15), 0.14)   # frędzle
		_cap(_v(-0.55, 1.05), _v(0.55, 1.05), OL, 0.5)
		_cap(_v(-0.5, 1.05), _v(0.5, 1.05), gold, 0.32)                            # ryngraf
		_cap(rh - _fR * 0.2, rh + _fR * 0.2, OL, 0.5)
		_cap(rh - _fR * 0.2, rh + _fR * 0.2, BRASS, 0.3)                            # jelec szabli
		return
	# chorąży: bez muszkietu, obie dłonie na drzewcu (drzewce i płachtę dorysowuje _draw_standard)
	var sb := st.duplicate()
	sb["pack"] = false
	_figure(p, dir, sb, j, 1.0, _v(-0.35, 1.9), _v(0.55, 1.35))


func _inf_one(p: Vector2, dir: Vector2, st: Dictionary, j: Vector2) -> void:
	if bake_pose >= 14:
		_staff_one(p, dir, st, j)
		return
	var rifle := base_key == "rifles"
	var wood := Color(0.28, 0.18, 0.10)
	var steel := Color(0.80, 0.81, 0.87)
	_soft_shadow(p - dir * 0.8, 5.0)
	_legs(p, dir, st, _stride())
	_frame(p, dir)
	if bake_pose == 6:
		# podsypanie panewki: muszkiet skosem przed sobą na wysokości pasa, prawa ręka przy zamku
		var k0 := _v(2.0, 0.3)
		var k1 := _v(-1.7, 5.0)
		_musket(k0, k1, not rifle)
		var kd := (k1 - k0).normalized()
		var kn := Vector2(-kd.y, kd.x)
		_figure(p, dir, st, j, 1.0, k0.lerp(k1, 0.6) - kn * 0.35, k0.lerp(k1, 0.3) + kn * 0.35)
		_lay = LY_ARMS
		_ci(k0.lerp(k1, 0.36) + kn * 0.5, 0.3, OL)
		_ci(k0.lerp(k1, 0.36) + kn * 0.5, 0.2, Color(0.93, 0.91, 0.84))   # ładunek w palcach
		return
	if bake_pose == 3 or bake_pose == 4 or bake_pose == 5:
		# "na ramię broń": muszkiet pionowo przy lewym barku - z góry widać kolbę, krótki skrót lufy i bagnet
		var s0 := _v(-1.75, -0.5)
		var s1 := _v(-2.0, 1.5)
		var swing := 0.0 if bake_pose == 3 else (0.9 if bake_pose == 4 else -1.1)
		_figure(p, dir, st, j, 1.0, _v(-1.95, 1.0), _v(2.25, 0.9 + swing))
		_lay = LY_HIGH
		_cap(s0, s1, OL, 1.3)
		_cap(s0, s1, wood.lightened(0.08), 0.9)
		_ln(s0.lerp(s1, 0.25), s1, Color(0.40, 0.41, 0.45), 0.3)
		_ci(s1, 0.52, OL)
		_ci(s1, 0.36, steel)
		if not rifle:
			_cap(s1, s1 + _fF * 1.1 - _fR * 0.3, OL, 0.42)          # bagnet sterczy w górę
			_cap(s1, s1 + _fF * 1.05 - _fR * 0.28, steel, 0.2)
		return
	if bake_pose == 1 or bake_pose == 2:
		# muszkiet postawiony kolbą na ziemi przy prawej nodze, lufa przy barku - z góry widać krótki skrót
		var b0 := _v(2.1, 0.9)
		var b1 := _v(1.75, 2.4)
		_lay = LY_WEAPON
		_cap(b0, b1, OL, 1.3)
		_cap(b0, b1, wood.lightened(0.08), 0.9)
		_ln(b0.lerp(b1, 0.3), b1, Color(0.40, 0.41, 0.45), 0.3)
		_ci(b1, 0.52, OL)
		_ci(b1, 0.36, steel)                                        # wylot lufy
		var rod := b1 + _fF * 1.4 - _fR * 2.6 if bake_pose == 2 else b1 - _fR * 0.7 + _fF * 0.15
		_figure(p, dir, st, j, 1.0, b0.lerp(b1, 0.45) - _fR * 0.45, b1.lerp(rod, 0.8))
		_lay = LY_HIGH
		_cap(b1, rod, OL, 0.36)                                     # stempel: w górze albo w lufie
		_cap(b1, rod, steel, 0.16)
		return
	# gotowy / bieg do ataku: muszkiet przy prawym boku, lewa dłoń pod łożem, prawa na szyjce kolby za zamkiem
	var m0 := _v(1.6, -0.4)
	var m1 := _v(1.1, 6.2 if rifle else 7.2)
	_musket(m0, m1, not rifle)
	var md := (m1 - m0).normalized()
	var ms := Vector2(-md.y, md.x)
	var gl := m0 + md * 4.35
	var gr := m0 + md * 2.05
	_figure(p, dir, st, j, 1.0, gl - ms * 0.42, gr + ms * 0.3)
	_lay = LY_ARMS
	var skin_l := SKIN.lightened(0.25)
	for k in 4:   # lewa dłoń: palce owinięte od spodu wychodzą na wierzch z prawej strony łoża
		_cap(gl + ms * 0.46 + md * (-0.27 + 0.18 * k), gl + ms * 0.12 + md * (-0.27 + 0.18 * k), OL, 0.3)
	_cap(gl - ms * 0.34 + md * 0.16, gl - ms * 0.02 + md * 0.44, OL, 0.38)
	_cap(gl - ms * 0.34 + md * 0.16, gl - ms * 0.02 + md * 0.44, SKIN, 0.22)   # kciuk na łożu
	for k in 4:
		_cap(gl + ms * 0.46 + md * (-0.27 + 0.18 * k), gl + ms * 0.12 + md * (-0.27 + 0.18 * k), SKIN, 0.15)
	for k in 4:   # prawa dłoń: palce owinięte wokół szyjki kolby
		var z := gr + md * (-0.26 + 0.17 * k) + ms * 0.02
		_cap(z, z - ms * 0.44, OL, 0.27)
	for k in 4:
		var z := gr + md * (-0.26 + 0.17 * k) + ms * 0.02
		_cap(z, z - ms * 0.44, SKIN, 0.13)
		_ci(z, 0.085, skin_l)


func _cav_one(p: Vector2, dir: Vector2, j: Vector2, sway: float, st: Dictionary) -> void:
	var lancer := base_key == "lancers"
	var heavy := base_key == "cuirassiers" or base_key == "dragoons"
	var side := Vector2(-dir.y, dir.x)   # prawa strona jeźdźca
	var hc: Color = HORSE_COLORS[int((j.y + 0.7) * 2.8) % 4]
	if base_key == "cuirassiers" or (base_key == "dragoons" and Battle.nation(team) == 1):
		hc = HORSE_COLORS[1]
	var hd := hc.darkened(0.35)
	var hb := 1.1 if heavy else 1.0
	_soft_ell(p + dir * 0.4, dir * 9.2, side * 4.6 * hb)
	_lay = LY_UNDER
	if bake_pose == 4 or bake_pose == 5:
		# nogi konia w biegu: wyciągnięte (przednie daleko w przód, zadnie w tył) albo zebrane pod kłodą
		var ext := bake_pose == 4
		var hoof := Color(0.07, 0.06, 0.05)
		for sgn in [-1.0, 1.0]:
			var f0: Vector2 = p + dir * 2.6 + side * 1.25 * sgn * hb
			var f1: Vector2 = p + dir * (6.3 if ext else 3.6) + side * (1.7 if ext else 2.7) * sgn * hb
			var h0: Vector2 = p - dir * 3.8 + side * 1.3 * sgn * hb
			var h1: Vector2 = p - dir * (7.0 if ext else 4.4) + side * (1.8 if ext else 2.8) * sgn * hb
			if sgn > 0.0 and ext:
				f1 -= dir * 1.1   # nogi nie idą idealnie parami
				h1 += dir * 1.0
			_dl(f0, f1, hd.darkened(0.35), 1.5)
			_dl(f0, f1, hd, 0.95)
			_dc(f1, 0.6, hoof)
			_dl(h0, h1, hd.darkened(0.35), 1.6)
			_dl(h0, h1, hd, 1.0)
			_dc(h1, 0.6, hoof)
	_horse_shape(p - dir * 0.3, dir, hc, 0.8 * hb, sway)
	_lay = LY_WEAPON
	# czaprak w barwie munduru z jasną lamówką, popręg
	var cloth: Color = (st["coat"] as Color).darkened(0.3)
	_quad(p, side, dir, 2.0 * hb, 2.1 * hb, -3.0, -0.6, cloth)
	_dl(p - dir * 3.0 - side * 2.0 * hb, p - dir * 3.0 + side * 2.0 * hb, st["facing"], 0.4)
	_dl(p + dir * 0.9 - side * 1.7 * hb, p + dir * 0.9 + side * 1.7 * hb, LEATHER, 0.5)
	if lancer:
		var lp := p + side * 1.9
		_dl(lp - dir * 4.0, lp + dir * 13.5, Color(0.40, 0.30, 0.18), 0.65)
		_dl(lp + dir * 11.5, lp + dir * 13.0, Color(0.92, 0.92, 0.95), 0.5)
		_dl(lp + dir * 10.6 + side * 0.1, lp + dir * 11.6 - side * 1.3, Color(0.9, 0.15, 0.15), 0.9)
		_dl(lp + dir * 10.6 + side * 0.1, lp + dir * 11.0 - side * 1.5, Color(0.97, 0.97, 0.97), 0.55)
	else:
		var curve := 0.0 if heavy else 0.5
		_dl(p + side * 2.1, p + side * 2.4 + dir * 3.5, STEEL, 0.6)
		_dl(p + side * 2.4 + dir * 3.5, p + side * (2.4 + curve) + dir * 5.6, STEEL, 0.5)
	# nogi jeźdźca na bokach konia: udo, cholewa
	var tr: Color = st.get("trousers", Color(0.87, 0.86, 0.80))
	_frame(p - dir * 0.6, dir, 0.85)
	for sgn in [-1.0, 1.0]:
		var knee := _v(2.55 * sgn * hb, 1.5)
		var toe := _v(2.75 * sgn * hb, 0.1)
		_tp(_v(1.1 * sgn, 0.0), knee, 1.5, 1.3, OL)
		_tp(knee, toe, 1.3, 1.1, OL)
		_tp(_v(1.1 * sgn, 0.0), knee, 1.08, 0.9, tr)
		_tp(knee, toe, 0.9, 0.72, Color(0.09, 0.08, 0.08))
		_ci(knee, 0.3, Color(0.2, 0.19, 0.19))
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
	_dp(PackedVector2Array([
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
	_dl(c - along * half_len, c + along * half_len, IRON, 0.45)
	# żelazna obręcz po obu krawędziach, dzwona (odcinki wieńca) i światło na górze koła
	for e in [-1.0, 1.0]:
		_dl(c - along * half_len + ax * 1.25 * e, c + along * half_len + ax * 1.25 * e, IRON.lightened(0.12), 0.3)
	for k in 6:
		var t := (float(k) + 0.5) / 6.0 * 2.0 - 1.0
		_dl(c + along * half_len * t - ax * 1.1, c + along * half_len * t + ax * 1.1, _wood_dark.darkened(0.2), 0.3)
	_dl(c - along * half_len * 0.55, c + along * half_len * 0.55, _wood.lightened(0.22), 0.5)
	_dc(c + ax * out * 1.9, 1.25, IRON)
	_dc(c + ax * out * 1.9, 0.8, _wood)
	_dc(c + ax * out * 1.9, 0.35, IRON.lightened(0.3))


func _draw_gun(gp: Vector2, gd: Vector2) -> void:
	## Działo polowe: lufa w kierunku gd, laweta (dwie belki) zwężająca się do tyłu, skrzynka, koła, ucha.
	var ax := gd.orthogonal()
	var bk := -gd
	# cień
	_soft_ell(gp + bk * 1.0, gd * 20.0, ax * 10.0, 0.03)
	_lay = LY_UNDER
	# laweta: dwie belki zbiegające się ku końcowi + poprzeczki
	for sd in [-1.0, 1.0]:
		var a0: Vector2 = gp + ax * 2.8 * sd
		var a1: Vector2 = gp + bk * 16.0 + ax * 0.9 * sd
		_dl(a0, a1, _wood_dark, 2.0)
		_dl(a0 + bk * 0.3, a1, _wood, 1.1)
	for k in [4.0, 9.0]:
		_dl(gp + bk * k - ax * (2.8 - k * 0.12), gp + bk * k + ax * (2.8 - k * 0.12), _wood_dark, 1.0)
	for k in [1.6, 6.5, 14.2]:   # żelazne okucia lawety
		_dl(gp + bk * k - ax * (3.2 - k * 0.12), gp + bk * k + ax * (3.2 - k * 0.12), IRON, 0.4)
	# skrzynka amunicyjna między belkami + koniec lawety z drągiem do kierowania
	_quad(gp, ax, bk, 1.7, 1.5, 10.0, 14.0, Color(0.30, 0.22, 0.12))
	_dl(gp + bk * 12.0 - ax * 1.5, gp + bk * 12.0 + ax * 1.5, _wood_dark, 0.5)
	_dc(gp + bk * 16.5, 1.3, IRON)
	_dl(gp + bk * 16.5 - ax * 0.4, gp + bk * 20.0 + ax * 1.6, Color(0.45, 0.33, 0.2), 0.8)
	# oś i koła
	_dl(gp - ax * 7.2, gp + ax * 7.2, IRON, 1.5)
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
	_dc(gp - gd * (4.6 + 1.0 * B), 1.1 * B, bd)
	_quad(gp, ax, gd, 2.9 * B, 2.3 * B, -4.6, 2.0, bd)
	_quad(gp, ax, gd, 2.4 * B, 1.8 * B, -4.2, 1.8, br)
	_quad(gp, ax, gd, 2.2 * B, 1.5 * B * mz, 1.6, e, bd)
	_quad(gp, ax, gd, 1.7 * B, 1.15 * B * mz, 1.8, e - 0.2, br)
	for k in [-4.4, 1.8, 1.8 + (e - 1.8) * 0.45]:
		var w: float = (2.6 - (k + 4.4) * 0.09 / maxf(L, 0.5)) * B
		_dl(gp + gd * k - ax * w, gp + gd * k + ax * w, bd, 0.7)
	_quad(gp, ax, gd, 1.9 * B * mz, 1.9 * B * mz, e - 0.4, e + 2.2, bd)
	_quad(gp, ax, gd, 1.4 * B * mz, 1.4 * B * mz, e - 0.1, e + 1.9, br)

	if spec.get("polish", false):
		_dl(gp - ax * 3.0 * B + gd * 0.2, gp + ax * 3.0 * B + gd * 0.2, Color(0.95, 0.8, 0.35), 0.6)   # mosiężne okucia Gwardii
	# czopy na lawecie z żelaznymi nakładkami
	_dl(gp - ax * 3.2, gp + ax * 3.2, BRONZE_DARK, 1.1)
	for sd2 in [-1.0, 1.0]:
		_dl(gp + ax * 2.9 * sd2 - gd * 0.9, gp + ax * 2.9 * sd2 + gd * 0.9, IRON, 0.7)
		# ucha (delfiny) do podnoszenia lufy
		if not how:
			_dl(gp + gd * (e * 0.36) + ax * 0.75 * B * sd2, gp + gd * (e * 0.5) + ax * 0.75 * B * sd2, bd.darkened(0.2), 0.45)
	# cień pod spodem lufy (bryła walca), otwór zapałowy
	_dl(gp - gd * 3.5 + ax * 1.5 * B, gp + gd * (e - 0.6) + ax * 0.95 * B * mz, bd.darkened(0.3), 0.45)
	_dc(gp - gd * 3.3, 0.36, Color(0.05, 0.05, 0.05))
	# odblask na lufie
	_dl(gp - gd * 3.5 - ax * 1.0 * B, gp + gd * (e - 1.0) - ax * 0.6 * B, Color(1, 0.95, 0.75, 0.45 if spec.get("polish", false) else 0.38), 0.6)


func _horse_shape(p: Vector2, d: Vector2, hc: Color, s: float, sway: float) -> void:
	## Koń widziany z góry: zad szerszy od kłody, zwężenie w słabiźnie, łopatki, szyja z grzywą, łeb z uszami,
	## ogon. Ciemny obrys, jaśniejszy grzbiet i krągłości zadu, cień na bokach - bryła zamiast płaskiej kreski.
	var sd := d.orthogonal()
	var ol := hc.darkened(0.55)
	var lt := hc.lightened(0.18)
	var dk := hc.darkened(0.25)
	var mane := hc.darkened(0.65)
	var tail := p - d * 8.9 * s + sd * sway * 2.4
	_dl(p - d * 4.8 * s, tail, mane, 1.7 * s)
	_dl(p - d * 6.4 * s + sd * sway * 0.8, tail - d * 0.5 * s, mane.lightened(0.12), 0.7 * s)
	var nb := p + d * 2.8 * s
	var nk := p + d * 6.4 * s + sd * sway
	var he := nk + d * 3.0 * s + sd * sway * 0.5
	for lay in 2:
		var g := 0.42 if lay == 0 else 0.0
		var c := ol if lay == 0 else hc
		_dc(p - d * 3.5 * s, (2.25 + g) * s, c)                                   # zad
		_quad(p, sd, d, (2.25 + g) * s, (2.4 + g) * s, -3.5 * s, -1.4 * s, c)             # kłoda
		_quad(p, sd, d, (2.4 + g) * s, (1.85 + g) * s, -1.4 * s, 0.9 * s, c)              # słabizna
		_quad(p, sd, d, (1.85 + g) * s, (2.0 + g) * s, 0.9 * s, 2.7 * s, c)               # łopatki
		_dc(p + d * 2.7 * s, (2.0 + g) * s, c)
		_dl(nb, nk, c, (2.5 + g * 2.0) * s)                                         # szyja
		_dl(nk - d * 0.3 * s, he, c, (1.75 + g * 2.0) * s)                          # łeb
		_dc(he, (0.8 + g) * s, c)
		for sgn in [-1.0, 1.0]:
			_dc(nk + d * 0.1 * s + sd * 0.8 * s * sgn, (0.36 + g * 0.5) * s, c)   # uszy
	# bryła: cień na bokach, światło wzdłuż grzbietu i na krągłościach zadu
	for sgn in [-1.0, 1.0]:
		_dl(p - d * 3.6 * s + sd * 1.85 * s * sgn, p + d * 2.4 * s + sd * 1.6 * s * sgn, dk, 0.7 * s)
		_dc(p - d * 3.9 * s + sd * 0.95 * s * sgn, 0.95 * s, lt)
	_dl(p - d * 3.2 * s, p + d * 2.4 * s, lt, 1.2 * s)
	_dl(p - d * 4.6 * s, p - d * 3.0 * s, dk, 0.45 * s)                             # bruzda zadu
	_dl(nb + d * 0.4 * s, nk, lt, 0.9 * s)
	_dl(nb + d * 0.2 * s - sd * 0.5 * s, nk - sd * 0.35 * s, mane, 0.95 * s)       # grzywa na jedną stronę
	_dc(nk + d * 0.6 * s, 0.5 * s, mane)                                          # grzywka
	_dl(nk + d * 0.9 * s, he - d * 0.4 * s, lt, 0.55 * s)                           # grzbiet nosa
	_dc(he + d * 0.25 * s, 0.55 * s, hc.darkened(0.45))                           # chrapy


func _horse_top(p: Vector2, d: Vector2, hc: Color) -> void:
	## Koń pociągowy z góry + chomąto na karku i popręg.
	var sd := d.orthogonal()
	_soft_ell(p + d * 0.5, d * 9.4, sd * 4.4, 0.035 * hc.a)
	_lay = LY_UNDER
	_horse_shape(p - d * 0.4, d, hc, 1.0, 0.0)
	_dl(p + d * 2.4 - sd * 2.4, p + d * 2.4 + sd * 2.4, LEATHER, 1.1)   # chomąto
	_dl(p + d * 2.7 - sd * 2.0, p + d * 2.7 + sd * 2.0, Color(0.55, 0.42, 0.2, hc.a), 0.35)
	_dl(p + d * 0.3 - sd * 2.3, p + d * 0.3 + sd * 2.3, LEATHER, 0.65)  # popręg
	_dl(p - d * 2.2 - sd * 2.2, p - d * 2.2 + sd * 2.2, LEATHER, 0.45)  # nakrzyżnik


func _draw_team(anchor: Vector2, td: Vector2, pairs: int, g: int, st: Dictionary) -> void:
	## Przodek (dwukołowy wózek ze skrzynią amunicyjną) + dyszel + pary koni; woźnica na lewym koniu każdej pary.
	var ax := td.orthogonal()
	# przodek
	_soft_ell(anchor, td * 8.5, ax * 10.0, 0.03)
	_lay = LY_UNDER
	_dl(anchor - ax * 7.0, anchor + ax * 7.0, IRON, 1.3)
	for sd in [-1.0, 1.0]:
		_wheel(anchor + ax * 6.2 * sd, ax, td, 5.0, sd)
	_quad(anchor, ax, td, 4.4, 4.4, -3.6, 3.6, _wood_dark)
	_quad(anchor, ax, td, 3.8, 3.8, -3.0, 3.0, Color(0.34, 0.30, 0.20))
	_dl(anchor - ax * 3.8, anchor + ax * 3.8, _wood_dark, 0.6)          # wieko skrzyni
	_dl(anchor - td * 3.6, anchor - td * 6.5, IRON, 0.9)                  # hak na lawetę
	# dyszel i postronki
	var front := anchor + td * (10.0 + pairs * 12.0)
	_dl(anchor + td * 3.6, anchor + td * 22.0, _wood, 1.0)
	for sd in [-1.0, 1.0]:
		_dl(anchor + td * 4.0 + ax * 2.5 * sd, front - td * 6.0 + ax * 4.2 * sd, LEATHER, 0.45)
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


static func _crew_post(role: int, mz: float) -> Vector2:
	## Stanowiska obsługi względem działa: (w prawo, do tyłu od osi kół). Wylot lufy jest mz przed osią.
	match role:
		1: return Vector2(5.5, -(mz + 1.0))     # wyciorowy - prawa strona wylotu
		2: return Vector2(-5.5, -(mz + 1.0))    # ładowniczy - lewa strona wylotu
		3: return Vector2(4.8, 6.0)             # przy zapale - za prawym kołem
		4: return Vector2(-9.0, 8.5)            # kanonier z lontem - z tyłu po lewej
		5: return Vector2(-3.0, 34.0)           # amunicyjny - przy skrzyni z tyłu
	return Vector2(0.0, 20.5)                   # celowniczy - przy ogonie lawety


static func _stroke(t: float, n: int) -> float:
	## Płynny ruch tam i z powrotem (n razy) z zatrzymaniem w głębi lufy - bez szarpania.
	var x := clampf(t, 0.0, 1.0) * n
	var k := x - floorf(x)
	return smoothstep(0.0, 0.45, k) * (1.0 - smoothstep(0.55, 1.0, k))


static func _phase(f: float, a: float, b: float) -> float:
	## Płynne wejście/wyjście w fazę musztry [a, b] (0 poza nią, 1 w środku).
	var ramp := 0.09
	return smoothstep(a, a + ramp, f) * (1.0 - smoothstep(b - ramp, b, f))


func _crew_tool_rammer(p: Vector2, dir: Vector2, muzzle: Vector2, gd: Vector2, depth: float, L: float, rammer_end: bool) -> void:
	## Wycior albo stempel: drzewce od rąk do wylotu, w lufie na głębokość depth. Głowica to walec na końcu drzewca:
	## wycior - gruby, kosmaty wałek z owczej wełny (mokry po zanurzeniu w wiadrze), stempel - gładki drewniany kloc.
	var tip := muzzle - gd * (depth * 11.0 * L)
	var hand := p + dir * 1.5
	var staff := Color(0.45, 0.33, 0.2)
	var inside := depth > 0.1
	draw_line(hand, muzzle if inside else tip, staff.darkened(0.45), 1.1)
	draw_line(hand, muzzle if inside else tip, staff, 0.7)
	draw_line(hand, hand + (hand - tip).normalized() * 3.0, staff, 0.7)
	if inside:
		return   # głowica siedzi w lufie - widać tylko drzewce wchodzące w wylot
	var ax := (tip - hand).normalized()
	var nr := ax.orthogonal()
	if rammer_end:
		var wood := Color(0.36, 0.25, 0.14)
		draw_line(tip - ax * 1.25, tip + ax * 1.25, Color(0.1, 0.07, 0.05), 2.3)
		draw_line(tip - ax * 1.05, tip + ax * 1.05, wood, 1.7)
		draw_line(tip - ax * 1.0 - nr * 0.35, tip + ax * 1.0 - nr * 0.35, wood.lightened(0.25), 0.4)
		draw_line(tip + ax * 0.85 - nr * 0.8, tip + ax * 0.85 + nr * 0.8, wood.darkened(0.35), 0.3)
	else:
		var wool := Color(0.56, 0.53, 0.46)
		draw_line(tip - ax * 1.9, tip + ax * 1.9, Color(0.12, 0.11, 0.1), 2.7)
		draw_line(tip - ax * 1.7, tip + ax * 1.7, wool, 2.1)
		for k in 7:   # kosmaty brzeg: kłaczki wełny po obu stronach i na czole
			var u := -1.6 + float(k) * 0.53
			var wob := 0.18 * sin(float(k) * 2.3)
			draw_circle(tip + ax * u + nr * (1.05 + wob), 0.42, wool.lightened(0.18))
			draw_circle(tip + ax * u - nr * (1.05 - wob), 0.42, wool.darkened(0.2))
		draw_circle(tip + ax * 1.85, 0.75, wool.lightened(0.1))
		draw_line(tip - ax * 1.5 - nr * 0.3, tip + ax * 1.5 - nr * 0.3, wool.lightened(0.3), 0.45)
		draw_line(tip - ax * 1.95 - nr * 1.0, tip - ax * 1.95 + nr * 1.0, staff.darkened(0.3), 0.4)   # okucie przy drzewcu


func _draw_artillery(n: int, body: Color, dark: Color, crew := true) -> void:
	## Bateria z góry: działa (laweta, koła, lufa z brązu) + przodki z zaprzęgami koni i woźnicami.
	## limber_u: 0 = działa rozłożone, zaprzęgi stoją z tyłu; 1 = działa zaczepione lufą do tyłu, konie ciągną.
	var fwd := forward()
	var right := fwd.rotated(PI * 0.5)
	var guns := gun_count()
	var u := limber_u
	if Net.is_client() or _gun_p.size() != guns:
		_update_guns(0.0 if battle.paused else clampf(get_process_delta_time(), 0.0, 0.1) * battle.time_scale)
	var spec: Dictionary = Battle.UNIT_TYPES[unit_key].get("gun", {})
	var pairs: int = spec.get("pairs", 3 if base_key == "horse_art" else 2)
	var st := _uniform()
	var fr_wood := Battle.nation(team) == 0
	_wood = Color(0.33, 0.36, 0.20) if fr_wood else LIMBER_WOOD          # francuskie lawety: oliwkowe
	_wood_dark = Color(0.19, 0.21, 0.11) if fr_wood else LIMBER_DARK
	for g in guns:
		var rec: float = _recoil[g % _recoil.size()]
		_recoil[g % _recoil.size()] = maxf(0.0, rec - (0.0 if battle.paused else clampf(get_process_delta_time(), 0.0, 0.1) * battle.time_scale) / 1.5)
		var gd := Vector2.from_angle(gun_angle(g))
		var gp := gun_pos(g) - gd * (rec * rec * 2.5 + rec * 4.5)   # do 7 j. w tył tuż po strzale
		# zaprzęg jedzie jak pojazd (łukami, przodem w kierunku jazdy), a działo obraca się na kołach dopiero,
		# gdy przodek stoi przed nim - ogon lawety przerzucany stroną z dala od koni (bez obrotów w miejscu)
		var anchor: Vector2 = _team_p[g]
		var tdir := Vector2.from_angle(_team_ang[g])
		var swing := smoothstep(0.0, 1.0, _gun_swing)
		var ttex: Texture2D = sprite_tex.get(sprite_key() + "#team%d" % (g % 2))
		var gtex: Texture2D = sprite_tex.get(sprite_key() + "#gun")
		if ttex != null:
			_blit(ttex, anchor + tdir * _team_off(pairs), tdir.angle())
		else:
			_draw_team(anchor, tdir, pairs, g, st)
		if gtex != null:
			_blit(gtex, gp, gd.rotated(-PI * swing).angle())   # ogon lawety przez lewą stronę - z dala od pasa zaprzęgu
		else:
			_draw_gun(gp, gd.rotated(-PI * swing))

	var detail := battle.cam.zoom.x >= DETAIL_ZOOM
	var L: float = spec.get("len", 1.0)
	var settled := limber_u <= 0.01 and guns_settled()
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
		var deployed := settled and g < guns
		var gd2 := Vector2.RIGHT
		var sd2 := Vector2.DOWN
		var gp2 := Vector2.ZERO
		var mz := 0.0
		var rod_in := 0.0      # jak głęboko wycior/stempel siedzi w lufie (0..1)
		var ram_end := false   # true = stempel (ubijanie), false = mokra gąbka (czyszczenie)
		var spike := 0.0       # celowniczy: wychylenie drąga przy naprowadzaniu
		if deployed:
			# Musztra przy dziale, w kolejności jak w regulaminie:
			#   1) wycior z mokrą gąbką do lufy i z powrotem (nr 3 trzyma kciuk na zapale)
			#   2) ładowniczy podchodzi od lewej i wkłada nabój w wylot
			#   3) stempel: dwa pchnięcia aż do dna
			#   4) celowniczy drągiem przesuwa ogon lawety
			#   5) lont do zapału - ognia
			gd2 = Vector2.from_angle(gun_angle(g))
			sd2 = gd2.rotated(PI * 0.5)
			gp2 = gun_pos(g)
			mz = 13.4 * L + 3.5
			var bore := 10.5 * L
			var reloading := s_reload[g] > 0.0 and battle.sim_time - last_fire_time < reload_time * 1.6
			if reloading:
				f = 1.0 - clampf(s_reload[g] / maxf(reload_time, 0.1), 0.0, 1.0)
			var post := _crew_post(role, mz)
			var look := gd2
			match role:
				1:   # wyciorowy: stoi z prawej strony przed wylotem, drzewce prowadzi w osi lufy
					look = -sd2
					if reloading and f > 0.04 and f < 0.72:
						tool = 1
						if f < 0.32:
							rod_in = _stroke((f - 0.06) / 0.24, 1)
						elif f > 0.48:
							rod_in = _stroke((f - 0.50) / 0.20, 2)
							ram_end = true
						else:
							ram_end = f > 0.40
						# idzie z drzewcem: krok w stronę wylotu przy pchnięciu, krok w tył przy wyciąganiu
						post = Vector2(3.4, -(mz + 2.0 + (1.0 - rod_in) * bore * 0.5))
						look = (-sd2 - gd2 * 0.5).normalized()
				2:   # ładowniczy: z lewej; z nabojem robi krok przed wylot i wsuwa go w lufę
					look = sd2
					var step_in := _phase(f, 0.32, 0.48) if reloading else 0.0
					post = post.lerp(Vector2(-2.6, -(mz + 2.6)), step_in)
					if step_in > 0.05:
						tool = 2
						look = (sd2 - gd2 * 0.6).normalized()
				3:   # przy zapale: kciuk na zapale podczas czyszczenia i ubijania, na koniec przykłada lont
					var thumb := _phase(f, 0.04, 0.72) if reloading else 0.0
					post = post.lerp(Vector2(3.9, 3.6), thumb)
					look = (gp2 - gd2 * 3.0 - (gp2 + sd2 * post.x - gd2 * post.y)).normalized()
					if thumb < 0.3:
						tool = 4
				4:   # kanonier z lontem (w większych obsługach)
					tool = 4
					look = (gp2 - gd2 * 3.0 - (gp2 + sd2 * post.x - gd2 * post.y)).normalized()
				0:   # celowniczy przy ogonie lawety: drąg w rękach przy naprowadzaniu
					if reloading and f > 0.70 and f < 0.90:
						tool = 3
						spike = sin((f - 0.70) / 0.20 * TAU)
						post.x += spike * 1.8
				5:   # amunicyjny: skrzynia z tyłu -> ładowniczy -> z powrotem (dookoła koła, nie przez nie)
					ammo_go = smoothstep(0.10, 0.30, f) * (1.0 - smoothstep(0.40, 0.62, f)) if reloading else 0.0
					if reloading and f > 0.08 and f < 0.32:
						tool = 2
			p = gp2 + sd2 * post.x - gd2 * post.y
			if role == 5:
				var front := Vector2(-9.5, -(mz - 3.0))
				p = _crew_path(p, gp2 + sd2 * front.x - gd2 * front.y, gp2, gd2, ammo_go)
			dir = look
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
			cur = p   # nowa pozycja baterii (przemarsz) - bez biegu przez pół mapy
		var walked := cur.move_toward(p, CREW_SPEED * crew_dt)
		if walked.distance_to(cur) > 0.05 and walked.distance_to(p) > 3.0:
			dir = (walked - cur).normalized()   # idąc dłuższy kawałek patrzy przed siebie
		_crew_cur[i] = walked
		_crew_dir[i] = rotate_toward(_crew_dir[i], dir.angle(), 2.6 * crew_dt)   # spokojny obrót
		p = walked
		dir = Vector2.from_angle(_crew_dir[i])
		_pose_pos[i] = p
		_pose_aim[i] = dir.angle()
		if deployed and detail and tool != 0:
			# narzędzia rysowane tam, gdzie człowiek FAKTYCZNIE stoi (po dojściu krokiem) - nic nie wisi w powietrzu
			var wood_c := Color(0.47, 0.35, 0.21)
			var sleeve := (st["coat"] as Color).darkened(0.25)
			var muzzle := gp2 + gd2 * mz
			var vent := gp2 - gd2 * 3.0
			match tool:
				1:
					# drzewce leży w OSI lufy: część w lufie jest niewidoczna, reszta wystaje z wylotu
					var bore2 := 10.5 * L
					var rod_len := bore2 + 5.0
					var tip := muzzle - gd2 * (rod_in * bore2 - 1.2)
					var butt := tip + gd2 * rod_len
					var out0 := tip if rod_in < 0.1 else muzzle + gd2 * 0.3
					draw_line(out0, butt, wood_c.darkened(0.35), 1.2)
					draw_line(out0, butt, wood_c, 0.7)
					if rod_in < 0.1:
						# główka: mokra gąbka z owczej skóry albo drewniany stempel
						draw_circle(tip, 1.25, Color(0.18, 0.17, 0.16) if not ram_end else Color(0.34, 0.25, 0.14))
						draw_circle(tip - gd2 * 0.3, 0.7, Color(0.36, 0.36, 0.34) if not ram_end else Color(0.5, 0.38, 0.22))
					# ręce na drzewcu
					var grip := muzzle + gd2 * clampf((p - muzzle).dot(gd2), 1.5, rod_len - rod_in * bore2)
					for hs in [-1.1, 1.1]:
						draw_line(p + dir * 0.6, grip + gd2 * hs, sleeve, 0.9)
						draw_circle(grip + gd2 * hs, 0.5, Color(0.86, 0.68, 0.52))
				2:
					# nabój: płócienny worek z prochem i kula - niesiony przed sobą, przy wylocie wsuwany w lufę
					var hand := p + dir * 2.4
					var near := 1.0 - clampf(hand.distance_to(muzzle + gd2 * 1.5) / 4.0, 0.0, 1.0)
					hand = hand.lerp(muzzle + gd2 * 1.2, near)
					draw_line(p + dir * 0.8, hand, sleeve, 0.9)
					draw_circle(hand, 1.15, Color(0.80, 0.76, 0.62))
					draw_circle(hand, 0.65, Color(0.93, 0.90, 0.80))
					draw_circle(hand - gd2 * 1.0, 0.85, Color(0.13, 0.13, 0.14))
				3:
					# drąg wsunięty w ucho na końcu lawety - celowniczy przerzuca ogon w lewo i w prawo
					var eye := gp2 - gd2 * 17.0
					var tail := gp2 - gd2 * 25.0 + sd2 * spike * 2.4
					draw_line(eye, tail, wood_c.darkened(0.3), 1.2)
					draw_line(eye, tail, wood_c, 0.7)
					draw_line(p + dir * 0.8, tail.lerp(eye, 0.3), sleeve, 0.9)
				4:
					# lontownica: drzewce z tlącym się lontem; gdy działo gotowe - przyłożona do zapału
					var ready := f >= 0.93 and f < 1.0   # przykłada lont tylko w chwili strzału; poza tym trzyma go z boku
					var tipl := vent if ready else p + dir.rotated(-0.9) * 4.6
					draw_line(p + dir * 0.8, tipl, wood_c.darkened(0.2), 0.75)
					var glow := 0.6 + 0.4 * sin(battle.sim_time * 9.0 + float(i))
					draw_circle(tipl, 0.75, Color(1.0, 0.45 + 0.3 * glow, 0.12))
					draw_circle(tipl, 1.5, Color(1.0, 0.6, 0.2, 0.18 * glow))
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

