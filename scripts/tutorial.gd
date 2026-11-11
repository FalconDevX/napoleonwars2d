extends RefCounted
## Samouczek: generał prowadzi gracza przez kolejne lekcje na polu ćwiczeń. Każda lekcja to kwestia generała
## i zadanie, które trzeba wykonać samemu (zaznaczyć, przemaszerować, dać ognia, oskrzydlić...), zanim padnie następna.
## Przeciwnik w samouczku jest bierny - rusza się tylko wtedy, gdy każe mu scenariusz lekcji.

const GENERAL := "GÉNÉRAL DUVAL"
const PORTRAIT := "res://assets/units/fr/fr_marshal.png"

# id, tytuł lekcji, kwestia generała, zadanie (puste = sama rozmowa, przycisk Continue)
const STEPS := [
	["intro", "The drill field",
		"Bonjour, mon ami! I am Général Duval, and the Emperor has asked me to make a commander of you. This is our drill field. Those redcoats over there are only here to be practised upon - they will not bite. Not yet. Listen, then do each thing yourself.",
		""],
	["camera", "Your eyes",
		"First, a commander must see. Move your view with W, A, S, D or by dragging with the middle mouse button, and turn the mouse wheel to come closer or to rise above the field. From high up you see the whole battle; close in you see every bayonet.",
		"Move the camera and zoom in or out"],
	["select", "Your voice",
		"Bien. Now speak to your men. Left-click a regiment - its portrait card or the soldiers themselves - and it is yours to command. The panel on the right shows its men, morale and stamina.",
		"Left-click the marked battalion: the 1st Line"],
	["march", "The march",
		"A regiment goes where you point. Right-click the ground and the battalion marches there, keeping its ranks. Short moves are made in line; long marches they make in column, which is faster but helpless if caught.",
		"Right-click the marked spot and wait for the battalion to arrive"],
	["line", "The battle line",
		"Where a line stands matters less than where it faces - muskets only fire forward. Hold the left mouse button on the ground and drag: you draw the battle line itself. Its position, its facing and its width are all yours.",
		"Left-drag on the ground to turn the battalion to a new facing"],
	["box", "Many at once",
		"One battalion is a skirmish; two are the beginning of an army. Hold Shift and drag a box around several regiments to select them together. Ctrl+A takes the whole army, and G binds your selection into a named army you can recall with a number key.",
		"Hold Shift and drag a box around both infantry battalions"],
	["arrows", "Reading the field",
		"When orders fly, the field fills with arrows. A regiment's arrow shows where it is going; a red one shows whom it means to attack. Hold Space and every regiment shows its orders and its formation at once - yours and what you can see of the enemy.",
		"Hold Space for a moment to show every regiment's orders"],
	["advance", "Musket range",
		"Now we go to work. A musket is honest at a hundred paces and a liar at two hundred. Bring both battalions up to the marked line, facing the enemy, close enough for the volley to tell.",
		"March both battalions to the marked line in front of the enemy"],
	["fire", "Feu!",
		"Right-click the enemy battalion. The first order means: fire on them! Only the front rank fires; when it has fired, the second rank steps through and gives its volley while the first reloads - and so they turn, rank after rank. One warning: a ball does not ask whose coat it meets. Never fire through your own men.",
		"Select your infantry and right-click the enemy line until they have fired"],
	["modes", "Fire, steel, or my judgement",
		"Press T to change how the battalion fights. Auto: it fires first and charges on your second order. Fire at will: it shoots and never charges. Melee only: it holds its fire and goes in with the bayonet at once. Choose before the enemy chooses for you.",
		"With infantry selected, press T to change the fire mode"],
	["flank", "The flank",
		"Écoutez bien - this is the whole art of war. A line struck in front fights back. Struck in the side it suffers half again as much, and from behind more than double. Surround a regiment on most sides and its courage runs out like water - it will throw down its arms. Take your hussars around the second enemy battalion and charge it from the side or the rear.",
		"Select the hussars, ride to the marked flank, then right-click the enemy to charge - not from the front!"],
	["square", "The square",
		"Cavalry! See them come for your 2nd Line. Horsemen ride down a line or a column, but they will not charge home on a hedge of bayonets. Select the threatened battalion and press Q: it forms square, facing every way at once. A square laughs at cavalry - and dies to cannon, so do not stay in it longer than you must.",
		"Select the 2nd Line and press Q to form square before the cavalry arrives"],
	["guns", "The guns",
		"Now my favourite children. Select the battery and right-click a target. The crew lays the guns and fires - but a battery that has just unlimbered must load first, so do not expect thunder at once. Guns reach far beyond musket range and their shot bounds through rank after rank - and through friends who stand in the way.",
		"Select the battery and right-click the distant enemy battalion; wait for two shots"],
	["ammo", "Shot, shell, canister",
		"Press B to choose the ammunition. Round shot for distance and deep formations. Shell bursts over the target. Canister turns the gun into a giant fowling-piece - murderous up close, useless far away. On Auto the gunners choose by the range.",
		"With the battery selected, press B to change the ammunition"],
	["limber", "Guns on the move",
		"A gun in action cannot run. Order the battery to a new place and watch: the teams come up, the crews hook the guns and the horses pull. On arrival the men unhitch, wheel the pieces round by hand and the teams withdraw to the rear. All of that takes time - move your guns early, not when the enemy is upon them.",
		"Right-click the marked spot and wait until the battery has unlimbered there"],
	["morale", "What breaks an army",
		"One last truth. Men do not fight until they are dead; they fight until they are afraid. Losses, fire from the flank, friends running, exhaustion - all drain morale, and a regiment with none left turns and flees. Keep your battalions close so they steady each other, rest tired troops, and send in the fresh reserve at the moment the enemy wavers.",
		""],
	["outro", "En avant!",
		"Voilà. You can see, march, form a line, give fire, turn a flank, stand in square and handle your guns. The rest only battle can teach. Go, and bring me a victory - the Emperor is watching.",
		""],
]

var battle
var step := -1
var step_t := 0.0            # czas (rzeczywisty) w bieżącej lekcji
var done_t := -1.0           # > 0: zadanie wykonane, odliczanie do następnej lekcji
var finished := false
var markers: Array = []      # [pozycja na świecie, podpis]
var unit_marks: Array = []   # pułki do wskazania (obwódka wokół karty)
var hint := ""               # dodatkowa podpowiedź pod zadaniem (np. po błędzie gracza)
var type_speed := 70.0      # znaków na sekundę: szybko bez głosu, w tempie mowy z nagraniem generała

var a_line       # 1. batalion liniowy gracza
var b_line       # 2. batalion liniowy gracza
var hussars
var battery
var e_fire       # wróg do ostrzelania muszkietami
var e_flank      # wróg do oskrzydlenia
var e_guns       # wróg dla artylerii
var e_cav        # jazda wroga (lekcja czworoboku)

var _cam0 := Vector2.ZERO
var _zoom0 := 1.0
var _facing0 := 0.0
var _mode0 := 0
var _ammo0 := 0
var _shots0 := 0
var _losses0 := 0
var _space_t := 0.0
var _cav_sent := false
var test_hold_space := false   # test automatyczny: udaje przytrzymaną spację
var _origin := Vector2.ZERO


func setup(b) -> void:
	battle = b
	var c: Vector2 = battle.map_size * 0.5
	_origin = c
	var mine: Array = []
	var foes: Array = []
	for r in battle.regiments:
		if r.team == 0:
			mine.append(r)
		else:
			foes.append(r)
	for r in mine:
		if r.kind == "inf" and a_line == null:
			a_line = r
		elif r.kind == "inf" and b_line == null:
			b_line = r
		elif r.kind == "cav" and hussars == null:
			hussars = r
		elif r.kind == "art" and battery == null:
			battery = r
	for r in foes:
		if r.kind == "inf" and e_fire == null:
			e_fire = r
		elif r.kind == "inf" and e_flank == null:
			e_flank = r
		elif r.kind == "inf" and e_guns == null:
			e_guns = r
		elif r.kind == "cav" and e_cav == null:
			e_cav = r
	# pole ćwiczeń: nasi po lewej frontem na wschód, przeciwnik po prawej frontem na zachód
	_place(a_line, c + Vector2(-620, -130), 0.0)
	_place(b_line, c + Vector2(-620, 130), 0.0)
	_place(hussars, c + Vector2(-760, 470), 0.0)
	_place(battery, c + Vector2(-900, -420), 0.0)
	_place(e_fire, c + Vector2(260, 0), PI)
	_place(e_flank, c + Vector2(560, 620), PI)
	_place(e_guns, c + Vector2(820, -520), PI)
	_place(e_cav, c + Vector2(1500, 250), PI)
	for r in foes:
		r.fire_mode = 2          # manekiny: nie strzelają i same nie atakują
		r.fire_at_will = false
	battle.cam.position = c + Vector2(-380, 0)
	battle.cam.set_zoom_instant(0.75)
	_go(0)


func _place(r, pos: Vector2, ang: float) -> void:
	if r == null:
		return
	r.center = pos
	r.set_facing(ang)
	r.move_facing = ang
	if r.kind == "art":
		r._line_ang = INF
		r._gun_p.clear()
		r._update_guns(0.0)
	var n: int = r.s_pos.size()
	for k in n:
		r.s_pos[k] = r.slot_pos(k, n)
		r.s_aim[k] = ang


func cur() -> Array:
	return STEPS[clampi(step, 0, STEPS.size() - 1)]


func is_talk() -> bool:
	return String(cur()[3]) == ""


func total() -> int:
	return STEPS.size()


func next() -> void:
	## Przycisk Continue (lekcje bez zadania) albo pominięcie bieżącej lekcji.
	if String(cur()[0]) == "square":
		after_square()
	if step >= STEPS.size() - 1:
		finished = true
		if battle.sfx != null:
			battle.sfx.stop_speech()
		return
	_go(step + 1)


func _go(i: int) -> void:
	step = i
	step_t = 0.0
	done_t = -1.0
	hint = ""
	# głos generała: assets/voice/tut_NN_<id>.mp3 (bez pliku zostaje sam tekst)
	var vlen: float = battle.sfx.speech("tut_%02d_%s.mp3" % [i + 1, String(STEPS[i][0])]) if battle.sfx != null else 0.0
	type_speed = (float(String(STEPS[i][2]).length()) / vlen) * 1.06 if vlen > 1.0 else 70.0
	markers.clear()
	unit_marks.clear()
	var id := String(cur()[0])
	var c := _origin
	_cam0 = battle.cam.position
	_zoom0 = battle.cam.zoom.x
	match id:
		"select":
			unit_marks = [a_line]
		"march":
			unit_marks = [a_line]
			markers = [[a_line.center + Vector2(230, 0), "March here"]]
		"line":
			unit_marks = [a_line]
			_facing0 = a_line.facing
		"box":
			unit_marks = [a_line, b_line]
		"advance":
			unit_marks = [a_line, b_line]
			markers = [[e_fire.center + Vector2(-175, -105), "1st Line"], [e_fire.center + Vector2(-175, 105), "2nd Line"]]
		"fire":
			unit_marks = [a_line, b_line]
			markers = [[e_fire.center, "Fire on them"]]
			_losses0 = e_fire.alive_count()
		"modes":
			unit_marks = [a_line, b_line]
			_mode0 = a_line.fire_mode * 10 + b_line.fire_mode
		"flank":
			unit_marks = [hussars]
			markers = [[e_flank.center + Vector2(60, 300), "Flank position"], [e_flank.center, "Charge from the side"]]
		"square":
			unit_marks = [b_line]
			_cav_sent = false
		"guns":
			unit_marks = [battery]
			markers = [[e_guns.center, "Target"]]
			_shots0 = battery.cannon_shots[0]
		"ammo":
			unit_marks = [battery]
			_ammo0 = battery.ammo
		"limber":
			unit_marks = [battery]
			markers = [[battery.center + Vector2(330, 60), "New position"]]
	if id == "square" and e_cav != null and not e_cav.dead:
		_place(e_cav, b_line.center + Vector2(780, -260), PI)
	if _dead(a_line) and _dead(b_line) and id in ["select", "march", "line", "box", "advance", "fire", "modes"]:
		next()   # nie ma kim ćwiczyć tej lekcji


func _dead(r) -> bool:
	return r == null or r.dead or r.s_pos.is_empty()


func _gone(r) -> bool:
	## Pułk nie nadaje się już na cel lekcji: rozbity albo ucieka z pola.
	return _dead(r) or r.state == 4


func _sel(r) -> bool:
	return r != null and battle.selected.has(r)


func update(delta: float) -> void:
	if finished or battle == null or step < 0:
		return
	step_t += delta
	if done_t >= 0.0:
		done_t += delta
		if done_t > 1.8:
			next()
		return
	if is_talk():
		return
	if _check(delta):
		done_t = 0.0
		markers.clear()
		unit_marks.clear()
		hint = ""


func _check(delta: float) -> bool:
	var id := String(cur()[0])
	match id:
		"camera":
			var moved: bool = battle.cam.position.distance_to(_cam0) > 220.0
			var zoomed: bool = absf(battle.cam.zoom.x - _zoom0) > _zoom0 * 0.15
			hint = "" if not (moved or zoomed) else ("Now use the mouse wheel to zoom" if not zoomed else "Now move the view with WASD or middle-drag")
			return moved and zoomed
		"select":
			return _sel(a_line)
		"march":
			if _dead(a_line):
				return true
			return a_line.center.distance_to(markers[0][0]) < 110.0 and a_line.state == 0
		"line":
			if _dead(a_line):
				return true
			return absf(angle_difference(a_line.facing, _facing0)) > 0.35 and a_line.state == 0
		"box":
			return (_sel(a_line) or _dead(a_line)) and (_sel(b_line) or _dead(b_line))
		"arrows":
			_space_t = _space_t + delta if (battle.show_all or test_hold_space) else 0.0
			return _space_t > 0.7
		"advance":
			var ok := 0
			for r in [a_line, b_line]:
				if _dead(r) or (r.center.distance_to(e_fire.center) < r.fire_range + 10.0 and r.state == 0):
					ok += 1
			return ok == 2 or _gone(e_fire)
		"fire":
			if _gone(e_fire):
				return true
			var fired := false
			for r in [a_line, b_line]:
				if not _dead(r) and r.last_fire_time > battle.sim_time - 8.0:
					fired = true
			return fired and e_fire.alive_count() <= _losses0 - 3
		"modes":
			return a_line.fire_mode * 10 + b_line.fire_mode != _mode0
		"flank":
			if _dead(e_flank) or _dead(hussars) or e_flank.state == 4:
				return true
			if hussars.state == 3:   # walka wręcz: skąd przyszło uderzenie?
				var from: Vector2 = (hussars.center - e_flank.center).normalized()
				var off := absf(angle_difference(e_flank.facing, from.angle()))
				if off > 1.0:
					return true
				hint = "That was a frontal charge! Right-click the ground to pull back, then come at them from the side."
			return false
		"square":
			if _dead(b_line):
				return true
			if not _cav_sent and step_t > 4.0 and not _dead(e_cav):
				_cav_sent = true
				e_cav.fire_mode = 0
				e_cav.order_attack(b_line)
			return b_line.square
		"guns":
			if _dead(battery) or _gone(e_guns):
				return true
			return battery.cannon_shots[0] >= _shots0 + 2
		"ammo":
			return _dead(battery) or battery.ammo != _ammo0
		"limber":
			if _dead(battery):
				return true
			return battery.center.distance_to(markers[0][0]) < 120.0 and battery.limber_u <= 0.01 and battery.state == 0 and battery.guns_settled()
	return false


func after_square() -> void:
	## Jazda wroga po nieudanej szarży na czworobok wraca na swoje pole.
	if e_cav != null and not e_cav.dead and e_cav.state != 4:
		e_cav.fire_mode = 2
		e_cav.order_move(_origin + Vector2(1500, 250), PI)
