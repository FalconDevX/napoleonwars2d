class_name Battle
extends Node2D
## Główna scena: duża mapa z osadami, ekonomia, rekrutacja, symulacja walk, wejście gracza, AI.

const MAP_SIZE := Vector2(12000, 8000)
const MAP_SIZES := {"Small": Vector2(7200, 4800), "Medium": Vector2(9600, 6400), "Large": Vector2(12000, 8000), "Huge": Vector2(18000, 12000)}
const MAP_SIZE_ORDER := ["Small", "Medium", "Large", "Huge"]
static var chosen_size := "Large"   # przetrwa restart sceny - wybór z menu
static var chosen_map := "Random"   # domyślnie losowy rodzaj terenu - każda bitwa na innej mapie
static var chosen_theme := "Waterloo (Summer)"   # teatr wojny i pora roku (Terrain.THEMES)
static var chosen_scenario := "Skirmish"
static var tutorial_mode := false   # bieżąca bitwa to samouczek (pole ćwiczeń, bierny przeciwnik, lekcje generała)
static var _pre_tutorial: Array = []   # ustawienia bitwy sprzed samouczka - wracają po jego zakończeniu
const TutorialScript := preload("res://scripts/tutorial.gd")
var tutorial   # kontroler samouczka (null poza samouczkiem)


static func begin_tutorial(tree: SceneTree) -> void:
	if not tutorial_mode:
		_pre_tutorial = [chosen_scenario, chosen_map, chosen_size, chosen_theme, side_nation.duplicate()]
	tutorial_mode = true
	chosen_scenario = "Tutorial"
	chosen_map = "Open Plains"
	chosen_size = "Small"
	chosen_theme = "Waterloo (Summer)"
	side_nation = [0, 1]
	first_launch = false
	show_title_next = false
	tree.reload_current_scene()


static func end_tutorial(tree: SceneTree) -> void:
	tutorial_mode = false
	if Regiment.battle != null and Regiment.battle.sfx != null:
		Regiment.battle.sfx.stop_speech()
	if _pre_tutorial.size() == 5:
		chosen_scenario = _pre_tutorial[0]
		chosen_map = _pre_tutorial[1]
		chosen_size = _pre_tutorial[2]
		chosen_theme = _pre_tutorial[3]
		side_nation = _pre_tutorial[4]
	_pre_tutorial = []
	show_title_next = true
	tree.reload_current_scene()
static var side_nation := [0, 1]    # naród drużyny 0 (gracz) i drużyny 1 (wróg): 0 Fr, 1 GB, 2 Austria, 3 Rosja, 4 Prusy
static var first_launch := true
static var show_title_next := false   # po przeładowaniu sceny pokaż ekran tytułowy (powrót do menu po bitwie)
var _gen_key := ""                     # ustawienia, z którymi wygenerowano bieżącą mapę
static var net_seed := 0
static var open_lobby := false       # po bitwie sieciowej: od razu menu z lobby             # gra sieciowa: wspólne ziarno mapy hosta i gościa

# "field": true = bitwa w polu - sam teren, bez miast, złota i werbunku; walczy się tym, co się ma.
const SCENARIOS := {
	"Tutorial": {"desc": "Drill field: Général Duval teaches you to command, step by step.", "field": true,
		"gold": [0, 0], "army": [["line", "line", "hussars", "artillery"], ["line", "line", "line", "hussars"]]},
	"Skirmish": {"desc": "Field battle: two brigades meet in open country. No towns, no reinforcements.", "field": true,
		"gold": [0, 0], "army": [["line", "line", "line", "light", "light", "grenadier", "artillery", "hussars", "dragoons"],
			["line", "line", "line", "light", "light", "grenadier", "artillery", "hussars", "dragoons"]]},
	"Conquest": {"desc": "Campaign mode: capture towns for gold and recruit new regiments.",
		"gold": [400, 400], "army": [["line", "line", "light", "line", "artillery", "hussars"], ["line", "line", "light", "line", "artillery", "hussars"]]},
	"Grand Battle": {"field": true, "desc": "Two full corps face each other from the first minute.",
		"gold": [600, 600], "army": [
			["line", "line", "line", "line", "grenadier", "grenadier", "light", "light", "artillery", "artillery", "hussars", "dragoons", "dragoons", "cuirassiers"],
			["line", "line", "line", "line", "grenadier", "grenadier", "light", "light", "artillery", "artillery", "hussars", "dragoons", "dragoons", "cuirassiers"]]},
	"Cavalry Clash": {"field": true, "desc": "Mounted armies with a thin infantry screen.",
		"gold": [500, 500], "army": [
			["line", "line", "hussars", "hussars", "dragoons", "dragoons", "lancers", "cuirassiers", "cuirassiers", "horse_art"],
			["line", "line", "hussars", "hussars", "dragoons", "dragoons", "lancers", "cuirassiers", "cuirassiers", "horse_art"]]},
	"Grand Battery": {"field": true, "desc": "Massed guns. Close the distance or be ground down.",
		"gold": [500, 500], "army": [
			["line", "line", "line", "grenadier", "artillery", "artillery", "artillery", "artillery", "horse_art", "hussars"],
			["line", "line", "line", "grenadier", "artillery", "artillery", "artillery", "artillery", "horse_art", "hussars"]]},
	"Light Troops": {"field": true, "desc": "Skirmishers, riflemen and hussars - fast and loose.",
		"gold": [300, 300], "army": [
			["light", "light", "light", "rifles", "rifles", "hussars", "hussars", "horse_art"],
			["light", "light", "light", "rifles", "rifles", "hussars", "hussars", "horse_art"]]},
	"Last Stand": {"field": true, "desc": "You are outnumbered 3 to 1. Hold the line.",
		"gold": [1200, 250], "army": [
			["line", "line", "grenadier", "artillery"],
			["line", "line", "line", "line", "line", "light", "light", "grenadier", "artillery", "artillery", "dragoons", "hussars", "hussars"]]},
	"Offensive": {"field": true, "desc": "Strike hard: you outnumber the enemy 3 to 1.",
		"gold": [250, 1200], "army": [
			["line", "line", "line", "line", "line", "light", "light", "grenadier", "artillery", "artillery", "dragoons", "hussars", "hussars"],
			["line", "line", "grenadier", "artillery"]]},
	"Guard Duel": {"field": true, "desc": "Elite against elite: guards, grenadiers and cuirassiers.",
		"gold": [450, 450], "army": [
			["guard", "guard", "grenadier", "grenadier", "rifles", "artillery", "cuirassiers", "lancers"],
			["guard", "guard", "grenadier", "grenadier", "rifles", "artillery", "cuirassiers", "lancers"]]},
}
const SCENARIO_ORDER := ["Skirmish", "Grand Battle", "Cavalry Clash", "Grand Battery", "Light Troops", "Last Stand", "Offensive", "Guard Duel", "Conquest"]


static func is_field() -> bool:
	## Bitwa w polu: bez osad, ekonomii i werbunku.
	return bool(SCENARIOS.get(chosen_scenario, SCENARIOS["Skirmish"]).get("field", false))


static func nation(t: int) -> int:
	## Druzyna -> narod (0 Francja, 1 Wielka Brytania). Gracz to druzyna 0, ale moze grac Brytyjczykami.
	return t if t < 0 else int(side_nation[clampi(t, 0, 1)])
const STEP := 1.0 / 30.0
const AI_INTERVAL := 1.5
const START_GOLD := 400.0
const MAX_QUEUE := 5

const UNIT_ORDER := ["militia", "line", "light", "rifles", "grenadier", "guard", "hussars", "dragoons", "lancers", "cuirassiers", "artillery", "horse_art"]
const NATIONS := ["France", "Britain", "Austria", "Russia", "Prussia"]
const NATION_DIRS := ["fr", "gb", "at", "ru", "pr"]   # podkatalogi assets/units/ z portretami danej strony
# kolor płaszcza piechoty liniowej i wyłogów każdej nacji
const NATION_COATS := [Color(0.22, 0.36, 0.86), Color(0.86, 0.18, 0.15), Color(0.92, 0.91, 0.86), Color(0.13, 0.30, 0.19), Color(0.11, 0.14, 0.33)]
const NATION_FACINGS := [Color(0.97, 0.97, 0.97), Color(0.95, 0.85, 0.3), Color(0.75, 0.13, 0.15), Color(0.8, 0.15, 0.15), Color(0.85, 0.2, 0.18)]
# oddziały unikalne: zamiast ogólnej jednostki danego rodzaju nacja dostaje swoją
const NATION_SUBS := [
	{"militia": "fr_garde_nat", "line": "fr_fusiliers", "light": "fr_chasseurs", "rifles": "fr_voltigeurs",
		"grenadier": "fr_grenadiers", "guard": "fr_fus_gren", "hussars": "fr_hussars", "dragoons": "fr_dragoons",
		"lancers": "fr_lancers", "cuirassiers": "fr_cuirassiers", "artillery": "fr_art8", "horse_art": "fr_horse_art"},
	{"militia": "gb_militia", "line": "gb_line", "light": "gb_light", "rifles": "gb_95th",
		"grenadier": "gb_grenadiers", "guard": "gb_coldstream", "hussars": "gb_hussars", "dragoons": "gb_heavy_drag",
		"lancers": "gb_light_drag", "cuirassiers": "gb_life_guards", "artillery": "gb_art9", "horse_art": "gb_rha"},
	{"light": "grenzer", "grenadier": "hun_grenadier", "lancers": "uhlans"},
	{"militia": "opolchenie", "guard": "pavlov", "lancers": "cossacks", "artillery": "unicorns"},
	{"militia": "landwehr", "light": "fusiliers", "hussars": "black_hussars", "guard": "garde_pr"},
]


static func unit_for(nat: int, base: String) -> String:
	return NATION_SUBS[clampi(nat, 0, NATION_SUBS.size() - 1)].get(base, base)


static func base_of(key: String) -> String:
	return UNIT_TYPES[key].get("base", key)


# Francja ma pełną listę 39 jednostek (arkusz "Francja – jednostki i statystyki"), w tej kolejności.
const FR_ORDER := ["fr_fusiliers", "fr_chasseurs", "fr_voltigeurs", "fr_garde_nat", "fr_chass_cheval", "fr_hussars", "fr_dragoons", "fr_art6", "fr_art8", "fr_grenadiers", "fr_carabiniers", "fr_sappers", "fr_lancers", "fr_cuirassiers", "fr_carab_cheval", "fr_art12", "fr_horse_art", "fr_howitzers", "fr_yg_tirailleurs", "fr_fus_gren", "fr_marins", "fr_chass_pied", "fr_gren_pied", "fr_chass_garde", "fr_mamelukes", "fr_red_lancers", "fr_drag_imp", "fr_gren_cheval", "fr_gendarmes", "fr_art_garde", "fr_horse_art_garde", "fr_pontoniers", "fr_larrey", "fr_marshal", "fr_napoleon", "fr_pol_chevau", "fr_swiss", "fr_irish", "fr_westphal"]
# Wielka Brytania: 38 jednostek z arkusza "Britain – units and stats", w tej kolejności.
const GB_ORDER := ["gb_line", "gb_light", "gb_militia", "gb_light_drag", "gb_hussars", "gb_art6", "gb_art9", "gb_grenadiers", "gb_95th", "gb_60th", "gb_highlanders", "gb_marines", "gb_sappers", "gb_heavy_drag", "gb_drag_guards", "gb_scots_greys", "gb_rha", "gb_howitzers", "gb_rockets", "gb_coldstream", "gb_1st_guards", "gb_3rd_guards", "gb_guards_light", "gb_life_guards", "gb_blues", "gb_chestnut", "gb_surgeons", "gb_commissariat", "gb_general", "gb_wellington", "gb_kgl_line", "gb_kgl_light", "gb_kgl_hussars", "gb_nl_carab", "gb_brunswick", "gb_brunswick_hus", "gb_cacadores", "gb_port_line"]
const TIER_TABS := ["line", "elite", "guard", "support", "allies"]
const TIER_LABELS := ["Line", "Elite", "Guard", "Support", "Allies"]


static func roster(nat: int) -> Array:
	## Jednostki do werbunku danej nacji (kolejność jak UNIT_ORDER; Francja - FR_ORDER, Brytania - GB_ORDER).
	if nat == 0:
		return FR_ORDER.duplicate()
	if nat == 1:
		return GB_ORDER.duplicate()
	var out: Array = []
	for k in UNIT_ORDER:
		out.append(unit_for(nat, k))
	return out
const UNIT_TYPES := {
	"militia": {"name": "Militia", "kind": "inf", "count": 60, "files": 20, "accuracy": 0.75, "melee": 0.75,
		"discipline": 0.7, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 27.0, "range": 190.0, "reload": 11.0,
		"cost": 70, "upkeep": 0.14, "time": 15.0, "city_only": false},
	"rifles": {"name": "Riflemen", "kind": "inf", "count": 36, "files": 18, "accuracy": 1.8, "melee": 0.8,
		"discipline": 1.15, "spacing": 11.0, "rank_spacing": 10.0, "walk": 14.0, "run": 30.0, "range": 320.0, "reload": 11.0,
		"cost": 115, "upkeep": 0.32, "time": 32.0, "city_only": true},
	"dragoons": {"name": "Dragoons", "kind": "cav", "count": 32, "files": 16, "accuracy": 1.0, "melee": 1.45,
		"discipline": 1.2, "spacing": 13.0, "rank_spacing": 15.0, "walk": 30.0, "run": 64.0, "range": 0.0, "reload": 1.0,
		"cost": 210, "upkeep": 0.45, "time": 34.0, "city_only": false, "charge": 1.3},
	"cuirassiers": {"name": "Cuirassiers", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.9,
		"discipline": 1.45, "spacing": 14.0, "rank_spacing": 16.0, "walk": 27.0, "run": 58.0, "range": 0.0, "reload": 1.0,
		"cost": 320, "upkeep": 0.6, "time": 50.0, "city_only": true, "charge": 1.9},
	"horse_art": {"name": "Horse Artillery", "kind": "art", "count": 12, "files": 3, "accuracy": 0.9, "melee": 0.6,
		"discipline": 1.15, "spacing": 34.0, "rank_spacing": 7.0, "walk": 20.0, "run": 28.0, "range": 600.0, "reload": 12.0,
		"cost": 260, "upkeep": 0.5, "time": 45.0, "city_only": true, "gun": {"len": 0.85, "bore": 0.9}},
	"line": {"name": "Line Infantry", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.0, "melee": 1.0,
		"discipline": 1.0, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 9.0,
		"cost": 135, "upkeep": 0.25, "time": 25.0, "city_only": false},
	"light": {"name": "Skirmishers", "kind": "inf", "count": 40, "files": 20, "accuracy": 1.35, "melee": 0.85,
		"discipline": 1.0, "spacing": 10.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 240.0, "reload": 8.0,
		"cost": 110, "upkeep": 0.22, "time": 22.0, "city_only": false},
	"grenadier": {"name": "Grenadiers", "kind": "inf", "count": 48, "files": 16, "accuracy": 1.05, "melee": 1.35,
		"discipline": 1.35, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 8.5,
		"cost": 235, "upkeep": 0.35, "time": 35.0, "city_only": true},
	"guard": {"name": "Guard", "kind": "inf", "count": 60, "files": 20, "accuracy": 1.15, "melee": 1.45,
		"discipline": 1.6, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 220.0, "reload": 8.0,
		"cost": 290, "upkeep": 0.5, "time": 50.0, "city_only": true},
	"hussars": {"name": "Hussars", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.35,
		"discipline": 1.05, "spacing": 13.0, "rank_spacing": 15.0, "walk": 34.0, "run": 72.0, "range": 0.0, "reload": 1.0,
		"cost": 150, "upkeep": 0.4, "time": 30.0, "city_only": false},
	"lancers": {"name": "Lancers", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.6,
		"discipline": 1.25, "spacing": 13.0, "rank_spacing": 15.0, "walk": 32.0, "run": 68.0, "range": 0.0, "reload": 1.0,
		"cost": 240, "upkeep": 0.5, "time": 40.0, "city_only": true},
	"artillery": {"name": "Artillery", "kind": "art", "count": 16, "files": 4, "accuracy": 1.0, "melee": 0.55,
		"discipline": 1.1, "spacing": 34.0, "rank_spacing": 7.0, "walk": 9.0, "run": 12.0, "range": 720.0, "reload": 14.0,
		"cost": 240, "upkeep": 0.45, "time": 45.0, "city_only": true},
	"grenzer": {"name": "Grenzer", "kind": "inf", "count": 44, "files": 20, "accuracy": 1.3, "melee": 0.95, "discipline": 0.95, "spacing": 10.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 240.0, "reload": 8.0, "cost": 95, "upkeep": 0.18, "time": 20.0, "city_only": false, "fmt": "%s Grenz Infantry", "base": "light", "nation": 2},
	"hun_grenadier": {"name": "Hungarian Grenadiers", "kind": "inf", "count": 48, "files": 16, "accuracy": 1.05, "melee": 1.5, "discipline": 1.4, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 8.5, "cost": 250, "upkeep": 0.35, "time": 35.0, "city_only": true, "fmt": "%s Hungarian Grenadier Bn", "base": "grenadier", "nation": 2},
	"uhlans": {"name": "Uhlans", "kind": "cav", "count": 32, "files": 15, "accuracy": 1.0, "melee": 1.55, "discipline": 1.25, "spacing": 13.0, "rank_spacing": 15.0, "walk": 32.0, "run": 68.0, "range": 0.0, "reload": 1.0, "cost": 225, "upkeep": 0.5, "time": 40.0, "city_only": false, "fmt": "%s Uhlan Regiment", "base": "lancers", "nation": 2},
	"opolchenie": {"name": "Opolchenie", "kind": "inf", "count": 72, "files": 24, "accuracy": 0.6, "melee": 0.85, "discipline": 0.6, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 27.0, "range": 190.0, "reload": 11.0, "cost": 60, "upkeep": 0.12, "time": 12.0, "city_only": false, "fmt": "%s Opolchenie Druzhina", "base": "militia", "nation": 3},
	"pavlov": {"name": "Pavlov Grenadiers", "kind": "inf", "count": 60, "files": 20, "accuracy": 1.05, "melee": 1.55, "discipline": 1.75, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 220.0, "reload": 8.0, "cost": 300, "upkeep": 0.5, "time": 50.0, "city_only": true, "fmt": "%s Pavlovsky Grenadiers", "base": "guard", "nation": 3},
	"cossacks": {"name": "Cossacks", "kind": "cav", "count": 36, "files": 18, "accuracy": 1.0, "melee": 1.05, "discipline": 0.85, "spacing": 13.0, "rank_spacing": 15.0, "walk": 38.0, "run": 80.0, "range": 0.0, "reload": 1.0, "cost": 120, "upkeep": 0.25, "time": 22.0, "city_only": false, "charge": 0.85, "fmt": "%s Don Cossack Regiment", "base": "lancers", "nation": 3},
	"unicorns": {"name": "Licorne Battery", "kind": "art", "count": 16, "files": 4, "accuracy": 1.0, "melee": 0.55, "discipline": 1.1, "spacing": 34.0, "rank_spacing": 7.0, "walk": 9.0, "run": 12.0, "range": 640.0, "reload": 13.0, "cost": 230, "upkeep": 0.45, "time": 45.0, "city_only": true, "shell": 0.65, "fmt": "%s Licorne Battery", "base": "artillery", "nation": 3, "gun": {"len": 1.1, "bore": 1.3, "how": true}},
	"landwehr": {"name": "Landwehr", "kind": "inf", "count": 60, "files": 20, "accuracy": 0.85, "melee": 0.9, "discipline": 0.85, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 27.0, "range": 190.0, "reload": 11.0, "cost": 85, "upkeep": 0.16, "time": 15.0, "city_only": false, "fmt": "%s Landwehr Regiment", "base": "militia", "nation": 4},
	"fusiliers": {"name": "Fusiliers", "kind": "inf", "count": 44, "files": 20, "accuracy": 1.3, "melee": 0.95, "discipline": 1.05, "spacing": 10.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 240.0, "reload": 8.0, "cost": 115, "upkeep": 0.22, "time": 22.0, "city_only": false, "fmt": "%s Fusilier Battalion", "base": "light", "nation": 4},
	"black_hussars": {"name": "Black Hussars", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.45, "discipline": 1.2, "spacing": 13.0, "rank_spacing": 15.0, "walk": 34.0, "run": 72.0, "range": 0.0, "reload": 1.0, "cost": 170, "upkeep": 0.4, "time": 30.0, "city_only": false, "charge": 1.15, "fmt": "%s Leib-Hussars", "base": "hussars", "nation": 4},
	"garde_pr": {"name": "Prussian Guard", "kind": "inf", "count": 60, "files": 20, "accuracy": 1.2, "melee": 1.4, "discipline": 1.6, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 220.0, "reload": 8.0, "cost": 280, "upkeep": 0.5, "time": 50.0, "city_only": true, "fmt": "%s Garde zu Fuss", "base": "guard", "nation": 4},
	# --- Francja: 39 jednostek z arkusza "Francja – jednostki i statystyki" (generowane, gen_fr.py)
	"fr_fusiliers": {"name": "Line Fusiliers", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.0, "melee": 1.0, "defense": 1.0, "discipline": 1.0, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 9.0, "cost": 135, "upkeep": 0.25, "time": 26.0, "city_only": false, "charge": 1.0, "base": "line", "nation": 0, "tier": "line", "ai": 1.0, "desc": "Line, column, square", "pl": true},
	"fr_chasseurs": {"name": "Light Infantry (Chasseurs)", "kind": "inf", "count": 54, "files": 27, "accuracy": 1.125, "melee": 0.857, "defense": 0.857, "discipline": 1.0, "spacing": 10.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 231.0, "reload": 7.875, "cost": 160, "upkeep": 0.283, "time": 28.0, "city_only": false, "charge": 0.95, "base": "light", "nation": 0, "tier": "line", "ai": 1.0, "desc": "Loose order, square", "pl": true},
	"fr_voltigeurs": {"name": "Voltigeurs", "kind": "inf", "count": 40, "files": 20, "accuracy": 1.375, "melee": 0.714, "defense": 0.571, "discipline": 0.925, "spacing": 10.0, "rank_spacing": 9.0, "walk": 15.0, "run": 32.0, "range": 252.0, "reload": 7.0, "cost": 145, "upkeep": 0.267, "time": 26.0, "city_only": false, "charge": 0.85, "base": "light", "nation": 0, "tier": "line", "ai": 1.0, "desc": "Loose order, hidden in woods, fire on the move", "pl": true, "look": {"plume": Color(0.95, 0.85, 0.2), "facing": Color(0.95, 0.85, 0.2)}},
	"fr_garde_nat": {"name": "National Guard", "kind": "inf", "count": 54, "files": 18, "accuracy": 0.675, "melee": 0.571, "defense": 0.714, "discipline": 0.775, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 189.0, "reload": 10.5, "cost": 80, "upkeep": 0.15, "time": 20.0, "city_only": false, "charge": 0.8, "base": "militia", "nation": 0, "tier": "line", "ai": 1.0, "desc": "+3 morale defending a town", "pl": true},
	"fr_chass_cheval": {"name": "Chasseurs-a-Cheval", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.286, "defense": 0.714, "discipline": 1.0, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 160, "upkeep": 0.3, "time": 28.0, "city_only": false, "charge": 1.161, "base": "hussars", "nation": 0, "tier": "line", "ai": 1.0, "desc": "Scouting, pursuit", "pl": true, "look": {"coat": Color(0.13, 0.32, 0.2), "hat": "shako", "hat_col": Color(0.08, 0.08, 0.09), "facing": Color(0.8, 0.15, 0.12), "plume": Color(0.15, 0.45, 0.2)}},
	"fr_hussars": {"name": "Hussars", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.429, "defense": 0.571, "discipline": 1.0, "spacing": 13.0, "rank_spacing": 15.0, "walk": 35.2, "run": 73.6, "range": 0.0, "reload": 1.0, "cost": 170, "upkeep": 0.317, "time": 29.0, "city_only": false, "charge": 1.29, "base": "hussars", "nation": 0, "tier": "line", "ai": 1.0, "desc": "+5 charge vs routing troops", "pl": true, "look": {"coat": Color(0.55, 0.68, 0.85), "hat": "shako"}},
	"fr_dragoons": {"name": "Dragoons", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.286, "defense": 1.0, "discipline": 1.075, "spacing": 13.0, "rank_spacing": 15.0, "walk": 28.6, "run": 59.8, "range": 0.0, "reload": 1.0, "cost": 190, "upkeep": 0.35, "time": 31.0, "city_only": false, "charge": 1.29, "base": "dragoons", "nation": 0, "tier": "line", "ai": 1.0, "desc": "Can dismount and fight on foot", "pl": true, "look": {"coat": Color(0.13, 0.3, 0.18), "facing": Color(0.8, 0.15, 0.12)}},
	"fr_art6": {"name": "6-pounder Foot Battery", "kind": "art", "count": 16, "files": 4, "accuracy": 0.938, "melee": 0.429, "defense": 0.429, "discipline": 0.85, "spacing": 34.0, "rank_spacing": 7.0, "walk": 10.4, "run": 14.04, "range": 560.0, "reload": 10.5, "cost": 170, "upkeep": 0.333, "time": 29.0, "city_only": false, "base": "artillery", "nation": 0, "tier": "line", "ai": 1.0, "desc": "Roundshot, canister", "pl": true, "power": 0.727, "gun": {"len": 0.82, "bore": 0.85}},
	"fr_art8": {"name": "8-pounder Battery", "kind": "art", "count": 16, "files": 4, "accuracy": 1.0, "melee": 0.429, "defense": 0.429, "discipline": 0.85, "spacing": 34.0, "rank_spacing": 7.0, "walk": 8.8, "run": 11.88, "range": 700.0, "reload": 14.0, "cost": 200, "upkeep": 0.367, "time": 32.0, "city_only": false, "base": "artillery", "nation": 0, "tier": "line", "ai": 1.0, "desc": "Roundshot, canister", "pl": true, "power": 1.0, "gun": {"len": 1.0, "bore": 1.0}},
	"fr_grenadiers": {"name": "Line Grenadiers", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.238, "melee": 1.429, "defense": 1.286, "discipline": 1.225, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 8.289, "cost": 215, "upkeep": 0.383, "time": 34.0, "city_only": true, "charge": 1.15, "base": "grenadier", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "Assault: +3 melee, fatigue resistant", "pl": true},
	"fr_carabiniers": {"name": "Light Infantry Carabiniers", "kind": "inf", "count": 40, "files": 20, "accuracy": 1.512, "melee": 1.286, "defense": 1.0, "discipline": 1.225, "spacing": 10.0, "rank_spacing": 9.0, "walk": 15.0, "run": 32.0, "range": 252.0, "reload": 7.0, "cost": 215, "upkeep": 0.383, "time": 34.0, "city_only": true, "charge": 1.1, "base": "light", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "Loose order, elite light infantry", "pl": true, "look": {"hat": "bearskin", "hat_col": Color(0.13, 0.10, 0.08), "plume": Color(0.9, 0.1, 0.1), "facing": Color(0.9, 0.1, 0.1)}},
	"fr_sappers": {"name": "Sappers", "kind": "inf", "count": 27, "files": 9, "accuracy": 0.875, "melee": 1.143, "defense": 1.143, "discipline": 1.075, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 189.0, "reload": 9.0, "cost": 160, "upkeep": 0.3, "time": 28.0, "city_only": true, "charge": 1.0, "base": "line", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "Demolish fortifications, build earthworks", "pl": true, "look": {"plume": Color(0.85, 0.15, 0.12), "facing": Color(0.1, 0.1, 0.12)}},
	"fr_lancers": {"name": "Lancers", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.286, "defense": 0.714, "discipline": 1.075, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 215, "upkeep": 0.367, "time": 34.0, "city_only": true, "charge": 1.806, "base": "lancers", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "+10 charge vs infantry, break squares", "pl": true, "look": {"coat": Color(0.13, 0.3, 0.18), "hat": "helmet", "hat_col": Color(0.85, 0.68, 0.28), "facing": Color(0.85, 0.15, 0.12), "plume": Color(0.08, 0.06, 0.05)}},
	"fr_cuirassiers": {"name": "Cuirassiers", "kind": "cav", "count": 26, "files": 13, "accuracy": 1.0, "melee": 1.714, "defense": 1.429, "discipline": 1.225, "spacing": 14.0, "rank_spacing": 16.0, "walk": 26.4, "run": 55.2, "range": 0.0, "reload": 1.0, "cost": 290, "upkeep": 0.5, "time": 41.0, "city_only": true, "charge": 1.935, "base": "cuirassiers", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "Armour: -25% damage from fire", "pl": true, "armor": 0.25},
	"fr_carab_cheval": {"name": "Carabiniers-a-Cheval", "kind": "cav", "count": 26, "files": 13, "accuracy": 1.0, "melee": 1.857, "defense": 1.571, "discipline": 1.3, "spacing": 14.0, "rank_spacing": 16.0, "walk": 26.4, "run": 55.2, "range": 0.0, "reload": 1.0, "cost": 315, "upkeep": 0.533, "time": 44.0, "city_only": true, "charge": 1.935, "base": "cuirassiers", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "Armour: -25% damage from fire", "pl": true, "armor": 0.25, "look": {"coat": Color(0.93, 0.93, 0.9), "facing": Color(0.55, 0.68, 0.85), "hat_col": Color(0.85, 0.68, 0.28), "plume": Color(0.85, 0.15, 0.12)}},
	"fr_art12": {"name": "12-pounder Battery", "kind": "art", "count": 16, "files": 4, "accuracy": 1.094, "melee": 0.429, "defense": 0.429, "discipline": 0.85, "spacing": 34.0, "rank_spacing": 7.0, "walk": 8.8, "run": 11.88, "range": 840.0, "reload": 17.5, "cost": 270, "upkeep": 0.433, "time": 39.0, "city_only": true, "base": "artillery", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "Roundshot, canister, long range", "pl": true, "power": 1.273, "gun": {"len": 1.22, "bore": 1.22, "pairs": 3}},
	"fr_horse_art": {"name": "Horse Artillery", "kind": "art", "count": 16, "files": 4, "accuracy": 0.938, "melee": 0.571, "defense": 0.571, "discipline": 1.0, "spacing": 34.0, "rank_spacing": 7.0, "walk": 20.0, "run": 27.0, "range": 532.0, "reload": 9.545, "cost": 250, "upkeep": 0.417, "time": 37.0, "city_only": true, "base": "horse_art", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "Fast unlimber and limber", "pl": true, "power": 0.727, "gun": {"len": 0.85, "bore": 0.9}},
	"fr_howitzers": {"name": "Howitzers", "kind": "art", "count": 16, "files": 4, "accuracy": 0.781, "melee": 0.429, "defense": 0.429, "discipline": 0.85, "spacing": 34.0, "rank_spacing": 7.0, "walk": 8.8, "run": 11.88, "range": 630.0, "reload": 14.0, "cost": 225, "upkeep": 0.383, "time": 34.0, "city_only": true, "base": "artillery", "nation": 0, "tier": "elite", "ai": 0.5, "desc": "High-angle fire, incendiary shells", "pl": true, "power": 1.091, "shell": 0.7, "gun": {"len": 0.55, "bore": 1.55, "how": true}},
	"fr_yg_tirailleurs": {"name": "Young Guard Tirailleurs", "kind": "inf", "count": 54, "files": 27, "accuracy": 1.32, "melee": 1.429, "defense": 1.286, "discipline": 1.3, "spacing": 10.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 231.0, "reload": 7.875, "cost": 250, "upkeep": 0.433, "time": 37.0, "city_only": true, "charge": 1.1, "base": "light", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Loose order", "pl": true, "look": {"plume": Color(0.85, 0.15, 0.12), "facing": Color(0.85, 0.15, 0.12)}},
	"fr_fus_gren": {"name": "Fusilier-Grenadiers of the Guard", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.375, "melee": 1.571, "defense": 1.429, "discipline": 1.375, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 7.5, "cost": 290, "upkeep": 0.5, "time": 41.0, "city_only": true, "charge": 1.15, "base": "guard", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Solid elite", "pl": true, "look": {"hat": "shako", "hat_col": Color(0.08, 0.08, 0.09), "big": 1.1}},
	"fr_marins": {"name": "Sailors of the Guard", "kind": "inf", "count": 40, "files": 13, "accuracy": 1.32, "melee": 1.571, "defense": 1.286, "discipline": 1.375, "spacing": 9.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 210.0, "reload": 7.875, "cost": 270, "upkeep": 0.467, "time": 39.0, "city_only": true, "charge": 1.1, "base": "line", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Build bridges, +3 attack in towns", "pl": true, "look": {"coat": Color(0.1, 0.14, 0.32), "facing": Color(0.95, 0.5, 0.15), "plume": Color(0.95, 0.5, 0.15)}},
	"fr_chass_pied": {"name": "Foot Chasseurs of the Guard", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.8, "melee": 1.857, "defense": 1.714, "discipline": 1.525, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 231.0, "reload": 6.562, "cost": 380, "upkeep": 0.633, "time": 50.0, "city_only": true, "charge": 1.2, "base": "guard", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Platoon fire, fearless", "pl": true, "look": {"plume": Color(0.2, 0.55, 0.25)}},
	"fr_gren_pied": {"name": "Foot Grenadiers of the Guard", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.74, "melee": 2.143, "defense": 2.0, "discipline": 1.6, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 7.0, "cost": 430, "upkeep": 0.7, "time": 55.0, "city_only": true, "charge": 1.3, "base": "guard", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Never break; if destroyed, -3 morale to the whole army", "pl": true, "steadfast": true},
	"fr_chass_garde": {"name": "Horse Chasseurs of the Guard", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.857, "defense": 1.143, "discipline": 1.45, "spacing": 13.0, "rank_spacing": 15.0, "walk": 35.2, "run": 73.6, "range": 0.0, "reload": 1.0, "cost": 315, "upkeep": 0.533, "time": 44.0, "city_only": true, "charge": 1.548, "base": "hussars", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Emperor's escort: +2 morale near Napoleon", "pl": true, "look": {"coat": Color(0.13, 0.32, 0.2), "facing": Color(0.95, 0.5, 0.15), "plume": Color(0.15, 0.45, 0.2)}},
	"fr_mamelukes": {"name": "Mamelukes", "kind": "cav", "count": 22, "files": 11, "accuracy": 1.0, "melee": 2.143, "defense": 1.0, "discipline": 1.375, "spacing": 13.0, "rank_spacing": 15.0, "walk": 35.2, "run": 73.6, "range": 0.0, "reload": 1.0, "cost": 290, "upkeep": 0.5, "time": 41.0, "city_only": true, "charge": 1.548, "base": "hussars", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Melee bonus, frighten the enemy", "pl": true, "look": {"coat": Color(0.8, 0.15, 0.13), "hat": "round", "hat_col": Color(0.95, 0.95, 0.92), "facing": Color(0.13, 0.42, 0.25), "plume": Color(0.95, 0.95, 0.95), "belts": false}},
	"fr_red_lancers": {"name": "Red Lancers", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.714, "defense": 1.0, "discipline": 1.45, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 325, "upkeep": 0.533, "time": 44.0, "city_only": true, "charge": 2.065, "base": "lancers", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "+10 charge vs infantry, break squares", "pl": true, "look": {"coat": Color(0.82, 0.15, 0.13), "facing": Color(0.1, 0.14, 0.4), "hat_col": Color(0.82, 0.15, 0.13)}},
	"fr_drag_imp": {"name": "Empress Dragoons", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.857, "defense": 1.429, "discipline": 1.45, "spacing": 13.0, "rank_spacing": 15.0, "walk": 28.6, "run": 59.8, "range": 0.0, "reload": 1.0, "cost": 340, "upkeep": 0.55, "time": 46.0, "city_only": true, "charge": 1.677, "base": "dragoons", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Can dismount and fight on foot", "pl": true, "look": {"coat": Color(0.13, 0.3, 0.18), "facing": Color(0.93, 0.93, 0.9), "plume": Color(0.85, 0.15, 0.12)}},
	"fr_gren_cheval": {"name": "Horse Grenadiers of the Guard", "kind": "cav", "count": 26, "files": 13, "accuracy": 1.0, "melee": 2.286, "defense": 1.714, "discipline": 1.6, "spacing": 13.0, "rank_spacing": 15.0, "walk": 26.4, "run": 55.2, "range": 0.0, "reload": 1.0, "cost": 430, "upkeep": 0.7, "time": 55.0, "city_only": true, "charge": 2.323, "base": "dragoons", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Decisive charge: +2 morale to allies after a successful charge", "pl": true, "look": {"hat": "bearskin", "hat_col": Color(0.13, 0.10, 0.08), "coat": Color(0.1, 0.12, 0.3), "facing": Color(0.95, 0.95, 0.95), "plume": Color(0.85, 0.15, 0.12), "big": 1.15}},
	"fr_gendarmes": {"name": "Elite Gendarmes", "kind": "cav", "count": 22, "files": 11, "accuracy": 1.0, "melee": 1.714, "defense": 1.429, "discipline": 1.45, "spacing": 13.0, "rank_spacing": 15.0, "walk": 28.6, "run": 59.8, "range": 0.0, "reload": 1.0, "cost": 270, "upkeep": 0.467, "time": 39.0, "city_only": true, "charge": 1.419, "base": "dragoons", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Aura: no panic nearby", "pl": true, "aura": 0.35, "aura_r": 320.0, "look": {"hat": "bearskin", "hat_col": Color(0.13, 0.10, 0.08), "coat": Color(0.1, 0.12, 0.3), "facing": Color(0.85, 0.15, 0.12), "plume": Color(0.85, 0.15, 0.12)}},
	"fr_art_garde": {"name": "Foot Artillery of the Guard (12-pdr)", "kind": "art", "count": 16, "files": 4, "accuracy": 1.406, "melee": 0.714, "defense": 0.714, "discipline": 1.15, "spacing": 34.0, "rank_spacing": 7.0, "walk": 8.8, "run": 11.88, "range": 868.0, "reload": 14.0, "cost": 380, "upkeep": 0.633, "time": 50.0, "city_only": true, "base": "artillery", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Grand battery: +10% accuracy next to another battery", "pl": true, "power": 1.364, "look": {"hat": "bearskin", "hat_col": Color(0.13, 0.10, 0.08)}, "gun": {"len": 1.22, "bore": 1.25, "pairs": 3, "polish": true}},
	"fr_horse_art_garde": {"name": "Horse Artillery of the Guard", "kind": "art", "count": 16, "files": 4, "accuracy": 1.25, "melee": 0.857, "defense": 0.857, "discipline": 1.225, "spacing": 34.0, "rank_spacing": 7.0, "walk": 21.6, "run": 29.16, "range": 560.0, "reload": 8.077, "cost": 340, "upkeep": 0.567, "time": 46.0, "city_only": true, "base": "horse_art", "nation": 0, "tier": "guard", "ai": 0.25, "desc": "Fast deployment", "pl": true, "power": 0.818, "gun": {"len": 0.9, "bore": 0.95, "polish": true}},
	"fr_pontoniers": {"name": "Pontonniers", "kind": "inf", "count": 20, "files": 7, "accuracy": 0.562, "melee": 0.714, "defense": 0.857, "discipline": 0.925, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 189.0, "reload": 10.5, "cost": 135, "upkeep": 0.25, "time": 26.0, "city_only": true, "charge": 0.75, "base": "line", "nation": 0, "tier": "support", "ai": 0.08, "desc": "Build bridges", "pl": true, "look": {"plume": Color(0.85, 0.15, 0.12), "pack": false}},
	"fr_larrey": {"name": "Larrey's Flying Ambulance", "kind": "inf", "count": 8, "files": 4, "accuracy": 0.05, "melee": 0.143, "defense": 0.286, "discipline": 0.85, "spacing": 9.0, "rank_spacing": 9.0, "walk": 17.0, "run": 36.0, "range": 0.0, "reload": 1.0, "cost": 180, "upkeep": 0.333, "time": 30.0, "city_only": true, "charge": 0.6, "base": "line", "nation": 0, "tier": "support", "ai": 0.08, "desc": "Heals: +2% men/min to nearby units", "pl": true, "heal": 0.02, "heal_r": 380.0, "unique": 1, "look": {"hat": "bicorne", "pack": false, "belts": false, "facing": Color(0.6, 0.12, 0.12)}},
	"fr_marshal": {"name": "Marshal", "kind": "cav", "count": 8, "files": 4, "accuracy": 1.0, "melee": 2.0, "defense": 1.714, "discipline": 1.525, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 340, "upkeep": 0.5, "time": 46.0, "city_only": true, "charge": 1.613, "base": "dragoons", "nation": 0, "tier": "support", "ai": 0.08, "desc": "Aura depends on the marshal (Ney/Davout/Murat)", "pl": true, "aura": 0.4, "aura_r": 520.0, "unique": 3, "names": ["Ney", "Davout", "Murat", "Lannes", "Masséna", "Soult"], "look": {"hat": "bicorne", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0.95, 0.95, 0.95), "coat": Color(0.1, 0.12, 0.3), "facing": Color(0.85, 0.68, 0.28), "big": 1.15}},
	"fr_napoleon": {"name": "Napoleon", "kind": "cav", "count": 11, "files": 6, "accuracy": 1.0, "melee": 2.143, "defense": 1.857, "discipline": 1.75, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 560, "upkeep": 0.833, "time": 68.0, "city_only": true, "charge": 1.806, "base": "dragoons", "nation": 0, "tier": "support", "ai": 0.08, "desc": "Global +2 morale; Sun of Austerlitz", "pl": true, "aura": 0.3, "aura_r": 100000.0, "unique": 1, "fmt": "Napoleon", "look": {"hat": "bicorne", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0, 0, 0, 0), "coat": Color(0.55, 0.55, 0.53), "facing": Color(0.13, 0.3, 0.18), "big": 1.2}},
	"fr_pol_chevau": {"name": "Polish Light Horse", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.714, "defense": 1.143, "discipline": 1.45, "spacing": 13.0, "rank_spacing": 15.0, "walk": 35.2, "run": 73.6, "range": 0.0, "reload": 1.0, "cost": 305, "upkeep": 0.5, "time": 42.0, "city_only": true, "charge": 1.806, "base": "lancers", "nation": 0, "tier": "allies", "ai": 0.4, "desc": "Somosierra: +10 charge vs artillery", "pl": true, "look": {"coat": Color(0.1, 0.12, 0.3), "facing": Color(0.8, 0.12, 0.15), "hat_col": Color(0.8, 0.12, 0.15)}},
	"fr_swiss": {"name": "Swiss Regiment", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.238, "melee": 1.286, "defense": 1.286, "discipline": 1.3, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 8.289, "cost": 200, "upkeep": 0.367, "time": 32.0, "city_only": true, "charge": 1.05, "base": "line", "nation": 0, "tier": "allies", "ai": 0.4, "desc": "+2 defense and morale when defending", "pl": true, "look": {"coat": Color(0.78, 0.18, 0.14), "facing": Color(0.92, 0.75, 0.2)}},
	"fr_irish": {"name": "Irish Legion", "kind": "inf", "count": 40, "files": 13, "accuracy": 1.05, "melee": 1.143, "defense": 1.0, "discipline": 1.15, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 8.75, "cost": 180, "upkeep": 0.333, "time": 30.0, "city_only": true, "charge": 1.05, "base": "line", "nation": 0, "tier": "allies", "ai": 0.4, "desc": "+2 morale vs Britain", "pl": true, "look": {"coat": Color(0.13, 0.4, 0.2), "facing": Color(0.92, 0.75, 0.2)}},
	"fr_westphal": {"name": "Westphalian Infantry", "kind": "inf", "count": 54, "files": 18, "accuracy": 0.95, "melee": 0.857, "defense": 0.857, "discipline": 0.925, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 9.545, "cost": 110, "upkeep": 0.217, "time": 23.0, "city_only": false, "charge": 0.95, "base": "line", "nation": 0, "tier": "allies", "ai": 0.4, "desc": "Cheap line infantry", "pl": true, "look": {"coat": Color(0.92, 0.91, 0.86), "facing": Color(0.1, 0.12, 0.3)}},
	# --- Wielka Brytania: 38 jednostek z arkusza "Britain – units and stats" (generowane, gen_gb.py)
	"gb_line": {"name": "Line Infantry (Redcoats)", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.25, "melee": 0.857, "defense": 1.0, "discipline": 1.075, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 7.5, "cost": 145, "upkeep": 0.267, "time": 26.0, "city_only": false, "charge": 0.95, "base": "line", "nation": 1, "tier": "line", "ai": 1.0, "desc": "Two-rank line: +15% firepower; square", "pl": true},
	"gb_light": {"name": "Light Infantry", "kind": "inf", "count": 54, "files": 27, "accuracy": 1.375, "melee": 0.857, "defense": 0.857, "discipline": 1.075, "spacing": 10.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 231.0, "reload": 7.159, "cost": 170, "upkeep": 0.3, "time": 29.0, "city_only": false, "charge": 0.95, "base": "light", "nation": 1, "tier": "line", "ai": 1.0, "desc": "Loose order, square", "pl": true},
	"gb_militia": {"name": "Militia", "kind": "inf", "count": 54, "files": 18, "accuracy": 0.72, "melee": 0.571, "defense": 0.714, "discipline": 0.775, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 189.0, "reload": 9.844, "cost": 80, "upkeep": 0.15, "time": 20.0, "city_only": false, "charge": 0.8, "base": "militia", "nation": 1, "tier": "line", "ai": 1.0, "desc": "+3 morale defending own territory", "pl": true},
	"gb_light_drag": {"name": "Light Dragoons", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.143, "defense": 0.714, "discipline": 1.0, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 160, "upkeep": 0.3, "time": 28.0, "city_only": false, "charge": 1.161, "base": "hussars", "nation": 1, "tier": "line", "ai": 1.0, "desc": "Scouting, pursuit", "pl": true, "look": {"coat": Color(0.1, 0.12, 0.3), "hat": "shako", "hat_col": Color(0.08, 0.08, 0.09), "facing": Color(0.8, 0.15, 0.12), "plume": Color(0.95, 0.95, 0.95)}},
	"gb_hussars": {"name": "Hussars", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.286, "defense": 0.571, "discipline": 1.0, "spacing": 13.0, "rank_spacing": 15.0, "walk": 35.2, "run": 73.6, "range": 0.0, "reload": 1.0, "cost": 175, "upkeep": 0.317, "time": 30.0, "city_only": false, "charge": 1.29, "base": "hussars", "nation": 1, "tier": "line", "ai": 1.0, "desc": "+5 charge vs routing troops", "pl": true, "look": {"coat": Color(0.1, 0.12, 0.3), "facing": Color(0.93, 0.93, 0.9)}},
	"gb_art6": {"name": "6-pounder Foot Battery", "kind": "art", "count": 16, "files": 4, "accuracy": 1.0, "melee": 0.429, "defense": 0.429, "discipline": 0.85, "spacing": 34.0, "rank_spacing": 7.0, "walk": 10.4, "run": 14.04, "range": 560.0, "reload": 10.5, "cost": 170, "upkeep": 0.333, "time": 29.0, "city_only": false, "base": "artillery", "nation": 1, "tier": "line", "ai": 1.0, "desc": "Roundshot, canister", "pl": true, "power": 0.727, "gun": {"len": 0.82, "bore": 0.85}, "look": {"coat": Color(0.1, 0.12, 0.28), "facing": Color(0.8, 0.15, 0.12)}},
	"gb_art9": {"name": "9-pounder Foot Battery", "kind": "art", "count": 16, "files": 4, "accuracy": 1.062, "melee": 0.429, "defense": 0.429, "discipline": 0.925, "spacing": 34.0, "rank_spacing": 7.0, "walk": 8.8, "run": 11.88, "range": 728.0, "reload": 13.125, "cost": 215, "upkeep": 0.383, "time": 34.0, "city_only": false, "base": "artillery", "nation": 1, "tier": "line", "ai": 1.0, "desc": "Roundshot, canister, shrapnel", "pl": true, "power": 1.055, "gun": {"len": 1.08, "bore": 1.08}, "look": {"coat": Color(0.1, 0.12, 0.28), "facing": Color(0.8, 0.15, 0.12)}},
	"gb_grenadiers": {"name": "Grenadier Company", "kind": "inf", "count": 40, "files": 13, "accuracy": 1.43, "melee": 1.286, "defense": 1.286, "discipline": 1.225, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 7.159, "cost": 215, "upkeep": 0.383, "time": 34.0, "city_only": true, "charge": 1.1, "base": "grenadier", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Assault: +3 melee", "pl": true, "look": {"hat": "shako", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0.95, 0.95, 0.95)}},
	"gb_95th": {"name": "95th Rifles", "kind": "inf", "count": 40, "files": 20, "accuracy": 2.275, "melee": 0.714, "defense": 0.714, "discipline": 1.15, "spacing": 11.0, "rank_spacing": 10.0, "walk": 15.0, "run": 32.0, "range": 336.0, "reload": 10.5, "cost": 270, "upkeep": 0.467, "time": 39.0, "city_only": true, "charge": 0.85, "base": "rifles", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Baker rifle: +20% damage vs officers and gun crews; loose order", "pl": true, "fmt": "%s Bn, 95th Rifles"},
	"gb_60th": {"name": "5/60th Rifles", "kind": "inf", "count": 40, "files": 20, "accuracy": 1.98, "melee": 0.714, "defense": 0.714, "discipline": 1.15, "spacing": 11.0, "rank_spacing": 10.0, "walk": 15.0, "run": 32.0, "range": 315.0, "reload": 10.5, "cost": 250, "upkeep": 0.433, "time": 37.0, "city_only": true, "charge": 0.85, "base": "rifles", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Rifles, loose order, hidden in woods", "pl": true, "fmt": "%s Bn, 60th Rifles", "look": {"facing": Color(0.7, 0.12, 0.12)}},
	"gb_highlanders": {"name": "Highlanders", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.375, "melee": 1.571, "defense": 1.143, "discipline": 1.375, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 7.5, "cost": 235, "upkeep": 0.417, "time": 36.0, "city_only": true, "charge": 1.25, "base": "line", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "+3 melee; bagpipes: +1 morale to nearby allies", "pl": true, "aura": 0.15, "aura_r": 220.0, "look": {"hat": "bearskin", "hat_col": Color(0.07, 0.07, 0.07), "facing": Color(0.1, 0.12, 0.3), "plume": Color(0.85, 0.12, 0.12)}},
	"gb_marines": {"name": "Royal Marines", "kind": "inf", "count": 40, "files": 13, "accuracy": 1.3, "melee": 1.143, "defense": 1.143, "discipline": 1.225, "spacing": 9.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 210.0, "reload": 7.5, "cost": 200, "upkeep": 0.367, "time": 32.0, "city_only": true, "charge": 1.0, "base": "line", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Landing party, +3 attack in towns", "pl": true, "look": {"hat": "round", "facing": Color(0.1, 0.12, 0.3)}},
	"gb_sappers": {"name": "Royal Sappers and Miners", "kind": "inf", "count": 27, "files": 9, "accuracy": 0.95, "melee": 1.0, "defense": 1.143, "discipline": 1.075, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 189.0, "reload": 8.75, "cost": 160, "upkeep": 0.3, "time": 28.0, "city_only": true, "charge": 0.95, "base": "line", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Demolish fortifications, build earthworks", "pl": true, "look": {"facing": Color(0.1, 0.12, 0.3), "pack": false}},
	"gb_heavy_drag": {"name": "Heavy Dragoons", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.571, "defense": 1.143, "discipline": 1.15, "spacing": 13.0, "rank_spacing": 15.0, "walk": 28.6, "run": 59.8, "range": 0.0, "reload": 1.0, "cost": 250, "upkeep": 0.433, "time": 37.0, "city_only": true, "charge": 1.806, "base": "dragoons", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Heavy charge", "pl": true},
	"gb_drag_guards": {"name": "Dragoons of the Guard", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.714, "defense": 1.286, "discipline": 1.225, "spacing": 13.0, "rank_spacing": 15.0, "walk": 28.6, "run": 59.8, "range": 0.0, "reload": 1.0, "cost": 270, "upkeep": 0.467, "time": 39.0, "city_only": true, "charge": 1.871, "base": "dragoons", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Heavy charge", "pl": true, "look": {"facing": Color(0.1, 0.12, 0.3)}},
	"gb_scots_greys": {"name": "Royal Scots Greys", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.714, "defense": 1.143, "discipline": 1.3, "spacing": 13.0, "rank_spacing": 15.0, "walk": 30.8, "run": 64.4, "range": 0.0, "reload": 1.0, "cost": 280, "upkeep": 0.483, "time": 40.0, "city_only": true, "charge": 2.065, "base": "dragoons", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Devastating charge; then uncontrolled pursuit (hard to recall)", "pl": true, "fmt": "%s Squadron, Royal Scots Greys", "look": {"hat": "bearskin", "hat_col": Color(0.08, 0.07, 0.06), "facing": Color(0.1, 0.12, 0.3), "plume": Color(0.95, 0.95, 0.95), "big": 1.1}},
	"gb_rha": {"name": "Royal Horse Artillery", "kind": "art", "count": 16, "files": 4, "accuracy": 1.125, "melee": 0.714, "defense": 0.714, "discipline": 1.15, "spacing": 34.0, "rank_spacing": 7.0, "walk": 23.2, "run": 31.32, "range": 560.0, "reload": 7.5, "cost": 270, "upkeep": 0.45, "time": 39.0, "city_only": true, "base": "horse_art", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Fastest unlimbering in the game", "pl": true, "power": 0.764, "gun": {"len": 0.85, "bore": 0.9}, "look": {"coat": Color(0.1, 0.12, 0.28), "facing": Color(0.8, 0.15, 0.12)}},
	"gb_howitzers": {"name": "5.5-inch Howitzers", "kind": "art", "count": 16, "files": 4, "accuracy": 0.875, "melee": 0.429, "defense": 0.429, "discipline": 0.85, "spacing": 34.0, "rank_spacing": 7.0, "walk": 8.8, "run": 11.88, "range": 630.0, "reload": 14.0, "cost": 225, "upkeep": 0.383, "time": 34.0, "city_only": true, "base": "artillery", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "High-angle fire, shrapnel", "pl": true, "power": 1.091, "shell": 0.7, "gun": {"len": 0.55, "bore": 1.55, "how": true}, "look": {"coat": Color(0.1, 0.12, 0.28), "facing": Color(0.8, 0.15, 0.12)}},
	"gb_rockets": {"name": "Congreve Rockets", "kind": "art", "count": 16, "files": 4, "accuracy": 0.469, "melee": 0.429, "defense": 0.429, "discipline": 0.85, "spacing": 34.0, "rank_spacing": 7.0, "walk": 16.8, "run": 22.68, "range": 980.0, "reload": 8.4, "cost": 160, "upkeep": 0.267, "time": 28.0, "city_only": true, "base": "artillery", "nation": 1, "tier": "elite", "ai": 0.5, "desc": "Inaccurate; -2 target morale, frighten cavalry", "pl": true, "power": 0.909, "shell": 0.6, "gun": {"len": 1.3, "bore": 0.45}, "look": {"coat": Color(0.1, 0.12, 0.28), "facing": Color(0.8, 0.15, 0.12)}},
	"gb_coldstream": {"name": "Coldstream Guards", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.8, "melee": 1.714, "defense": 1.714, "discipline": 1.525, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 6.3, "cost": 360, "upkeep": 0.6, "time": 48.0, "city_only": true, "charge": 1.2, "base": "guard", "nation": 1, "tier": "guard", "ai": 0.25, "desc": "Hold the line: +3 defense when stationary", "pl": true, "fmt": "%s Bn, Coldstream Guards", "look": {"hat": "shako", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0.95, 0.95, 0.95), "big": 1.1}},
	"gb_1st_guards": {"name": "1st Foot Guards", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.86, "melee": 1.857, "defense": 1.857, "discipline": 1.6, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 6.058, "cost": 405, "upkeep": 0.667, "time": 52.0, "city_only": true, "charge": 1.25, "base": "guard", "nation": 1, "tier": "guard", "ai": 0.25, "desc": "Close volley: +25% damage under 50 m", "pl": true, "fmt": "%s Bn, 1st Foot Guards", "look": {"hat": "shako", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0.95, 0.95, 0.95), "big": 1.1}},
	"gb_3rd_guards": {"name": "3rd Foot Guards (Scots)", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.8, "melee": 1.857, "defense": 1.714, "discipline": 1.525, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 6.3, "cost": 370, "upkeep": 0.617, "time": 49.0, "city_only": true, "charge": 1.25, "base": "guard", "nation": 1, "tier": "guard", "ai": 0.25, "desc": "Fortify buildings: +4 defense in buildings", "pl": true, "fmt": "%s Bn, 3rd Foot Guards", "look": {"hat": "shako", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0.95, 0.95, 0.95), "big": 1.1}},
	"gb_guards_light": {"name": "Guards Light Companies", "kind": "inf", "count": 40, "files": 20, "accuracy": 1.86, "melee": 1.429, "defense": 1.286, "discipline": 1.45, "spacing": 10.0, "rank_spacing": 9.0, "walk": 14.0, "run": 30.0, "range": 231.0, "reload": 6.3, "cost": 290, "upkeep": 0.5, "time": 41.0, "city_only": true, "charge": 1.1, "base": "light", "nation": 1, "tier": "guard", "ai": 0.25, "desc": "Loose order; Hougoumont: +5 defense in buildings", "pl": true, "look": {"plume": Color(0.95, 0.95, 0.95), "facing": Color(0.1, 0.12, 0.3)}},
	"gb_life_guards": {"name": "Life Guards", "kind": "cav", "count": 26, "files": 13, "accuracy": 1.0, "melee": 2.143, "defense": 1.714, "discipline": 1.525, "spacing": 13.0, "rank_spacing": 15.0, "walk": 28.6, "run": 59.8, "range": 0.0, "reload": 1.0, "cost": 380, "upkeep": 0.633, "time": 50.0, "city_only": true, "charge": 2.194, "base": "dragoons", "nation": 1, "tier": "guard", "ai": 0.25, "desc": "Elite heavy cavalry", "pl": true, "fmt": "%s Life Guards", "look": {"facing": Color(0.1, 0.12, 0.3), "hat_col": Color(0.75, 0.75, 0.78), "plume": Color(0.95, 0.95, 0.95), "big": 1.1}},
	"gb_blues": {"name": "Royal Horse Guards (Blues)", "kind": "cav", "count": 26, "files": 13, "accuracy": 1.0, "melee": 2.0, "defense": 1.714, "discipline": 1.525, "spacing": 13.0, "rank_spacing": 15.0, "walk": 28.6, "run": 59.8, "range": 0.0, "reload": 1.0, "cost": 370, "upkeep": 0.617, "time": 49.0, "city_only": true, "charge": 2.129, "base": "dragoons", "nation": 1, "tier": "guard", "ai": 0.25, "desc": "Elite heavy cavalry", "pl": true, "fmt": "%s Squadron, Royal Horse Guards", "look": {"coat": Color(0.1, 0.12, 0.3), "facing": Color(0.8, 0.15, 0.12), "hat_col": Color(0.75, 0.75, 0.78), "plume": Color(0.85, 0.12, 0.12), "big": 1.1}},
	"gb_chestnut": {"name": "Chestnut Troop RHA", "kind": "art", "count": 16, "files": 4, "accuracy": 1.25, "melee": 0.857, "defense": 0.857, "discipline": 1.3, "spacing": 34.0, "rank_spacing": 7.0, "walk": 23.2, "run": 31.32, "range": 588.0, "reload": 7.0, "cost": 340, "upkeep": 0.55, "time": 46.0, "city_only": true, "base": "horse_art", "nation": 1, "tier": "guard", "ai": 0.25, "desc": "Veteran horse battery: +10% accuracy", "pl": true, "power": 0.818, "unique": 1, "fmt": "Chestnut Troop RHA", "gun": {"len": 0.88, "bore": 0.92, "polish": true}, "look": {"coat": Color(0.1, 0.12, 0.28), "facing": Color(0.8, 0.15, 0.12)}},
	"gb_surgeons": {"name": "Regimental Surgeons", "kind": "inf", "count": 8, "files": 4, "accuracy": 0.05, "melee": 0.143, "defense": 0.286, "discipline": 0.85, "spacing": 9.0, "rank_spacing": 9.0, "walk": 17.0, "run": 36.0, "range": 0.0, "reload": 1.0, "cost": 180, "upkeep": 0.333, "time": 30.0, "city_only": true, "charge": 0.6, "base": "line", "nation": 1, "tier": "support", "ai": 0.08, "desc": "Heal: +2% men/min to nearby units", "pl": true, "heal": 0.02, "heal_r": 380.0, "unique": 2, "look": {"hat": "bicorne", "pack": false, "belts": false, "coat": Color(0.12, 0.12, 0.14)}},
	"gb_commissariat": {"name": "Commissariat Train", "kind": "inf", "count": 8, "files": 4, "accuracy": 0.05, "melee": 0.143, "defense": 0.286, "discipline": 0.775, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 0.0, "reload": 1.0, "cost": 135, "upkeep": 0.25, "time": 26.0, "city_only": true, "charge": 0.6, "base": "line", "nation": 1, "tier": "support", "ai": 0.08, "desc": "Supply: -20% upkeep in region, replenishes ammo", "pl": true, "unique": 2, "look": {"hat": "round", "pack": false, "belts": false, "coat": Color(0.1, 0.12, 0.3)}},
	"gb_general": {"name": "General", "kind": "cav", "count": 8, "files": 4, "accuracy": 1.0, "melee": 1.857, "defense": 1.571, "discipline": 1.45, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 315, "upkeep": 0.5, "time": 44.0, "city_only": true, "charge": 1.548, "base": "dragoons", "nation": 1, "tier": "support", "ai": 0.08, "desc": "Command aura (e.g. Picton: infantry, Uxbridge: cavalry)", "pl": true, "aura": 0.4, "aura_r": 520.0, "unique": 3, "names": ["Picton", "Uxbridge", "Hill", "Ponsonby", "Somerset", "Maitland"], "look": {"hat": "bicorne", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0.95, 0.95, 0.95), "facing": Color(0.85, 0.68, 0.28), "big": 1.15}},
	"gb_wellington": {"name": "Wellington", "kind": "cav", "count": 11, "files": 6, "accuracy": 1.0, "melee": 2.0, "defense": 1.857, "discipline": 1.75, "spacing": 13.0, "rank_spacing": 15.0, "walk": 33.0, "run": 69.0, "range": 0.0, "reload": 1.0, "cost": 560, "upkeep": 0.833, "time": 68.0, "city_only": true, "charge": 1.677, "base": "dragoons", "nation": 1, "tier": "support", "ai": 0.08, "desc": "Reverse slope: units hidden behind ridges; +2 morale to all defenders", "pl": true, "aura": 0.3, "aura_r": 100000.0, "unique": 1, "fmt": "Wellington", "look": {"hat": "bicorne", "hat_col": Color(0.08, 0.08, 0.09), "plume": Color(0, 0, 0, 0), "coat": Color(0.12, 0.13, 0.2), "facing": Color(0.93, 0.93, 0.9), "big": 1.2}},
	"gb_kgl_line": {"name": "KGL Line Infantry", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.375, "melee": 1.143, "defense": 1.143, "discipline": 1.3, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 7.5, "cost": 200, "upkeep": 0.367, "time": 32.0, "city_only": true, "charge": 1.05, "base": "line", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "Veteran line infantry", "pl": true, "look": {"facing": Color(0.1, 0.12, 0.3)}},
	"gb_kgl_light": {"name": "KGL Light Infantry", "kind": "inf", "count": 40, "files": 20, "accuracy": 1.92, "melee": 1.143, "defense": 1.143, "discipline": 1.375, "spacing": 11.0, "rank_spacing": 10.0, "walk": 14.0, "run": 30.0, "range": 294.0, "reload": 9.844, "cost": 250, "upkeep": 0.433, "time": 37.0, "city_only": true, "charge": 1.0, "base": "rifles", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "Rifles; +4 defense in buildings", "pl": true},
	"gb_kgl_hussars": {"name": "KGL Hussars", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.571, "defense": 0.857, "discipline": 1.3, "spacing": 13.0, "rank_spacing": 15.0, "walk": 35.2, "run": 73.6, "range": 0.0, "reload": 1.0, "cost": 235, "upkeep": 0.4, "time": 36.0, "city_only": true, "charge": 1.419, "base": "hussars", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "Disciplined: no uncontrolled pursuit", "pl": true, "look": {"coat": Color(0.1, 0.12, 0.3), "facing": Color(0.8, 0.15, 0.12)}},
	"gb_nl_carab": {"name": "Dutch-Belgian Carabiniers", "kind": "cav", "count": 26, "files": 13, "accuracy": 1.0, "melee": 1.571, "defense": 1.286, "discipline": 1.075, "spacing": 13.0, "rank_spacing": 15.0, "walk": 26.4, "run": 55.2, "range": 0.0, "reload": 1.0, "cost": 250, "upkeep": 0.433, "time": 37.0, "city_only": true, "charge": 1.742, "base": "dragoons", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "Heavy cavalry, lower morale", "pl": true, "look": {"coat": Color(0.1, 0.12, 0.3), "facing": Color(0.8, 0.15, 0.12), "hat_col": Color(0.85, 0.68, 0.28)}},
	"gb_brunswick": {"name": "Black Brunswickers", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.15, "melee": 1.286, "defense": 1.0, "discipline": 1.3, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 7.875, "cost": 190, "upkeep": 0.35, "time": 31.0, "city_only": true, "charge": 1.1, "base": "line", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "+2 attack vs France", "pl": true, "look": {"coat": Color(0.08, 0.08, 0.09), "facing": Color(0.45, 0.6, 0.8), "plume": Color(0.05, 0.05, 0.05), "hat_col": Color(0.05, 0.05, 0.05)}},
	"gb_brunswick_hus": {"name": "Brunswick Hussars", "kind": "cav", "count": 30, "files": 15, "accuracy": 1.0, "melee": 1.429, "defense": 0.714, "discipline": 1.225, "spacing": 13.0, "rank_spacing": 15.0, "walk": 35.2, "run": 73.6, "range": 0.0, "reload": 1.0, "cost": 190, "upkeep": 0.333, "time": 31.0, "city_only": true, "charge": 1.29, "base": "hussars", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "+2 morale vs France", "pl": true, "look": {"coat": Color(0.08, 0.08, 0.09), "facing": Color(0.45, 0.6, 0.8), "plume": Color(0.05, 0.05, 0.05)}},
	"gb_cacadores": {"name": "Portuguese Cacadores", "kind": "inf", "count": 40, "files": 20, "accuracy": 1.375, "melee": 0.857, "defense": 0.857, "discipline": 1.075, "spacing": 10.0, "rank_spacing": 9.0, "walk": 15.0, "run": 32.0, "range": 252.0, "reload": 7.875, "cost": 160, "upkeep": 0.283, "time": 28.0, "city_only": true, "charge": 0.9, "base": "light", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "Loose order, cheap light infantry", "pl": true, "look": {"coat": Color(0.4, 0.28, 0.17), "facing": Color(0.08, 0.08, 0.08), "plume": Color(0.2, 0.4, 0.2)}},
	"gb_port_line": {"name": "Portuguese Line Infantry", "kind": "inf", "count": 54, "files": 18, "accuracy": 1.1, "melee": 0.857, "defense": 0.857, "discipline": 1.0, "spacing": 9.0, "rank_spacing": 9.0, "walk": 13.0, "run": 28.0, "range": 210.0, "reload": 8.289, "cost": 125, "upkeep": 0.233, "time": 24.0, "city_only": false, "charge": 0.95, "base": "line", "nation": 1, "tier": "allies", "ai": 0.4, "desc": "Cheap line infantry", "pl": true, "look": {"coat": Color(0.12, 0.16, 0.38), "facing": Color(0.93, 0.93, 0.9)}},
}

const NAME_FORMATS := [
	{"line": "%s Regiment of the Line", "light": "%s Light Regiment", "grenadier": "%s Grenadier Bn",
		"guard": "%s Imperial Guard", "hussars": "%s Hussars", "lancers": "%s Chevau-Legers Lancers", "artillery": "%s Foot Battery",
		"militia": "%s National Guard", "rifles": "%s Voltigeurs", "dragoons": "%s Dragoons", "cuirassiers": "%s Cuirassiers",
		"horse_art": "%s Horse Battery"},
	{"line": "%s Regiment of Foot", "light": "%s Light Infantry", "grenadier": "%s Grenadier Coy", "guard": "%s Foot Guards",
		"hussars": "%s Hussars", "lancers": "%s Lancers", "artillery": "%s Battery RA",
		"militia": "%s County Militia", "rifles": "%s Rifles", "dragoons": "%s Light Dragoons", "cuirassiers": "%s Heavy Dragoons",
		"horse_art": "%s Troop RHA"},
	{"line": "%s Infantry Regiment", "light": "%s Jäger Battalion", "grenadier": "%s Grenadier Bn", "guard": "%s Leib-Garde",
		"hussars": "%s Hussar Regiment", "lancers": "%s Uhlans", "artillery": "%s Position Battery", "militia": "%s Landwehr Bn",
		"rifles": "%s Feldjäger", "dragoons": "%s Dragoon Regiment", "cuirassiers": "%s Kürassier Regiment", "horse_art": "%s Cavalry Battery"},
	{"line": "%s Musketeer Regiment", "light": "%s Jäger Regiment", "grenadier": "%s Grenadier Regiment", "guard": "%s Life Guard",
		"hussars": "%s Hussar Regiment", "lancers": "%s Uhlan Regiment", "artillery": "%s Field Battery", "militia": "%s Militia",
		"rifles": "%s Sharpshooters", "dragoons": "%s Dragoon Regiment", "cuirassiers": "%s Cuirassier Regiment", "horse_art": "%s Horse Battery"},
	{"line": "%s Infantry Regiment", "light": "%s Light Battalion", "grenadier": "%s Grenadier Bn", "guard": "%s Garde",
		"hussars": "%s Hussar Regiment", "lancers": "%s Uhlan Regiment", "artillery": "%s Foot Battery", "militia": "%s Reserve Bn",
		"rifles": "%s Jäger Battalion", "dragoons": "%s Dragoon Regiment", "cuirassiers": "%s Kürassier Regiment", "horse_art": "%s Horse Battery"},
]

const TEAM_COLORS := [Color(0.22, 0.36, 0.86), Color(0.86, 0.18, 0.15), Color(0.93, 0.76, 0.16), Color(0.16, 0.6, 0.42), Color(0.16, 0.16, 0.2)]   # barwy nacji na mapie
const NEUTRAL_COLOR := Color(0.62, 0.62, 0.6)

var map_size: Vector2 = MAP_SIZES[chosen_size]
var terrain: Terrain
var corpses: CorpseLayer
var effects: Effects
var cam: BattleCamera
var overlay: Overlay
var units_root: Node2D
var regiments: Array[Regiment] = []
var territory: Territory
var deploy_pos: Array = []   # punkty, od których strony rozwijają armie (stolice albo krańce pola bitwy)
var sfx: Sfx
var _slow_acc := 0.0
var armies := {}          # id -> nazwa ("1st Army")
var _army_counter := 0
var selected: Array[Regiment] = []
var settlements: Array[Settlement] = []
var selected_settlement: Settlement = null
var balls: Array = []

var gold := [START_GOLD, START_GOLD]
var income := [0.0, 0.0]
var upkeep := [0.0, 0.0]
var _unpaid := [0.0, 0.0]
var _name_counters := {}
var messages: Array = []   # [tekst, czas]

var sim_time := 0.0
var time_scale := 1.0
var paused := false
var menu_open := false
var stats := {"kills": [0, 0], "losses": [0, 0], "drowned": [0, 0], "captured": [0, 0], "prisoners": [0, 0], "recruited": [0, 0],
	"earned": [0.0, 0.0], "spent": [0.0, 0.0], "peak_men": [0, 0], "battles": [0, 0]}
var stats_hist: Array = []   # przebieg bitwy: [czas, ludzie 0, ludzie 1, straty 0, straty 1] co HIST_STEP sekund
var _hist_next := 0.5
const HIST_STEP := 5.0
var show_all := false  # trzymana Spacja: podgląd wszystkich oddziałów i rozkazów
var soldier_alpha := 1.0
var icon_alpha := 0.0
var result_text := ""
var victory_ack := false   # gracz po zwycięstwie wybrał "graj dalej": bitwa trwa, wynik już nie wraca
var _ai_timer := 2.0
var _fade_timer := 0.0
var _autotest := OS.get_cmdline_user_args().has("--autotest")
static var PROF := OS.get_cmdline_user_args().has("--perftest")   # test wydajności: pomiar czasu części symulacji
static var perf := {}
var last_step := true   # czy bieżący krok symulacji jest ostatnim w tej klatce (ciężkie rzeczy raz na klatkę)
var _cinematic := OS.get_cmdline_user_args().has("--cinematic")   # ujęcie filmowe (zwiastun): bez HUD, kamera po torze

# stan myszy
var lmb_down := false
var box_active := false
var box_start := Vector2.ZERO
var rmb_down := false
var form_active := false   # trwa przeciąganie LPM = ustawianie szyku
var _lmb_can_form := false
var order_start := Vector2.ZERO
var order_drag_now := Vector2.ZERO
var rmb_start_screen := Vector2.ZERO


static func owner_color(t: int) -> Color:
	return TEAM_COLORS[nation(t)] if t >= 0 else NEUTRAL_COLOR


func _ready() -> void:
	Net.ensure(get_tree())
	if Net.inst != null:
		Net.inst.battle = self
	if Net.active():
		seed(net_seed)   # ta sama mapa u wszystkich graczy
		first_launch = false
	else:
		randomize()
	_parse_server_args()
	if OS.get_cmdline_user_args().has("--tuttest") and not tutorial_mode:   # test: start prosto w samouczku
		tutorial_mode = true
		chosen_scenario = "Tutorial"
		chosen_map = "Open Plains"
		chosen_size = "Small"
		side_nation = [0, 1]
	var dn := OS.get_cmdline_user_args().find("--dump-nations")   # narzędzie: zrzut sprite'ów wybranych nacji (z --dump-sprites)
	if dn >= 0 and dn + 1 < OS.get_cmdline_user_args().size():
		var dpr := OS.get_cmdline_user_args()[dn + 1].split(",")
		side_nation = [int(dpr[0]), int(dpr[1])]
	if _autotest and OS.get_cmdline_user_args().has("--conquest"):
		chosen_scenario = "Conquest"   # test: mapa z miastami i wioskami (zrzuty zabudowy)
	if _autotest:
		var targs := OS.get_cmdline_user_args()
		var mi := targs.find("--map")
		if mi >= 0 and mi + 1 < targs.size() and Terrain.MAP_TYPES.has(targs[mi + 1]):
			chosen_map = targs[mi + 1]   # test: zrzut wybranego rodzaju mapy
	if _cinematic or PROF:
		# ujęcie filmowe: otwarta równina, Francja (dół) przeciw Wielkiej Brytanii (góra), bez interfejsu
		chosen_scenario = "Guard Duel"
		if not OS.get_cmdline_user_args().has("--map"):
			chosen_map = "Open Plains"
		side_nation = [0, 1]
	# ujęcie filmowe zaczyna się na skraju lasu za francuską baterią - dosadzamy go, jeśli mapa go tam nie ma
	Terrain.extra_woods = [[map_size * 0.5 + Vector2(0, 2050), Vector2(1300, 340)]] if _cinematic else []
	GameSettings.ensure_loaded()
	Regiment.battle = self
	Terrain.apply_map_type(chosen_map)
	Terrain.apply_theme(chosen_theme)
	var sc: Dictionary = SCENARIOS.get(chosen_scenario, SCENARIOS["Skirmish"])
	gold = [float(sc["gold"][0]), float(sc["gold"][1])]
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(map_size)
	territory = Territory.new()
	add_child(territory)
	var settle_root := Node2D.new()
	add_child(settle_root)
	var field := is_field()
	var mid := map_size * 0.5
	for t in 2:
		var site_p: Vector2 = terrain.sites[t][0] if terrain.sites.size() > t else mid + Vector2(-1500.0 if t == 0 else 1500.0, 0)
		deploy_pos.append(mid + (site_p - mid).normalized() * minf(1500.0, (site_p - mid).length()) if field else site_p)
	for i in (0 if field else terrain.sites.size()):
		var site: Array = terrain.sites[i]
		var s := Settlement.new()
		var faction := 0 if i == 0 else (1 if i == 1 else -1)
		s.setup(site[2], site[0], site[1], faction)
		settle_root.add_child(s)
		settlements.append(s)
	_build_house_grid()
	corpses = CorpseLayer.new()
	add_child(corpses)
	units_root = Node2D.new()
	add_child(units_root)
	effects = Effects.new()
	add_child(effects)
	var fog: EdgeFog = EdgeFog.new()
	fog.map_size = map_size
	add_child(fog)
	cam = BattleCamera.new()
	cam.process_priority = -100   # kamera przed bitwą: widok/przezroczystość liczone z tej samej klatki (bez drgania przy zoomie)
	cam.map_size = map_size
	cam.min_zoom = minf(0.12, 1600.0 / map_size.x * 0.85)
	add_child(cam)
	cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = Overlay.new()
	overlay.battle = self
	layer.add_child(overlay)

	if _cinematic:
		_spawn_cinematic()
		overlay.visible = false   # bez ikon, napisów i paneli
	elif PROF:
		_spawn_cinematic()   # test wydajności: te same wielkie armie co w ujęciu filmowym
	elif not Net.is_client():   # gość dostaje pułki od hosta
		_spawn_start_army(0)
		_spawn_start_army(1)
	_bake_sprites()   # tylko brakujące (nacje obu stron)
	if not field:
		territory.setup(self)
	sfx = Sfx.new()
	add_child(sfx)
	sfx.setup(self)
	if field:
		cam.position = deploy_pos[0].lerp(mid, 0.45)
		cam.set_zoom_instant(0.32)
		message("Field battle: no towns and no reinforcements - win with the army you have.")
	else:
		cam.position = deploy_pos[0] + Vector2(900, 0)
		cam.set_zoom_instant(0.3)
		message("Capture towns and villages - they bring gold and recruits. Click your town to recruit.")
	if Net.dedicated_args:
		first_launch = false
	_gen_key = _settings_key()
	if (first_launch or show_title_next) and not _autotest and not Net.dedicated_args and not Net.active():
		overlay.open_title()   # gra startuje od ekranu tytułowego; mapa w tle jest już gotowa do szybkiej bitwy
	elif _autotest and OS.get_cmdline_user_args().has("--title"):
		overlay.open_title()   # test: zrzut ekranu tytułowego
	first_launch = false
	show_title_next = false
	if tutorial_mode and not Net.active():
		tutorial = TutorialScript.new()
		tutorial.setup(self)
		menu_open = false
	if open_lobby:
		open_lobby = false
		overlay.open_title("mp")


# ------------------------------------------------------------------ budynki jako przeszkody

const HOUSE_CELL := 64.0
const HOUSE_PAD := 2.5
var _house_grid := {}   # Vector2i -> [[środek, oś, połowa_dł, połowa_szer], ...]


func _build_house_grid() -> void:
	## Siatka domów: żołnierze nie wchodzą w budynki, tylko obchodzą je bokiem.
	_house_grid.clear()
	for s in settlements:
		for hs in s.houses:
			var c: Vector2 = s.position + hs[0]
			var sz: Vector2 = hs[1]
			var h := [c, Vector2.from_angle(hs[2]), sz.x * 0.5 + HOUSE_PAD, sz.y * 0.5 + HOUSE_PAD]
			var rad := sz.length() * 0.5 + HOUSE_PAD
			for gy in range(floori((c.y - rad) / HOUSE_CELL), floori((c.y + rad) / HOUSE_CELL) + 1):
				for gx in range(floori((c.x - rad) / HOUSE_CELL), floori((c.x + rad) / HOUSE_CELL) + 1):
					var k := Vector2i(gx, gy)
					if not _house_grid.has(k):
						_house_grid[k] = []
					_house_grid[k].append(h)


func house_push(p: Vector2) -> Vector2:
	## Wektor, o który trzeba przesunąć punkt, żeby wyszedł z budynku (zero, gdy jest na zewnątrz).
	var list: Variant = _house_grid.get(Vector2i(floori(p.x / HOUSE_CELL), floori(p.y / HOUSE_CELL)))
	if list == null:
		return Vector2.ZERO
	var push := Vector2.ZERO
	for h in list:
		var d: Vector2 = p + push - h[0]
		var ax: Vector2 = h[1]
		var lx := d.dot(ax)
		var ly := d.cross(ax)
		var hx: float = h[2]
		var hy: float = h[3]
		if absf(lx) < hx and absf(ly) < hy:
			var ox := hx - absf(lx)
			var oy := hy - absf(ly)
			if ox < oy:
				push += ax * ox * signf(lx if lx != 0.0 else 1.0)
			else:
				push += ax.orthogonal() * oy * signf(ly if ly != 0.0 else 1.0)
	return push


func _bake_sprites() -> void:
	## Rysuje raz każdego żołnierza (typ x strona) do tekstury; potem pułki rysują się MultiMeshem.
	var cell := 256   # rozdzielczość sprite'a (bok 34 j. świata → ~7.5 teksela na jednostkę; kamera zbliża do 6 px/j.)
	var cols := 16
	var names: Array[String] = []
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var todo: Array = []
	for team in 2:
		for key in roster(nation(team)):
			if not Regiment.sprite_tex.has("%s/%d" % [key, nation(team)]) and not todo.has([team, key, 0]):
				todo.append([team, key, 0])
				if UNIT_TYPES[key]["kind"] == "inf":
					for pose in [1, 2, 3, 4, 5, 6, 7, 8]:   # ładowanie, broń na ramię, krok marszowy, bieg do ataku
						todo.append([team, key, pose])
					for pose in [14, 15, 16, 17, 18, 19]:   # sztab pułku: dobosz (3 klatki), oficer (2), chorąży
						todo.append([team, key, pose])
				elif UNIT_TYPES[key]["kind"] == "cav":
					todo.append([team, key, 4])   # galop: nogi wyciągnięte / zebrane
					todo.append([team, key, 5])
				elif UNIT_TYPES[key]["kind"] == "art":
					todo.append([team, key, 4])   # obsługa w marszu
					todo.append([team, key, 5])
					for pose in [10, 11, 12]:      # działo, przodek z zaprzęgiem (2 umaszczenia koni)
						todo.append([team, key, pose])
					if base_of(key) == "horse_art":
						todo.append([team, key, 13])   # koń obsługi artylerii konnej
	if todo.is_empty():
		vp.free()
		return
	var count := todo.size()
	vp.size = Vector2i(cell * cols, cell * ceili(count / float(cols)))
	vp.msaa_2d = Viewport.MSAA_4X
	add_child(vp)
	# cieniowanie warstw: osobny materiał dla żołnierzy i dla dużych sprite'ów (działa, zaprzęgi) - inna skala
	var shade := Shader.new()
	shade.code = SHADE_SHADER
	var mats: Array = []
	for upx in [cell / Regiment.SPRITE_WORLD, cell / Regiment.ART_WORLD]:
		var m := ShaderMaterial.new()
		m.shader = shade
		m.set_shader_parameter("unit_px", upx)
		mats.append(m)
	var idx := 0
	for job in todo:
		var team: int = job[0]
		var key: String = job[1]
		var nat := nation(team)
		var big := int(job[2]) >= 10 and int(job[2]) <= 13
		for lay in Regiment.LAYERS:
			# każda warstwa postaci w osobnej grupie: shader dodaje jej światło, cień własny i cień rzucany niżej
			var grp := CanvasGroup.new()
			grp.fit_margin = 12.0
			grp.clear_margin = 12.0
			if lay != Regiment.LY_SHADOW:
				grp.material = mats[1 if big else 0]
			var r := Regiment.new()
			r.team = team
			r.unit_key = key
			r.base_key = base_of(key)
			r.kind = UNIT_TYPES[key]["kind"]
			r.color = TEAM_COLORS[nat]
			r._bake = true
			r.bake_pose = int(job[2])
			r.bake_layer = lay
			r.position = Vector2((idx % cols + 0.5) * cell, (idx / cols + 0.5) * cell)
			r.scale = Vector2.ONE * (cell / (Regiment.ART_WORLD if big else Regiment.SPRITE_WORLD))
			grp.add_child(r)
			vp.add_child(grp)
		names.append("%s/%d%s" % [key, nat, POSE_SUFFIX[int(job[2])]])
		idx += 1
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	# drugi przebieg na GPU: odwrócenie premnożenia alfy z przezroczystego viewportu
	var vp2 := SubViewport.new()
	vp2.transparent_bg = true
	vp2.disable_3d = true
	vp2.size = vp.size
	vp2.render_target_update_mode = SubViewport.UPDATE_ONCE
	var flat := Sprite2D.new()
	flat.centered = false
	flat.texture = vp.get_texture()
	var um := ShaderMaterial.new()
	um.shader = Shader.new()
	um.shader.code = UNPREMULT_SHADER
	flat.material = um
	vp2.add_child(flat)
	add_child(vp2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp2.get_texture().get_image()
	var dargs := OS.get_cmdline_user_args()
	var dump := dargs.find("--dump-sprites")
	for k in names.size():
		var c := img.get_region(Rect2i((k % cols) * cell, (k / cols) * cell, cell, cell))
		c.flip_y()   # QuadMesh ma oś Y do góry
		c.fix_alpha_edges()
		if dump >= 0 and dump + 1 < dargs.size():
			var d2 := c.duplicate() as Image
			d2.flip_y()
			d2.save_png(dargs[dump + 1].path_join(String(names[k]).replace("/", "_").replace("#", "-") + ".png"))
		c.generate_mipmaps()
		Regiment.sprite_tex[names[k]] = ImageTexture.create_from_image(c)
	vp.queue_free()
	vp2.queue_free()
	if dump >= 0:
		get_tree().quit()


const SHADE_SHADER := """shader_type canvas_item;
// Warstwa postaci: swiatlo z przodu-lewej zolnierza (sprite wypalany twarza w prawo), cien wlasny po przeciwnej
// stronie i miekki cien rzucany na warstwy lezace nizej.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float unit_px = 7.5;
uniform float k = 1.0;

float blur_a(vec2 uv, vec2 ps, float r) {
	float a = textureLod(screen_texture, uv, 0.0).a * 0.16;
	for (int i = 0; i < 6; i++) {
		float ang = float(i) * 1.0472;
		a += textureLod(screen_texture, uv + vec2(cos(ang), sin(ang)) * r * 0.75 * ps, 0.0).a * 0.085;
	}
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.7854 + 0.39;
		a += textureLod(screen_texture, uv + vec2(cos(ang), sin(ang)) * r * 1.6 * ps, 0.0).a * 0.04125;
	}
	return a;
}

void fragment() {
	vec2 ps = SCREEN_PIXEL_SIZE;
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	float r = 0.38 * unit_px;
	vec2 l = vec2(1.0, -1.0) * 0.32 * unit_px * ps;
	float hi = clamp(1.0 - blur_a(SCREEN_UV + l, ps, r), 0.0, 1.0);
	float sh = clamp(1.0 - blur_a(SCREEN_UV - l, ps, r), 0.0, 1.0);
	c.rgb = c.rgb * (1.0 - 0.62 * k * sh) + 0.26 * k * hi;
	float cast = blur_a(SCREEN_UV + l * 0.7, ps, 0.2 * unit_px) * 0.42 * k;
	float a = c.a + cast * (1.0 - c.a);
	COLOR = vec4(c.rgb * c.a / max(a, 0.0001), a);
}
"""

const UNPREMULT_SHADER := """shader_type canvas_item;
render_mode blend_disabled;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	COLOR = c;
}
"""


func _parse_server_args() -> void:
	## Serwer dedykowany: --server [--port N] [--scenario "..."] [--map "..."] [--size Large]
	var args := OS.get_cmdline_user_args()
	if not args.has("--server") or Net.inst == null or Net.inst.role != Net.Role.NONE:
		return
	Net.dedicated_args = true
	var port := Net.PORT
	for i in args.size() - 1:
		match args[i]:
			"--port": port = int(args[i + 1])
			"--scenario": chosen_scenario = args[i + 1] if SCENARIOS.has(args[i + 1]) else chosen_scenario
			"--map": chosen_map = args[i + 1] if Terrain.MAP_TYPES.has(args[i + 1]) or args[i + 1] == "Random" else chosen_map
			"--size": chosen_size = args[i + 1] if MAP_SIZES.has(args[i + 1]) else chosen_size
	for i in args.size() - 1:
		if args[i] == "--nations":
			var parts := args[i + 1].split(",")
			if parts.size() == 2 and NATIONS.has(parts[0].strip_edges()) and NATIONS.has(parts[1].strip_edges()):
				side_nation = [NATIONS.find(parts[0].strip_edges()), NATIONS.find(parts[1].strip_edges())]
	Net.inst.host_game.call_deferred(true, port)


func _spawn_start_army(team: int) -> void:
	## Armia startowa strony. W grze sieciowej każdy gracz strony dostaje swoją część (do 2 pełnych armii na stronę).
	var sc: Dictionary = SCENARIOS.get(chosen_scenario, SCENARIOS["Skirmish"])
	var base: Array = sc["army"][team]
	var owners: Array = [1 if team == 0 and not Net.server_idle() else 0]
	if Net.active():
		owners = Net.inst.team_players(team)
		if owners.is_empty():
			owners = [0]   # strona bez ludzi - dowodzi AI
	var n := owners.size()
	var pool: Array = []
	for k in mini(n, 2):
		pool.append_array(base)
	var lists: Array = []
	for k in n:
		lists.append([])
	for i in pool.size():
		lists[i % n].append(pool[i])
	var spacing := minf(1400.0, map_size.y * 0.75 / n)
	for k in n:
		_deploy_army(team, lists[k], owners[k], (k - (n - 1) * 0.5) * spacing)


func _deploy_army(team: int, keys: Array, owner: int, lateral: float) -> void:
	var cap: Vector2 = deploy_pos[team]
	var toward := (map_size * 0.5 - cap).normalized()
	var facing := toward.angle()
	var side := toward.orthogonal()
	var front := cap + toward * 650.0 + side * lateral
	var inf: Array = []
	var cav: Array = []
	var art: Array = []
	for bk in keys:
		var key := unit_for(nation(team), bk)
		match UNIT_TYPES[key]["kind"]:
			"inf": inf.append(key)
			"cav": cav.append(key)
			_: art.append(key)
	# piechota w liniach (po 6), dziala za srodkiem, jazda na skrzydlach
	var per_line := 6
	for k in inf.size():
		var line := k / per_line
		var in_line := mini(per_line, inf.size() - line * per_line)
		var col := k % per_line
		spawn_regiment(team, inf[k], front - toward * line * 240.0 + side * (col - (in_line - 1) * 0.5) * 210.0, facing, owner)
	var lines := ceili(inf.size() / float(per_line))
	var wing := (mini(per_line, inf.size()) * 0.5 + 0.9) * 210.0
	for k in art.size():
		spawn_regiment(team, art[k], front - toward * (lines * 240.0 - 10.0) + side * (k - (art.size() - 1) * 0.5) * 190.0, facing, owner)
	for k in cav.size():
		var sgn := 1.0 if k % 2 == 0 else -1.0
		var depth := k / 2
		spawn_regiment(team, cav[k], front - toward * (60.0 + depth * 200.0) + side * sgn * (wing + depth * 60.0), facing, owner)


var _by_id := {}
var _next_net_id := 1


func reg_by_id(id: int) -> Regiment:
	return _by_id.get(id)


func spawn_remote(id: int, team: int, key: String, reg_name: String, pos: Vector2, facing: float) -> Regiment:
	## Gość: pułk utworzony na podstawie snapshotu hosta.
	var r := Regiment.new()
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.setup(team, reg_name, key, pos, facing, TEAM_COLORS[nation(team)])
	r.net_id = id
	units_root.add_child(r)
	regiments.append(r)
	_by_id[id] = r
	return r


func _settings_key() -> String:
	return "%s|%s|%s|%s|%s" % [chosen_scenario, chosen_map, chosen_size, str(side_nation), chosen_theme]


func can_start_in_place() -> bool:
	## Czy bitwę za ekranem tytułowym można zacząć bez przeładowania (świeża mapa, te same ustawienia).
	return sim_time < 0.5 and result_text == "" and not Net.active() and _gen_key == _settings_key()


func restart_game() -> void:
	var net := Net.inst
	if net != null and net.role == Net.Role.HOST and not net.dedicated and net.players.size() > 1:
		net.start_match()   # nowa bitwa u wszystkich graczy
		return
	if net != null and net.role == Net.Role.CLIENT:
		# gość: nową bitwę zaczyna host - wracamy do lobby
		result_text = ""
		menu_open = true
		overlay.menu_tab = 3
		return
	get_tree().reload_current_scene()


func is_mine(r: Regiment) -> bool:
	## Pułk, którym ten gracz może dowodzić (w grze sieciowej: tylko własne, nie sojuszników).
	return r != null and r.team == 0 and (not Net.active() or r.commander == Net.my_id())


func player_left(id: int, team: int, pname: String) -> void:
	## Gracz wyszedł z bitwy: jego wojska przejmuje sojusznik (albo AI).
	var heir := 0
	for pid in Net.inst.team_players(team):
		heir = pid
		break
	for r in regiments:
		if r.commander == id:
			r.commander = heir
	for s in settlements:
		for q in s.queue:
			if q.size() > 3 and q[3] == id:
				q[3] = heir
	var who := Net.inst.player_name(heir) if heir != 0 else "the AI"
	message("%s left - their troops now follow %s" % [pname, who])


func spawn_regiment(team: int, key: String, pos: Vector2, facing: float, owner := -1) -> Regiment:
	var r := Regiment.new()
	r.commander = owner if owner >= 0 else (1 if team == 0 else 0)
	r.net_id = _next_net_id
	_next_net_id += 1
	_by_id[r.net_id] = r
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pos = terrain.dry_spot(pos)
	r.setup(team, _next_name(team, key), key, pos, facing, TEAM_COLORS[nation(team)])
	units_root.add_child(r)
	regiments.append(r)
	return r


func _next_name(team: int, key: String) -> String:
	var ck := "%d_%s" % [team, key]
	var n: int = _name_counters.get(ck, 0) + 1
	_name_counters[ck] = n
	var t: Dictionary = UNIT_TYPES[key]
	if t.has("names"):
		var names: Array = t["names"]
		return "%s %s" % [t["name"], names[(n - 1) % names.size()]]
	var num := _ordinal(n)
	if t.get("pl", false) and not t.has("fmt"):
		var nm: String = t["name"]
		var re := RegEx.create_from_string("^\\d+(st|nd|rd|th|/)")
		if re.search(nm) != null:
			return "%s (%s Bn)" % [nm, num]   # nazwa z własnym numerem pułku: "95th Rifles (2nd Bn)"
		return "%s %s" % [num, nm]            # "1st Hussars"
	var fmt: String = UNIT_TYPES[key].get("fmt", NAME_FORMATS[nation(team)].get(base_of(key), "%s " + UNIT_TYPES[key]["name"]))
	if not fmt.contains("%s"):
		return fmt
	return fmt % num


const SPRITE_PX := 128   # rozdzielczość pikselowego sprite'a żołnierza (bok 34 jednostek świata → ~1.9 teksela na jednostkę)


const POSE_SUFFIX := {0: "", 1: "#r1", 2: "#r2", 3: "#sh", 4: "#w1", 5: "#w2", 6: "#r3", 7: "#c1", 8: "#c2",
	10: "#gun", 11: "#team0", 12: "#team1", 13: "#horse",
	14: "#dr1", 15: "#dr2", 16: "#dr0", 17: "#of1", 18: "#of2", 19: "#col"}


static func _pixelize_sprite(src: Image, size := SPRITE_PX) -> Image:
	## Styl lekko pikselowy: zmniejszenie z uśrednieniem, twarde krawędzie (alfa 0/1), lekka posteryzacja
	## i ciemny obrys jednego piksela wokół sylwetki - jak w pixel-arcie.
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var n := size
	var d := img.get_data()
	var out := PackedByteArray()
	out.resize(n * n * 4)   # wyzerowane = przezroczyste
	const LV := 32.0
	var solid := PackedInt32Array()
	for i in n * n:
		var o := i * 4
		var a := d[o + 3]
		if a < 107:
			continue
		var inv := 1.0 / float(a)   # odwrócenie premnożenia z przezroczystego viewportu
		out[o] = int(roundf(minf(d[o] * inv, 1.0) * LV) / LV * 255.0)
		out[o + 1] = int(roundf(minf(d[o + 1] * inv, 1.0) * LV) / LV * 255.0)
		out[o + 2] = int(roundf(minf(d[o + 2] * inv, 1.0) * LV) / LV * 255.0)
		out[o + 3] = 255
		solid.append(i)
	for i in solid:
		var x := i % n
		var y := i / n
		for o2 in [-1, 1, -n, n]:
			var j: int = i + o2
			if j < 0 or j >= n * n or (o2 == -1 and x == 0) or (o2 == 1 and x == n - 1):
				continue
			if out[j * 4 + 3] == 0:
				out[j * 4] = 20
				out[j * 4 + 1] = 15
				out[j * 4 + 2] = 13
				out[j * 4 + 3] = 230
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, out)


static func _ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suf = "st"
			2: suf = "nd"
			3: suf = "rd"
	return "%d%s" % [n, suf]


func message(t: String) -> void:
	messages.append([t, Time.get_ticks_msec() / 1000.0])
	if messages.size() > 5:
		messages.remove_at(0)


func home_dir(team: int, from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var bd := INF
	for s in settlements:
		if s.faction == team and s.is_city:
			var d := from.distance_to(s.position)
			if d < bd:
				bd = d
				best = s.position
	if bd < INF and bd > 50.0:
		return (best - from).normalized()
	return Vector2.LEFT if team == 0 else Vector2.RIGHT


# ------------------------------------------------------------------ pętla

func _process(delta: float) -> void:
	if not is_inside_tree() or get_viewport() == null:
		return
	var _pt := Time.get_ticks_usec() if PROF else 0
	_process_impl(delta)
	if PROF:
		pf("process_total", _pt)


func _process_impl(delta: float) -> void:
	if tutorial != null and not menu_open:
		tutorial.update(delta)
		if tutorial.finished:
			end_tutorial(get_tree())
			return
	var z := cam.zoom.x
	soldier_alpha = clampf((z - 0.5) / 0.35, 0.0, 1.0)
	icon_alpha = 1.0 - clampf((z - 0.75) / 0.35, 0.0, 1.0)

	if Net.inst != null:
		Net.inst.lobby_tick(delta)
		if not is_inside_tree():
			return   # start bitwy przeładował scenę
	if Net.is_client():
		Net.inst.client_tick(delta)
		effects.update(delta)
	elif Net.server_idle():
		pass
	elif not paused and (not menu_open or Net.active()):
		if Net.active():
			time_scale = 1.0
		var dt := minf(delta, 0.1) * time_scale
		while dt > 0.0001:
			var s := minf(dt, STEP)
			dt -= s
			last_step = dt <= 0.0001   # ostatni krok tej klatki: wtedy liczy się to, co i tak tylko widać
			_simulate(s)

	if _autotest and OS.get_cmdline_user_args().has("--title"):
		_title_shots(delta)
	if _cinematic:
		_cinematic_camera()
	_sample_history()
	show_all = Input.is_key_pressed(KEY_SPACE)
	if not settlements.is_empty():
		territory.tick(delta)
	if terrain.tree_shadows != null:
		terrain.tree_shadows.visible = z > 0.3
	var show := soldier_alpha > 0.01
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	for r in regiments:
		r.modulate.a = soldier_alpha
		var vis := show and r.on_screen(view)
		r.visible = vis
		if vis:
			r.queue_redraw()
	effects.modulate.a = soldier_alpha
	effects.visible = show
	if show:
		effects.queue_redraw()
	corpses.modulate.a = lerpf(0.35, 1.0, soldier_alpha)
	_fade_timer -= delta
	if _fade_timer <= 0.0:
		_fade_timer = 0.1
		terrain.update_tree_fade(regiments)
	overlay.queue_redraw()
	if Net.is_host():
		Net.inst.host_tick(delta)


static func pf(key: String, t0: int) -> void:
	perf[key] = int(perf.get(key, 0)) + Time.get_ticks_usec() - t0


func _simulate(dt: float) -> void:
	sim_time += dt
	var t0 := Time.get_ticks_usec()
	for r in regiments:
		r.simulate(dt)
	for i in range(regiments.size() - 1, -1, -1):
		var r := regiments[i]
		if r.dead:
			selected.erase(r)
			regiments.remove_at(i)  # węzeł zostaje (ukryty), bo inne pułki mogą mieć do niego referencję
	if PROF:
		pf("regiments", t0)
		t0 = Time.get_ticks_usec()
	_push_apart(dt)
	if PROF:
		pf("push_apart", t0)
		t0 = Time.get_ticks_usec()
	if last_step:
		_separate_foes()   # raz na klatkę: przy kilku krokach w jednej klatce pośrednie i tak nie są widoczne
	if PROF:
		pf("separate_foes", t0)
		t0 = Time.get_ticks_usec()
	_update_balls(dt)
	_update_support_units(dt)
	effects.update(dt)
	if PROF:
		pf("balls_effects", t0)
		_perftest(dt)
	_slow_acc += dt
	if _slow_acc >= 0.25:
		if not is_field():
			_update_settlements(_slow_acc)
			_update_economy(_slow_acc)
		_slow_acc = 0.0
	_ai_timer -= dt
	if _ai_timer <= 0.0:   # AI dowodzi tylko pułkami bez gracza (owner 0) strony 1
		_ai_timer = AI_INTERVAL
		if tutorial == null:
			_run_ai()
		if tutorial == null:
			_ai_squares()
	if tutorial == null:
		_check_victory()
	if _cinematic:
		_cinematic_sim(dt)
	if _autotest and OS.get_cmdline_user_args().has("--cavart"):
		# test: dwie szarże jazdy (z dwóch stron) na baterię, która właśnie zmienia pozycję
		var art: Regiment = null
		var cavs: Array[Regiment] = []
		for r in regiments:
			if r.team == 1 and r.kind == "art" and art == null:
				art = r
			elif r.team == 0 and r.kind == "cav":
				cavs.append(r)
		if art != null and cavs.size() >= 2:
			if sim_time >= 1.0 and sim_time - dt < 1.0:
				art.center = Vector2(map_size.x * 0.5, map_size.y * 0.5 - 2300.0)
				art._gun_p.clear()
				art._update_guns(0.0)
				for k in art.s_pos.size():
					art.s_pos[k] = art.slot_pos(k, art.s_pos.size())
				cavs[0].center = art.center + Vector2(-420, 0)
				cavs[1].center = art.center + Vector2(0, 420)
				for c in cavs:
					for k in c.s_pos.size():
						c.s_pos[k] = c.slot_pos(k, c.s_pos.size())
					c.order_attack(art)
				art.order_move(art.center + Vector2(300, -200), 0.0)
			if sim_time > 1.0 and DisplayServer.get_name() != "headless":
				cam.position = art.centroid()
				cam.set_zoom_instant(1.3)
				if sim_time >= 7.0 and sim_time - dt < 7.0:
					get_viewport().get_texture().get_image().save_png("user://melee_icon.png")
			if int(sim_time / 4.0) != int((sim_time - dt) / 4.0) and sim_time < 80.0:
				print("cavart t=%d art=%d/%s morale=%d lim=%.2f  cav=%d/%s %d/%s" % [int(sim_time), art.alive_count(), Regiment.State.keys()[art.state], int(art.morale), art.limber_u,
					cavs[0].alive_count(), Regiment.State.keys()[cavs[0].state], cavs[1].alive_count(), Regiment.State.keys()[cavs[1].state]])
	if _autotest and OS.get_cmdline_user_args().has("--marchtest"):
		# test: pułki dostają rozkaz marszu PRZEZ własne linie i przez całe pole - każdy ma dojść tam, gdzie kazano
		if sim_time >= 1.0 and sim_time - dt < 1.0:
			var k := 0
			for r in regiments:
				if r.team == 0:
					var dest: Vector2 = r.center + Vector2(700.0, (4 - k) * 260.0)
					r.set_meta("dest", dest)
					r.order_move(dest, 0.0)
					k += 1
		if int(sim_time / 15.0) != int((sim_time - dt) / 15.0):
			var rows := []
			for r in regiments:
				if r.team == 0 and r.has_meta("dest"):
					rows.append("%s:%s:%d" % [r.unit_key.left(6), Regiment.State.keys()[r.state].left(4), int(r.centroid().distance_to(r.get_meta("dest")))])
			print("march t=%d  %s" % [int(sim_time), " ".join(rows)])
	if _autotest and OS.get_cmdline_user_args().has("--gangtest"):
		# test: trzy pułki (piechota z dwóch stron + jazda z trzeciej) atakują wręcz jeden wrogi pułk piechoty
		var foe: Regiment = null
		var mine: Array[Regiment] = []
		for r in regiments:
			if r.team == 1 and r.kind == "inf" and foe == null:
				foe = r
			elif r.team == 0 and r.kind != "art" and mine.size() < 3 and (r.kind == "inf" or mine.size() == 2):
				mine.append(r)
		if foe != null and mine.size() == 3:
			if sim_time >= 1.0 and sim_time - dt < 1.0:
				var spot := Vector2(map_size.x * 0.5, map_size.y * 0.5 - 2300.0)
				var offs := [Vector2(-260, 0), Vector2(0, 260), Vector2(260, 0)]
				var all: Array[Regiment] = [foe]
				all.append_array(mine)
				for k in all.size():
					var r := all[k]
					r.center = spot if k == 0 else spot + offs[k - 1]
					r.facing = 0.0 if k == 0 else (spot - r.center).angle()
					r.move_target = r.center
					for q in r.s_pos.size():
						r.s_pos[q] = r.slot_pos(q, r.s_pos.size())
				for r in mine:
					r.fire_at_will = false
					r.order_attack(foe)   # pierwszy rozkaz na wroga w zasięgu = ogień
					r.order_attack(foe)   # drugi = szarża na bagnety
			if int(sim_time / 3.0) != int((sim_time - dt) / 3.0) and sim_time < 70.0:
				var row := "gang t=%d foe=%d/%s m=%d |" % [int(sim_time), foe.alive_count(), Regiment.State.keys()[foe.state].left(4), int(foe.morale)]
				for r in mine:
					var fighting := 0
					for q in r.s_tgt_reg.size():
						if r.s_tgt_reg[q] != null:
							fighting += 1
					row += " %s:%d/%s enemies=%d fighting=%d d=%d |" % [r.kind, r.alive_count(), Regiment.State.keys()[r.state].left(4), r.melee_enemies.size(), fighting, int(r.center.distance_to(foe.centroid()))]
				print(row)
	if _autotest and OS.get_cmdline_user_args().has("--sqtest"):
		_sqtest(dt)
	if _autotest and OS.get_cmdline_user_args().has("--disengtest"):
		_disengtest(dt)
	if _autotest and OS.get_cmdline_user_args().has("--formtest"):
		_formtest(dt)
	if _autotest and int(sim_time / 20.0) != int((sim_time - dt) / 20.0):
		var owned := [0, 0, 0]
		for s in settlements:
			owned[s.faction + 1] += 1
		var info := []
		for r in regiments:
			info.append("%s:%d/%s" % [r.unit_key.left(4), r.alive_count(), Regiment.State.keys()[r.state].left(4)])
		print("guns fired=%s " % str(Regiment.cannon_shots))
		print("t=%d gold=%d/%d owned(n/p/e)=%s regs=%d drowned=%s lim=%d/%d  %s %s" % [int(sim_time), int(gold[0]), int(gold[1]), str(owned), regiments.size(),
			str(stats["drowned"]), command_limit(0), command_limit(1), result_text, " ".join(info)])
	if _autotest and OS.get_cmdline_user_args().has("--shots") and DisplayServer.get_name() != "headless":
		_autotest_shots(dt)


# ------------------------------------------------------------------ ujęcie filmowe (--cinematic)
# Sekwencja ujęć (czas bitwy w s):
#  1) 0.3-11   przelot z dołu do góry nad liniami piechoty obu armii
#  2) 11-24    przejazd na prawą flankę: szarża kilkunastu pułków jazdy na jazdę (kamera śledzi starcie)
#  3) 24-33    tyły Francuzów: salwy wielkiej baterii stojącej za kilkoma liniami piechoty
#  4) 33-48    od dział na lewą flankę: jazda szarżuje na angielskie czworoboki i przejeżdża między nimi
#  5) 48-60    powrót do centrum: część piechoty, która w międzyczasie ruszyła naprzód, zwiera się na bagnety
# Jazda w szyku klinowym, rozstawiona bezładnie (chaos bitwy).

const CINE_END := 64.0
const CINE_COLS := 7          # pułków piechoty w linii
const CINE_FLANK := 180.0     # o tyle flanki odsunięte od szerszego centrum
const CINE_CHARGE_R := 11.5   # rozkaz szarży na prawej flance (starcie ok. 17-18 s)
const CINE_CHARGE_L := 28.5   # rozkaz szarży na czworoboki (dojazd ok. 36-38 s)
const CINE_LINES := 6         # linii piechoty na stronę w centrum
const CINE_INTRO := 6.0       # s intro: łąka przy lesie, pasące się sarny i króliki (czas scenariusza od -6 do 0)
const WildlifeScript := preload("res://scripts/wildlife.gd")
var _cine_meadow := Vector2.ZERO
var _cine_wild = null          # węzeł dzikich zwierząt (scripts/wildlife.gd)
var _cine_push: Array = []    # kolumny frontu, w których część armii naciera
const CINE_VOLLEYS := [27.8, 31.6]
const CINE_ADVANCE := 20.0    # druga i trzecia linia w centrum podchodzą pod pierwszą (gdy kamera jest na flankach)
const CINE_BAYONETS := 43.5   # ogólne natarcie piechoty w centrum - starcie pokazane na końcu
var _cine_inf: Array = []     # [strona][linia] -> pułki piechoty w centrum
var _cine_next_blast := 0.0
var _cine_cav_r: Array[Regiment] = []   # [francuskie..., brytyjskie...] na prawej flance
var _cine_cav_l: Array[Regiment] = []   # francuska jazda lewej flanki
var _cine_squares: Array[Regiment] = []
var _cine_guns: Array[Regiment] = []
var _cine_track := {}                   # wygładzone punkty śledzenia kamery
var _cine_done := {}


func _cine_mid() -> Vector2:
	return terrain.dry_spot(map_size * 0.5)


func _cine_jit(p: Vector2, jx: float, jy: float) -> Vector2:
	return p + Vector2(randf_range(-jx, jx), randf_range(-jy, jy))


func _cine_row_xs(n: int, gap_min: float, gap_max: float, shift: float) -> Array:
	## Pozycje pułków w linii: nierówne odstępy (jak po marszu i manewrach), cała linia lekko przesunięta.
	var xs: Array = [0.0]
	for k in range(1, n):
		xs.append(float(xs[k - 1]) + randf_range(gap_min, gap_max))
	var off := float(xs[n - 1]) * 0.5 - randf_range(-shift, shift)
	for k in n:
		xs[k] = float(xs[k]) - off
	return xs


func _cine_scatter(n: int, area: Rect2, min_d: float) -> Array:
	## Losowe, nieregularne miejsca w prostokącie, nie bliżej niż min_d od siebie.
	var pts: Array = []
	var tries := 0
	while pts.size() < n and tries < 4000:
		tries += 1
		var p := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		var ok := true
		for q in pts:
			if p.distance_to(q) < min_d:
				ok = false
				break
		if ok:
			pts.append(p)
	while pts.size() < n:
		pts.append(area.get_center())
	return pts


func _cine_pick(pool: Array, n: int) -> Array:
	var out: Array = []
	for k in n:
		out.append(pool[randi() % pool.size()])
	return out


func _spawn_cinematic() -> void:
	## Centrum: po sześć linii różnorodnej piechoty na stronę, rozstawionych nierówno, za nimi wielkie baterie
	## (zasięg sztucznie zwiększony - strzelają nad głowami własnej piechoty). Prawa flanka: masa jazdy naprzeciw
	## jazdy. Lewa flanka: brytyjskie czworoboki i francuska jazda. Jazda raz w linii, raz w klinie, bezładnie.
	var m := _cine_mid()
	var up := -PI * 0.5
	var down := PI * 0.5
	var fl := CINE_FLANK
	var fr_pools := [
		["fr_grenadiers", "fr_grenadiers", "fr_fusiliers", "fr_gren_pied", "fr_grenadiers"],
		["fr_fusiliers", "fr_swiss", "fr_westphal", "fr_irish", "fr_fusiliers"],
		["fr_fusiliers", "fr_chasseurs", "fr_westphal", "fr_voltigeurs", "fr_fusiliers"],
		["fr_westphal", "fr_fusiliers", "fr_yg_tirailleurs", "fr_swiss", "fr_irish"],
		["fr_fusiliers", "fr_fusiliers", "fr_chasseurs", "fr_westphal", "fr_swiss"],
		["fr_fus_gren", "fr_chass_pied", "fr_gren_pied", "fr_marins", "fr_fus_gren"]]
	var gb_pools := [
		["gb_line", "gb_grenadiers", "gb_coldstream", "gb_highlanders", "gb_line"],
		["gb_line", "gb_kgl_line", "gb_95th", "gb_brunswick", "gb_60th"],
		["gb_line", "gb_port_line", "gb_kgl_line", "gb_highlanders", "gb_line"],
		["gb_light", "gb_line", "gb_kgl_light", "gb_marines", "gb_line"],
		["gb_line", "gb_port_line", "gb_brunswick", "gb_line", "gb_kgl_line"],
		["gb_coldstream", "gb_1st_guards", "gb_3rd_guards", "gb_guards_light", "gb_1st_guards"]]
	_cine_inf = [[], []]
	for side in 2:
		var sg := 1.0 if side == 0 else -1.0
		var pools: Array = fr_pools if side == 0 else gb_pools
		for li in CINE_LINES:
			_cine_inf[side].append([])
			var keys := _cine_pick(pools[li], CINE_COLS)
			var xs := _cine_row_xs(CINE_COLS, 235.0, 335.0, 60.0 + li * 12.0)
			var y := 110.0 + li * 190.0
			for k in CINE_COLS:
				var p := m + Vector2(float(xs[k]), sg * (y + randf_range(-6.0, 26.0) * (1.0 if li > 0 else 0.4)))
				var r := spawn_regiment(side, keys[k], p, (up if side == 0 else down) + randf_range(-0.06, 0.06), 1 if side == 0 else 0)
				r.jitter_scale = 1.8
				_cine_inf[side][li].append(r)
	var gy := _cine_gun_y()
	var fr_guns := ["fr_art12", "fr_art_garde", "fr_art12", "fr_art8", "fr_art_garde", "fr_art12", "fr_howitzers"]
	var gb_guns := ["gb_art9", "gb_rha", "gb_art9", "gb_howitzers", "gb_art9", "gb_rha", "gb_art9"]
	for side in 2:
		var xs := _cine_row_xs(7, 220.0, 320.0, 80.0)
		for k in 7:
			var p := m + Vector2(float(xs[k]), (gy + randf_range(-25.0, 25.0)) * (1.0 if side == 0 else -1.0))
			if side == 0:
				_cine_guns.append(spawn_regiment(0, fr_guns[k], p, up, 1))
			else:
				spawn_regiment(1, gb_guns[k], p, down, 0)
	# prawa flanka: 9 pułków jazdy na stronę, bezładnie rozrzucone
	var fr_cav := ["fr_cuirassiers", "fr_carab_cheval", "fr_cuirassiers", "fr_dragoons", "fr_lancers", "fr_red_lancers",
		"fr_hussars", "fr_chass_cheval", "fr_dragoons"]
	var gb_cav := ["gb_scots_greys", "gb_life_guards", "gb_blues", "gb_heavy_drag", "gb_drag_guards", "gb_light_drag",
		"gb_hussars", "gb_kgl_hussars", "gb_light_drag"]
	var area := Rect2(1250.0 + fl, 300.0, 1300.0, 420.0)
	var spots := _cine_scatter(9, area, 230.0)
	for k in 9:
		_cine_cav_r.append(spawn_regiment(0, fr_cav[k], m + spots[k], up + randf_range(-0.35, 0.35), 1))
	spots = _cine_scatter(9, area, 230.0)
	for k in 9:
		_cine_cav_r.append(spawn_regiment(1, gb_cav[k], m + (spots[k] as Vector2) * Vector2(1, -1), down + randf_range(-0.35, 0.35), 0))
	# lewa flanka: 6 czworoboków (3 kolumny x 2 rzędy, między kolumnami korytarze), nie w równych odstępach
	var sq_keys := ["gb_line", "gb_highlanders", "gb_kgl_line", "gb_port_line", "gb_line", "gb_brunswick"]
	var i := 0
	for row in [-20.0, -400.0]:
		for x in [-1250.0, -1700.0, -2150.0]:
			_cine_squares.append(spawn_regiment(1, sq_keys[i], _cine_jit(m + Vector2(x - fl, row), 40.0, 35.0), down, 0))
			i += 1
	# kolejność: 0/3/4 uderzają na dolne czworoboki, 1/2/5/6 galopują korytarzami i obejściem, 7/8 to druga fala
	var l_cav := ["fr_cuirassiers", "fr_chass_cheval", "fr_lancers", "fr_cuirassiers", "fr_gren_cheval", "fr_drag_imp",
		"fr_hussars", "fr_carab_cheval", "fr_red_lancers"]
	var l_xy := [Vector2(-1700, 430), Vector2(-1475, 560), Vector2(-1925, 600), Vector2(-1250, 450), Vector2(-2150, 470),
		Vector2(-1020, 640), Vector2(-2400, 650), Vector2(-1650, 760), Vector2(-1280, 800)]
	for k in 9:
		_cine_cav_l.append(spawn_regiment(0, l_cav[k], _cine_jit(m + l_xy[k] - Vector2(fl, 0), 70.0, 80.0), up + randf_range(-0.3, 0.3), 1))
	# brytyjska jazda w odwodzie za czworobokami (tło)
	for k in 3:
		spawn_regiment(1, ["gb_heavy_drag", "gb_hussars", "gb_light_drag"][k], _cine_jit(m + Vector2(-1350.0 - fl - k * 420.0, -780.0), 60.0, 60.0),
			down + randf_range(-0.3, 0.3), 0)
	for r in regiments:
		r.fire_at_will = true
		if r.kind == "art":
			r.fire_range = 1900.0   # sztucznie: baterie strzelają z tyłów nad własną piechotą
		elif r.kind == "cav":
			# jazda raz w klinie, raz w linii - i nigdy jak od linijki
			var w := randf() < 0.55
			r.order_wedge(w)
			r.jitter_scale = 22.0 if w else 9.0
	_ai_timer = 1.0e9   # bez AI: wszystko dzieje się według scenariusza
	# intro: zwierzęta na łące przy lesie (pod koronami drzew, żeby uciekając znikały w gęstwinie)
	_cine_find_meadow()
	_cine_wild = WildlifeScript.new()
	terrain.add_child(_cine_wild)
	if terrain.tree_shadows != null:
		terrain.move_child(_cine_wild, terrain.tree_shadows.get_index())
	var flock = WildlifeScript.BirdFlock.new()
	flock.z_index = 50
	add_child(flock)
	_cine_wild.birds = flock
	_cine_wild.setup_meadow(_cine_meadow, Vector2.DOWN, 6, 8)
	_cine_wild.add_birds(_cine_meadow + Vector2(0, 150), 14, 170.0)


func _cine_gun_y() -> float:
	return 110.0 + CINE_LINES * 190.0 + 20.0


func _cine_t() -> float:
	## Czas scenariusza: 0 = koniec intro w lesie (intro trwa od -CINE_INTRO).
	return sim_time - CINE_INTRO


func _cine_find_meadow() -> void:
	## Skraj lasu na tyłach Francuzów: komórka lasu, nad którą (w stronę pola bitwy) jest otwarta łąka,
	## a pod nią las ciągnie się w głąb. Najbliższa środka tyłów wygrywa.
	var m := _cine_mid()
	var want := m + Vector2(0, _cine_gun_y() + 420.0)
	var best := INF
	for pass_i in 2:
		var x0 := -1700.0 if pass_i == 0 else -3400.0
		var y1 := 3000.0 if pass_i == 0 else 3700.0
		var y := 1250.0
		while y < y1:
			var x := x0
			while x <= -x0:
				var f := m + Vector2(x, y)
				if terrain.cell_at(f) == Terrain.FOREST and terrain.cell_at(f + Vector2(0, 90)) == Terrain.FOREST \
						and terrain.cell_at(f + Vector2(0, 180)) == Terrain.FOREST and terrain.cell_at(f + Vector2(0, -70)) == Terrain.GRASS \
						and terrain.cell_at(f + Vector2(0, -170)) == Terrain.GRASS and terrain.cell_at(f + Vector2(-150, -110)) == Terrain.GRASS \
						and terrain.cell_at(f + Vector2(150, -110)) == Terrain.GRASS:
					var d := f.distance_to(want)
					if d < best:
						best = d
						_cine_meadow = f + Vector2(0, -100)
				x += 40.0
			y += 40.0
		if best < INF:
			break
	if best == INF:
		_cine_meadow = m + Vector2(0, 1600)   # nie ma lasu: zwierzęta na otwartej łące
	print("CINE meadow ", _cine_meadow - m, " forest=", best < INF)


func _cine_once(key: String, t: float) -> bool:
	if _cine_t() >= t and not _cine_done.has(key):
		_cine_done[key] = true
		return true
	return false


func _cinematic_sim(dt: float) -> void:
	_ai_timer = 1.0e9
	var m := _cine_mid()
	var ct := _cine_t()
	if _cine_once("startle", -2.4) or _cine_once("startle2", -1.6):
		# kula pada niedaleko łąki: zwierzęta podrywają łby i uciekają w las, ptaki zrywają się z drzew
		var bp := _cine_meadow + Vector2(randf_range(-160.0, 160.0), randf_range(-165.0, -125.0))
		effects.add_explosion(bp, 1.1)
		if sfx != null:
			sfx.ball_impact(bp)
		if _cine_wild != null:
			_cine_wild.startle(bp)
	if _cine_once("squares", 0.4):
		for r in _cine_squares:
			r.order_square(true)
	if _cine_once("charge_r", CINE_CHARGE_R):
		# każdy francuski pułk na swój odpowiednik po drugiej stronie
		# każdy na najbliższy wrogi pułk, którego nikt jeszcze nie wziął (bez par na sztywno - chaos)
		var n := _cine_cav_r.size() / 2
		var taken := {}
		for k in n:
			var a := _cine_cav_r[k]
			var best: Regiment = null
			for j in range(n, 2 * n):
				var b := _cine_cav_r[j]
				if not taken.has(b) and (best == null or a.center.distance_to(b.center) < a.center.distance_to(best.center)):
					best = b
			taken[best] = true
			a.order_attack(best)
			best.order_attack(a)
	if _cine_once("charge_l", CINE_CHARGE_L):
		# szpica i boczne pary szarżują na dolny rząd czworoboków, reszta klina galopuje korytarzami między nimi
		_cine_cav_l[0].order_attack(_cine_squares[1])
		_cine_cav_l[3].order_attack(_cine_squares[0])
		_cine_cav_l[4].order_attack(_cine_squares[2])
		var lanes := {1: -1475.0, 2: -1925.0, 5: -1020.0, 6: -2420.0}
		for k in lanes:
			var r := _cine_cav_l[k]
			r.order_move(m + Vector2(float(lanes[k]) - CINE_FLANK + randf_range(-40.0, 40.0), -950), -PI * 0.5 + randf_range(-0.3, 0.3))
			r._disengage_until = sim_time + 30.0   # galopem, nie stępa
	if _cine_once("charge_l1b", CINE_CHARGE_L + 3.0):
		# druga fala na te same czworoboki
		_cine_cav_l[7].order_attack(_cine_squares[1])
		_cine_cav_l[8].order_attack(_cine_squares[0])
	if _cine_once("charge_l2", CINE_CHARGE_L + 13.0):
		# za czworobokami jazda zawraca i uderza na górny rząd od tyłu
		var back := {1: 3, 2: 4, 6: 5, 5: 3}
		for k in back:
			if not _cine_cav_l[k].dead:
				_cine_cav_l[k].order_attack(_cine_squares[back[k]])
	if _cine_once("advance", CINE_ADVANCE):
		# natarcie tylko części armii: w kilku losowych miejscach frontu druga linia podchodzi tuż pod pierwszą,
		# a trzecia na miejsce drugiej - reszta stoi i strzela dalej
		var cols: Array = range(CINE_COLS)
		cols.shuffle()
		_cine_push = cols.slice(0, 3)
		_cine_push.sort()
		for side in 2:
			var sg := 1.0 if side == 0 else -1.0
			for k in _cine_push:
				var r2: Regiment = _cine_inf[side][1][k]
				var r3: Regiment = _cine_inf[side][2][k]
				r2.order_move(Vector2(r2.center.x, m.y + sg * 200.0), -PI * 0.5 * sg)
				r3.order_move(Vector2(r3.center.x, m.y + sg * 330.0), -PI * 0.5 * sg)
	if _cine_once("bayonets", CINE_BAYONETS):
		# natarcie na bagnety tylko tam, gdzie podeszły posiłki: pierwsza i druga linia na wroga naprzeciw
		for k in _cine_push:
			var fa: Regiment = _cine_inf[0][0][k]
			var fb: Regiment = _cine_inf[0][1][k]
			var ga: Regiment = _cine_inf[1][0][k]
			for rr in 2:
				fa.order_attack(ga)
				fb.order_attack(ga)
				ga.order_attack(fa)
	for k in CINE_VOLLEYS.size():
		if _cine_once("volley%d" % k, CINE_VOLLEYS[k]):
			# salwa całej wielkiej baterii: działa odpalają jedno po drugim wzdłuż linii
			for g in _cine_guns.size():
				var r := _cine_guns[g]
				for q in r.s_reload.size():
					r.s_reload[q] = minf(r.s_reload[q], 0.05 + g * 0.12 + q * 0.04)
	# wygładzone środki starć dla kamery
	_cine_follow("R", _cine_cav_r, dt)
	_cine_follow("L", _cine_cav_l, dt)
	for k in mini(_cine_push.size(), 3):
		# punkty zwarć w centrum: między francuskim a brytyjskim pułkiem naprzeciw
		var c := _cine_inf[0][0][_cine_push[k]] as Regiment
		var g := _cine_inf[1][0][_cine_push[k]] as Regiment
		var pair: Array[Regiment] = [c, g]
		_cine_follow("M%d" % k, pair, dt)
	# dodatkowe kule upadające w okolicy kadru (nie w samym środku, żeby nie zasłaniać akcji)
	if ct >= 1.5 and ct < CINE_END and sim_time >= _cine_next_blast:
		_cine_next_blast = sim_time + randf_range(0.3, 0.7)
		var p := cam.position + Vector2.from_angle(randf() * TAU) * randf_range(260.0, 650.0) / maxf(cam.zoom.x, 0.8)
		if terrain.cell_at(p) != Terrain.WATER:
			effects.add_explosion(p, randf_range(0.6, 1.2))
			if sfx != null:
				sfx.ball_impact(p)
	var stop_i := OS.get_cmdline_user_args().find("--cinestop")   # nagranie tylko początku (podgląd)
	var stop_t := CINE_END + 0.5
	if stop_i >= 0 and stop_i + 1 < OS.get_cmdline_user_args().size():
		stop_t = float(OS.get_cmdline_user_args()[stop_i + 1])
	if ct > stop_t and _autotest:
		get_tree().quit()


func _cine_follow(key: String, regs: Array[Regiment], dt: float) -> void:
	var c := Vector2.ZERO
	var n := 0
	for r in regs:
		if not r.dead and r.state != Regiment.State.ROUTING:
			c += r.centroid()
			n += 1
	if n == 0:
		return
	c /= n
	if not _cine_track.has(key):
		_cine_track[key] = c
	_cine_track[key] = (_cine_track[key] as Vector2).lerp(c, 1.0 - exp(-1.5 * dt))


func _cine_melee(k: int) -> Vector2:
	## Wygładzony środek k-tego zwarcia piechoty w centrum (do końcowych zbliżeń).
	return _cine_track.get("M%d" % k, _cine_mid())


func _cine_shot(i: int) -> Array:
	## Klatka kluczowa kamery: [czas, pozycja, zoom, czy dojazd do niej to przelot z oddaleniem].
	var m := _cine_mid()
	var tr: Vector2 = _cine_track.get("R", m + Vector2(1600, 0))
	var tl: Vector2 = _cine_track.get("L", m + Vector2(-1700, 300))
	match i:
		-2: return [-CINE_INTRO, _cine_meadow + Vector2(0, 15), 4.6, false]    # łąka na skraju lasu: pasące się zwierzęta
		-1: return [-2.0, _cine_meadow + Vector2(0, -25), 3.6, false]
		0: return [1.8, m + Vector2(0, _cine_gun_y() - 120.0), 2.4, true]      # przelot nad tyły armii
		1: return [11.0, m + Vector2(0, -330), 1.0, false]
		2: return [14.5, tr, 0.88, true]
		3: return [24.0, tr, 1.5, false]
		4: return [27.5, m + Vector2(260, _cine_gun_y() + 20.0), 2.3, true]
		5: return [33.0, m + Vector2(-650, _cine_gun_y() + 20.0), 2.3, false]
		6: return [37.0, tl + Vector2(0, -60), 1.1, true]
		7: return [48.0, tl + Vector2(0, -60), 1.45, false]
		# finał: z bliska bezpośrednie starcia oddziałów - jedno zwarcie, potem przejazd na drugie
		8: return [51.5, _cine_melee(0), 2.6, true]
		9: return [56.5, _cine_melee(0), 3.4, false]
		10: return [59.0, _cine_melee(1), 3.0, false]
		_: return [CINE_END, _cine_melee(1), 3.8, false]


func _cinematic_camera() -> void:
	var ct := _cine_t()
	var a := _cine_shot(-2)
	var b := a
	for i in range(-1, 12):
		b = _cine_shot(i)
		if ct < float(b[0]):
			break
		a = b
	var span := maxf(float(b[0]) - float(a[0]), 0.001)
	var u := clampf((ct - float(a[0])) / span, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var pos: Vector2 = (a[1] as Vector2).lerp(b[1], e)
	var lz := lerpf(log(float(a[2])), log(float(b[2])), e)
	if bool(b[3]):
		lz -= 0.45 * sin(u * PI)   # przelot: kamera unosi się (oddala) w połowie drogi
	elif float(a[0]) > 1.0 and float(a[0]) < 2.0:
		pos.x += sin(u * PI) * 60.0   # przelot nad liniami: lekkie kołysanie na boki
	cam.position = pos
	cam.set_zoom_instant(exp(lz))


func _perftest(dt: float) -> void:
	## Test wydajności: po 2 s wszyscy na najbliższego wroga (masowe zwarcie), co 5 s rozkład czasu symulacji.
	_ai_timer = 1.0e9
	if sim_time >= 2.0 and sim_time - dt < 2.0:
		perf.clear()
		for r in regiments:
			var e := r._nearest_enemy()
			if e != null and r.kind != "art":
				r.order_attack(e)
				r.order_attack(e)
	if DisplayServer.get_name() != "headless" and sim_time < 31.0:
		cam.position = _cine_mid() + Vector2(0, 40)   # kamera nad starciem w centrum, jak gracz oglądający walkę
		cam.set_zoom_instant(1.3)
	if sim_time > 2.0 and int(sim_time / 5.0) != int((sim_time - dt) / 5.0):
		print("FPS t=%d fps=%d frame_ms_avg=%.1f" % [int(sim_time), Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)])
		var total := 0
		for k in perf:
			if k.begins_with("r_") == false:
				total += int(perf[k])
		var men := 0
		var melee := 0
		for r in regiments:
			men += r.alive_count()
			if r.state == Regiment.State.MELEE:
				melee += 1
		var parts := []
		var keys := perf.keys()
		keys.sort_custom(func(a, b): return int(perf[a]) > int(perf[b]))
		for k in keys:
			parts.append("%s=%d" % [k, int(perf[k]) / 5000])
		print("PERF t=%d sim_ms_per_s=%d regs=%d men=%d melee=%d | %s" % [int(sim_time), total / 5000, regiments.size(), men, melee, " ".join(parts)])
		perf.clear()
	if sim_time > 31.0 and sim_time - dt <= 31.0 and DisplayServer.get_name() != "headless":
		cam.set_zoom_instant(3.0)
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			get_viewport().get_texture().get_image().save_png("user://perf_end.png"))
	if sim_time > 32.0:
		get_tree().quit()


func _disengtest(dt: float) -> void:
	## test odwrotu jazdy: szarża na linię piechoty, po 4 s walki rozkaz odwrotu o 500 j. do tyłu, potem ponowna
	## szarża. Pokazuje, czy jazda się odrywa, ile to trwa i ile kosztuje.
	time_scale = 4.0
	_ai_timer = 99.0
	var foe: Regiment = null
	var cav: Regiment = null
	for r in regiments:
		if r.team == 1 and r.kind == "inf" and r.base_key == "line" and foe == null:
			foe = r
		elif r.team == 0 and r.kind == "cav" and cav == null:
			cav = r
	if foe == null or cav == null:
		return
	var spot := Vector2(map_size.x * 0.5, map_size.y * 0.5)
	if sim_time >= 1.0 and sim_time - dt < 1.0:
		for r in regiments:
			if r != foe and r != cav:
				r.center = Vector2(200.0 + 60.0 * regiments.find(r), 200.0 if r.team == 0 else map_size.y - 200.0)
				r.move_target = r.center
				for q in r.s_pos.size():
					r.s_pos[q] = r.slot_pos(q, r.s_pos.size())
		foe.center = spot
		foe.facing = PI
		cav.center = spot + Vector2(-430.0, 0.0)
		cav.facing = 0.0
		for r in [foe, cav]:
			r.move_target = r.center
			r.move_facing = r.facing
			for q in r.s_pos.size():
				r.s_pos[q] = r.slot_pos(q, r.s_pos.size())
		cav.order_attack(foe)
	if not has_meta("dg_contact") and cav.state == Regiment.State.MELEE:
		set_meta("dg_contact", sim_time)
	if has_meta("dg_contact") and not has_meta("dg_back") and sim_time >= float(get_meta("dg_contact")) + 4.0:
		set_meta("dg_back", sim_time)
		set_meta("dg_n", cav.alive_count())
		cav.order_move(spot + Vector2(-500.0, 0.0), 0.0)
	if has_meta("dg_back") and not has_meta("dg_free"):
		var dd := cav.centroid().distance_to(foe.centroid())
		if cav.state != Regiment.State.MELEE and dd > 220.0:
			set_meta("dg_free", sim_time)
			print("DISENG free after %.1fs lost_while_leaving=%d" % [sim_time - float(get_meta("dg_back")), int(get_meta("dg_n")) - cav.alive_count()])
	if has_meta("dg_back") and not has_meta("dg_again") and sim_time >= float(get_meta("dg_back")) + 14.0:
		set_meta("dg_again", sim_time)
		cav.order_attack(foe)
	if int(sim_time) != int(sim_time - dt) and sim_time > 1.0:
		print("dg t=%d cav=%d/%s d=%d m=%d | foe=%d/%s m=%d" % [int(sim_time), cav.alive_count(), Regiment.State.keys()[cav.state].left(4),
			int(cav.centroid().distance_to(foe.centroid())), int(cav.morale), foe.alive_count(), Regiment.State.keys()[foe.state].left(4), int(foe.morale)])
	if sim_time > 45.0 or cav.dead or foe.dead:
		print("DISENG END free=%s" % str(has_meta("dg_free")))
		get_tree().quit()


func _sqtest(dt: float) -> void:
	## test szarży jazdy na piechotę. Warianty (--variant N): 0 = AI samo formuje czworobok w ostatniej chwili,
	## 1 = czworobok uformowany zawczasu, 2 = cienka linia (2 szeregi), 3 = zwykła linia (3 szeregi) od frontu.
	var targs := OS.get_cmdline_user_args()
	var variant := 0
	var vi := targs.find("--variant")
	if vi >= 0 and vi + 1 < targs.size():
		variant = int(targs[vi + 1])
	time_scale = 4.0
	if variant != 0:
		_ai_timer = 99.0
	var foe: Regiment = null
	var cav: Regiment = null
	for r in regiments:
		if r.team == 1 and r.kind == "inf" and r.base_key == "line" and foe == null:
			foe = r
		elif r.team == 0 and r.kind == "cav" and cav == null:
			cav = r
	if foe == null or cav == null:
		return
	if sim_time >= 1.0 and sim_time - dt < 1.0:
		var spot := Vector2(map_size.x * 0.5, map_size.y * 0.5)
		for r in regiments:
			if r != foe and r != cav:
				r.center = Vector2(200.0 + 60.0 * regiments.find(r), 200.0 if r.team == 0 else map_size.y - 200.0)
				r.move_target = r.center
				for q in r.s_pos.size():
					r.s_pos[q] = r.slot_pos(q, r.s_pos.size())
		foe.center = spot
		foe.facing = PI
		if variant == 2:
			foe.base_files = ceili(foe.alive_count() / 2.0)
			foe._wide_files = foe.base_files
		cav.center = spot + Vector2(-430.0, 0.0)
		cav.facing = 0.0
		for r in [foe, cav]:
			r.move_target = r.center
			r.move_facing = r.facing
			for q in r.s_pos.size():
				r.s_pos[q] = r.slot_pos(q, r.s_pos.size())
		set_meta("sq_n0", [foe.alive_count(), cav.alive_count()])
		if variant == 1:
			foe.order_square(true)
		cav.order_attack(foe)
	if sim_time > 1.0 and int(sim_time) != int(sim_time - dt):
		print("sq t=%d d=%d foe=%d/%s sq=%s ready=%.2f m=%d | cav=%d/%s m=%d" % [int(sim_time), int(cav.centroid().distance_to(foe.centroid())),
			foe.alive_count(), Regiment.State.keys()[foe.state].left(4), foe.square, foe.square_ready(), int(foe.morale),
			cav.alive_count(), Regiment.State.keys()[cav.state].left(4), int(cav.morale)])
	if sim_time > 60.0 or (sim_time > 5.0 and (foe.dead or cav.dead)):
		var n0: Array = get_meta("sq_n0")
		print("SQ RESULT variant=%d foe_lost=%d/%d cav_lost=%d/%d foe=%s cav=%s" % [variant, n0[0] - foe.alive_count(), n0[0], n0[1] - cav.alive_count(), n0[1],
			Regiment.State.keys()[foe.state], Regiment.State.keys()[cav.state]])
		get_tree().quit()


func _formtest(dt: float) -> void:
	## test: cała armia dostaje rozkaz ustawienia się na linii skośnej do kierunku marszu.
	## Warianty (--variant N): 0 = daleka linia skośna, 1 = bliska linia skośna, 2 = zamiana miejsc skrzydłami,
	## 3 = jak 0, ale w połowie drogi przychodzi nowy rozkaz, 4 = linia tuż za własnymi stojącymi pułkami.
	var targs := OS.get_cmdline_user_args()
	var variant := 0
	var vi := targs.find("--variant")
	if vi >= 0 and vi + 1 < targs.size():
		variant = int(targs[vi + 1])
	time_scale = 8.0
	_ai_timer = 99.0   # wróg stoi: test dotyczy tylko ruchu własnych pułków
	var mine: Array[Regiment] = []
	for r in regiments:
		if r.team == 0 and not r.dead:
			mine.append(r)
	if mine.is_empty():
		return
	var give := func(dist: float, side: float, turn: float) -> void:
		var c := Vector2.ZERO
		var total := 0.0
		for r in mine:
			c += r.centroid()
			if r.kind == "inf":
				total += r.formation_width() + 30.0
		c /= mine.size()
		var fwd := mine[0].forward()
		var mid := c + fwd * dist + fwd.rotated(PI * 0.5) * side
		var d := fwd.rotated(PI * 0.5 + turn)
		selected.assign(mine)
		for plan in plan_move(mid - d * total * 0.5, mid + d * total * 0.5, true):
			var r: Regiment = plan[0]
			r.set_meta("dest", plan[1])
			r.set_meta("face", plan[2])
			r.set_meta("t_done", -1.0)
			r.order_move(plan[1], plan[2], plan[3], plan[4])
		selected.clear()
	if variant >= 5 and sim_time >= 1.0 and sim_time - dt < 1.0:
		# 5 = pułki piechoty zamieniają się miejscami "na czołówkę"; 6 = rozkaz na miejsce zajęte przez stojący pułk
		var inf: Array[Regiment] = []
		for r in mine:
			r.set_meta("dest", r.center)
			r.set_meta("face", r.facing)
			r.set_meta("t_done", -1.0)
			if r.kind == "inf":
				inf.append(r)
		var h := inf.size() / 2
		for k in h:
			var a := inf[k]
			var b := inf[k + h]
			var pa := a.center
			var pb := b.center
			a.set_meta("dest", pb)
			a.order_move(pb, a.facing)
			if variant == 5:
				b.set_meta("dest", pa)
				b.order_move(pa, b.facing)
	if variant < 5 and sim_time >= 1.0 and sim_time - dt < 1.0:
		match variant:
			1: give.call(-60.0, 120.0, 0.7)
			2: give.call(0.0, 0.0, PI)
			4: give.call(-700.0, 0.0, 0.0)
			_: give.call(-350.0, 650.0, 0.8)
	if variant == 3 and sim_time >= 14.0 and sim_time - dt < 14.0:
		give.call(-200.0, -500.0, -0.8)
	if variant == 4 and sim_time >= 6.0 and sim_time - dt < 6.0:
		# połowa armii staje w miejscu, reszta ma przejść na linię tuż za nimi
		for k in mine.size():
			if k % 2 == 0:
				mine[k].order_halt()
				mine[k].set_meta("dest", mine[k].center)
				mine[k].set_meta("face", mine[k].facing)
	if sim_time < 1.0 or not mine[0].has_meta("dest"):
		return
	var all_done := true
	for r in mine:
		if r.state != Regiment.State.IDLE:
			all_done = false
		elif float(r.get_meta("t_done")) < 0.0:
			r.set_meta("t_done", sim_time)
	if int(sim_time / 5.0) != int((sim_time - dt) / 5.0) or (all_done and not has_meta("ft_done")):
		var rows := []
		for r in mine:
			var dest: Vector2 = r.get_meta("dest")
			var face: float = r.get_meta("face")
			var want := dest - Vector2.from_angle(face) * r.formation_depth() * 0.5
			rows.append("%s:%s%s d=%d a=%d coh=%d" % [r.kind, Regiment.State.keys()[r.state].left(4), "*" if r._direct else "",
				int(r.centroid().distance_to(want)), int(absf(rad_to_deg(angle_difference(r.facing, face)))), int(r._cohesion)])
		print("form t=%d | %s" % [int(sim_time), " | ".join(rows)])
	if (all_done and not has_meta("ft_done") and (variant != 3 or sim_time > 15.0) and (variant != 4 or sim_time > 7.0)) or sim_time > 240.0:
		set_meta("ft_done", true)
		var lost := 0
		var worst := 0.0
		for r in mine:
			var dest: Vector2 = r.get_meta("dest")
			var face: float = r.get_meta("face")
			var want := dest - Vector2.from_angle(face) * r.formation_depth() * 0.5
			var off := r.centroid().distance_to(want)
			worst = maxf(worst, off)
			if off > 40.0 or r.state != Regiment.State.IDLE:
				lost += 1
		print("FORM RESULT variant=%d t=%.1f lost=%d/%d worst_off=%d" % [variant, sim_time, lost, mine.size(), int(worst)])
		get_tree().quit()


var _title_t := 0.0


func _title_shots(delta: float) -> void:
	## Test menu: kursor na pozycji menu (podświetlenie), potem podstrony; zrzut po każdym kroku.
	var prev := _title_t
	_title_t += minf(delta, 0.05)
	var steps := [[1.0, "warp", Vector2(200, 360)], [2.2, "shot", "title"], [2.4, "sub", "battle"], [3.6, "shot", "title_battle"],
		[3.8, "sub", "settings"], [5.0, "shot", "title_settings"], [5.2, "pause", null], [6.4, "shot", "title_pause"], [6.6, "quit", null]]
	for s in steps:
		if prev < s[0] and _title_t >= s[0]:
			match s[1]:
				"warp":
					overlay.test_mouse = s[2]
				"sub":
					overlay.sub = s[2]
					overlay.test_mouse = Vector2(1110, 705) if s[2] == "battle" else Vector2(670, 524)
				"pause":
					overlay.title = false
					overlay.sub = ""
					overlay.menu_tab = 2
				"shot":
					get_viewport().get_texture().get_image().save_png("user://shot_%s.png" % s[2])
					print("saved ", s[2], " t=", _title_t, " mouse=", overlay.test_mouse, " anim=", overlay._anim)
				"quit":
					get_tree().quit()


func _autotest_shots(dt: float) -> void:
	if OS.get_cmdline_user_args().has("--tuttest") and tutorial != null:
		_tutorial_autoplay(dt)
		return
	if OS.get_cmdline_user_args().has("--ravineshot"):
		# test wyglądu: wąwóz z oddalenia i z bliska
		for r in regiments:
			r.visible = false
		if not terrain.ravines.is_empty():
			var rp: PackedVector2Array = terrain.ravines[0][0]
			var mid := rp[rp.size() / 2]
			for k in 2:
				var t0 := 1.5 + k * 1.5
				if sim_time >= t0 and sim_time - dt < t0:
					cam.position = mid
					cam.set_zoom_instant(0.9 if k == 0 else 3.0)
				if sim_time >= t0 + 0.9 and sim_time - dt < t0 + 0.9:
					get_viewport().get_texture().get_image().save_png("user://ravine_%d.png" % k)
		return
	if OS.get_cmdline_user_args().has("--roadshot"):
		# test wyglądu: droga z bliska i z dalszej odległości (najlepiej przy lesie)
		for r in regiments:
			r.visible = false
		if not has_meta("rdp"):
			var pick := map_size * 0.5
			var best := -1
			var gy := 300.0
			while gy < map_size.y - 300.0:
				var gx := 300.0
				while gx < map_size.x - 300.0:
					var q := Vector2(gx, gy)
					if terrain.cell_at(q) == Terrain.ROAD:
						var sc := 0
						for o in [Vector2(90, 0), Vector2(-90, 0), Vector2(0, 90), Vector2(0, -90)]:
							if terrain.cell_at(q + o) == Terrain.FOREST:
								sc += 1
						if sc > best:
							best = sc
							pick = q
					gx += 50.0
				gy += 50.0
			set_meta("rdp", pick)
		for k in 2:
			var t0 := 1.5 + k * 1.5
			if sim_time >= t0 and sim_time - dt < t0:
				cam.position = get_meta("rdp")
				cam.set_zoom_instant(4.0 if k == 0 else 1.6)
			if sim_time >= t0 + 0.9 and sim_time - dt < t0 + 0.9:
				get_viewport().get_texture().get_image().save_png("user://road_%d.png" % k)
		return
	if OS.get_cmdline_user_args().has("--mapshot"):
		# test wyglądu: cała mapa z góry (drogi, jeziora, lasy)
		for r in regiments:
			r.visible = false
		if sim_time >= 1.0 and sim_time - dt < 1.0:
			cam.position = map_size * 0.5
			cam.set_zoom_instant(minf(1600.0 / map_size.x, 644.0 / map_size.y) * 0.98)
		if sim_time >= 2.0 and sim_time - dt < 2.0:
			get_viewport().get_texture().get_image().save_png("user://map_full.png")
		return
	if OS.get_cmdline_user_args().has("--lakeshot"):
		# test wyglądu: po jednym ujęciu każdego stylu jeziora obecnego na mapie (+ zbliżenie wyspy z pomostem)
		for r in regiments:
			r.visible = false
		if not has_meta("lk"):
			var found := {}
			for i in terrain.w * terrain.h:
				var st := int(terrain.lake_style_d[i]) / 40
				var ex := float(i % terrain.w) / terrain.w
				var ey := float(i / terrain.w) / terrain.h
				if st > 0 and ex > 0.14 and ex < 0.86 and ey > 0.16 and ey < 0.84:
					# najgłębsze miejsce jeziora danego stylu, z dala od krawędzi mapy
					if not found.has(st) or terrain.lake_d[i] > terrain.lake_d[found[st]]:
						found[st] = i
			var lst: Array = []
			for st in found:
				var fi: int = found[st]
				lst.append([st, Vector2((fi % terrain.w + 0.5) * Terrain.CELL, (fi / terrain.w + 0.5) * Terrain.CELL)])
				lst.append([st + 10, Vector2((fi % terrain.w + 0.5) * Terrain.CELL, (fi / terrain.w + 0.5) * Terrain.CELL)])
			for jt in terrain._lake_jetties:
				lst.append([6, jt[0]])
			set_meta("lk", lst)
			print("LAKES styles=", found.keys(), " isles=", terrain._lake_isles.size(), " jetties=", terrain._lake_jetties.size())
		var lk: Array = get_meta("lk")
		for k in lk.size():
			var t0 := 1.5 + k * 1.2
			if sim_time >= t0 and sim_time - dt < t0:
				cam.position = lk[k][1]
				cam.set_zoom_instant(3.0 if int(lk[k][0]) == 6 else (2.4 if int(lk[k][0]) > 10 else 0.8))
			if sim_time >= t0 + 0.8 and sim_time - dt < t0 + 0.8:
				get_viewport().get_texture().get_image().save_png("user://lake_%d_%d.png" % [int(lk[k][0]), k])
		return
	if OS.get_cmdline_user_args().has("--guntest"):
		# test wyglądu: bateria dostaje rozkaz marszu, zaprzęga, jedzie, staje i rozkłada się - klatka co sekundę
		time_scale = 2.0
		for r in regiments:
			if r.team == 0 and r.kind == "art":
				if sim_time >= 1.0 and sim_time - dt < 1.0:
					r.order_move(r.center + r.forward() * 260.0, r.facing)
				cam.position = r.gun_pos(0) - r.forward() * 20.0
				cam.set_zoom_instant(4.6)
				var gi := int(sim_time)
				if gi >= 1 and gi < 60 and gi != int(sim_time - dt):
					get_viewport().get_texture().get_image().save_png("user://gun_%02d.png" % gi)
					print("GUN t=%d lim=%.2f swing=%.2f state=%d" % [gi, r.limber_u, r._gun_swing, r.state])
				break
		return
	if OS.get_cmdline_user_args().has("--windshot"):
		# test wyglądu: seria klatek łanu zboża na wietrze (do złożenia w animację) - z bliska i z oddalenia
		time_scale = 1.0
		for r in regiments:
			r.visible = false
		if sim_time >= 0.8 and sim_time - dt < 0.8:
			cam.position = map_size * 0.5
			cam.set_zoom_instant(0.45)
		if sim_time >= 1.6 and sim_time - dt < 1.6:
			# najbardziej "pszeniczne" miejsce w kadrze: złoty kolor, z dala od interfejsu
			var im := get_viewport().get_texture().get_image()
			var vs := Vector2(im.get_size())
			im.resize(160, 90, Image.INTERPOLATE_BILINEAR)
			var best := -1.0
			var bp := Vector2(80, 40)
			for y in range(12, 62):
				for x in range(8, 152):
					var sc := 0.0
					for o in [Vector2i(0, 0), Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 3), Vector2i(0, -3)]:
						var c := im.get_pixel(x + o.x, y + o.y)
						sc += clampf((c.r - c.b) * 2.0, 0.0, 1.0) * clampf((c.r - c.g + 0.08) * 6.0, 0.0, 1.0) * c.r
					if sc > best:
						best = sc
						bp = Vector2(x, y)
			set_meta("wheat", get_viewport().get_canvas_transform().affine_inverse() * (bp / Vector2(160, 90) * vs))
		if has_meta("wheat"):
			var fi := int((sim_time - 2.2) / 0.1)
			if sim_time >= 1.7 and fi < 40:
				cam.position = get_meta("wheat")
				cam.set_zoom_instant(5.0)
			elif fi >= 40:
				cam.position = get_meta("wheat")
				cam.set_zoom_instant(2.2)
			if sim_time >= 2.2 and fi < 84 and fi != int((sim_time - dt - 2.2) / 0.1) and fi != 40 and fi != 41:
				get_viewport().get_texture().get_image().save_png("user://wind_%02d.png" % fi)
		return
	if OS.get_cmdline_user_args().has("--forestshot"):
		# test wyglądu: wnętrze lasu (dwa zbliżenia), skraj lasu i łąka z kwiatami
		if not has_meta("fshot"):
			var deep := map_size * 0.5
			var edge := map_size * 0.5
			var best := -1
			var gy := 150.0
			while gy < map_size.y - 150.0:
				var gx := 150.0
				while gx < map_size.x - 150.0:
					var n := 0
					for o in [Vector2.ZERO, Vector2(160, 0), Vector2(-160, 0), Vector2(0, 110), Vector2(0, -110), Vector2(300, 0), Vector2(-300, 0)]:
						if terrain.cell_at(Vector2(gx, gy) + o) == Terrain.FOREST:
							n += 1
					if n > best:
						best = n
						deep = Vector2(gx, gy)
					if n == 3 or n == 4:
						edge = Vector2(gx, gy)
					gx += 120.0
				gy += 120.0
			set_meta("fshot", [[deep, 2.0, "las_srodek"], [deep, 4.0, "las_blisko"], [edge, 2.4, "las_skraj"], [edge + Vector2(260, 120), 3.0, "laka"]])
		var shots: Array = get_meta("fshot")
		for k in shots.size():
			var t0 := 2.0 + k * 1.5
			if sim_time >= t0 and sim_time - dt < t0:
				cam.position = shots[k][0]
				cam.set_zoom_instant(shots[k][1])
			if sim_time >= t0 + 0.9 and sim_time - dt < t0 + 0.9:
				get_viewport().get_texture().get_image().save_png("user://%s.png" % shots[k][2])
		# seria klatek kołyszących się koron (do animacji)
		time_scale = 1.0
		var tf := int((sim_time - 8.6) / 0.1)
		if sim_time >= 8.0 and sim_time - dt < 8.0:
			cam.position = shots[0][0]
			cam.set_zoom_instant(3.2)
		if sim_time >= 8.6 and tf < 44 and tf != int((sim_time - dt - 8.6) / 0.1):
			get_viewport().get_texture().get_image().save_png("user://tree_%02d.png" % tf)
		return
	if OS.get_cmdline_user_args().has("--unitshot"):
		# test wyglądu: zbliżenia na piechotę, jazdę i artylerię gracza (sprite'y żołnierzy)
		var k := 0
		for want in ["inf", "cav", "art"]:
			for r in regiments:
				if r.team == 0 and r.kind == want:
					var t0 := 2.0 + k * 1.5
					if sim_time >= t0 and sim_time - dt < t0:
						cam.position = r.centroid()
						cam.set_zoom_instant(5.0 if want == "inf" else 3.4)
					if sim_time >= t0 + 0.8 and sim_time - dt < t0 + 0.8:
						get_viewport().get_texture().get_image().save_png("user://unit_%s.png" % want)
					break
			k += 1
		return
	if OS.get_cmdline_user_args().has("--resultshot"):
		# test wyglądu: ekran końcowy ze statystykami i wykresami po krótkiej, przyspieszonej bitwie
		time_scale = 8.0
		if sim_time >= 1.0 and sim_time - dt < 1.0:
			for r in regiments:
				if r.team == 0:
					var foe := r._nearest_enemy()
					if foe != null:
						r.order_attack(foe)
		if sim_time > 150.0 and result_text == "":
			result_text = "VICTORY"
			set_meta("rs_t", Time.get_ticks_msec())
		if has_meta("rs_t") and Time.get_ticks_msec() - int(get_meta("rs_t")) > 700:
			get_viewport().get_texture().get_image().save_png("user://result.png")
			print("saved result ", ProjectSettings.globalize_path("user://result.png"), " samples=", stats_hist.size())
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--townshot"):
		# test wyglądu: pułki wchodzą do własnej stolicy - zabudowa ma zblednąć, szyk przejść przez domy
		var town: Settlement = null
		for s in settlements:
			if s.faction == 0 and s.is_city:
				town = s
		if town != null:
			cam.position = town.position
			cam.set_zoom_instant(1.5)
			if sim_time >= 0.5 and sim_time - dt < 0.5:
				for r in regiments:
					if r.team == 0 and r.kind == "inf":
						r.order_move(town.position + Vector2(randf_range(-120, 120), randf_range(-120, 120)), 0.0)
			for tt in [1.0, 60.0]:
				if sim_time >= tt and sim_time - dt < tt:
					get_viewport().get_texture().get_image().save_png("user://town_%d.png" % int(tt))
		return
	if OS.get_cmdline_user_args().has("--artshot"):
		# test wyglądu: musztra przy dziale - kolejne fazy ładowania z bliska
		for r in regiments:
			if r.team == 0 and r.kind == "art":
				cam.position = r.gun_pos(1) + Vector2(4, 4)
				cam.set_zoom_instant(9.0)
				if sim_time >= 3.0 and sim_time - dt < 3.0:
					r.last_fire_time = sim_time
					for g in r.gun_count():
						r.s_reload[g] = r.reload_time
				if OS.get_cmdline_user_args().has("--canister"):
					cam.position = r.gun_pos(1) + r.forward() * 110.0
					cam.set_zoom_instant(3.2)
					for tt in [4.0, 4.05, 4.12, 4.3]:
						if sim_time >= tt and sim_time - dt < tt:
							if tt == 4.0:
								for g in r.gun_count():
									effects.add_canister(r.gun_pos(g) + r.forward() * 17.0, r.forward(), 0.22, 240.0)
							else:
								get_viewport().get_texture().get_image().save_png("user://can_%d.png" % int(tt * 100.0))
					break
				for k in 8:
					var ts := 3.3 + k * r.reload_time / 7.5
					if sim_time >= ts and sim_time - dt < ts:
						get_viewport().get_texture().get_image().save_png("user://art_%d.png" % k)
				break
		return
	# Zrzuty ekranu do sprawdzenia wyglądu (tylko w trybie testowym).
	var art_pos: Vector2 = deploy_pos[0]
	for r in regiments:
		if r.team == 0 and r.kind == "art":
			art_pos = r.center
	var plan := {2.0: [map_size * 0.5, 0.13], 4.0: [deploy_pos[0], 2.6], 6.0: [art_pos, 3.5]}
	# ujęcia wyglądu terenu: most z brodem, las, jezioro
	if not terrain.bridges.is_empty():
		plan[8.0] = [terrain.bridges[terrain.bridges.size() / 2][0], 1.3]
	var forest_p := map_size * 0.5
	var lake_p := map_size * 0.5
	for k in 4000:
		var q := Vector2(fposmod(k * 977.0, map_size.x), fposmod(k * 613.0, map_size.y))
		if terrain.cell_at(q) == Terrain.FOREST and terrain.cell_at(q + Vector2(250, 0)) != Terrain.FOREST and forest_p == map_size * 0.5:
			forest_p = q + Vector2(150, 0)
		if terrain.cell_at(q) == Terrain.WATER and not terrain.is_deep_fast(q) and lake_p == map_size * 0.5:
			lake_p = q
	plan[10.0] = [forest_p, 3.0]
	if sim_time >= 5.6 and sim_time - dt < 5.6:
		# test wyglądu: upadek kuli (kurz, grudy, trawa) i kula sunąca po ziemi obok baterii
		effects.add_explosion(art_pos + Vector2(-130, -40), 0.5)
		for k in 6:
			effects.add_impact(art_pos + Vector2(-150 + k * 12, 40))
	if sim_time >= 8.0 and sim_time - dt < 8.0:
		# test wyglądu: kilka przewróconych drzew przy kamerze (pnie, karpy, liście)
		for k in 8:
			var q2 := forest_p + Vector2(randf_range(-160, 160), randf_range(-90, 90))
			var tid := terrain.hit_tree(q2, Vector2.from_angle(randf() * TAU), 40.0, true)
			if tid >= 0:
				effects.add_tree_hit(q2, Vector2.RIGHT, true, terrain.tree_color(tid))
	plan[12.0] = [lake_p, 0.5]
	# test wyglądu pola ostrzału: na ujęciu 4 zaznaczony pierwszy własny pułk piechoty
	for r in regiments:
		if r.team == 0 and r.kind == "inf":
			if sim_time >= 1.0 and sim_time - dt < 1.0:
				# test: przejście na pozycję obróconą o ~55° - każdy idzie na swoje miejsce
				var fw := r.forward()
				r.order_move(r.center + fw * 70.0 + fw.orthogonal() * 60.0, r.facing + 0.95)
			if sim_time >= 3.5 and sim_time - dt < 3.5:
				r.selected = true
				selected.append(r)
				cam.position = r.center + r.forward() * r.fire_range * 0.45
			elif sim_time >= 4.5 and sim_time - dt < 4.5:
				r.selected = false
				selected.erase(r)
			break
	# ujęcia zabudowy: wioska i miasto z bliska
	for s in settlements:
		if not s.is_city and not plan.has(14.0):
			plan[14.0] = [s.position, 2.2]
		if s.is_city and not plan.has(16.0):
			plan[16.0] = [s.position, 1.4]
	for t in plan:
		if sim_time >= t - 1.0 and sim_time - dt < t - 1.0:
			cam.position = plan[t][0]
			cam.set_zoom_instant(plan[t][1])
	if sim_time >= 16.5 and sim_time - dt < 16.5 and not OS.get_cmdline_user_args().has("--fight"):
		# test wyglądu: zakładka ustawień w menu pod Esc
		menu_open = true
		overlay.menu_tab = 4
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			get_viewport().get_texture().get_image().save_png("user://shot_menu.png"))
	for t in [2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0, 150.0, 300.0]:
		if sim_time >= t and sim_time - dt < t:
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://shot_%d.png" % int(t))
			print("saved shot ", t)
	for t2 in [150.4, 300.4]:
		# zbliżenie na walkę wręcz (albo najbliższą wymianę ognia) - ujęcie do README / oceny wyglądu
		if sim_time >= t2 and sim_time - dt < t2:
			var pick: Regiment = null
			for r in regiments:
				if r.state == Regiment.State.MELEE and (pick == null or r.alive_count() > pick.alive_count()):
					pick = r
			if pick != null:
				cam.position = pick.centroid()
				cam.set_zoom_instant(4.2)
		if sim_time >= t2 + 0.6 and sim_time - dt < t2 + 0.6:
			get_viewport().get_texture().get_image().save_png("user://close_%d.png" % int(t2))
	if sim_time >= 149.0 and sim_time - dt < 149.0 or sim_time >= 299.0 and sim_time - dt < 299.0:
		# kamera na najbliższą walkę
		var best := INF
		for a in regiments:
			for b in regiments:
				if a.team == 0 and b.team == 1:
					var d := a.center.distance_to(b.center)
					if d < best:
						best = d
						cam.position = (a.center + b.center) * 0.5
		cam.set_zoom_instant(1.6)


func _separate_foes() -> void:
	## Żołnierze wrogich pułków nie przenikają przez siebie: konie odbijają się od koni, jeźdźcy nie wjeżdżają
	## w czworobok, tylko krążą wokół niego. Liczone tylko dla par pułków, które naprawdę się stykają, i tylko
	## dla żołnierzy w strefie styku (zwykle pierwsze szeregi) - nie dla całych pułków.
	var pairs := {}
	for r in regiments:
		if r.dead or (r.state != Regiment.State.MELEE and r.state != Regiment.State.CHARGING):
			continue
		var foes: Array[Regiment] = []
		foes.append_array(r.melee_enemies)
		if r.attack_target != null:
			foes.append(r.attack_target)
		for e in foes:
			if e == null or e.dead or e.team == r.team:
				continue
			var a := r if r.get_instance_id() < e.get_instance_id() else e
			var b := e if a == r else r
			pairs[Vector2i(a.get_instance_id(), b.get_instance_id())] = [a, b]
	if pairs.is_empty():
		return
	var rects := {}
	for pr in pairs.values():
		for q in pr:
			if not rects.has(q):
				rects[q] = (q as Regiment).soldier_rect(6.0)
	for pr in pairs.values():
		var a: Regiment = pr[0]
		var b: Regiment = pr[1]
		var ov := (rects[a] as Rect2).intersection(rects[b])
		if not ov.has_area():
			continue
		var ia := PackedInt32Array()
		var ib := PackedInt32Array()
		for i in a.s_pos.size():
			if a.s_hp[i] > 0.0 and ov.has_point(a.s_pos[i]):
				ia.append(i)
		if ia.is_empty():
			continue
		for j in b.s_pos.size():
			if b.s_hp[j] > 0.0 and ov.has_point(b.s_pos[j]):
				ib.append(j)
		if ib.is_empty():
			continue
		var a_cav := a.kind == "cav"
		var b_cav := b.kind == "cav"
		var min_d := 11.0 if a_cav and b_cav else (9.5 if a_cav or b_cav else 7.0)
		var md2 := min_d * min_d
		# kto ustępuje: zwarty czworobok trzyma miejsce, jazda odbija się od piechoty
		var sa := 0.5
		if a_cav and not b_cav:
			sa = 0.9 if b.square else 0.65
		elif b_cav and not a_cav:
			sa = 0.1 if a.square else 0.35
		var sb := 1.0 - sa
		for i in ia:
			var p := a.s_pos[i]
			for j in ib:
				var dv := p - b.s_pos[j]
				var d2 := dv.length_squared()
				if d2 >= md2 or d2 < 0.0001:
					continue
				var d := sqrt(d2)
				var push := (dv / d * (min_d - d)).limit_length(4.0)
				p += push * sa
				b.s_pos[j] -= push * sb
			a.s_pos[i] = p


func _push_apart(dt: float) -> void:
	## Sojusznicze pułki nie stoją jeden na drugim. Każdy pułk to prostokąt (front x głębokość) - stojące
	## rozsuwają się wzdłuż osi najmniejszego nachodzenia; maszerujący przepuszcza się przez stojących,
	## ale nie zatrzyma się na cudzym miejscu.
	var n := regiments.size()
	var rects: Array = []
	rects.resize(n)
	for i in n:
		var r := regiments[i]
		var f := r.forward()
		var hw := r.formation_width() * 0.5 + (16.0 if r.kind == "art" else 7.0)
		var hd := r.formation_depth() * 0.5 + (22.0 if r.kind == "art" else 7.0)
		if r.square:
			hd = hw
		var c := r.center - f * (r.formation_depth() * 0.5) if not r.square else r.center
		if r.kind == "art" and r.limber_u >= 1.0:
			c -= f * 40.0   # zaprzęgi z działami ciągną się za linią baterii
			hd += 42.0
		rects[i] = [c, f, hw, hd, maxf(hw, hd) * 1.5]
	# Maszerujący pułk (zwłaszcza bateria z zaprzęgami) nie przechodzi PRZEZ sojuszników: zsuwa się w bok
	# i mija ich skrzydłem, a stojący robią mu trochę miejsca. Dwa maszerujące mijają się bokami.
	for i in n:
		var a := regiments[i]
		if a.state != Regiment.State.MOVING or a.dead or a._direct or a.reg_vel.length_squared() < 4.0:
			continue
		var ra: Array = rects[i]
		var v := a.reg_vel.normalized()
		for j in n:
			var b := regiments[j]
			if i == j or a.team != b.team or b.dead or b._direct:
				continue
			if b.state == Regiment.State.ROUTING or b.state == Regiment.State.CHARGING:
				continue
			var rb: Array = rects[j]
			var dv: Vector2 = ra[0] - rb[0]
			var reach: float = ra[4] + rb[4]
			if absf(dv.x) > reach or absf(dv.y) > reach:
				continue
			var mtv := _rect_overlap(ra, rb)
			if mtv == Vector2.ZERO:
				continue
			# tylko w bok względem kierunku marszu - pułk nie jest zatrzymywany ani cofany
			var perp := mtv - v * mtv.dot(v)
			if perp.length() < 2.0:
				var sidev := Vector2(-v.y, v.x)
				var sgn := signf(sidev.dot(dv))
				if sgn == 0.0:
					sgn = 1.0 if a.get_instance_id() % 2 == 0 else -1.0
				perp = sidev * sgn * maxf(mtv.length(), 6.0)
			# zsuwanie nie szybciej, niż ludzie nadążą krokiem - inaczej środek pułku uciekałby żołnierzom,
			# pułk stawałby "na smyczy" i gubił rozkaz
			var rate := minf(maxf(14.0, a.reg_vel.length() * 0.9), a.walk_speed * a.move_mult() * 1.1) * dt
			var step := perp.limit_length(rate)
			var both_march := b.state == Regiment.State.MOVING
			# stojący pułk zostaje tam, gdzie mu kazano stać: omija go maszerujący (dawniej był spychany -
			# kolumna idąca wprost na niego potrafiła przepchnąć go o ponad sto kroków)
			a.center += step * (0.5 if both_march else 1.0)
	for i in n:
		var a := regiments[i]
		if a.state != Regiment.State.IDLE or a.dead or a.kind == "art":
			continue   # rozłożona bateria stoi: przetaczanie dział przerywałoby ogień
		var ra: Array = rects[i]
		for j in n:
			var b := regiments[j]
			if i == j or a.team != b.team or b.dead:
				continue
			if b.state != Regiment.State.IDLE and b.state != Regiment.State.MELEE:
				continue
			var rb: Array = rects[j]
			var dv: Vector2 = ra[0] - rb[0]
			var reach: float = ra[4] + rb[4]
			if absf(dv.x) > reach or absf(dv.y) > reach:
				continue
			var mtv := _rect_overlap(ra, rb)
			if mtv == Vector2.ZERO:
				continue
			# dwa stojące dzielą przesunięcie; walczący nie ustępuje
			var share := 0.5 if b.state == Regiment.State.IDLE and b.kind != "art" else 1.0
			var step := mtv * share
			a.center += step.limit_length(maxf(28.0 * dt, 0.0))
			a.move_target = a.center


static func _rect_overlap(a: Array, b: Array) -> Vector2:
	## Test osi rozdzielających dla dwóch obróconych prostokątów [środek, przód, pół-szerokość, pół-głębokość].
	## Zwraca najkrótsze przesunięcie `a`, które je rozdziela (ZERO = nie nachodzą).
	var af: Vector2 = a[1]
	var bf: Vector2 = b[1]
	var ar := Vector2(-af.y, af.x)
	var br := Vector2(-bf.y, bf.x)
	var d: Vector2 = a[0] - b[0]
	var best := INF
	var out := Vector2.ZERO
	for ax in [af, ar, bf, br]:
		var axis: Vector2 = ax
		var pa: float = absf(af.dot(axis)) * a[3] + absf(ar.dot(axis)) * a[2]
		var pb: float = absf(bf.dot(axis)) * b[3] + absf(br.dot(axis)) * b[2]
		var dist := d.dot(axis)
		var pen := pa + pb - absf(dist)
		if pen <= 0.0:
			return Vector2.ZERO
		if pen < best:
			best = pen
			out = axis * (pen * (1.0 if dist >= 0.0 else -1.0))
	return out


# ------------------------------------------------------------------ kule armatnie

func spawn_ball(from: Vector2, impact: Vector2, team: int, shell_chance := 0.3, power := 1.0) -> void:
	var d := impact - from
	var dist := maxf(d.length(), 1.0)
	balls.append({"pos": from, "dir": d / dist, "fly": dist, "flown": 0.0, "roll": randf_range(140.0, 230.0) * power,
		"speed": 380.0, "team": team, "lift": 0.0, "kills": 0, "shell": randf() < shell_chance, "fuse": -1.0})


func _update_balls(dt: float) -> void:
	var keep: Array = []
	for b in balls:
		var step: float = b["speed"] * dt
		var dir: Vector2 = b["dir"]
		if b["fuse"] >= 0.0:
			# granat leży na ziemi z tlącym się lontem, potem wybucha
			b["fuse"] -= dt
			if randf() < 0.5:
				effects.add_spark(b["pos"] + Vector2(randf_range(-2, 2), randf_range(-2, 2)))
			if b["fuse"] <= 0.0:
				effects.add_explosion(b["pos"], 1.35)
				_shell_burst(b)
				continue
			keep.append(b)
			continue
		if b["flown"] < b["fly"]:
			# nisko nad ziemią (początek i koniec toru) kula może przebić koronę drzewa
			if b["lift"] < 12.0:
				var tid := terrain.hit_tree(b["pos"], dir, 8.0)
				if tid >= 0 and b.get("tree", -1) != tid:
					b["tree"] = tid
					effects.add_tree_hit(b["pos"], dir, terrain.tree_fell(tid), terrain.tree_color(tid))
			# świst nadlatującej kuli: szczyt dźwięku (1.3 s od początku pliku) w chwili upadku
			var left: float = (b["fly"] - b["flown"]) / maxf(b["speed"], 1.0)
			if not b.get("whiz", false) and left <= Sfx.BALL_PRE and time_scale <= 2.0 and sfx != null:
				b["whiz"] = true
				sfx.ball_incoming(b["pos"] + dir * (b["fly"] - b["flown"]), left)
			b["flown"] += step
			b["pos"] += dir * step
			var t: float = clampf(b["flown"] / b["fly"], 0.0, 1.0)
			b["lift"] = sin(t * PI) * minf(b["fly"] * 0.06, 40.0)
			if b["flown"] >= b["fly"]:
				b["lift"] = 0.0
				if terrain.is_water(b["pos"]):
					effects.add_splash(b["pos"])
					continue
				if b["shell"]:
					# granat: nie toczy się - leży chwilę i wybucha
					b["fuse"] = randf_range(0.25, 1.1)
					b["speed"] = 0.0
					keep.append(b)
					continue
				# pełna kula: tylko wyrzuca ziemię i toczy się dalej, kosząc szeregi
				effects.add_explosion(b["pos"], 0.5)
				if sfx != null:
					sfx.ball_impact(b["pos"])
				_ball_hits(b, 9.0)
			keep.append(b)
		else:
			b["speed"] = maxf(b["speed"] - 420.0 * dt, 50.0)
			b["pos"] += dir * step
			b["roll"] -= step
			_ball_hits(b, 5.0)
			var rid := terrain.hit_tree(b["pos"], dir, 7.0)
			if rid >= 0 and b.get("tree", -1) != rid:
				b["tree"] = rid
				b["roll"] -= 70.0   # pień zatrzymuje toczącą się kulę
				effects.add_tree_hit(b["pos"], dir, terrain.tree_fell(rid), terrain.tree_color(rid))
			if b["roll"] <= 0.0 or terrain.is_water(b["pos"]) or b["kills"] >= 7:
				continue
			if randf() < 0.25:
				effects.add_impact(b["pos"])
			keep.append(b)
	balls = keep


func _shell_burst(b: Dictionary) -> void:
	## Wybuch granatu: odłamki w promieniu ~40 px, szansa trafienia maleje z odległością; mocno bije w morale.
	var p: Vector2 = b["pos"]
	const R := 42.0
	for r in regiments:
		if r.center.distance_to(p) > r.formation_width() + r.formation_depth() + 90.0:
			continue
		var hit := false
		var kills := 0
		for j in r.s_pos.size():
			var d := r.s_pos[j].distance_to(p)
			if r.s_hp[j] > 0.0 and d < R and randf() < 0.75 * (1.0 - d / R) + 0.1:
				r.damage(j, randf_range(60.0, 220.0))
				hit = true
				kills += 1
				if kills >= 8:
					break
		if hit:
			r.morale -= 3.0 / r.discipline


func _ball_hits(b: Dictionary, radius: float) -> void:
	var p: Vector2 = b["pos"]
	for r in regiments:
		if r.team == b["team"] and float(b["flown"]) < 90.0:
			continue   # własna bateria tuż przy wylocie; dalej kula kosi każdego, kto stoi na drodze - także swoich
		if r.center.distance_to(p) > r.formation_width() + r.formation_depth() + 80.0:
			continue
		for j in r.s_pos.size():
			if r.s_hp[j] > 0.0 and r.s_pos[j].distance_to(p) < radius and randf() < 0.8:
				r.damage(j, 250.0)
				r.morale -= 1.5 / r.discipline
				b["kills"] += 1
				if b["kills"] >= 7:
					return


# ------------------------------------------------------------------ osady i ekonomia

func _update_settlements(dt: float) -> void:
	for s in settlements:
		var present := [false, false]
		var troops := false
		for r in regiments:
			var d := r.center.distance_to(s.position)
			if d < s.radius + r.formation_width() * 0.5 + 50.0:
				troops = true   # ktokolwiek w zabudowie albo tuż przy niej (także uciekający i maszerujący)
			if r.state != Regiment.State.ROUTING and d < s.radius:
				present[r.team] = true
		s.occupied = troops
		s.contested = present[0] and present[1]
		var t := -1
		if present[0] != present[1]:
			t = 0 if present[0] else 1
		if t >= 0 and t != s.faction:
			if s.capture_team != t:
				s.capture_team = t
				s.capture = 0.0
			s.capture += dt / s.capture_time()
			if s.capture >= 1.0:
				var old := s.faction
				s.set_faction(t)
				stats["captured"][t] += 1
				s.capture = 0.0
				s.capture_team = -1
				if t == 0:
					message("Captured %s" % s.s_name)
				elif old == 0:
					message("%s has fallen to the enemy!" % s.s_name)
		elif not s.contested:
			s.capture = maxf(0.0, s.capture - dt * 0.1)
			if s.capture <= 0.0:
				s.capture_team = -1
		# rekrutacja
		# rekrutacja trwa także, gdy wróg jest w pobliżu (nowy pułk staje po stronie odwrotnej do wroga)
		if s.faction >= 0 and not s.queue.is_empty():
			s.queue[0][1] -= dt
			if s.queue[0][1] <= 0.0:
				var key: String = s.queue[0][0]
				var q_owner: int = s.queue[0][3] if s.queue[0].size() > 3 else -1
				s.queue.pop_front()
				var toward := (map_size * 0.5 - s.position).normalized()
				var threat := _nearest_enemy_to(s.position, s.faction, s.radius * 2.5)
				if threat != null:
					toward = (s.position - threat.center).normalized()
				var pos := s.position + toward * (s.radius * 0.6) + Vector2(randf_range(-60, 60), randf_range(-60, 60))
				var r := spawn_regiment(s.faction, key, pos, toward.angle(), q_owner)
				stats["recruited"][s.faction] += 1
				if s.faction == 0 and is_mine(r):
					message("%s raised in %s" % [r.reg_name, s.s_name])


# ------------------------------------------------------------------ limit armii (przeciw "kto więcej wyśle")

const LIMIT_BASE := 8          # pułków bez żadnych osad poza stolicą
const LIMIT_CITY := 3          # każde miasto utrzyma tylu więcej
const LIMIT_VILLAGE := 1
const OVER_UPKEEP := 0.2       # +20% żołdu CAŁEJ armii za każdy pułk ponad limit
const OVER_COST := 0.12        # +12% ceny werbunku za każdy pułk ponad limit
const GARRISON_FREE_CITY := 3  # ile pułków miasto kwateruje za darmo
const GARRISON_FREE_VILLAGE := 1


func command_limit(team: int) -> int:
	## Ile pułków strona utrzyma bez kar: zależy od zdobytych osad (nie od złota),
	## ale nigdy mniej niż armia startowa scenariusza.
	var lim := LIMIT_BASE
	for s in settlements:
		if s.faction == team:
			lim += LIMIT_CITY if s.is_city else LIMIT_VILLAGE
	var sc: Dictionary = SCENARIOS.get(chosen_scenario, SCENARIOS["Skirmish"])
	return maxi(lim, (sc["army"][clampi(team, 0, 1)] as Array).size())


func army_size(team: int, with_queue := true) -> int:
	var n := 0
	for r in regiments:
		if r.team == team and not r.dead:
			n += 1
	if with_queue:
		for s in settlements:
			if s.faction == team:
				n += s.queue.size()
	return n


func unit_cost(team: int, key: String) -> int:
	## Cena werbunku: rośnie za każdy pułk (z kolejką) ponad limit armii.
	var over := maxi(0, army_size(team) + 1 - command_limit(team))
	return int(float(UNIT_TYPES[key]["cost"]) * (1.0 + OVER_COST * over))


func upkeep_mult(team: int) -> float:
	return 1.0 + OVER_UPKEEP * maxi(0, army_size(team, false) - command_limit(team))


func in_town(p: Vector2) -> bool:
	for s in settlements:
		if p.distance_squared_to(s.position) < s.radius * s.radius * 0.6:
			return true
	return false


func _update_economy(dt: float) -> void:
	for t in 2:
		income[t] = 0.0
		upkeep[t] = 0.0
	for s in settlements:
		if s.faction >= 0:
			income[s.faction] += s.income
	var mult := [upkeep_mult(0), upkeep_mult(1)]
	var quartered := {}   # osada -> ilu już kwateruje za darmo
	for r in regiments:
		# Garnizon: oddział stojący we własnym mieście/wsi - leczy rannych i uzupełnia straty.
		# Za darmo kwateruje tylko kilka pułków (miasto 3, wieś 1); reszta płaci żołd jak w polu.
		var gs := garrison_of(r)
		r.garrisoned = false
		if gs != null:
			# kwatery: leczenie rannych i uzupełnianie strat (rekrut za pół ceny żołnierza)
			if r.can_resupply():
				var price := float(UNIT_TYPES[r.unit_key]["cost"]) / r.initial_count * 0.5
				if r.resupply(dt, gs.is_city, gold[r.team] >= price):
					gold[r.team] -= price
			var used: int = quartered.get(gs, 0)
			if used < (GARRISON_FREE_CITY if gs.is_city else GARRISON_FREE_VILLAGE):
				quartered[gs] = used + 1
				r.garrisoned = true
				continue
		var t: Dictionary = UNIT_TYPES[r.unit_key]
		upkeep[r.team] += float(t["upkeep"]) * (0.5 + 0.5 * float(r.alive_count()) / r.initial_count) * mult[r.team]
	var men := [0, 0]
	for r in regiments:
		men[r.team] += r.alive_count()
	for t in 2:
		stats["earned"][t] += income[t] * dt
		stats["peak_men"][t] = maxi(stats["peak_men"][t], men[t])
		gold[t] += (income[t] - upkeep[t]) * dt
		if gold[t] < 0.0:
			gold[t] = 0.0
			# Brak żołdu: dezercje i spadek morale.
			_unpaid[t] += dt
			if _unpaid[t] > 6.0:
				_unpaid[t] = 0.0
				var mine: Array[Regiment] = []
				for r in regiments:
					if r.team == t:
						mine.append(r)
				if not mine.is_empty():
					var r: Regiment = mine.pick_random()
					r.morale -= 4.0
					if r.alive_count() > 1:
						r.s_hp[randi() % r.alive_count()] = 0.0
						stats["losses"][t] += 1
					if t == 0:
						message("Treasury empty - unpaid soldiers are deserting!")
		else:
			_unpaid[t] = 0.0


func garrison_of(r: Regiment) -> Settlement:
	if r.state == Regiment.State.ROUTING:
		return null
	for s in settlements:
		if s.faction == r.team and r.center.distance_to(s.position) < s.radius:
			return s
	return null


func _nearest_enemy_to(p: Vector2, team: int, max_d: float) -> Regiment:
	var best: Regiment = null
	var bd := max_d
	for r in regiments:
		if r.team != team and not r.dead and r.state != Regiment.State.ROUTING:
			var d := r.center.distance_to(p)
			if d < bd:
				bd = d
				best = r
	return best


# ------------------------------------------------------------------ armie gracza

func army_name(id: int) -> String:
	return armies.get(id, "Reserve")


func army_groups() -> Array:
	## [[id, [pułki]], ...] - armie w kolejności tworzenia, na końcu rezerwa.
	var by_id := {}
	for r in regiments:
		if not is_mine(r):
			continue
		var id := r.army_id if armies.has(r.army_id) else -1
		if not by_id.has(id):
			by_id[id] = []
		by_id[id].append(r)
	var out: Array = []
	var ids: Array = armies.keys()
	ids.sort()
	for id in ids:
		if by_id.has(id):
			out.append([id, by_id[id]])
	if by_id.has(-1):
		out.append([-1, by_id[-1]])
	return out


func form_army() -> void:
	var mine: Array[Regiment] = []
	for r in selected:
		if r.team == 0:
			mine.append(r)
	if mine.is_empty():
		return
	_cleanup_armies()
	# Zaznaczenie należy do jednej istniejącej armii (+ ewentualnie luźne pułki): nie rozwiązujemy jej,
	# tylko dołączamy luźne pułki. Nowa armia powstaje z luźnych pułków albo z kilku armii naraz.
	var ids := {}
	for r in mine:
		if r.army_id >= 0:
			ids[r.army_id] = true
	if ids.size() == 1:
		var keep: int = ids.keys()[0]
		var added := 0
		for r in mine:
			if r.army_id != keep:
				r.army_id = keep
				added += 1
		if added > 0:
			message("%d regiments joined %s" % [added, armies.get(keep, "the army")])
		else:
			message("%s is already formed" % armies.get(keep, "This army"))
		return
	_army_counter += 1
	var id := _army_counter
	# najniższy wolny numer porządkowy armii
	var used := {}
	for k in armies:
		used[armies[k]] = true
	var n := 1
	while used.has("%s Army" % _ordinal(n)):
		n += 1
	armies[id] = "%s Army" % _ordinal(n)
	for r in mine:
		r.army_id = id
	_cleanup_armies()
	message("%s formed (%d regiments)" % [armies[id], mine.size()])


func toggle_square() -> void:
	## Q: zaznaczona piechota formuje czworobok (albo go rozwiązuje, gdy wszyscy już w nim stoją).
	var inf: Array[Regiment] = []
	var all_sq := true
	for r in selected:
		if r.team == 0 and r.kind == "inf":
			inf.append(r)
			all_sq = all_sq and r.square
	for r in inf:
		r.order_square(not all_sq)


func toggle_fire_at_will() -> void:
	## T: zaznaczona piechota przełącza tryb walki: Auto → Fire at will (tylko ogień) → Melee only (tylko bagnety).
	var inf: Array[Regiment] = []
	var cur := 0
	for r in selected:
		if r.team == 0 and r.kind == "inf":
			inf.append(r)
			cur = maxi(cur, r.fire_mode)
	if inf.is_empty():
		return
	var next := (cur + 1) % 3
	for r in inf:
		r.order_fire_mode(next)
	message(["Auto: fire first, charge on the second attack order", "Fire at will: shoot only, never charge",
		"Melee only: hold fire, attack order charges with the bayonet"][next])


func cycle_ammo() -> void:
	## B: zaznaczone baterie przechodzą na następny rodzaj pocisków (Auto → kule → granaty → kartacze).
	var art: Array[Regiment] = []
	for r in selected:
		if r.team == 0 and r.kind == "art":
			art.append(r)
	if art.is_empty():
		return
	var next := (art[0].ammo + 1) % Regiment.AMMO_NAMES.size()
	for r in art:
		r.order_ammo(next)
	var hints := ["by range: canister up close, shot and shell beyond", "long range, ploughs through ranks",
		"bursts on target - area damage, less accurate", "short range only - devastating up close"]
	message("Ammunition: %s (%s)" % [Regiment.AMMO_NAMES[next], hints[next]])


func toggle_wedge() -> void:
	## V: zaznaczona jazda formuje klin (albo wraca do linii, gdy wszyscy już są w klinie).
	var cav: Array[Regiment] = []
	var all_w := true
	for r in selected:
		if r.team == 0 and r.kind == "cav":
			cav.append(r)
			all_w = all_w and r.wedge
	for r in cav:
		r.order_wedge(not all_w)


func _ai_squares() -> void:
	## AI: piechota formuje czworobok, gdy nadciąga wroga jazda; rozwiązuje, gdy zagrożenie minie.
	for r in regiments:
		if r.team != 1 or r.commander != 0 or r.kind != "inf" or r.dead or r.state == Regiment.State.ROUTING or r.state == Regiment.State.MELEE:
			continue
		var cav_d := INF
		var inf_d := INF
		for e in regiments:
			if e.team == r.team or e.dead or e.state == Regiment.State.ROUTING:
				continue
			var d := e.center.distance_to(r.center)
			if e.kind == "cav":
				cav_d = minf(cav_d, d)
			elif e.kind == "inf":
				inf_d = minf(inf_d, d)
		if not r.square and cav_d < 380.0 and inf_d > 260.0:
			r.order_square(true)
		elif r.square and (cav_d > 650.0 or inf_d < 180.0):
			r.order_square(false)


func _army_id_for(n: int) -> int:
	var nm := "%s Army" % _ordinal(n)
	for id in armies:
		if armies[id] == nm:
			return id
	return -1


func assign_to_army(n: int) -> void:
	## Ctrl + cyfra: zaznaczone pułki przechodzą do armii nr n (tworzona, jeśli jej nie ma).
	var mine: Array[Regiment] = []
	for r in selected:
		if r.team == 0:
			mine.append(r)
	if mine.is_empty():
		return
	var id := _army_id_for(n)
	if id < 0:
		_army_counter += 1
		id = _army_counter
		armies[id] = "%s Army" % _ordinal(n)
	for r in mine:
		r.army_id = id
	_cleanup_armies()
	message("%d regiment%s -> %s" % [mine.size(), "" if mine.size() == 1 else "s", armies[id]])


var _last_army_key := -1
var _last_army_time := 0.0


func select_army(n: int) -> void:
	## Cyfra: zaznacza armię nr n; drugie naciśnięcie w krótkim czasie = skok kamery do niej.
	var id := _army_id_for(n)
	if id < 0:
		return
	var sel: Array[Regiment] = []
	for r in regiments:
		if r.team == 0 and r.army_id == id:
			sel.append(r)
	_set_selection(sel)
	var now := Time.get_ticks_msec() / 1000.0
	if _last_army_key == n and now - _last_army_time < 0.4:
		_focus_selected()
	_last_army_key = n
	_last_army_time = now


func leave_army() -> void:
	for r in selected:
		r.army_id = -1
	_cleanup_armies()


func _cleanup_armies() -> void:
	var alive := {}
	for r in regiments:
		if r.team == 0 and r.army_id >= 0:
			alive[r.army_id] = true
	for id in armies.keys():
		if not alive.has(id):
			armies.erase(id)


func can_recruit(s: Settlement, key: String) -> bool:
	if s == null or s.faction < 0 or s.queue.size() >= MAX_QUEUE:
		return false
	var t: Dictionary = UNIT_TYPES[key]
	if t["city_only"] and not s.is_city:
		return false
	if t.has("unique") and unique_count(s.faction, key) >= int(t["unique"]):
		return false   # Napoleon, marszałkowie, ambulans Larreya - ograniczona liczba
	return gold[s.faction] >= float(unit_cost(s.faction, key))


func unique_count(team: int, key: String) -> int:
	## Ile oddziałów danego typu strona ma w polu i w kolejkach werbunku.
	var n := 0
	for r in regiments:
		if is_instance_valid(r) and r.team == team and r.unit_key == key and r.alive_count() > 0:
			n += 1
	for st in settlements:
		if st.faction == team:
			for q in st.queue:
				if q[0] == key:
					n += 1
	return n


func aura_at(r: Regiment) -> float:
	## Premia do odzyskiwania morale od dowódców i żandarmerii w pobliżu (najsilniejsza aura).
	var best := 0.0
	for a in _aura_units:
		if is_instance_valid(a) and a != r and a.team == r.team and a.state != Regiment.State.ROUTING and a.alive_count() > 0:
			var t: Dictionary = UNIT_TYPES[a.unit_key]
			if a.center.distance_to(r.center) <= float(t["aura_r"]):
				best = maxf(best, float(t["aura"]))
	return best


var _aura_units: Array = []
var _heal_acc := 0.0


func _update_support_units(dt: float) -> void:
	## Raz na sekundę: lista oddziałów z aurą i leczenie przez ambulans Larreya.
	_heal_acc += dt
	if _heal_acc < 1.0:
		return
	var step := _heal_acc
	_heal_acc = 0.0
	_aura_units.clear()
	for h in regiments:
		if not is_instance_valid(h) or h.alive_count() == 0:
			continue
		var t: Dictionary = UNIT_TYPES[h.unit_key]
		if t.has("aura"):
			_aura_units.append(h)
		if t.has("heal") and h.state != Regiment.State.ROUTING:
			for r in regiments:
				if is_instance_valid(r) and r != h and r.team == h.team and r.state != Regiment.State.ROUTING 						and r.center.distance_to(h.center) <= float(t["heal_r"]):
					r.heal_acc += float(t["heal"]) / 60.0 * step * r.initial_count
					if r.heal_acc >= 1.0 and r.alive_count() < r.initial_count:
						r.heal_acc -= 1.0
						r.add_recruit()


func recruit(s: Settlement, key: String, owner := -1) -> bool:
	if not can_recruit(s, key):
		return false
	if Net.is_client():
		Net.inst.cmd(["recruit", settlements.find(s), key])
		return true
	if owner < 0:
		owner = Net.my_id() if s.faction == 0 and not Net.server_idle() else 0
	var t: Dictionary = UNIT_TYPES[key]
	var price := float(unit_cost(s.faction, key))
	gold[s.faction] -= price
	stats["spent"][s.faction] += price
	s.queue.append([key, float(t["time"]), float(t["time"]), owner])
	return true


func _check_victory() -> void:
	if result_text != "" or sim_time < 3.0 or victory_ack:
		return
	var cities := [0, 0]
	var any := [0, 0]
	for s in settlements:
		if s.faction >= 0:
			any[s.faction] += 1
			if s.is_city:
				cities[s.faction] += 1
	var regs := [0, 0]
	var standing := [0, 0]
	for r in regiments:
		regs[r.team] += 1
		if r.state != Regiment.State.ROUTING:
			standing[r.team] += 1
	if is_field():
		# bitwa w polu: przegrywa strona, której wszystkie oddziały zginęły albo uciekają
		for t in 2:
			if standing[t] == 0:
				result_text = "DEFEAT" if t == 0 else "VICTORY"
				return
		return
	for t in 2:
		if cities[t] == 0 or (regs[t] == 0 and any[t] == 0):
			result_text = "DEFEAT" if t == 0 else "VICTORY"
			return


# ------------------------------------------------------------------ AI

func _run_ai() -> void:
	var players: Array[Regiment] = []
	var ais: Array[Regiment] = []
	for r in regiments:
		if r.team == 0:
			players.append(r)
		elif r.commander == 0:
			ais.append(r)
	if not Net.active() or Net.inst.team_players(1).is_empty():
		_ai_recruit()
	var claimed := PackedVector2Array()
	var settle_claims := {}
	for r in ais:
		if r.square or r.state == Regiment.State.ROUTING or r.state == Regiment.State.MELEE or r.state == Regiment.State.CHARGING:
			continue
		var tgt: Regiment = null
		var bd := INF
		for p in players:
			var d := r.center.distance_to(p.center) + (400.0 if p.state == Regiment.State.ROUTING else 0.0)
			if d < bd:
				bd = d
				tgt = p
		var engage := 1300.0 if r.kind != "art" else 1500.0
		if tgt != null and bd < engage:
			# Nie wchodzić pojedynczo: gdy lokalnie jesteśmy wyraźnie słabsi, a walka jeszcze się nie zaczęła,
			# pułk dołącza do najbliższej grupy sojuszników (albo wraca do osady) i atakuje razem z nimi.
			if r.kind == "inf" and bd > r.fire_range * 1.3 \
					and _men_near(r.center, 1, 650.0) < _men_near(tgt.center, 0, 650.0) * 0.75:
				var rally := _ai_rally_point(r, tgt)
				if rally != Vector2.INF and r.center.distance_to(rally) > 120.0 \
						and (r.state != Regiment.State.MOVING or r.final_target().distance_to(rally) > 150.0):
					r.order_move(rally, (tgt.center - rally).angle())
					continue
			_ai_tactical(r, tgt, claimed)
			continue
		# Strategia: idź zdobywać osady (wrogie i neutralne), bronić swoich zagrożonych.
		var goal: Settlement = null
		var gd := INF
		for s in settlements:
			var score := r.center.distance_to(s.position)
			if s.faction == 1:
				if s.capture_team == 0:
					score *= 0.5
				else:
					continue
			if s.faction == 0:
				score *= 0.8 if s.is_city else 1.0
			if settle_claims.get(s, 0) >= (3 if s.is_city else 1):
				score *= 3.0
			if score < gd:
				gd = score
				goal = s
		if goal != null:
			settle_claims[goal] = settle_claims.get(goal, 0) + 1
			var dest := goal.position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * goal.radius * 0.3
			if r.state != Regiment.State.MOVING or r.final_target().distance_to(goal.position) > goal.radius:
				if r.center.distance_to(goal.position) > goal.radius * 0.6:
					r.order_move(dest, (goal.position - r.center).angle())
		elif tgt != null:
			_ai_tactical(r, tgt, claimed)


func _men_near(p: Vector2, team: int, radius: float) -> int:
	var n := 0
	for r in regiments:
		if r.team == team and not r.dead and r.state != Regiment.State.ROUTING and r.center.distance_squared_to(p) < radius * radius:
			n += r.alive_count()
	return n


func _ai_rally_point(r: Regiment, tgt: Regiment) -> Vector2:
	## Punkt zbiórki: za najbliższym pułkiem AI, który już ma sąsiadów (zaczątek linii); inaczej najbliższa własna osada.
	var best := Vector2.INF
	var bd := INF
	for f in regiments:
		if f == r or f.team != r.team or f.dead or f.state == Regiment.State.ROUTING or f.support < 1:
			continue
		var d := r.center.distance_to(f.center)
		if d < bd and d < 2500.0:
			bd = d
			var back := (f.center - tgt.center).normalized()
			best = f.center + back * 60.0 + back.orthogonal() * (f.formation_width() + 40.0) * (1.0 if r.net_id % 2 == 0 else -1.0)
	if best != Vector2.INF:
		return best
	for s in settlements:
		if s.faction == r.team:
			var d := r.center.distance_to(s.position)
			if d < bd:
				bd = d
				best = s.position
	return best


func _ai_tactical(r: Regiment, tgt: Regiment, claimed: PackedVector2Array) -> void:
	var dist := r.center.distance_to(tgt.center)
	var my_n := r.alive_count()
	var their_n := tgt.alive_count()
	if r.kind == "cav":
		# Kawaleria: szarżuje na artylerię, uciekających, związanych walką lub słabych; inaczej czeka z boku.
		var juicy := tgt.kind == "art" or tgt.state == Regiment.State.ROUTING or tgt.state == Regiment.State.MELEE or tgt.morale < 45.0
		# szarżuje na nas jazda: kontrszarża zamiast uciekania (inaczej pościg w kółko)
		var charged := tgt.state == Regiment.State.CHARGING and tgt.attack_target == r and dist < 500.0
		if charged or juicy and dist < 900.0 and r.morale > 50.0 and r.stamina > 40.0:
			r.order_attack(tgt)
			return
		if dist < 300.0 or dist > 650.0:
			var dir := (tgt.center - r.center).normalized()
			var dest := tgt.center - dir * 450.0 + dir.orthogonal() * 250.0
			# nowy rozkaz tylko, gdy cel wyraźnie się przesunął - inaczej jazda co chwilę przestawiałaby szyk
			if r.state != Regiment.State.MOVING or r.final_target().distance_to(dest) > 180.0:
				r.order_move(dest, dir.angle())
		return
	var should_charge := r.kind == "inf" and tgt.state != Regiment.State.ROUTING and dist < 230.0 and r.morale > 55.0 and r.stamina > 35.0 and (tgt.morale < 40.0 or my_n > their_n * 1.5)
	if should_charge:
		r.order_attack(tgt)
		return
	if dist > r.fire_range * 0.9:
		var dir := (tgt.center - r.center).normalized()
		var dest := tgt.center - dir * r.fire_range * 0.75
		var perp := dir.orthogonal()
		for _iter in 4:
			for c in claimed:
				if c.distance_to(dest) < 170.0:
					var side := signf(perp.dot(dest - c))
					if side == 0.0:
						side = 1.0
					dest += perp * side * 90.0
		claimed.append(dest)
		if r.state != Regiment.State.MOVING or r.final_target().distance_to(dest) > 60.0:
			r.order_move(dest, dir.angle())
	else:
		claimed.append(r.center)
		if r.state == Regiment.State.MOVING:
			r.order_halt()


func _ai_recruit() -> void:
	var weights := {"militia": 2.0, "line": 5.0, "light": 2.0, "rifles": 1.0, "grenadier": 1.5, "guard": 0.7, "hussars": 1.5,
		"dragoons": 1.2, "lancers": 1.0, "cuirassiers": 0.6, "artillery": 1.2, "horse_art": 0.6}
	var owned: Array[Settlement] = []
	for s in settlements:
		if s.faction == 1 and s.queue.size() < 2:
			owned.append(s)
	if owned.is_empty() or gold[1] < 160.0:
		return
	var s: Settlement = owned.pick_random()
	var total := 0.0
	var allowed: Array = []
	for key in s.allowed_units():
		if can_recruit(s, key) or not UNIT_TYPES[key].has("unique"):
			allowed.append(key)
	for key in allowed:
		total += weights[base_of(key)] * float(UNIT_TYPES[key].get("ai", 1.0))
	var roll := randf() * total
	for key in allowed:
		roll -= weights[base_of(key)] * float(UNIT_TYPES[key].get("ai", 1.0))
		if roll <= 0.0:
			# AI też pilnuje limitu: ponad nim werbuje tylko, gdy ma dużą nadwyżkę złota
			var price := float(unit_cost(1, key))
			var over := army_size(1) + 1 - command_limit(1)
			if gold[1] - price > 40.0 + maxf(0.0, over) * 120.0:
				recruit(s, key)
			return


# ------------------------------------------------------------------ wejście

func screen_to_world(sp: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * sp


func world_to_screen(wp: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * wp


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and ((event as InputEventKey).keycode == KEY_ENTER or (event as InputEventKey).keycode == KEY_KP_ENTER) \
			and overlay.chat_available() and not overlay.chat_open():
		overlay.open_chat((event as InputEventKey).shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Interfejs (HUD, menu, karty, panele) ma pierwszeństwo przed kliknięciami na mapie.
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			if overlay.hud_click(mb.position, mb.button_index, mb.shift_pressed, mb.double_click):
				return
		if menu_open:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				lmb_down = true
				box_active = false
				form_active = false
				box_start = mb.position
				# Przeciągnięcie LPM z zaznaczonym oddziałem (nie zaczęte na własnym pułku) = ustawianie szyku.
				_lmb_can_form = not selected.is_empty() and not mb.shift_pressed and pick_regiment(mb.position, 0) == null
			elif lmb_down:
				if form_active:
					order_drag_now = screen_to_world(mb.position)
					for plan in plan_move(order_start, order_drag_now, true):
						(plan[0] as Regiment).order_move(plan[1], plan[2], plan[3], plan[4])
					_deselect_after_order()
				elif box_active:
					_box_select(Rect2(box_start, mb.position - box_start).abs(), mb.shift_pressed)
				else:
					_click_select(mb.position, mb.shift_pressed)
				lmb_down = false
				box_active = false
				form_active = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if selected.is_empty():
					return
				var enemy := pick_regiment(mb.position, 1)
				if enemy != null:
					for r in selected:
						r.order_attack(enemy)
					_deselect_after_order()
					return
				rmb_down = true
				rmb_start_screen = mb.position
				order_start = screen_to_world(mb.position)
				order_drag_now = order_start
			elif rmb_down:
				rmb_down = false
				order_drag_now = screen_to_world(mb.position)
				for plan in plan_move(order_start, order_drag_now, false):
					(plan[0] as Regiment).order_move(plan[1], plan[2], -1, plan[4])
				_deselect_after_order()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if lmb_down and not box_active and not form_active and mm.position.distance_to(box_start) > 8.0:
			if _lmb_can_form:
				form_active = true
				order_start = screen_to_world(box_start)
			else:
				box_active = true
		if form_active:
			order_drag_now = screen_to_world(mm.position)
		if rmb_down:
			order_drag_now = screen_to_world(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if menu_open and k.keycode != KEY_ESCAPE and k.keycode != KEY_F1:
			return
		if result_text == "DISCONNECTED" and k.keycode == KEY_R:
			Net.inst.stop()
			get_tree().reload_current_scene()
			return
		match k.keycode:
			KEY_P, KEY_PAUSE:
				if not Net.active():
					paused = not paused
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var n := int(k.keycode - KEY_0)
				if k.ctrl_pressed:
					assign_to_army(n)
				else:
					select_army(n)
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS when not Net.active():
				time_scale = minf(time_scale * 2.0, 8.0)
			KEY_MINUS, KEY_KP_SUBTRACT when not Net.active():
				time_scale = maxf(time_scale * 0.5, 1.0)
			KEY_H:
				for r in selected:
					r.order_halt()
			KEY_Q:
				toggle_square()
			KEY_V:
				toggle_wedge()
			KEY_T:
				toggle_fire_at_will()
			KEY_B:
				cycle_ammo()
			KEY_ESCAPE:
				if menu_open and overlay.title:
					overlay.title_back()
				elif menu_open:
					menu_open = false
					UiSound.play("back")
				elif not selected.is_empty() or selected_settlement != null:
					var none: Array[Regiment] = []
					_set_selection(none)
					selected_settlement = null
				else:
					menu_open = true
			KEY_F1:
				if not overlay.title:
					menu_open = not menu_open
					overlay.menu_tab = 0
			KEY_F:
				_focus_selected()
			KEY_C:
				# skok kamery do stolicy
				for s in settlements:
					if s.faction == 0 and s.is_city:
						cam.position = s.position
						break
			KEY_R:
				if k.ctrl_pressed or result_text != "":
					restart_game()
			KEY_G:
				form_army()
			KEY_U:
				leave_army()
			KEY_A:
				if k.ctrl_pressed:
					var all: Array[Regiment] = []
					for r in regiments:
						if r.team == 0:
							all.append(r)
					_set_selection(all)


func _sample_history() -> void:
	## Zapis przebiegu bitwy do wykresów na ekranie końcowym (działa też u klienta - z danych z serwera).
	if sim_time < _hist_next or stats_hist.size() >= 1500 or (result_text != "" and not victory_ack):
		return
	_hist_next = sim_time + HIST_STEP
	var men := [0, 0]
	for r in regiments:
		if not r.dead and r.team >= 0 and r.team < 2:
			men[r.team] += r.alive_count()
	if men[0] + men[1] == 0:
		return
	stats_hist.append([sim_time, men[0], men[1], int(stats["losses"][0]), int(stats["losses"][1])])


func is_dragging_order(current_screen: Vector2) -> bool:
	return current_screen.distance_to(rmb_start_screen) > 12.0


func _best_line_order(units: Array[Regiment], start: Vector2, dir: Vector2, length: float) -> Array[Regiment]:
	## Kolejność pułków na nowej linii, przy której łączna droga jest najmniejsza - takie trasy się nie krzyżują
	## i każdy idzie na najbliższe miejsce. Do 7 pułków sprawdzamy wszystkie permutacje, dla większej liczby
	## - kolejność wg rzutu na linię (też bez krzyżowania przy marszu z jednego kierunku).
	var n := units.size()
	var sorted := units.duplicate()
	sorted.sort_custom(func(a: Regiment, b: Regiment) -> bool: return a.center.dot(dir) < b.center.dot(dir))
	if n <= 1 or n > 7:
		return sorted
	var slots: Array[Vector2] = []
	for k in n:
		slots.append(start + dir * length * (k + 0.5) / n)
	var best: Array = range(n)
	var best_cost := INF
	var perm: Array = range(n)
	var c := PackedInt32Array()
	c.resize(n)
	# algorytm Heapa: wszystkie permutacje bez rekurencji
	var cost_of := func(pm: Array) -> float:
		var t := 0.0
		for k in n:
			t += (sorted[pm[k]] as Regiment).center.distance_to(slots[k])
		return t
	best_cost = cost_of.call(perm)
	var i := 0
	while i < n:
		if c[i] < i:
			var a := 0 if i % 2 == 0 else c[i]
			var tmp = perm[a]
			perm[a] = perm[i]
			perm[i] = tmp
			var cc: float = cost_of.call(perm)
			if cc < best_cost - 0.01:
				best_cost = cc
				best = perm.duplicate()
			c[i] += 1
			i = 0
		else:
			c[i] = 0
			i += 1
	var out: Array[Regiment] = []
	for k in n:
		out.append(sorted[best[k]])
	return out


func plan_move(p0: Vector2, p1: Vector2, dragged: bool) -> Array:
	## Zwraca [[pułk, pozycja, kierunek, szerokość], ...]. Przeciągnięta linia wyznacza front i szerokość szyku.
	var units: Array[Regiment] = []
	for r in selected:
		if r.state != Regiment.State.ROUTING:
			units.append(r)
	if units.is_empty():
		return []
	## Dywizja mieszana (piechota + jazda/działa) ustawia się jak w epoce: piechota w pierwszej linii,
	## artyleria za nią, jazda na skrzydłach. Piąty element planu to wspólne tempo marszu (najwolniejszy pułk).
	var line_u: Array[Regiment] = []
	var art_u: Array[Regiment] = []
	var cav_u: Array[Regiment] = []
	var has_inf := false
	for u in units:
		has_inf = has_inf or u.kind == "inf"
	for u in units:
		if not has_inf or u.kind == "inf":
			line_u.append(u)
		elif u.kind == "art":
			art_u.append(u)
		else:
			cav_u.append(u)
	var out: Array = []
	var dir: Vector2
	var f: float
	var mid: Vector2
	var half_len: float
	if dragged:
		var line := p1 - p0
		dir = line.normalized()
		f = dir.angle() - PI * 0.5
		mid = (p0 + p1) * 0.5
		half_len = line.length() * 0.5
		line_u = _best_line_order(line_u, p0, dir, line.length())
		const GAP := 18.0
		var men := 0
		for u in line_u:
			men += u.alive_count()
		var usable := maxf(line.length() - GAP * (line_u.size() - 1), 1.0)
		var x := 0.0
		for u in line_u:
			var seg := usable * u.alive_count() / float(men)
			var min_files := 2 if u.kind == "art" else 4
			var files := clampi(roundi(seg / u.spacing) + 1, min_files, maxi(min_files, u.alive_count()))
			if u.kind == "art":
				files = mini(files, ceili(u.alive_count() / 2.0))
			var wdt := (files - 1) * u.spacing
			out.append([u, p0 + dir * (x + maxf(seg, wdt) * 0.5), f, files])
			x += maxf(seg, wdt) + GAP
	else:
		var c := Vector2.ZERO
		for u in units:
			c += u.center
		c /= units.size()
		f = (p0 - c).angle() if p0.distance_to(c) > 5.0 else units[0].facing
		dir = Vector2.from_angle(f).rotated(PI * 0.5)
		mid = p0
		var total := 0.0
		for u in line_u:
			total += u.formation_width() + 30.0
		line_u = _best_line_order(line_u, p0 - dir * total * 0.5, dir, total)
		half_len = total * 0.5
		var xx := -half_len
		for u in line_u:
			var wd := u.formation_width() + 30.0
			out.append([u, p0 + dir * (xx + wd * 0.5), f, u.base_files])
			xx += wd
	var fwd := Vector2.from_angle(f)
	# artyleria: druga linia, równo rozłożona za piechotą (strzela ponad nią, a jest osłonięta)
	art_u.sort_custom(func(a: Regiment, b: Regiment) -> bool: return a.center.dot(dir) < b.center.dot(dir))
	for k in art_u.size():
		var u := art_u[k]
		var along := (float(k) - (art_u.size() - 1) * 0.5) * maxf(u.formation_width() + 60.0, half_len * 2.0 / maxf(1.0, art_u.size()))
		out.append([u, mid + dir * along - fwd * 110.0, f, u.base_files])
	# jazda: na skrzydłach, lekko cofnięta - naprzemiennie lewe / prawe
	cav_u.sort_custom(func(a: Regiment, b: Regiment) -> bool: return a.center.dot(dir) < b.center.dot(dir))
	var edge := [half_len + 30.0, half_len + 30.0]   # zajęta szerokość po lewej / prawej
	var left: Array[Regiment] = []
	var right: Array[Regiment] = []
	for k in cav_u.size():
		if k < (cav_u.size() + 1) / 2:
			left.append(cav_u[k])
		else:
			right.append(cav_u[k])
	left.reverse()   # najbliższy środka idzie pierwszy
	for side in 2:
		var group: Array[Regiment] = left if side == 0 else right
		var sgn := -1.0 if side == 0 else 1.0
		for u in group:
			var w := u.formation_width()
			out.append([u, mid + dir * sgn * (edge[side] + w * 0.5) - fwd * 40.0, f, u.base_files])
			edge[side] += w + 30.0
	# wspólne tempo: dywizja nie rozciąga się - jazda nie wyprzedza piechoty i nie wpada sama na wroga
	var cap := -1.0
	if units.size() > 1:
		cap = INF
		for e in out:
			var u: Regiment = e[0]
			var far := u.center.distance_to(e[1]) >= 70.0
			var spd := u.walk_speed
			if u.kind == "art" and far:
				spd *= 2.2 if u.base_key == "horse_art" else 1.9
			cap = minf(cap, spd)
	for e in out:
		e.append(cap)
	return out


# ------------------------------------------------------------------ karty oddziałów i panel rekrutacji

const CARD_SIZE := Vector2(76, 98)
const CARD_GAP := 6.0
const PANEL_W := 300.0


func card_rects() -> Array:
	## [[pułk, Rect2], ...] - karty twoich oddziałów na dole ekranu (zwężają się, gdy jest ich dużo).
	var mine: Array[Regiment] = []
	for r in regiments:
		if r.team == 0:
			mine.append(r)
	var vs := get_viewport_rect().size
	var avail := vs.x - 300.0 - PANEL_W - 40.0
	var cw := clampf(avail / maxf(1.0, mine.size()) - CARD_GAP, 40.0, CARD_SIZE.x)
	var total := mine.size() * (cw + CARD_GAP) - CARD_GAP
	var x := 290.0 + (avail - total) * 0.5
	var out: Array = []
	for r in mine:
		out.append([r, Rect2(Vector2(x, vs.y - CARD_SIZE.y - 10.0), Vector2(cw, CARD_SIZE.y))])
		x += cw + CARD_GAP
	return out


func recruit_layout() -> Dictionary:
	var out := {"panel": Rect2(), "buttons": [], "queue_y": 0.0}
	var s := selected_settlement
	if s == null:
		return out
	var vs := get_viewport_rect().size
	var units: Array = s.allowed_units() if s.faction == 0 else []
	var rows := units.size()
	var h := 70.0 + rows * 34.0 + (24.0 + MAX_QUEUE * 18.0 if s.faction == 0 else 20.0)
	var panel := Rect2(vs.x - PANEL_W - 10.0, vs.y - h - 10.0, PANEL_W, h)
	out["panel"] = panel
	for i in rows:
		out["buttons"].append([units[i], Rect2(panel.position + Vector2(10, 62 + i * 34), Vector2(PANEL_W - 20, 30))])
	out["queue_y"] = panel.position.y + 70.0 + rows * 34.0
	return out


func _card_at(sp: Vector2) -> Regiment:
	for cr in card_rects():
		if (cr[1] as Rect2).has_point(sp):
			return cr[0]
	return null


func _focus_selected() -> void:
	if selected.is_empty():
		if selected_settlement != null:
			cam.position = selected_settlement.position
		return
	var c := Vector2.ZERO
	for r in selected:
		c += r.center
	cam.position = c / selected.size()


func pick_regiment(screen_pos: Vector2, team: int) -> Regiment:
	var best: Regiment = null
	var best_d := INF
	var wp := screen_to_world(screen_pos)
	var z := cam.zoom.x
	for r in regiments:
		if team >= 0 and r.team != team:
			continue
		# karta z portretem jest klikalna przy każdym zoomie; z bliska można też kliknąć samych żołnierzy
		var d := overlay.card_screen_pos(r).distance_to(screen_pos)
		if d > 26.0:
			if icon_alpha > 0.5:
				continue
			d = r.distance_to_soldiers(wp) * z
			if d > 14.0:
				continue
		if d < best_d:
			best_d = d
			best = r
	return best


func pick_settlement(screen_pos: Vector2) -> Settlement:
	var wp := screen_to_world(screen_pos)
	var z := cam.zoom.x
	for s in settlements:
		var r := maxf(s.radius * 0.7, 22.0 / z)
		if s.position.distance_to(wp) < r:
			return s
	return null


func _click_select(sp: Vector2, additive: bool) -> void:
	var r := pick_regiment(sp, 0)
	var sel: Array[Regiment] = []
	if additive:
		sel.assign(selected)
	if r != null:
		if additive and sel.has(r):
			sel.erase(r)
		else:
			sel.append(r)
	elif not additive:
		var s := pick_settlement(sp)
		selected_settlement = s
	_set_selection(sel)


func _box_select(rect: Rect2, additive: bool) -> void:
	var sel: Array[Regiment] = []
	if additive:
		sel.assign(selected)
	for r in regiments:
		if r.team == 0 and rect.has_point(world_to_screen(r.center)) and not sel.has(r):
			sel.append(r)
	_set_selection(sel)


func _deselect_after_order() -> void:
	## Po wydaniu rozkazu jednostki same się odznaczają (następny rozkaz = najpierw zaznacz pułk).
	if not GameSettings.deselect_after:
		return
	var none: Array[Regiment] = []
	_set_selection(none)


func _set_selection(sel: Array[Regiment]) -> void:
	for r in selected:
		r.selected = false
	var mine: Array[Regiment] = []
	for x in sel:
		if is_mine(x):
			mine.append(x)
	selected = mine
	for r in selected:
		r.selected = true
	if not selected.is_empty():
		selected_settlement = null


var _tt_last := -1
var _tt_t := 0.0


func _tutorial_autoplay(dt: float) -> void:
	## Test: wykonuje zadania samouczka tak, jak zrobiłby to gracz (rozkazami), i zapisuje zrzut każdej lekcji.
	var tut = tutorial
	time_scale = 3.0
	if tut.step != _tt_last:
		_tt_last = tut.step
		_tt_t = 0.0
		print("TUT step ", tut.step, " ", tut.cur()[0], " t=", snappedf(sim_time, 0.1))
	var before := _tt_t
	_tt_t += dt
	if before < 0.9 and _tt_t >= 0.9:
		get_viewport().get_texture().get_image().save_png("user://tut_%02d.png" % tut.step)
	if _tt_t < 1.2 or tut.done_t >= 0.0:
		return
	var once := before < 1.2
	var id := String(tut.cur()[0])
	if tut.is_talk():
		if once:
			tut.next()
		return
	var both: Array[Regiment] = [tut.a_line, tut.b_line]
	match id:
		"camera":
			cam.position += Vector2(60, 0)
			cam.set_zoom_instant(cam.zoom.x * 1.02)
		"select":
			_set_selection([tut.a_line] as Array[Regiment])
		"march":
			if once:
				tut.a_line.order_move(tut.markers[0][0], tut.a_line.facing)
		"line":
			if once:
				tut.a_line.order_move(tut.a_line.center, tut.a_line.facing + 0.6)
		"box":
			_set_selection(both)
		"arrows":
			tut.test_hold_space = true
		"advance":
			if once:
				tut.a_line.order_move(tut.markers[0][0], 0.0)
				tut.b_line.order_move(tut.markers[1][0], 0.0)
		"fire":
			if once:
				tut.a_line.order_attack(tut.e_fire)
				tut.b_line.order_attack(tut.e_fire)
		"modes":
			if once:
				_set_selection(both)
				toggle_fire_at_will()
		"flank":
			if once:
				tut.hussars.order_move(tut.markers[0][0], -PI * 0.5)
			elif tut.hussars.state == Regiment.State.IDLE and tut.hussars.center.distance_to(tut.e_flank.center) < 420.0:
				tut.hussars.order_attack(tut.e_flank)
		"square":
			if once:
				tut.b_line.order_square(true)
		"guns":
			if once:
				tut.battery.order_attack(tut.e_guns)
		"ammo":
			if once:
				_set_selection([tut.battery] as Array[Regiment])
				cycle_ammo()
		"limber":
			if once:
				tut.battery.order_move(tut.markers[0][0], tut.battery.facing)
