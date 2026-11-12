class_name Terrain
extends Node2D
## Duża mapa: trawa, pola, lasy, rzeki z mostami, jeziora, drogi między osadami.
## Wygląd rysuje shader (GPU). Do logiki gry trzymamy niskorozdzielcze mapy bajtów.

const GRASS := 0
const FOREST := 1
const WATER := 2
const ROAD := 3
const MOUNTAIN := 4   # nie do przejścia
const RAVINE := 5     # wąwóz: wolno
const SWAMP := 6      # bagno: wolno
const FORD := 7       # bród: płycizna rzeki przy moście - da się przejść (wolno, bez topienia)

const FORD_R := 260.0    # promień płycizny wokół mostu; dalej rzeka jest głęboka i nie do przejścia

const CELL := 16.0       # rozdzielczość map szumu (las, jeziora, góry, bagna)
const FEAT := 8.0        # rozdzielczość map rzek/dróg/wąwozów
# Progi terenu - ustawiane przez rodzaj mapy (MAP_TYPES) przed generowaniem.
static var FOREST_T := 0.64
static var LAKE_T := 0.82
static var MOUNT_T := 0.78
static var SWAMP_T := 0.80
static var river_xs: Array = [0.36, 0.65]   # rzeki: polozenie w poprzek mapy (ulamek szerokosci)
static var ravine_count := 6
static var extra_woods: Array = []   # [[środek, półosie Vector2], ...] - lasy dosadzane na życzenie (ujęcie filmowe)

# Rodzaje pól bitwy. Poza progami szumu każda mapa ma UKŁAD:
#   "relief": gdzie leżą góry - zwarte pasma zamiast rozsypanych skałek:
#       "none" brak, "flank" jedno pasmo wzdłuż skrzydła, "pass" pasma po obu skrzydłach (dolina środkiem),
#       "massif" 2-3 zwarte masywy z dala od środka, "corner" góry w rogach mapy
#   "woods": "noise" lasy z szumu, "flank" wielki bór na jednym skrzydle, "belt" pas lasu w poprzek pola
#   "copse": próg zagajników (255 = bez pojedynczych kęp drzew), "open": promień czystego pola w środku (ułamek wysokości)
const MAP_TYPES := {
	"Open Plains": {"desc": "A vast flat plain with almost no cover. Pure manoeuvre - cavalry and guns rule.",
		"forest": 0.90, "lake": 0.99, "swamp": 0.99, "rivers": [], "ravines": 0,
		"relief": "none", "woods": "noise", "copse": 246, "open": 0.55},
	"Countryside": {"desc": "Rolling farmland with a few woods on the flanks - the classic battlefield.",
		"forest": 0.72, "lake": 0.95, "swamp": 0.96, "rivers": [], "ravines": 1,
		"relief": "none", "woods": "noise", "copse": 228, "open": 0.36},
	"River Crossing": {"desc": "One river between the armies. Wade across under fire or fight for the bridge.",
		"forest": 0.74, "lake": 0.96, "swamp": 0.93, "rivers": [0.5], "ravines": 0,
		"relief": "none", "woods": "noise", "copse": 232, "open": 0.30},
	"Mountain Pass": {"desc": "Two mountain walls and an open valley between them. No way around.",
		"forest": 0.76, "lake": 0.97, "swamp": 0.97, "rivers": [], "ravines": 1,
		"relief": "pass", "woods": "noise", "copse": 238, "open": 0.26},
	"Ridge Flank": {"desc": "A mountain range covers one flank; the other is open ground.",
		"forest": 0.73, "lake": 0.96, "swamp": 0.96, "rivers": [], "ravines": 1,
		"relief": "flank", "woods": "noise", "copse": 234, "open": 0.32},
	"Highlands": {"desc": "A few great massifs with wide valleys between them.",
		"forest": 0.72, "lake": 0.95, "swamp": 0.97, "rivers": [], "ravines": 3,
		"relief": "massif", "woods": "noise", "copse": 236, "open": 0.26},
	"Forest Edge": {"desc": "A great forest on one flank, open fields on the other.",
		"forest": 0.80, "lake": 0.96, "swamp": 0.95, "rivers": [], "ravines": 0,
		"relief": "none", "woods": "flank", "copse": 240, "open": 0.0},
	"Great Forest": {"desc": "Dense woods all around a single large clearing.",
		"forest": 0.52, "lake": 0.94, "swamp": 0.92, "rivers": [], "ravines": 1,
		"relief": "none", "woods": "noise", "copse": 255, "open": 0.30},
	"Marshes": {"desc": "Bogs, lakes and a slow river. Watch your step.",
		"forest": 0.72, "lake": 0.80, "swamp": 0.72, "rivers": [0.5], "ravines": 0,
		"relief": "none", "woods": "noise", "copse": 236, "open": 0.18},
	"Lake District": {"desc": "Large lakes split the land into corridors.",
		"forest": 0.70, "lake": 0.74, "swamp": 0.92, "rivers": [], "ravines": 1,
		"relief": "corner", "woods": "noise", "copse": 234, "open": 0.20},
	"River Delta": {"desc": "Three rivers cut the map - every crossing matters.",
		"forest": 0.74, "lake": 0.90, "swamp": 0.84, "rivers": [0.3, 0.5, 0.7], "ravines": 0,
		"relief": "none", "woods": "noise", "copse": 238, "open": 0.0},
	"Dry Steppe": {"desc": "Barren steppe, a few gullies and distant hills.",
		"forest": 0.88, "lake": 0.99, "swamp": 0.99, "rivers": [], "ravines": 5,
		"relief": "corner", "woods": "noise", "copse": 250, "open": 0.40},
}
const MAP_TYPE_ORDER := ["Open Plains", "Countryside", "River Crossing", "Mountain Pass", "Ridge Flank", "Highlands",
	"Forest Edge", "Great Forest", "Marshes", "Lake District", "River Delta", "Dry Steppe", "Random"]
static var layout := {}   # wybrany rodzaj mapy (układ gór i lasów)


static func apply_map_type(type_name: String) -> void:
	var key := type_name
	if not MAP_TYPES.has(key):
		key = MAP_TYPES.keys().pick_random()
	var t: Dictionary = MAP_TYPES[key]
	layout = t
	FOREST_T = t["forest"]
	LAKE_T = t["lake"]
	MOUNT_T = 0.78
	SWAMP_T = t["swamp"]
	river_xs = t["rivers"]
	ravine_count = t["ravines"]


# ------------------------------------------------------------------ teatry wojny i pory roku
# Motyw = paleta terenu (trawa/śnieg/piasek, uprawy, woda, drogi), rodzaj drzew i styl zabudowy.
# Wywołaj apply_theme() przed generate(); bez wywołania obowiązuje DEFAULT_THEME (klasyczny wygląd).
const DEFAULT_THEME := "Waterloo (Summer)"
const THEMES := {
	"Waterloo (Summer)": {"desc": "Belgium, June 1815: lush green fields, golden wheat and hedgerows.",
		"grass": [Color(0.25, 0.38, 0.16), Color(0.37, 0.48, 0.21)], "dry": Color(0.53, 0.56, 0.29),
		"wet": Color(0.20, 0.36, 0.15), "heath": Color(0.38, 0.38, 0.21), "flowers": 1.0,
		"flower": [Color(0.95, 0.88, 0.45), Color(0.88, 0.86, 0.95)],
		"crops": [Color(0.77, 0.66, 0.33), Color(0.45, 0.34, 0.22), Color(0.28, 0.45, 0.17), Color(0.63, 0.62, 0.35), Color(0.33, 0.47, 0.19)],
		"crop_w": [0.32, 0.22, 0.14, 0.16], "hedge": Color(0.16, 0.29, 0.11),
		"floor": [Color(0.12, 0.21, 0.08), Color(0.22, 0.20, 0.11)],
		"water": [Color(0.36, 0.55, 0.50), Color(0.17, 0.38, 0.43), Color(0.08, 0.22, 0.31)],
		"road": [Color(0.52, 0.43, 0.30), Color(0.62, 0.53, 0.38)], "sand": Color(0.63, 0.58, 0.42),
		"snow": 0.0, "desert": 0.0, "mud": 0.0, "grade": Color(1.0, 1.0, 1.0), "sat": 0.96,
		"trees": {"broad": 0.86, "conifer": 0.09, "bush": 0.05, "palm": 0.0},
		"tree_cols": [Color(0.33, 0.52, 0.22), Color(0.24, 0.42, 0.18), Color(0.44, 0.56, 0.22), Color(0.29, 0.47, 0.20)],
		"conifer_col": Color(0.20, 0.36, 0.22), "bush_col": Color(0.30, 0.45, 0.19), "palm_col": Color(0.36, 0.50, 0.20),
		"tree_snow": 0.0, "forest_add": 0.0, "swamp_add": 0.0, "river_farm": 0.3,
		"house": "timber", "church": "spire",
		"roofs": [Color(0.60, 0.30, 0.20), Color(0.52, 0.27, 0.19), Color(0.42, 0.40, 0.40), Color(0.35, 0.35, 0.38), Color(0.56, 0.49, 0.38), Color(0.64, 0.38, 0.24)],
		"thatch": [Color(0.66, 0.55, 0.33), Color(0.58, 0.49, 0.32), Color(0.50, 0.46, 0.37), Color(0.45, 0.42, 0.36)],
		"wall": Color(0.86, 0.82, 0.70), "yard": Color(0.36, 0.48, 0.21), "dirt": Color(0.55, 0.47, 0.33)},
	"Austerlitz (Autumn)": {"desc": "Moravia, December 1805: ploughed fields, stubble and blazing autumn woods.",
		"grass": [Color(0.33, 0.37, 0.18), Color(0.45, 0.45, 0.24)], "dry": Color(0.58, 0.51, 0.30),
		"wet": Color(0.26, 0.33, 0.17), "heath": Color(0.47, 0.35, 0.22), "flowers": 0.15,
		"flower": [Color(0.86, 0.60, 0.30), Color(0.72, 0.56, 0.62)],
		"crops": [Color(0.74, 0.63, 0.40), Color(0.40, 0.29, 0.19), Color(0.42, 0.44, 0.20), Color(0.66, 0.57, 0.36), Color(0.40, 0.44, 0.22)],
		"crop_w": [0.24, 0.42, 0.10, 0.12], "hedge": Color(0.32, 0.26, 0.12),
		"floor": [Color(0.27, 0.17, 0.08), Color(0.42, 0.27, 0.11)],
		"water": [Color(0.35, 0.48, 0.47), Color(0.18, 0.33, 0.38), Color(0.09, 0.19, 0.26)],
		"road": [Color(0.47, 0.38, 0.27), Color(0.56, 0.46, 0.33)], "sand": Color(0.58, 0.52, 0.40),
		"snow": 0.0, "desert": 0.0, "mud": 0.3, "grade": Color(1.03, 0.99, 0.92), "sat": 1.0,
		"trees": {"broad": 0.72, "conifer": 0.24, "bush": 0.04, "palm": 0.0},
		"tree_cols": [Color(0.74, 0.42, 0.13), Color(0.64, 0.22, 0.11), Color(0.80, 0.64, 0.19), Color(0.54, 0.34, 0.14), Color(0.38, 0.46, 0.20)],
		"conifer_col": Color(0.20, 0.33, 0.20), "bush_col": Color(0.55, 0.36, 0.15), "palm_col": Color(0.36, 0.50, 0.20),
		"tree_snow": 0.0, "forest_add": 0.0, "swamp_add": 0.0, "river_farm": 0.3,
		"house": "timber", "church": "spire",
		"roofs": [Color(0.58, 0.29, 0.19), Color(0.50, 0.26, 0.18), Color(0.40, 0.38, 0.38), Color(0.34, 0.34, 0.37), Color(0.62, 0.36, 0.23)],
		"thatch": [Color(0.60, 0.50, 0.32), Color(0.52, 0.45, 0.32), Color(0.46, 0.42, 0.35)],
		"wall": Color(0.84, 0.79, 0.68), "yard": Color(0.42, 0.44, 0.22), "dirt": Color(0.50, 0.41, 0.29)},
	"Russia (Winter)": {"desc": "Russia, 1812: deep snow, dark pine forests, log villages and frozen rivers.",
		"grass": [Color(0.30, 0.33, 0.22), Color(0.40, 0.40, 0.28)], "dry": Color(0.52, 0.48, 0.34),
		"wet": Color(0.26, 0.30, 0.22), "heath": Color(0.36, 0.32, 0.24), "flowers": 0.0,
		"flower": [Color(0.9, 0.9, 0.9), Color(0.9, 0.9, 0.9)],
		"crops": [Color(0.60, 0.55, 0.40), Color(0.36, 0.30, 0.24), Color(0.40, 0.40, 0.30), Color(0.60, 0.56, 0.42), Color(0.42, 0.42, 0.30)],
		"crop_w": [0.25, 0.35, 0.05, 0.20], "hedge": Color(0.17, 0.21, 0.15),
		"floor": [Color(0.56, 0.61, 0.70), Color(0.72, 0.77, 0.85)],
		"water": [Color(0.44, 0.54, 0.60), Color(0.25, 0.34, 0.41), Color(0.12, 0.18, 0.25)],
		"road": [Color(0.52, 0.48, 0.44), Color(0.64, 0.61, 0.58)], "sand": Color(0.70, 0.72, 0.76),
		"snow": 1.0, "desert": 0.0, "mud": 0.0, "grade": Color(0.95, 0.98, 1.05), "sat": 0.85,
		"trees": {"broad": 0.0, "conifer": 0.96, "bush": 0.04, "palm": 0.0},
		"tree_cols": [Color(0.38, 0.31, 0.24), Color(0.33, 0.27, 0.21), Color(0.42, 0.36, 0.29)],
		"conifer_col": Color(0.14, 0.26, 0.19), "bush_col": Color(0.20, 0.29, 0.21), "palm_col": Color(0.36, 0.50, 0.20),
		"tree_snow": 0.85, "forest_add": -0.05, "swamp_add": 0.0, "river_farm": 0.2,
		"house": "log", "church": "onion",
		"roofs": [Color(0.44, 0.44, 0.46), Color(0.36, 0.35, 0.37), Color(0.30, 0.42, 0.33), Color(0.50, 0.32, 0.24)],
		"thatch": [Color(0.42, 0.40, 0.37), Color(0.36, 0.34, 0.31), Color(0.47, 0.44, 0.38)],
		"wall": Color(0.47, 0.33, 0.21), "yard": Color(0.84, 0.87, 0.92), "dirt": Color(0.58, 0.55, 0.51)},
	"Egypt (Nile)": {"desc": "Egypt, 1798: desert sand, palm groves and green fields along the Nile.",
		"grass": [Color(0.72, 0.60, 0.40), Color(0.84, 0.72, 0.50)], "dry": Color(0.89, 0.79, 0.57),
		"wet": Color(0.48, 0.52, 0.28), "heath": Color(0.68, 0.55, 0.37), "flowers": 0.0,
		"flower": [Color(0.9, 0.8, 0.5), Color(0.9, 0.8, 0.5)],
		"crops": [Color(0.80, 0.70, 0.36), Color(0.40, 0.31, 0.22), Color(0.27, 0.50, 0.17), Color(0.50, 0.57, 0.25), Color(0.50, 0.53, 0.27)],
		"crop_w": [0.24, 0.16, 0.26, 0.16], "hedge": Color(0.27, 0.38, 0.15),
		"floor": [Color(0.60, 0.53, 0.34), Color(0.70, 0.60, 0.40)],
		"water": [Color(0.32, 0.56, 0.50), Color(0.17, 0.44, 0.47), Color(0.09, 0.29, 0.37)],
		"road": [Color(0.76, 0.66, 0.48), Color(0.87, 0.77, 0.57)], "sand": Color(0.80, 0.72, 0.52),
		"snow": 0.0, "desert": 1.0, "mud": 0.0, "grade": Color(1.04, 1.0, 0.93), "sat": 1.0,
		"trees": {"broad": 0.0, "conifer": 0.0, "bush": 0.25, "palm": 0.75},
		"tree_cols": [Color(0.36, 0.48, 0.18)],
		"conifer_col": Color(0.30, 0.40, 0.20), "bush_col": Color(0.43, 0.45, 0.22), "palm_col": Color(0.34, 0.48, 0.17),
		"tree_snow": 0.0, "forest_add": 0.08, "swamp_add": 0.04, "river_farm": 1.0, "site_farm": 0.6,
		"house": "mud", "church": "dome",
		"roofs": [Color(0.86, 0.82, 0.72), Color(0.80, 0.73, 0.60), Color(0.91, 0.88, 0.81), Color(0.74, 0.65, 0.50)],
		"thatch": [Color(0.80, 0.72, 0.56), Color(0.74, 0.64, 0.48), Color(0.86, 0.79, 0.64)],
		"wall": Color(0.70, 0.60, 0.44), "yard": Color(0.76, 0.66, 0.47), "dirt": Color(0.74, 0.64, 0.46)},
	"Peninsula (Spain)": {"desc": "Spain and Portugal, 1811: sun-baked hills, olive groves and terracotta roofs.",
		"grass": [Color(0.47, 0.45, 0.24), Color(0.61, 0.55, 0.32)], "dry": Color(0.74, 0.64, 0.40),
		"wet": Color(0.34, 0.40, 0.18), "heath": Color(0.53, 0.44, 0.28), "flowers": 0.35,
		"flower": [Color(0.92, 0.76, 0.30), Color(0.86, 0.32, 0.26)],
		"crops": [Color(0.82, 0.70, 0.40), Color(0.58, 0.39, 0.25), Color(0.38, 0.44, 0.20), Color(0.74, 0.66, 0.42), Color(0.50, 0.50, 0.26)],
		"crop_w": [0.38, 0.22, 0.18, 0.12], "hedge": Color(0.31, 0.35, 0.19),
		"floor": [Color(0.44, 0.39, 0.23), Color(0.55, 0.47, 0.29)],
		"water": [Color(0.30, 0.52, 0.52), Color(0.15, 0.38, 0.45), Color(0.07, 0.24, 0.34)],
		"road": [Color(0.68, 0.56, 0.40), Color(0.78, 0.66, 0.48)], "sand": Color(0.72, 0.62, 0.44),
		"snow": 0.0, "desert": 0.25, "mud": 0.0, "grade": Color(1.05, 1.0, 0.92), "sat": 0.95,
		"trees": {"broad": 0.38, "conifer": 0.10, "bush": 0.52, "palm": 0.0},
		"tree_cols": [Color(0.27, 0.37, 0.19), Color(0.33, 0.40, 0.21), Color(0.30, 0.36, 0.22)],
		"conifer_col": Color(0.24, 0.36, 0.19), "bush_col": Color(0.47, 0.51, 0.35), "palm_col": Color(0.36, 0.50, 0.20),
		"tree_snow": 0.0, "forest_add": 0.03, "swamp_add": 0.04, "river_farm": 0.45,
		"house": "stucco", "church": "bell",
		"roofs": [Color(0.70, 0.36, 0.22), Color(0.64, 0.32, 0.20), Color(0.76, 0.44, 0.28), Color(0.66, 0.40, 0.27)],
		"thatch": [Color(0.70, 0.37, 0.23), Color(0.64, 0.33, 0.21), Color(0.74, 0.45, 0.29)],
		"wall": Color(0.92, 0.89, 0.82), "yard": Color(0.58, 0.52, 0.32), "dirt": Color(0.70, 0.58, 0.42)},
	"Poland & Prussia (Spring)": {"desc": "Poland and East Prussia, 1807: fresh green, muddy roads and wet ploughland.",
		"grass": [Color(0.28, 0.42, 0.18), Color(0.42, 0.54, 0.24)], "dry": Color(0.50, 0.50, 0.30),
		"wet": Color(0.24, 0.34, 0.18), "heath": Color(0.38, 0.36, 0.24), "flowers": 0.7,
		"flower": [Color(0.96, 0.90, 0.40), Color(0.95, 0.95, 0.93)],
		"crops": [Color(0.52, 0.58, 0.26), Color(0.33, 0.25, 0.18), Color(0.36, 0.48, 0.20), Color(0.50, 0.56, 0.30), Color(0.34, 0.50, 0.22)],
		"crop_w": [0.26, 0.40, 0.10, 0.10], "hedge": Color(0.19, 0.31, 0.13),
		"floor": [Color(0.14, 0.22, 0.10), Color(0.24, 0.22, 0.13)],
		"water": [Color(0.38, 0.50, 0.46), Color(0.22, 0.35, 0.38), Color(0.12, 0.22, 0.27)],
		"road": [Color(0.40, 0.32, 0.22), Color(0.49, 0.39, 0.27)], "sand": Color(0.50, 0.46, 0.36),
		"snow": 0.0, "desert": 0.0, "mud": 1.0, "grade": Color(0.98, 1.0, 1.0), "sat": 0.95,
		"trees": {"broad": 0.56, "conifer": 0.40, "bush": 0.04, "palm": 0.0},
		"tree_cols": [Color(0.40, 0.58, 0.24), Color(0.34, 0.52, 0.22), Color(0.52, 0.62, 0.30)],
		"conifer_col": Color(0.18, 0.32, 0.20), "bush_col": Color(0.36, 0.50, 0.22), "palm_col": Color(0.36, 0.50, 0.20),
		"tree_snow": 0.0, "forest_add": -0.02, "swamp_add": -0.04, "river_farm": 0.3,
		"house": "timber", "church": "spire",
		"roofs": [Color(0.58, 0.28, 0.20), Color(0.50, 0.26, 0.19), Color(0.40, 0.38, 0.38), Color(0.62, 0.34, 0.22)],
		"thatch": [Color(0.60, 0.51, 0.33), Color(0.53, 0.46, 0.33), Color(0.46, 0.43, 0.36)],
		"wall": Color(0.84, 0.80, 0.70), "yard": Color(0.34, 0.48, 0.21), "dirt": Color(0.46, 0.37, 0.26)},
}
const THEME_ORDER := ["Waterloo (Summer)", "Austerlitz (Autumn)", "Russia (Winter)", "Egypt (Nile)",
	"Peninsula (Spain)", "Poland & Prussia (Spring)", "Random"]

static var theme_name: String = DEFAULT_THEME
static var theme: Dictionary = THEMES[DEFAULT_THEME]
static var current: Terrain      # ostatnio wygenerowany teren (osady czytają z niego drogi)


static func apply_theme(name: String) -> void:
	## Ustawia motyw (teatr wojny + pora roku). Nieznana nazwa / "Random" → losowy motyw.
	## Akceptuje też fragment nazwy bez względu na wielkość liter (np. "russia").
	var key := name
	if not THEMES.has(key):
		key = ""
		var low := name.to_lower().strip_edges()
		if low != "" and low != "random":
			for k in THEMES:
				if (k as String).to_lower().contains(low):
					key = k
					break
		if key == "":
			key = THEMES.keys().pick_random()
	theme_name = key
	theme = THEMES[key]


static func theme_minimap_colors() -> Dictionary:
	## Kolory minimapy dla bieżącego motywu: grass, field, forest, water, road, swamp, mountain.
	var g: Array = tv("grass")
	var snow := float(tv("snow"))
	var grass: Color = (g[0] as Color).lerp(g[1], 0.5)
	if snow > 0.0:
		grass = grass.lerp(Color(0.88, 0.91, 0.96), snow * 0.9)
	var crops: Array = tv("crops")
	var field: Color = (crops[0] as Color).lerp(crops[1], 0.4)
	if snow > 0.0:
		field = field.lerp(Color(0.84, 0.87, 0.93), snow * 0.85)
	var forest: Color = tv("conifer_col") if float((tv("trees") as Dictionary).get("conifer", 0.0)) > 0.5 else (tv("tree_cols") as Array)[0]
	var wa: Array = tv("water")
	var ro: Array = tv("road")
	return {"grass": grass, "field": field, "forest": (forest as Color).darkened(0.15),
		"water": (wa[1] as Color), "road": (ro[0] as Color), "swamp": (tv("wet") as Color).darkened(0.1),
		"mountain": Color(0.55, 0.52, 0.47).lerp(Color(0.9, 0.92, 0.95), snow * 0.5)}


static func tv(key: String) -> Variant:
	## Wartość z bieżącego motywu (z zapasem z motywu domyślnego).
	return theme[key] if theme.has(key) else THEMES[DEFAULT_THEME][key]


static func _cli_theme() -> void:
	## Hak do testów: `-- --theme <nazwa>` w argumentach użytkownika.
	var args := OS.get_cmdline_user_args()
	var i := args.find("--theme")
	if i >= 0 and i + 1 < args.size():
		apply_theme(args[i + 1])


const ROAD_WIDTH := 36.0

const CITY_NAMES := ["Valmont", "Kingsbridge", "Northgate", "Southwold", "Ravensholm", "Eastmarch"]
const NAME_PREFIX := ["Upper", "Lower", "Little", "Great", "East", "West", "North", "South"]
const VILLAGE_NAMES := [
	"Oakley", "Ashby", "Brookfield", "Millbrook", "Thornton", "Elmstead", "Fairford", "Greenhill",
	"Hawkridge", "Linden", "Marsh End", "Netherby", "Orchard Green", "Pinewood", "Redwater", "Stonebridge",
	"Tillingham", "Upton", "Whitmore", "Yarrow",
]

var map_size := Vector2.ZERO
var w := 0
var h := 0
var fw := 0
var fh := 0
var forest_d := PackedByteArray()
var lake_d := PackedByteArray()
var feat_d := PackedByteArray()
var mount_d := PackedByteArray()
var swamp_d := PackedByteArray()
var ravine_d := PackedByteArray()
var ravines: Array = []     # [PackedVector2Array, szerokość]

var rivers: Array = []      # [PackedVector2Array punktów, szerokość]
var roads: Array = []       # PackedVector2Array
var bridges: Array = []     # [pos, kąt]
var fords: Array = []       # [pos, indeks rzeki, czy_most] - miejsca, gdzie rzekę da się przekroczyć
var ford_d := PackedByteArray()   # mapa FEAT: 1 = płycizna (bród) w obrębie rzeki
var sites: Array = []       # [pos, is_city, nazwa]

# progi lasu/bagien po uwzględnieniu motywu (logika gry używa tych, nie statycznych)
var forest_t := 0.64
var swamp_t := 0.80

# --- pola uprawne: mapa "rolniczości" (bliskość osad, dróg, rzek) i komórki pól liczone tak samo na CPU i GPU
const FARM_CELL := 64.0      # rozdzielczość mapy upraw
const FIELD_CELL := 470.0    # rozmiar komórki działek (Voronoi), w środku dzielonej na zagony
var farm_w := 0
var farm_h := 0
var farm_d := PackedByteArray()   # RGBA8: R = uprawy 0..1, G = kierunek zagonów (kąt/2π), B = rdzeń osady
var field_seed := 0
var warp_ph := Vector4.ZERO
var _fseed_cache := {}


# --- style jezior: każde jezioro ma własny charakter (brzeg, barwa wody, roślinność)
const LAKE_REEDS := 1     # trzciny i lilie
const LAKE_BEACH := 2     # piaszczysta plaża, turkusowa płycizna
const LAKE_ROCKS := 3     # skaliste brzegi, ciemna toń
const LAKE_MARSH := 4     # bagniste rozlewisko z kępami
const LAKE_ISLE := 5      # wyspa z drzewami i pomost z łódką
var lake_style_d := PackedByteArray()   # styl * 40 na komórkę (0 = brak jeziora / rzeka)
var _lake_isles: Array = []             # [środek, promień] - zalesione wyspy
var _lake_jetties: Array = []           # [punkt na brzegu, kierunek w głąb jeziora]


func _style_lakes() -> void:
	## Dzieli wodę stojącą na osobne jeziora (wypełnianie obszaru) i każdemu losuje styl. Duże jeziora mogą dostać
	## wyspę (obniżenie pola jeziora w najgłębszym miejscu → ląd) i pomost na brzegu.
	lake_style_d = PackedByteArray()
	lake_style_d.resize(w * h)
	_lake_isles.clear()
	_lake_jetties.clear()
	var thr := int(LAKE_T * 255.0)
	var loose := thr - 30            # razem z pasem brzegu, który shader maluje piaskiem / trzciną
	var seen := PackedByteArray()
	seen.resize(w * h)
	var swampy := SWAMP_T < 0.8
	for start in w * h:
		if seen[start] != 0 or lake_d[start] <= thr:
			continue
		var stack := PackedInt32Array([start])
		seen[start] = 1
		var cells := PackedInt32Array()
		var area := 0
		var best := start
		while not stack.is_empty():
			var c := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cells.append(c)
			if lake_d[c] > thr:
				area += 1
			if lake_d[c] > lake_d[best]:
				best = c
			var cx := c % w
			var cy := c / w
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + o.x
				var ny: int = cy + o.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				if seen[ni] == 0 and lake_d[ni] > loose:
					seen[ni] = 1
					stack.append(ni)
		var style: int = [LAKE_REEDS, LAKE_BEACH, LAKE_ROCKS, LAKE_MARSH][randi() % 4]
		if swampy and randf() < 0.55:
			style = LAKE_MARSH if randf() < 0.7 else LAKE_REEDS
		var force := OS.get_cmdline_user_args().find("--lakestyle")   # narzędzie testowe: wszystkie jeziora w jednym stylu
		if force >= 0 and force + 1 < OS.get_cmdline_user_args().size():
			style = clampi(int(OS.get_cmdline_user_args()[force + 1]), 1, 4)
		var world_area := float(area) * CELL * CELL
		if world_area > 60000.0 and lake_d[best] > thr + 12 and randf() < 0.5:
			style = LAKE_ISLE
		for c in cells:
			lake_style_d[c] = style * 40
		if style != LAKE_ISLE:
			continue
		var bx := best % w
		var by := best / w
		var centre := Vector2((bx + 0.5) * CELL, (by + 0.5) * CELL)
		var rad := clampf(sqrt(world_area) * 0.14, 34.0, 80.0)
		var rc := int(ceil(rad / CELL)) + 1
		for dy in range(-rc, rc + 1):
			for dx in range(-rc, rc + 1):
				var ix := bx + dx
				var iy := by + dy
				if ix < 0 or iy < 0 or ix >= w or iy >= h:
					continue
				var d := Vector2(dx, dy).length() * CELL / rad
				if d < 1.0:
					lake_d[iy * w + ix] = mini(lake_d[iy * w + ix], int(lerpf(float(thr - 26), float(thr + 3), d * d)))
		_lake_isles.append([centre, rad])
		# pomost: od brzegu w stronę wyspy, w losowym kierunku, o ile brzeg jest w rozsądnej odległości
		for attempt in 8:
			var dir := Vector2.from_angle(randf() * TAU)
			var q := centre + dir * (rad + CELL)
			var steps := 0
			while steps < 60 and q.x > 0.0 and q.y > 0.0 and q.x < map_size.x and q.y < map_size.y and lake_d[_ci(q)] > thr:
				q += dir * CELL * 0.5
				steps += 1
			if steps > 6 and steps < 60:
				_lake_jetties.append([q - dir * CELL * 0.4, -dir])
				break


func _draw_lake_deco(node: Node2D) -> void:
	## Pomosty i łódki na jeziorach z wyspą - pikselowe, jak pnie i mosty.
	var px := 1.5
	for j in _lake_jetties:
		var a: Vector2 = j[0]
		var d: Vector2 = j[1]
		var sd := d.orthogonal()
		var ln := 34.0
		var k := -6.0
		while k < ln:
			var plank := Color(0.52, 0.39, 0.24) if int(k / px) % 3 != 0 else Color(0.38, 0.28, 0.17)
			for u in [-3.0, -1.5, 0.0, 1.5]:
				var q: Vector2 = ((a + d * k + sd * u) / px).floor() * px
				node.draw_rect(Rect2(q, Vector2(px, px)), plank if u > -3.0 else plank.lightened(0.15))
			if int(k / px) % 5 == 0 and k > 0.0:
				for u2 in [-4.5, 3.0]:
					var pq: Vector2 = ((a + d * k + sd * u2) / px).floor() * px
					node.draw_rect(Rect2(pq, Vector2(px, px)), Color(0.20, 0.14, 0.09))
			k += px
		# łódka przycumowana przy końcu pomostu
		var bc := a + d * (ln - 9.0) + sd * 9.0
		for by2 in range(-4, 5):
			var half := 2 if absi(by2) < 3 else (1 if absi(by2) < 4 else 0)
			for bx2 in range(-half, half + 1):
				var bq: Vector2 = ((bc + d * (by2 * px) + sd * (bx2 * px)) / px).floor() * px
				var rim := absi(bx2) == half or absi(by2) >= 3
				node.draw_rect(Rect2(bq, Vector2(px, px)), Color(0.30, 0.21, 0.13) if rim else Color(0.62, 0.48, 0.30))
		for by3 in [-1, 1]:
			var sq: Vector2 = ((bc + d * (by3 * px)) / px).floor() * px
			node.draw_rect(Rect2(sq, Vector2(px, px)), Color(0.40, 0.29, 0.18))   # ławki


func generate(size: Vector2) -> void:
	map_size = size
	w = int(size.x / CELL)
	h = int(size.y / CELL)
	fw = int(size.x / FEAT)
	fh = int(size.y / FEAT)
	_cli_theme()
	current = self
	forest_t = clampf(FOREST_T + float(tv("forest_add")), 0.3, 0.95)
	swamp_t = clampf(SWAMP_T + float(tv("swamp_add")), 0.3, 0.98)

	var ground_img := _noise(0.008, 4).get_image(w, h, false, false, true)
	# lasy: szum z zawirowaniem dziedziny → organiczne, postrzępione kształty zamiast okrągłych plam
	var fnoise := _noise(0.011, 4)
	fnoise.domain_warp_enabled = true
	fnoise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	fnoise.domain_warp_amplitude = 38.0
	fnoise.domain_warp_frequency = 0.018
	fnoise.domain_warp_fractal_octaves = 2
	var forest_img := fnoise.get_image(w, h, false, false, true)
	var copse_img := _noise(0.075, 2).get_image(w, h, false, false, true)
	var lake_img := _noise(0.0065, 3).get_image(w, h, false, false, true)
	var mn := _noise(0.0055, 5)
	mn.fractal_type = FastNoiseLite.FRACTAL_RIDGED   # grzbiety górskie
	var mount_img := mn.get_image(w, h, false, false, true)
	var swamp_img := _noise(0.014, 3).get_image(w, h, false, false, true)
	forest_d = forest_img.get_data()
	lake_d = lake_img.get_data()
	mount_d = mount_img.get_data()
	swamp_d = swamp_img.get_data()
	_apply_layout()
	# Nie ma gór ani bagien w jeziorach.
	for i in w * h:
		if lake_d[i] > LAKE_T * 255.0 - 10.0:
			mount_d[i] = mini(mount_d[i], 120)
			swamp_d[i] = mini(swamp_d[i], 120)

	_make_rivers()
	_clear_mountains_along_rivers()
	_open_centre()
	_place_sites()
	_make_roads()
	_build_farmland()
	_shape_forests(copse_img.get_data())
	_make_fords()
	_build_road_graph()
	_make_ravines()
	_rasterize_features()
	_build_ford_map()
	_clear_around_sites_and_roads()
	_build_mountain_grid()
	_style_lakes()
	_stamp_woods(fnoise)

	forest_img = Image.create_from_data(w, h, false, Image.FORMAT_L8, forest_d)
	lake_img = Image.create_from_data(w, h, false, Image.FORMAT_L8, lake_d)
	mount_img = Image.create_from_data(w, h, false, Image.FORMAT_L8, mount_d)
	swamp_img = Image.create_from_data(w, h, false, Image.FORMAT_L8, swamp_d)
	var feat_img := _soften(Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8, feat_d))
	var ravine_img := _soften(Image.create_from_data(fw, fh, false, Image.FORMAT_L8, ravine_d))
	var ford_img := Image.create_from_data(fw, fh, false, Image.FORMAT_L8, ford_d)
	ford_img.resize(fw / 8, fh / 8, Image.INTERPOLATE_BILINEAR)   # miękkie przejście płycizny w głębinę

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("ground_tex", ImageTexture.create_from_image(ground_img))
	mat.set_shader_parameter("forest_tex", ImageTexture.create_from_image(forest_img))
	mat.set_shader_parameter("lake_tex", ImageTexture.create_from_image(lake_img))
	mat.set_shader_parameter("lake_style_tex", ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_L8, lake_style_d)))
	mat.set_shader_parameter("mount_tex", ImageTexture.create_from_image(mount_img))
	mat.set_shader_parameter("swamp_tex", ImageTexture.create_from_image(swamp_img))
	mat.set_shader_parameter("ravine_tex", ImageTexture.create_from_image(ravine_img))
	mat.set_shader_parameter("feat_tex", ImageTexture.create_from_image(feat_img))
	mat.set_shader_parameter("ford_tex", ImageTexture.create_from_image(ford_img))
	mat.set_shader_parameter("detail_tex", _detail_texture())
	mat.set_shader_parameter("map_size", size)
	mat.set_shader_parameter("data_texel", Vector2(1.0 / w, 1.0 / h))
	mat.set_shader_parameter("forest_t", forest_t)
	mat.set_shader_parameter("lake_t", LAKE_T)
	mat.set_shader_parameter("mount_t", MOUNT_T)
	mat.set_shader_parameter("swamp_t", swamp_t)
	var farm_img := Image.create_from_data(farm_w, farm_h, false, Image.FORMAT_RGBA8, farm_d)
	var farm_tex := ImageTexture.create_from_image(farm_img)
	mat.set_shader_parameter("farm_tex", farm_tex)
	mat.set_shader_parameter("farm_lin", farm_tex)
	mat.set_shader_parameter("farm_scale", Vector2(1.0 / (farm_w * FARM_CELL), 1.0 / (farm_h * FARM_CELL)))
	mat.set_shader_parameter("field_seed", field_seed)
	mat.set_shader_parameter("field_cell", FIELD_CELL)
	mat.set_shader_parameter("warp_ph", warp_ph)
	_apply_palette(mat)
	_mat = mat
	var ground := ColorRect.new()
	ground.size = size
	ground.material = mat
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	var bridge_layer := BridgeLayer.new()
	bridge_layer.bridges = bridges
	bridge_layer.fords = fords
	bridge_layer.rivers = rivers
	add_child(bridge_layer)
	var lake_deco := Node2D.new()
	lake_deco.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lake_deco.draw.connect(_draw_lake_deco.bind(lake_deco))
	add_child(lake_deco)
	_build_trees()


# ------------------------------------------------------------------ styl pikselowy

const PIXEL_SCREEN := 1.05   # docelowy rozmiar "piksela" terenu na ekranie
var _mat: ShaderMaterial
var _pix := -1.0


func _process(_dt: float) -> void:
	_animate_hit_trees(clampf(get_process_delta_time(), 0.0, 0.1))
	## Rozmiar piksela terenu w świecie: potęga dwójki dobrana do zoomu (siatka zakotwiczona w świecie,
	## więc przy przesuwaniu nic nie pływa, a przy zoomie zmienia się skokowo jak poziomy mipmap).
	if _mat == null:
		return
	var cam := get_viewport().get_camera_2d()
	var z := cam.zoom.x if cam else 1.0
	var p := maxf(1.0, pow(2.0, roundf(log(PIXEL_SCREEN / z) / log(2.0))))
	if p != _pix:
		_pix = p
		_mat.set_shader_parameter("pix", p)


func _soften(img: Image) -> Image:
	## Wygładza kanciaste krawędzie dróg/rzek/wąwozów (tylko wygląd; logika gry używa ostrych danych).
	var w0 := img.get_width()
	var h0 := img.get_height()
	img.resize(w0 / 2, h0 / 2, Image.INTERPOLATE_BILINEAR)
	img.resize(w0, h0, Image.INTERPOLATE_CUBIC)
	return img


func _noise(freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.frequency = freq
	n.fractal_octaves = octaves
	return n


func _detail_texture() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.frequency = 0.015
	n.fractal_octaves = 5
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	return t


# ------------------------------------------------------------------ pola uprawne i paleta

func _build_farmland() -> void:
	## Mapa upraw: pola skupione wokół osad (zagony promieniście od wsi), wzdłuż dróg (w poprzek drogi)
	## i - zależnie od motywu - w dolinach rzek (Nil). Daleko od ludzi zostają dzikie łąki i wrzosowiska.
	field_seed = randi() % 1000000
	warp_ph = Vector4(randf() * TAU, randf() * TAU, randf() * TAU, randf() * TAU)
	_fseed_cache.clear()
	farm_w = ceili(map_size.x / FARM_CELL)
	farm_h = ceili(map_size.y / FARM_CELL)
	var n := farm_w * farm_h
	var f := PackedFloat32Array()
	f.resize(n)
	var best := PackedFloat32Array()
	best.resize(n)
	var ang := PackedFloat32Array()
	ang.resize(n)
	var core := PackedByteArray()
	core.resize(n)
	var nz := _noise(0.05, 2)
	var site_farm := float(theme.get("site_farm", 1.0))
	for s in sites:
		var p: Vector2 = s[0]
		var city: bool = s[1]
		var r0 := 370.0 if city else 235.0      # rdzeń: zabudowa i zagrody, bez pól
		var big_r := 1350.0 if city else 820.0
		var rc := int(big_r / FARM_CELL) + 1
		var cx := int(p.x / FARM_CELL)
		var cy := int(p.y / FARM_CELL)
		for y in range(maxi(0, cy - rc), mini(farm_h, cy + rc + 1)):
			for x in range(maxi(0, cx - rc), mini(farm_w, cx + rc + 1)):
				var q := Vector2((x + 0.5) * FARM_CELL, (y + 0.5) * FARM_CELL)
				var d := q.distance_to(p)
				if d > big_r:
					continue
				var i := y * farm_w + x
				if d < r0:
					core[i] = 255
				var v := (1.0 - smoothstep(r0 + 120.0, big_r, d)) * site_farm
				if v > f[i]:
					f[i] = v
				if v > best[i]:
					best[i] = v
					ang[i] = (q - p).angle()
	var lines: Array = []   # [punkty, promień, siła]
	for rd in roads:
		lines.append([rd, 260.0, 0.32, 2])   # wąski pas pól przy drodze; dalej dzikie łąki
	var rf := float(tv("river_farm"))
	if rf > 0.0:
		for r in rivers:
			lines.append([r[0], 450.0 + 1000.0 * rf, rf, 3])
	for ln in lines:
		var pts: PackedVector2Array = ln[0]
		var rr: float = ln[1]
		var strength: float = ln[2]
		var rc := int(rr / FARM_CELL) + 1
		for k in range(0, pts.size() - 1, int(ln[3])):
			var a := pts[k]
			var b := pts[mini(k + int(ln[3]), pts.size() - 1)]
			var along := (b - a).angle() + PI * 0.5   # zagony w poprzek drogi / rzeki
			var cx := int(a.x / FARM_CELL)
			var cy := int(a.y / FARM_CELL)
			for y in range(maxi(0, cy - rc), mini(farm_h, cy + rc + 1)):
				for x in range(maxi(0, cx - rc), mini(farm_w, cx + rc + 1)):
					var q := Vector2((x + 0.5) * FARM_CELL, (y + 0.5) * FARM_CELL)
					var d := q.distance_to(Geometry2D.get_closest_point_to_segment(q, a, b))
					if d > rr:
						continue
					var i := y * farm_w + x
					var v := strength * pow(1.0 - d / rr, 0.7)
					if v > f[i]:
						f[i] = v
					if v > best[i] * 1.3:
						best[i] = v
						ang[i] = along
	farm_d = PackedByteArray()
	farm_d.resize(n * 4)
	for y in farm_h:
		for x in farm_w:
			var i := y * farm_w + x
			var v := f[i] * (0.82 + 0.36 * (nz.get_noise_2d(x, y) * 0.5 + 0.5))   # postrzępiony zasięg upraw
			farm_d[i * 4] = clampi(int(v * 255.0), 0, 255)
			farm_d[i * 4 + 1] = int(fposmod(ang[i], TAU) / TAU * 255.0)
			farm_d[i * 4 + 2] = core[i]
			farm_d[i * 4 + 3] = 255


func farm_at(p: Vector2) -> float:
	## Natężenie upraw 0..1 w punkcie (tylko wygląd).
	if farm_d.is_empty():
		return 0.0
	var x := clampi(int(p.x / FARM_CELL), 0, farm_w - 1)
	var y := clampi(int(p.y / FARM_CELL), 0, farm_h - 1)
	return farm_d[(y * farm_w + x) * 4] / 255.0


func _shape_forests(copse: PackedByteArray) -> void:
	## Lasy ustępują polom wokół osad; w otwartym terenie małe zagajniki, w głębi lasów polany.
	var thr := forest_t * 255.0
	var copse_t := int(layout.get("copse", 200))
	for y in h:
		var fy := clampi(int((y + 0.5) * CELL / FARM_CELL), 0, farm_h - 1)
		for x in w:
			var fx := clampi(int((x + 0.5) * CELL / FARM_CELL), 0, farm_w - 1)
			var fv := farm_d[(fy * farm_w + fx) * 4] / 255.0
			var i := y * w + x
			var v := float(forest_d[i]) - fv * 22.0
			var c := copse[i]
			if c > copse_t and fv < 0.9:
				v = maxf(v, thr + (c - copse_t) * 0.5 + 2.0)    # zagajnik
			elif c < 38 and v > thr + 6.0:
				v = thr - 6.0                                   # polana w lesie
			forest_d[i] = clampi(int(v), 0, 255)


const _M32 := 0xFFFFFFFF


static func _pcg(x: int, y: int) -> Vector2:
	## Haszowanie całkowitoliczbowe (pcg2d) - identyczne z pcg2d() w terrain.gdshader.
	x = (x * 1664525 + 1013904223) & _M32
	y = (y * 1664525 + 1013904223) & _M32
	x = (x + y * 1664525) & _M32
	y = (y + x * 1664525) & _M32
	x = x ^ (x >> 16)
	y = y ^ (y >> 16)
	x = (x + y * 1664525) & _M32
	y = (y + x * 1664525) & _M32
	x = x ^ (x >> 16)
	y = y ^ (y >> 16)
	return Vector2(x / 4294967296.0, y / 4294967296.0)


func _hcell(c: Vector2i, salt: int) -> Vector2:
	return _pcg(c.x + field_seed, c.y + salt)


func _fwarp(p: Vector2) -> Vector2:
	## Zawirowanie granic pól (jak fwarp() w shaderze).
	return Vector2(sin(p.y * 0.0041 + warp_ph.x) * 40.0 + sin(p.x * 0.0107 + warp_ph.y) * 14.0,
		sin(p.x * 0.0037 + warp_ph.z) * 40.0 + sin(p.y * 0.0113 + warp_ph.w) * 14.0)


func _unwarp(q: Vector2) -> Vector2:
	var p := q
	for k in 4:
		p = q - _fwarp(p)
	return p


func _fseed(c: Vector2i) -> Vector2:
	## Środek komórki działek c (indeks z przesunięciem +1000), w przestrzeni zawirowanej.
	if _fseed_cache.has(c):
		return _fseed_cache[c]
	var o := _hcell(c, 0) * 0.9 + Vector2(0.05, 0.05)
	var s := (Vector2(c - Vector2i(1000, 1000)) + o) * FIELD_CELL
	_fseed_cache[c] = s
	return s


func _fkind(c: Vector2i) -> int:
	## 0 = dzika łąka, 1 = ogrodzone pastwisko/łąka kośna, 2 = pole uprawne (zagony). Jak w shaderze.
	var s := _fseed(c)
	var x := clampi(int(floor(s.x / FARM_CELL)), 0, farm_w - 1)
	var y := clampi(int(floor(s.y / FARM_CELL)), 0, farm_h - 1)
	var fv := farm_d[(y * farm_w + x) * 4] / 255.0
	var hy := _hcell(c, 1).y
	if hy <= fv * 1.15 - 0.14:
		return 2
	if hy <= fv * 1.3 + 0.03:
		return 1
	return 0


func _nearest2(q: Vector2) -> Array:
	var n := Vector2i(floori(q.x / FIELD_CELL), floori(q.y / FIELD_CELL)) + Vector2i(1000, 1000)
	var d0 := INF
	var d1 := INF
	var c0 := n
	var c1 := n
	for j in 3:
		for i in 3:
			var c := n + Vector2i(i - 1, j - 1)
			var d := q.distance_squared_to(_fseed(c))
			if d < d0:
				d1 = d0
				c1 = c0
				d0 = d
				c0 = c
			elif d < d1:
				d1 = d
				c1 = c
	return [c0, c1]


func _apply_palette(mat: ShaderMaterial) -> void:
	var g: Array = tv("grass")
	_sp(mat, "grass_dark", g[0])
	_sp(mat, "grass_light", g[1])
	_sp(mat, "grass_dry", tv("dry"))
	_sp(mat, "grass_wet", tv("wet"))
	_sp(mat, "heath_c", tv("heath"))
	_sp(mat, "flowers", tv("flowers"))
	var fl: Array = tv("flower")
	_sp(mat, "flower_a", fl[0])
	_sp(mat, "flower_b", fl[1])
	var cr: Array = tv("crops")
	_sp(mat, "crop_wheat", cr[0])
	_sp(mat, "crop_plough", cr[1])
	_sp(mat, "crop_veg", cr[2])
	_sp(mat, "crop_hay", cr[3])
	_sp(mat, "crop_pasture", cr[4])
	var cw: Array = tv("crop_w")
	var acc := 0.0
	var cum := Vector4.ZERO
	for k in 4:
		acc += float(cw[k])
		cum[k] = acc
	_sp(mat, "crop_cum", cum)
	_sp(mat, "hedge_c", tv("hedge"))
	var fo: Array = tv("floor")
	_sp(mat, "floor_a", fo[0])
	_sp(mat, "floor_b", fo[1])
	var wa: Array = tv("water")
	_sp(mat, "water_a", wa[0])
	_sp(mat, "water_b", wa[1])
	_sp(mat, "water_c", wa[2])
	var ro: Array = tv("road")
	_sp(mat, "road_a", ro[0])
	_sp(mat, "road_b", ro[1])
	_sp(mat, "sand_c", tv("sand"))
	_sp(mat, "snow", tv("snow"))
	_sp(mat, "desert", tv("desert"))
	_sp(mat, "mud", tv("mud"))
	_sp(mat, "grade", tv("grade"))
	_sp(mat, "sat", tv("sat"))


func _sp(mat: ShaderMaterial, pname: String, v: Variant) -> void:
	## Kolory motywu idą do shadera jako vec3 (bez konwersji sRGB).
	if v is Color:
		var c: Color = v
		mat.set_shader_parameter(pname, Vector3(c.r, c.g, c.b))
	else:
		mat.set_shader_parameter(pname, v)


# ------------------------------------------------------------------ rzeki

func _mask_image(shapes: Array, wobble: float) -> PackedByteArray:
	## Maska 0..255 w rozdzielczości map szumu: suma "kapsuł" [a, b, promień] (punkty w ułamkach mapy,
	## promień w ułamku wysokości) o postrzępionym, naturalnym brzegu. Liczona na rzadkiej siatce i wygładzana.
	var mw := maxi(8, w / 6)
	var mh := maxi(8, h / 6)
	var img := Image.create(mw, mh, false, Image.FORMAT_L8)
	var nz := FastNoiseLite.new()
	nz.seed = randi()
	nz.frequency = 0.0011
	nz.fractal_octaves = 3
	for y in mh:
		for x in mw:
			var p := Vector2((x + 0.5) / mw * map_size.x, (y + 0.5) / mh * map_size.y)
			var best := 0.0
			for s in shapes:
				var a: Vector2 = s[0] * map_size
				var b: Vector2 = s[1] * map_size
				var r: float = float(s[2]) * map_size.y
				var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
				d += nz.get_noise_2d(p.x, p.y) * r * wobble
				best = maxf(best, 1.0 - smoothstep(r * 0.55, r, d))
			img.set_pixel(x, y, Color(best, best, best))
	img.resize(w, h, Image.INTERPOLATE_CUBIC)
	return img.get_data()


func _apply_layout() -> void:
	## Układ pola bitwy: góry zebrane w zwarte pasma/masywy (zamiast skałek rozsianych po całej mapie),
	## opcjonalnie wielki las na skrzydle. Armie stoją na osi wschód-zachód, więc "skrzydła" to północ i południe.
	var relief: String = layout.get("relief", "none")
	var shapes: Array = []
	var top := randf() < 0.5
	match relief:
		"flank":
			var y := -0.02 if top else 1.02
			shapes.append([Vector2(-0.1, y), Vector2(1.1, y), 0.44])
			shapes.append([Vector2(randf_range(0.3, 0.7), y), Vector2(randf_range(0.3, 0.7), 0.16 if top else 0.84), 0.13])
		"pass":
			shapes.append([Vector2(-0.1, -0.03), Vector2(1.1, -0.03), randf_range(0.36, 0.44)])
			shapes.append([Vector2(-0.1, 1.03), Vector2(1.1, 1.03), randf_range(0.36, 0.44)])
		"massif":
			# dwa-trzy masywy: na skrzydłach, nigdy na osi między armiami
			var xs := [randf_range(0.22, 0.42), randf_range(0.58, 0.78), randf_range(0.4, 0.6)]
			var n := 2 + (randi() % 2)
			for k in n:
				var up := (k % 2 == 0) == top
				var c := Vector2(xs[k], randf_range(0.1, 0.2) if up else randf_range(0.8, 0.9))
				var ax := Vector2.from_angle(randf_range(-0.5, 0.5)) * randf_range(0.08, 0.16)
				shapes.append([c - ax, c + ax, randf_range(0.15, 0.2)])
		"corner":
			var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]
			corners.shuffle()
			for k in 2:
				shapes.append([corners[k], corners[k].lerp(Vector2(0.5, corners[k].y), 0.35), randf_range(0.16, 0.22)])
	if shapes.is_empty():
		mount_d.fill(0)
	else:
		var mask := _mask_image(shapes, 0.55)
		for i in w * h:
			# w głębi pasma lita skała z dolinkami, na brzegu postrzępione ostrogi; poza pasmem - nic
			var m := mask[i] / 255.0
			mount_d[i] = clampi(int(m * (190.0 + 65.0 * (mount_d[i] / 255.0))), 0, 255)
	var woods: String = layout.get("woods", "noise")
	if woods == "flank":
		var wy := 1.02 if top else -0.02   # po przeciwnej stronie niż ewentualne góry
		var wmask := _mask_image([[Vector2(-0.1, wy), Vector2(1.1, wy), 0.46]], 0.5)
		for i in w * h:
			var m2 := wmask[i] / 255.0
			forest_d[i] = clampi(int(forest_d[i] + m2 * 120.0 - 10.0), 0, 255)


func _open_centre() -> void:
	## Środek mapy - tam, gdzie staną i zetrą się armie - to czyste pole: bez jezior, bagien i skał,
	## z lasem najwyżej na obrzeżach. Rzeka (jeśli mapa ją ma) zostaje.
	var k: float = layout.get("open", 0.0)
	if k <= 0.0:
		return
	var r := map_size.y * k
	var mid := map_size * 0.5
	for dx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		_clear_area(mid + Vector2(dx * minf(1700.0, map_size.x * 0.2), 0.0), r, true, true, true, true)


func _make_rivers() -> void:
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.frequency = 0.0007
	n.fractal_octaves = 3
	for fx in river_xs:
		var x0: float = map_size.x * fx
		var pts := PackedVector2Array()
		var y := -100.0
		var off := randf() * 10000.0
		while y < map_size.y + 100.0:
			pts.append(Vector2(x0 + n.get_noise_1d(y + off) * 1300.0 * minf(1.0, map_size.x / 12000.0), y))
			y += 60.0
		rivers.append([pts, randf_range(55.0, 80.0)])


func river_distance(p: Vector2) -> float:
	var best := INF
	for r in rivers:
		var pts: PackedVector2Array = r[0]
		for i in pts.size() - 1:
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])))
	return best


# ------------------------------------------------------------------ osady

func _site_ok(p: Vector2, min_river := 280.0) -> bool:
	if p.x < 400 or p.y < 400 or p.x > map_size.x - 400 or p.y > map_size.y - 400:
		return false
	if _lake_byte(p) > LAKE_T * 255.0 - 25.0:
		return false
	var ci := _ci(p)
	if mount_d[ci] > MOUNT_T * 255.0 - 30.0 or swamp_d[ci] > swamp_t * 255.0:
		return false
	return river_distance(p) > min_river


func _ci(p: Vector2) -> int:
	return clampi(int(p.y / CELL), 0, h - 1) * w + clampi(int(p.x / CELL), 0, w - 1)


func _clear_mountains_along_rivers() -> void:
	# Rzeki płyną dolinami - bez skał nad samą wodą.
	for r in rivers:
		var pts: PackedVector2Array = r[0]
		for k in range(0, pts.size(), 2):
			_clear_area(pts[k], 260.0, false, false, true, false)


func _make_ravines() -> void:
	## Kilka krętych wąwozów z dala od osad.
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.frequency = 0.004
	var made := 0
	var tries := 0
	while made < ravine_count and tries < 60 + ravine_count * 8:
		tries += 1
		var p := Vector2(randf_range(800, map_size.x - 800), randf_range(800, map_size.y - 800))
		var ang := randf() * TAU
		var length := randf_range(1400.0, 2600.0)
		var pts := PackedVector2Array()
		var ok := true
		var walked := 0.0
		while walked < length:
			for s in sites:
				if (s[0] as Vector2).distance_to(p) < (650.0 if s[1] else 420.0):
					ok = false
			if not ok:
				break
			pts.append(p)
			ang += n.get_noise_2d(p.x, p.y) * 0.5
			p += Vector2.from_angle(ang) * 50.0
			walked += 50.0
		if ok and pts.size() > 10:
			ravines.append([pts, randf_range(40.0, 60.0)])
			made += 1


func _fix_site(p: Vector2) -> Vector2:
	# Przesuwa miejsce osady, aż przestanie wypadać w wodzie / przy rzece.
	if _site_ok(p):
		return p
	for radius in [200.0, 400.0, 600.0, 900.0, 1200.0]:
		for k in 12:
			var q: Vector2 = p + Vector2.from_angle(k * TAU / 12.0) * radius
			if _site_ok(q):
				return q
	return p


func _place_sites() -> void:
	var cy := map_size.y * 0.5
	var edge := minf(1300.0, map_size.x * 0.12)
	var cities := [Vector2(edge, cy), Vector2(map_size.x - edge, cy)]
	if map_size.x >= 16000.0:
		# ogromna mapa: 4 dodatkowe miasta
		for fx in [0.36, 0.64]:
			for fy in [0.22, 0.78]:
				cities.append(Vector2(map_size.x * fx, map_size.y * fy))
	else:
		cities.append(Vector2(map_size.x * 0.5, map_size.y * 0.22))
		cities.append(Vector2(map_size.x * 0.5, map_size.y * 0.78))
	var names := CITY_NAMES.duplicate()
	for c in cities:
		sites.append([_fix_site(c), true, names.pop_front()])
	var vnames := VILLAGE_NAMES.duplicate()
	vnames.shuffle()
	var cols := maxi(3, roundi(7.0 * map_size.x / 12000.0))
	var rows := maxi(2, roundi(4.0 * map_size.y / 8000.0))
	for gy in rows:
		for gx in cols:
			var p := Vector2((gx + 0.5) / cols * map_size.x, (gy + 0.5) / rows * map_size.y)
			p += Vector2(randf_range(-500, 500), randf_range(-450, 450))
			p = _fix_site(p)
			var ok := _site_ok(p, 200.0)
			for s in sites:
				var min_d := 1100.0 if s[1] else 850.0
				if (s[0] as Vector2).distance_to(p) < min_d:
					ok = false
			if ok:
				if vnames.is_empty():
					vnames.append("%s %s" % [NAME_PREFIX.pick_random(), VILLAGE_NAMES.pick_random()])
				sites.append([p, false, vnames.pop_front()])


# ------------------------------------------------------------------ drogi

func _make_roads() -> void:
	var done := {}
	for i in sites.size():
		var a: Vector2 = sites[i][0]
		var order: Array = range(sites.size())
		order.sort_custom(func(x: int, y: int) -> bool:
			return a.distance_to(sites[x][0]) < a.distance_to(sites[y][0]))
		var links := 0
		for j in order:
			if j == i:
				continue
			var key := "%d-%d" % [mini(i, j), maxi(i, j)]
			if not done.has(key):
				var b: Vector2 = sites[j][0]
				if a.distance_to(b) < 3200.0 or links == 0:
					done[key] = true
					roads.append(_road_avoid_lakes(_road_curve(a, b)))
			links += 1
			if links >= 3:
				break
	# Mosty: tam, gdzie droga przecina rzekę.
	for road in roads:
		var rp: PackedVector2Array = road
		for k in rp.size() - 1:
			for ri in rivers.size():
				var r: Array = rivers[ri]
				var pts: PackedVector2Array = r[0]
				for m in pts.size() - 1:
					var hit = Geometry2D.segment_intersects_segment(rp[k], rp[k + 1], pts[m], pts[m + 1])
					if hit != null:
						bridges.append([hit, (rp[k + 1] - rp[k]).angle(), float(r[1]), ri])


func _lake_wet(p: Vector2) -> bool:
	## Woda stojąca razem z wąskim pasem brzegu (droga trzyma się od niej z daleka).
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_size.x or p.y >= map_size.y:
		return false
	return lake_d[_ci(p)] > int(LAKE_T * 255.0) - 12


func _road_avoid_lakes(pts: PackedVector2Array) -> PackedVector2Array:
	## Droga nie idzie groblą przez jezioro: odcinek, który wpada w wodę, jest odginany na ten brzeg, do którego
	## jest bliżej, i prowadzony łukiem dookoła. Potem całość jest wygładzana, żeby objazd nie miał załamań.
	var n := pts.size()
	if n < 4:
		return pts
	for pass_i in 4:
		var changed := false
		var i := 1
		while i < n - 1:
			if not _lake_wet(pts[i]):
				i += 1
				continue
			var j := i
			while j < n - 1 and _lake_wet(pts[j]):
				j += 1
			# zamoczony odcinek to punkty i..j-1; objazd zaczyna się i kończy kilka punktów wcześniej / dalej
			var i0 := maxi(1, i - 3)
			var j0 := mini(n - 2, j + 2)
			var chord := pts[j0 + 1] - pts[i0 - 1]
			if chord.length() < 1.0:
				i = j
				continue
			var nrm := chord.normalized().orthogonal()
			var side := 0.0
			var need := 0.0
			var off := 40.0
			while off < 1800.0 and side == 0.0:
				for sgn in [1.0, -1.0]:
					var ok := true
					for k in range(i, j):
						var q: Vector2 = pts[k] + nrm * sgn * off
						if q.x < 60.0 or q.y < 60.0 or q.x > map_size.x - 60.0 or q.y > map_size.y - 60.0 or _lake_wet(q):
							ok = false
							break
					if ok:
						side = sgn
						need = off + 45.0
						break
				off += 40.0
			if side != 0.0:
				for k in range(i0, j0 + 1):
					var t := float(k - i0 + 1) / float(j0 - i0 + 2)
					var bell := pow(sin(t * PI), 0.55) if (k < i or k >= j) else 1.0
					pts[k] += nrm * side * need * bell
				changed = true
			i = j
		# wygładzenie objazdu (końce drogi zostają w osadach)
		for sm in 3:
			var prev := pts[0]
			for k in range(1, n - 1):
				var cur := pts[k]
				var cand := cur * 0.5 + (prev + pts[k + 1]) * 0.25
				if not _lake_wet(cand):
					pts[k] = cand
				prev = cur
		if not changed:
			break
	return pts


func _road_curve(a: Vector2, b: Vector2) -> PackedVector2Array:
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * randf_range(-0.18, 0.18) * a.distance_to(b)
	var pts := PackedVector2Array()
	var steps := maxi(8, int(a.distance_to(b) / 55.0))
	for s in steps + 1:
		var t := float(s) / steps
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return pts


# ------------------------------------------------------------------ brody i przeprawy

func _make_fords() -> void:
	## Przeprawy: płycizna wokół każdego mostu. Rzeka bez mostu dostaje dwa naturalne brody,
	## żeby żadnego brzegu nie dało się całkiem odciąć.
	fords.clear()
	for b in bridges:
		fords.append([b[0], int(b[3]), true])
	for ri in rivers.size():
		var has := false
		for f in fords:
			if f[1] == ri:
				has = true
				break
		if has:
			continue
		var pts: PackedVector2Array = rivers[ri][0]
		for fy in [0.3, 0.7]:
			var want: float = map_size.y * fy
			var best := pts[0]
			for p in pts:
				if absf(p.y - want) < absf(best.y - want):
					best = p
			fords.append([best, ri, false])


func _build_ford_map() -> void:
	ford_d = PackedByteArray()
	ford_d.resize(fw * fh)
	var rc := int(FORD_R / FEAT)
	for f in fords:
		var p: Vector2 = f[0]
		var cx := int(p.x / FEAT)
		var cy := int(p.y / FEAT)
		for y in range(maxi(0, cy - rc), mini(fh, cy + rc + 1)):
			for x in range(maxi(0, cx - rc), mini(fw, cx + rc + 1)):
				if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rc * rc:
					ford_d[y * fw + x] = 255


func _river_hits(a: Vector2, b: Vector2) -> Array:
	## Wszystkie przecięcia odcinka a→b z rzekami, posortowane od a: [[odległość, punkt, indeks rzeki], ...].
	var out: Array = []
	for ri in rivers.size():
		var pts: PackedVector2Array = rivers[ri][0]
		for m in pts.size() - 1:
			var hit = Geometry2D.segment_intersects_segment(a, b, pts[m], pts[m + 1])
			if hit != null:
				out.append([a.distance_to(hit), hit, ri])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return out


func _ford_dist(p: Vector2, ri: int) -> float:
	var best := INF
	for f in fords:
		if f[1] == ri:
			best = minf(best, p.distance_to(f[0]))
	return best


func crossing_route(a: Vector2, b: Vector2, half_w := 40.0, depth := 0, wade := false) -> Dictionary:
	## Trasa w liniach prostych. Rzekę wolno przejść tylko w brodzie przy moście: jeśli prosta linia
	## przecina głęboki nurt, trasa skręca na najlepszą przeprawę tej rzeki (most albo bród) i dalej znów prosto.
	## Zwraca {"points": [..., b], "bridge": bool} - bridge = idziemy wąsko przez most.
	if depth > 6:
		return {"points": [b], "bridge": false}
	for h in _river_hits(a, b):
		var ri: int = h[2]
		var hp: Vector2 = h[1]
		# szeroki szyk musi zmieścić się w płyciźnie - inaczej skrzydła wejdą w głęboki nurt
		if _ford_dist(hp, ri) + half_w * 0.8 < FORD_R:
			continue
		var best: Array = []
		var bd := INF
		for f in fords:
			if f[1] != ri:
				continue
			var fp: Vector2 = f[0]
			var cost := a.distance_to(fp) + fp.distance_to(b)
			if cost < bd:
				bd = cost
				best = f
		# piechota i jazda idą tam, gdzie kazano - prosto, wpław przez rzekę (wolno). Kto chce mostem,
		# ten sam wskazuje most. Tylko działa muszą jechać na przeprawę.
		if wade:
			continue
		if best.is_empty():
			return {"points": [b], "bridge": false}
		var fp: Vector2 = best[0]
		var entry := fp
		var exit := fp
		var narrow := false
		if best[2]:
			# most: wejście i zejście na osi mostu, po właściwej stronie
			for br in bridges:
				if (br[0] as Vector2).distance_to(fp) < 1.0:
					var dir := Vector2.from_angle(br[1])
					var half: float = float(br[2]) * 0.5 + 90.0
					entry = fp - dir * half
					exit = fp + dir * half
					if (a - fp).dot(dir) > 0.0:
						var tmp := entry
						entry = exit
						exit = tmp
					break
			narrow = half_w > 40.0
		else:
			# naturalny bród: przejście w poprzek nurtu przez jego środek
			var pts: PackedVector2Array = rivers[ri][0]
			var tan := Vector2.DOWN
			for m in pts.size() - 1:
				if pts[m].distance_to(fp) < 1.0:
					tan = (pts[m + 1] - pts[m]).normalized()
					break
			var across := tan.orthogonal()
			var half2: float = float(rivers[ri][1]) * 0.5 + 80.0
			entry = fp - across * half2
			exit = fp + across * half2
			if (a - fp).dot(across) > 0.0:
				var tmp2 := entry
				entry = exit
				exit = tmp2
		var first := crossing_route(a, entry, half_w, depth + 1, wade)
		var rest := crossing_route(exit, b, half_w, depth + 1, wade)
		var points: Array = first["points"].duplicate()
		points.append(exit)
		points.append_array(rest["points"])
		return {"points": points, "bridge": narrow or first["bridge"] or rest["bridge"]}
	return {"points": [b], "bridge": false}


func is_deep_fast(p: Vector2) -> bool:
	## Głęboki nurt rzeki (poza brodem i mostem) - nie do przejścia.
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_size.x or p.y >= map_size.y:
		return false
	var fx := int(p.x / FEAT)
	var fy := int(p.y / FEAT)
	var fi := fy * fw + fx
	if feat_d[fi * 4 + 1] > 127 or feat_d[fi * 4] <= 127:
		return false
	return ford_d.is_empty() or ford_d[fi] == 0


func is_blocked_fast(p: Vector2) -> bool:
	## Przeszkoda dla żołnierza: góry albo głęboka rzeka.
	return is_mountain_fast(p) or is_deep_fast(p)


func bank_point(p: Vector2) -> Vector2:
	## Cel kliknięty w głębokim nurcie → najbliższy suchy brzeg.
	if not is_deep_fast(p):
		return p
	for rad in range(16, 400, 16):
		for k in 16:
			var q := p + Vector2.from_angle(k * TAU / 16.0) * rad
			if not is_deep_fast(q) and cell_at(q) != WATER:
				return q
	return p


# ------------------------------------------------------------------ rasteryzacja

func _rasterize_features() -> void:
	var img := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var bank := Color(0, 0, 1, 1)
	var water := Color(1, 0, 1, 1)
	var road := Color(0, 1, 0, 1)
	for r in rivers:
		var pts: PackedVector2Array = r[0]
		var width: float = r[1]
		_stamp_line(img, pts, width + 50.0, bank, 1.0)
	for r in rivers:
		var pts: PackedVector2Array = r[0]
		var width: float = r[1]
		_stamp_line(img, pts, width, water, 0.85)
	for rd in roads:
		_stamp_line(img, rd, ROAD_WIDTH, road, 1.0)
	for b in bridges:
		# Szeroki most, by oddział mógł przejść (wąską kolumną - sucho, szerokim szykiem część wejdzie do wody).
		var dir := Vector2.from_angle(b[1])
		var length: float = float(b[2]) + 60.0
		var pts := PackedVector2Array([b[0] - dir * length * 0.5, b[0] + dir * length * 0.5])
		_stamp_line(img, pts, 70.0, road, 1.0)
	feat_d = img.get_data()
	# wąwozy w osobnej mapie
	var rimg := Image.create(fw, fh, false, Image.FORMAT_L8)
	rimg.fill(Color(0, 0, 0))
	for rv in ravines:
		_stamp_line(rimg, rv[0], rv[1], Color(0.5, 0.5, 0.5), 1.0)
		_stamp_line(rimg, rv[0], float(rv[1]) * 0.55, Color(1, 1, 1), 0.8)
	ravine_d = rimg.get_data()


func _stamp_line(img: Image, pts: PackedVector2Array, width: float, col: Color, wobble: float) -> void:
	var s := maxi(1, int(width / FEAT))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / (FEAT * 1.5)))
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			var ss := int(s * lerpf(wobble, 1.0, randf()))
			img.fill_rect(Rect2i(int(p.x / FEAT) - ss / 2, int(p.y / FEAT) - ss / 2, maxi(ss, 1), maxi(ss, 1)), col)


func _clear_around_sites_and_roads() -> void:
	for s in sites:
		var p: Vector2 = s[0]
		var r := 520.0 if s[1] else 330.0
		_clear_area(p, r, true, true, true, true)
	for rd in roads:
		var rp: PackedVector2Array = rd
		for k in range(0, rp.size(), 1):
			_clear_area(rp[k], 70.0, false, true, false, false)
			_clear_area(rp[k], 170.0, false, false, true, false)  # przełęcz w górach


func _stamp_woods(fnoise: FastNoiseLite) -> void:
	## Dodatkowe lasy zamówione z zewnątrz (np. przez ujęcie filmowe): owalny las z postrzępionym brzegiem.
	for wd in extra_woods:
		var c: Vector2 = wd[0]
		var r: Vector2 = wd[1]
		for y in range(maxi(0, int((c.y - r.y * 1.4) / CELL)), mini(h, int((c.y + r.y * 1.4) / CELL) + 1)):
			for x in range(maxi(0, int((c.x - r.x * 1.4) / CELL)), mini(w, int((c.x + r.x * 1.4) / CELL) + 1)):
				var q := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
				var d := ((q - c) / r).length() + fnoise.get_noise_2d(x * 1.7, y * 1.7) * 0.3
				if d >= 1.0:
					continue
				var i := y * w + x
				forest_d[i] = maxi(forest_d[i], int(lerpf(240.0, forest_t * 255.0 + 14.0, d * d)))
				lake_d[i] = mini(lake_d[i], int(LAKE_T * 255.0 - 20.0))
				swamp_d[i] = mini(swamp_d[i], int(swamp_t * 255.0 - 20.0))


func _clear_area(p: Vector2, radius: float, forest: bool, lake: bool, mount := false, swamp := false) -> void:
	var cr := int(radius / CELL)
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	for y in range(maxi(0, cy - cr), mini(h, cy + cr + 1)):
		for x in range(maxi(0, cx - cr), mini(w, cx + cr + 1)):
			var d := Vector2(x - cx, y - cy).length() / cr
			if d > 1.0:
				continue
			var i := y * w + x
			if forest:
				forest_d[i] = mini(forest_d[i], int(lerpf(110.0, forest_t * 255.0 + 10.0, d * d)))
			if lake:
				lake_d[i] = mini(lake_d[i], int(lerpf(150.0, LAKE_T * 255.0 + 5.0, d * d)))
			if mount:
				mount_d[i] = mini(mount_d[i], int(lerpf(MOUNT_T * 255.0 - 40.0, MOUNT_T * 255.0 + 8.0, d * d)))
			if swamp:
				swamp_d[i] = mini(swamp_d[i], int(lerpf(120.0, swamp_t * 255.0 + 5.0, d * d)))


# ------------------------------------------------------------------ trasy (mosty, omijanie jezior)

const MGRID := 60.0
var _mgrid: AStarGrid2D


func _build_mountain_grid() -> void:
	## Siatka do omijania gór: komórka zablokowana, gdy jest górą (z marginesem jednej komórki poza drogami).
	_mgrid = AStarGrid2D.new()
	var gw := ceili(map_size.x / MGRID)
	var gh := ceili(map_size.y / MGRID)
	_mgrid.region = Rect2i(0, 0, gw, gh)
	_mgrid.cell_size = Vector2(MGRID, MGRID)
	_mgrid.offset = Vector2(MGRID, MGRID) * 0.5
	_mgrid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_mgrid.update()
	var solid := PackedByteArray()
	solid.resize(gw * gh)
	for y in gh:
		for x in gw:
			var c := Vector2((x + 0.5) * MGRID, (y + 0.5) * MGRID)
			if _impassable(c) or _impassable(c + Vector2(-20, -20)) or _impassable(c + Vector2(20, 20)) \
					or _impassable(c + Vector2(20, -20)) or _impassable(c + Vector2(-20, 20)):
				solid[y * gw + x] = 1
	for y in gh:
		for x in gw:
			if solid[y * gw + x] == 1:
				_mgrid.set_point_solid(Vector2i(x, y))
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx := x + dx
						var ny := y + dy
						if nx >= 0 and ny >= 0 and nx < gw and ny < gh and solid[ny * gw + nx] == 0:
							if cell_at(Vector2((nx + 0.5) * MGRID, (ny + 0.5) * MGRID)) != ROAD:
								_mgrid.set_point_solid(Vector2i(nx, ny))


func _impassable(p: Vector2) -> bool:
	## Góry i woda (rzeki, jeziora). Mosty i drogi przez przełęcze są przejezdne (cell_at zwraca dla nich ROAD).
	var c := cell_at(p)
	return c == MOUNTAIN or c == WATER


func _blocked(a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / 15.0))
	for k in range(1, n + 1):
		if _impassable(a.lerp(b, float(k) / n)):
			return true
	return false


func _free_cell(p: Vector2) -> Vector2i:
	var r := _mgrid.region
	var c := Vector2i(clampi(int(p.x / MGRID), 0, r.size.x - 1), clampi(int(p.y / MGRID), 0, r.size.y - 1))
	if not _mgrid.is_point_solid(c):
		return c
	for rad in range(1, 12):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if absi(dx) != rad and absi(dy) != rad:
					continue
				var q := c + Vector2i(dx, dy)
				if r.has_point(q) and not _mgrid.is_point_solid(q):
					return q
	return c


func free_point(p: Vector2) -> Vector2:
	## Najbliższy punkt poza górami (cel kliknięty w górach → podnóże).
	if _mgrid == null or not _impassable(p):
		return p
	return Vector2(_free_cell(p)) * MGRID + Vector2(MGRID, MGRID) * 0.5


func _grid_path(a: Vector2, b: Vector2) -> Array:
	## Punkty pośrednie omijające góry (A* po siatce + wygładzenie "po linii wzroku").
	var path := _mgrid.get_point_path(_free_cell(a), _free_cell(b), true)
	if path.size() < 2:
		return []
	var out: Array = []
	var anchor := a
	var k := 0
	while k < path.size() - 1:
		var far := k + 1
		for m in range(path.size() - 1, k, -1):
			if not _blocked(anchor, path[m]):
				far = m
				break
		anchor = path[far]
		out.append(anchor)
		k = far
		if not _blocked(anchor, b):
			break
	return out


func route(a: Vector2, b: Vector2) -> Dictionary:
	## Trasa: mosty przez rzeki, obejście jezior, a na koniec ominięcie gór na każdym odcinku.
	b = free_point(b)
	var r := _route_raw(a, b)
	if _mgrid == null:
		return r
	var pts: Array = []
	var prev := a
	var narrow: bool = r["bridge"]
	for q in r["points"]:
		var qq: Vector2 = q
		if _blocked(prev, qq):
			pts.append_array(_grid_path(prev, qq))
			narrow = true   # obejście gór/wody: wąskie przejścia - idziemy wąską kolumną jak przez most
		pts.append(qq)
		prev = qq
	return {"points": pts, "bridge": narrow}


func _route_raw(a: Vector2, b: Vector2, depth := 0) -> Dictionary:
	## Zwraca {"points": [...punkty pośrednie..., b], "bridge": bool}. Rzeki przekracza po mostach, jeziora obchodzi.
	if depth > 4:
		return {"points": [b], "bridge": false}
	# 1) rzeka na drodze → najlepszy most na tej rzece
	for ri in rivers.size():
		var pts: PackedVector2Array = rivers[ri][0]
		var crosses := false
		for m in pts.size() - 1:
			if Geometry2D.segment_intersects_segment(a, b, pts[m], pts[m + 1]) != null:
				crosses = true
				break
		if not crosses:
			continue
		var best: Array = []
		var bd := INF
		for br in bridges:
			if br[3] != ri:
				continue
			var bp: Vector2 = br[0]
			var cost := a.distance_to(bp) + bp.distance_to(b)
			if cost < bd:
				bd = cost
				best = br
		if best.is_empty():
			break
		var dir := Vector2.from_angle(best[1])
		var half: float = float(best[2]) * 0.5 + 90.0
		var bp: Vector2 = best[0]
		var entry := bp - dir * half
		var exit := bp + dir * half
		if (a - bp).dot(dir) > 0.0:
			var tmp := entry
			entry = exit
			exit = tmp
		var first := _route_raw(a, entry, depth + 1)
		var rest := _route_raw(exit, b, depth + 1)
		var points: Array = first["points"].duplicate()
		points.append(exit)
		points.append_array(rest["points"])
		return {"points": points, "bridge": true}
	# 2) jezioro na drodze → obejście bokiem
	var blocked := _first_lake_on(a, b)
	if blocked != Vector2.INF:
		var dir := (b - a).normalized()
		var perp := dir.orthogonal()
		for off in [300.0, 600.0, 900.0, 1300.0, 1800.0, 2400.0, 3200.0]:
			for sgn in [1.0, -1.0]:
				var detour: Vector2 = blocked + perp * off * sgn
				if _lake_at(detour) or _first_lake_on(a, detour) != Vector2.INF or _first_lake_on(detour, b) != Vector2.INF:
					continue
				if detour.x < 50 or detour.y < 50 or detour.x > map_size.x - 50 or detour.y > map_size.y - 50:
					continue
				var r1 := _route_raw(a, detour, depth + 1)
				var r2 := _route_raw(detour, b, depth + 1)
				var points: Array = r1["points"].duplicate()
				points.append_array(r2["points"])
				return {"points": points, "bridge": r1["bridge"] or r2["bridge"]}
	return {"points": [b], "bridge": false}


func dry_spot(p: Vector2, clearance := 120.0) -> Vector2:
	## Najbliższe miejsce bez wody w promieniu `clearance` (żeby nie stawiać oddziałów w rzece/jeziorze).
	for radius in [0.0, 150.0, 300.0, 450.0, 650.0, 900.0, 1200.0]:
		for k in (1 if radius == 0.0 else 16):
			var q: Vector2 = p + Vector2.from_angle(k * TAU / 16.0) * radius
			var ok := true
			for j in 8:
				var c1 := cell_at(q + Vector2.from_angle(j * TAU / 8.0) * clearance)
				var c0 := cell_at(q)
				if c1 == WATER or c1 == MOUNTAIN or c0 == WATER or c0 == MOUNTAIN:
					ok = false
					break
			if ok and river_distance(q) > clearance + 40.0:
				return q
	return p


func _lake_at(p: Vector2) -> bool:
	## Przeszkoda dla tras: jezioro albo góry (rzeki obsługują mosty).
	var ci := _ci(p)
	return lake_d[ci] > LAKE_T * 255.0 or mount_d[ci] > MOUNT_T * 255.0 - 6.0


func is_blocked(p: Vector2) -> bool:
	return cell_at(p) == MOUNTAIN


func _first_lake_on(a: Vector2, b: Vector2) -> Vector2:
	var d := a.distance_to(b)
	var steps := int(d / 40.0)
	for k in range(1, steps):
		var p := a.lerp(b, float(k) / steps)
		if _lake_at(p):
			return p
	return Vector2.INF


# ------------------------------------------------------------------ zapytania

func _lake_byte(p: Vector2) -> int:
	var ix := clampi(int(p.x / CELL), 0, w - 1)
	var iy := clampi(int(p.y / CELL), 0, h - 1)
	return lake_d[iy * w + ix]


func cell_at(p: Vector2) -> int:
	var fx := int(p.x / FEAT)
	var fy := int(p.y / FEAT)
	if fx < 0 or fy < 0 or fx >= fw or fy >= fh:
		return GRASS
	var fi := (fy * fw + fx) * 4
	if feat_d[fi + 1] > 127:
		return ROAD
	if feat_d[fi] > 127:
		return FORD if not ford_d.is_empty() and ford_d[fy * fw + fx] != 0 else WATER
	var ci := int(p.y / CELL) * w + int(p.x / CELL)
	if lake_d[ci] > LAKE_T * 255.0:
		return WATER
	if mount_d[ci] > MOUNT_T * 255.0:
		return MOUNTAIN
	if ravine_d[fy * fw + fx] > 70:
		return RAVINE
	if swamp_d[ci] > swamp_t * 255.0:
		return SWAMP
	if forest_d[ci] > forest_t * 255.0:
		return FOREST
	return GRASS


func is_mountain_fast(p: Vector2) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_size.x or p.y >= map_size.y:
		return false
	var fx := int(p.x / FEAT)
	var fy := int(p.y / FEAT)
	if feat_d[(fy * fw + fx) * 4 + 1] > 127:
		return false  # droga przez przełęcz
	return mount_d[int(p.y / CELL) * w + int(p.x / CELL)] > MOUNT_T * 255.0


func mount_strength(p: Vector2) -> float:
	## Wysokość gór 0..1 w punkcie (do cieniowania zboczy na minimapie).
	var x := clampi(int(p.x / CELL), 0, w - 1)
	var y := clampi(int(p.y / CELL), 0, h - 1)
	return mount_d[y * w + x] / 255.0


func is_forest(p: Vector2) -> bool:
	return cell_at(p) == FOREST


func is_water(p: Vector2) -> bool:
	var c := cell_at(p)
	return c == WATER or c == FORD


static func mult_for(cell: int, kind: String, marching := false) -> float:
	match cell:
		FOREST:
			return 0.45 if kind != "inf" else 0.6
		WATER:
			return 0.25 if kind == "art" else 0.35
		ROAD:
			return 1.0   # droga = pole: ruch wojsk taki sam niezależnie od podłoża
		MOUNTAIN:
			return 0.0
		RAVINE:
			return 0.3 if kind == "art" else (0.4 if kind == "cav" else 0.5)
		SWAMP:
			return 0.25 if kind == "art" else (0.35 if kind == "cav" else 0.45)
		FORD:
			return 0.3 if kind == "art" else (0.55 if kind == "cav" else 0.45)
	return 1.0


static func cell_name(cell: int) -> String:
	return ["Open field", "Forest", "Water", "Road", "Mountains", "Ravine", "Swamp", "Ford"][cell]


# ------------------------------------------------------------------ sieć dróg (tryb marszowy)

var _road_graph: AStar2D


func _build_road_graph() -> void:
	_road_graph = AStar2D.new()
	var ids := {}
	var next_id := 0
	for rd in roads:
		var rp: PackedVector2Array = rd
		var prev := -1
		for p in rp:
			var key := Vector2i(roundi(p.x / 12.0), roundi(p.y / 12.0))
			var id: int
			if ids.has(key):
				id = ids[key]
			else:
				id = next_id
				next_id += 1
				ids[key] = id
				_road_graph.add_point(id, p)
			if prev >= 0 and prev != id:
				_road_graph.connect_points(prev, id)
			prev = id


func road_route(a: Vector2, b: Vector2) -> Dictionary:
	## Trasa po drogach: dojście do najbliższej drogi, marsz siecią dróg, zejście do celu.
	if _road_graph == null or _road_graph.get_point_count() == 0:
		return route(a, b)
	var s := _road_graph.get_closest_point(a)
	var e := _road_graph.get_closest_point(b)
	var path := _road_graph.get_point_path(s, e)
	if path.is_empty():
		return route(a, b)
	var first := route(a, path[0])
	var pts: Array = first["points"].duplicate()
	for k in range(1, path.size()):
		pts.append(path[k])
	var last := route(path[path.size() - 1], b)
	pts.append_array(last["points"])
	return {"points": pts, "bridge": first["bridge"] or last["bridge"]}


func path_time(start: Vector2, pts: Array, kind: String, marching: bool) -> float:
	## Szacowany czas przejścia łamanej (w jednostkach "sekundy przy prędkości 1"): długość / mnożnik terenu,
	## próbkowane co 40 px. Góry liczone jako prawie nieprzejezdne.
	var t := 0.0
	var prev := start
	for q in pts:
		var b: Vector2 = q
		var seg := prev.distance_to(b)
		var n := maxi(1, ceili(seg / 40.0))
		var step := seg / n
		for k in n:
			var m := mult_for(cell_at(prev.lerp(b, (k + 0.5) / n)), kind, marching)
			t += step / maxf(m, 0.08)
		prev = b
	return t


func speed_mult(p: Vector2, kind := "inf") -> float:
	return mult_for(cell_at(p), kind)


# ------------------------------------------------------------------ drzewa

func _build_trees() -> void:
	## Drzewa: lasy (na komórkach FOREST) + wyłącznie ozdobne drzewa poza lasem: pojedyncze drzewa i krzaki
	## na skraju lasu, drzewa w żywopłotach między polami, aleje przy drogach, wierzby nad rzekami,
	## samotne drzewa i kępy na łąkach. Ozdobne drzewa stoją na komórkach GRASS i nie zmieniają logiki gry.
	var tex := _make_canopy_atlas()
	_tp = PackedVector2Array()
	_ts = PackedFloat32Array()
	_tv = PackedFloat32Array()
	_tc = PackedColorArray()
	_kinds_w = tv("trees")
	var step := 24.0
	var thr := forest_t * 255.0
	var y := 0.0
	while y < map_size.y:
		var x := 0.0
		while x < map_size.x:
			var p := Vector2(x + randf() * step, y + randf() * step)
			var c := cell_at(p)
			if c == FOREST:
				if randf() < 0.9:
					_add_tree(p, _pick_kind())
				if randf() < 0.5:
					# runo leśne: paprocie, młode drzewka, kępy trawy, czasem kwiaty
					var u := randf()
					_add_plant(Vector2(x + randf() * step, y + randf() * step), "fern" if u < 0.5 else ("sapling" if u < 0.68 else ("grass" if u < 0.9 else "flower")))
			elif c == GRASS:
				# postrzępiony skraj lasu: pojedyncze drzewa i krzaki wychodzące w pole
				var diff := thr - float(forest_d[_ci(p)])
				if diff < 18.0 and randf() < 0.30 * (1.0 - diff / 18.0) and not _near_site(p, 40.0):
					_add_tree(p, "bush" if randf() < 0.35 else _pick_kind())
			x += step
		y += step
	_hedge_trees()
	_line_trees()
	_lone_trees()
	_meadow_plants()
	for isl in _lake_isles:   # wyspy na jeziorach: kępa drzew i krzewów
		var ic: Vector2 = isl[0]
		var ir: float = isl[1]
		for k in int(clampf(ir / 5.0, 5.0, 14.0)):
			var ip := ic + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * ir * 0.62
			_add_tree(ip, _pick_kind() if randf() < 0.75 else "bush", 0.9)
		for k in 6:
			_add_plant(ic + Vector2.from_angle(randf() * TAU) * randf() * ir * 0.8, "grass" if randf() < 0.6 else "fern")

	# drzewa rysowane od góry do dołu - dolne korony zachodzą na górne (jak na ilustracjach z góry)
	var order: Array = range(_tp.size())
	order.sort_custom(func(i: int, j: int) -> bool: return _tp[i].y < _tp[j].y)
	var positions := PackedVector2Array()
	var sizes := PackedFloat32Array()
	var variants := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in order:
		positions.append(_tp[i])
		sizes.append(_ts[i])
		variants.append(_tv[i])
		cols.append(_tc[i])

	# rośliny przyziemne: osobna warstwa pod cieniami i koronami drzew, bez cienia i bez kolizji z kulami
	var plant_mm := _tree_multimesh(_pp.size())
	for i in _pp.size():
		var pq := _ps[i] * float(CANOPY_CELL) / float(CANOPY_SIZE)
		plant_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(pq, pq), 0.0, _pp[i]))
		plant_mm.set_instance_custom_data(i, Color(_pv[i], randf(), 0, 0))
		plant_mm.set_instance_color(i, _pc[i])
	var plants := MultiMeshInstance2D.new()
	plants.multimesh = plant_mm
	plants.texture = tex
	plants.material = _canopy_material(false)
	plants.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	add_child(plants)
	_pp = PackedVector2Array()
	_ps = PackedFloat32Array()
	_pv = PackedFloat32Array()
	_pc = PackedColorArray()

	var shadow_mm := _tree_multimesh(positions.size())
	var tree_mm := _tree_multimesh(positions.size())
	for i in positions.size():
		var s := sizes[i]
		# rozmiar komórki atlasu (z marginesem) zamiast samej korony
		var q := s * float(CANOPY_CELL) / float(CANOPY_SIZE)
		var variant := variants[i]
		var sh_off := Vector2(7, 8) * clampf(s / 30.0, 0.5, 1.2)
		shadow_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(q, q) * 1.04, 0.0, positions[i] + sh_off))
		shadow_mm.set_instance_color(i, Color(0, 0, 0, 0.42))
		var sway_ph := randf()   # faza kołysania - ta sama dla korony i jej cienia
		shadow_mm.set_instance_custom_data(i, Color(variant, sway_ph, 0, 0))
		tree_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(q, q), 0.0, positions[i]))
		tree_mm.set_instance_custom_data(i, Color(variant, sway_ph, 0, 0))
		tree_mm.set_instance_color(i, cols[i])

	var shadows := MultiMeshInstance2D.new()
	shadows.multimesh = shadow_mm
	shadows.texture = tex
	shadows.material = _canopy_material(true)
	shadows.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	add_child(shadows)
	var trees := MultiMeshInstance2D.new()
	trees.multimesh = tree_mm
	trees.texture = tex
	trees.material = _canopy_material(false)
	trees.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	add_child(trees)

	_tree_mm = tree_mm
	_shadow_mm = shadow_mm
	tree_shadows = shadows
	_tree_pos = positions
	_tree_col = cols
	for i in positions.size():
		var key := Vector2i(int(positions[i].x / TREE_BUCKET), int(positions[i].y / TREE_BUCKET))
		if not _tree_grid.has(key):
			_tree_grid[key] = PackedInt32Array()
		var arr: PackedInt32Array = _tree_grid[key]
		arr.append(i)
		_tree_grid[key] = arr
	_tp = PackedVector2Array()
	_ts = PackedFloat32Array()
	_tv = PackedFloat32Array()
	_tc = PackedColorArray()


var _tp := PackedVector2Array()
var _ts := PackedFloat32Array()
var _tv := PackedFloat32Array()
var _tc := PackedColorArray()
var _kinds_w: Dictionary = {}


var _pp := PackedVector2Array()
var _ps := PackedFloat32Array()
var _pv := PackedFloat32Array()
var _pc := PackedColorArray()
const FLOWER_COLS := [Color(0.95, 0.88, 0.36), Color(0.93, 0.93, 0.88), Color(0.82, 0.30, 0.34), Color(0.58, 0.50, 0.86), Color(0.95, 0.62, 0.24)]


func _add_plant(p: Vector2, kind: String, col_i := -1) -> void:
	## Roślina przyziemna (paproć, kępa trawy / trzciny, kwiaty, młody świerk) - sama ozdoba.
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_size.x or p.y >= map_size.y:
		return
	var snowy := float(tv("tree_snow")) > 0.5
	var dry := float(_kinds_w.get("palm", 0.0)) > 0.3
	if kind == "flower" and snowy:
		kind = "grass"
	if kind == "fern" and dry:
		kind = "grass"
	var v := 21.0
	var s := randf_range(18.0, 24.0)
	var col := Color(0.50, 0.58, 0.26)
	match kind:
		"fern":
			v = 20.0
			s = randf_range(20.0, 28.0)
			col = Color(0.27, 0.47, 0.21)
		"flower":
			v = 22.0 + float(randi() % 3)
			s = randf_range(20.0, 27.0)
			col = FLOWER_COLS[col_i if col_i >= 0 else randi() % FLOWER_COLS.size()]
		"sapling":
			v = 25.0
			s = randf_range(20.0, 26.0)
			col = tv("conifer_col")
		_:
			col = Color(0.62, 0.60, 0.34) if (snowy or dry) else Color(0.50, 0.58, 0.26)
	col = col * randf_range(0.88, 1.1)
	col.a = 1.0
	_pp.append(p)
	_ps.append(s)
	_pv.append(v)
	_pc.append(col)


func _meadow_plants() -> void:
	## Łąki: płaty kwiatów jednej barwy i kępy trawy; przy skraju lasu krzewy i paprocie wychodzą w pole.
	var count := int(map_size.x * map_size.y / (300.0 * 300.0))
	for k in count:
		var c := Vector2(randf() * map_size.x, randf() * map_size.y)
		if not _tree_ok(c):
			continue
		var flowers := randf() < 0.6
		var ci := randi() % FLOWER_COLS.size()
		var rad := randf_range(18.0, 46.0)
		for j in randi_range(3, 9):
			var q := c + Vector2.from_angle(randf() * TAU) * sqrt(randf()) * rad
			if _tree_ok(q):
				_add_plant(q, "flower" if flowers and randf() < 0.8 else "grass", ci)


func _pick_kind() -> String:
	var r := randf()
	var acc := 0.0
	for k in ["broad", "conifer", "palm", "bush"]:
		acc += float(_kinds_w.get(k, 0.0))
		if r < acc:
			return k
	return "broad"


func _add_tree(p: Vector2, kind: String, scale := 1.0) -> void:
	var v := 0
	var s := 30.0
	var col: Color
	# gatunek w obrębie rodzaju: wśród liściastych dęby, brzozy, topole i z rzadka suche drzewo; wśród iglastych sosny
	if kind == "broad":
		var sp := randf()
		if sp < 0.20:
			kind = "oak"
		elif sp < 0.36:
			kind = "birch"
		elif sp < 0.44:
			kind = "poplar"
		elif sp < 0.46:
			kind = "dead"
	elif kind == "conifer" and randf() < 0.35:
		kind = "pine"
	var tcs: Array = tv("tree_cols")
	var leaf: Color = (tcs[randi() % tcs.size()] as Color).lerp(tcs[randi() % tcs.size()], randf() * 0.5)
	var green := float(tv("tree_snow")) < 0.5 and leaf.g > leaf.r * 1.15   # jesienią / zimą bez dobarwiania na zielono
	match kind:
		"oak":
			v = 10 + randi() % 2
			s = randf_range(32.0, 44.0)
			col = leaf * randf_range(0.78, 0.92)
		"birch":
			v = 12 + randi() % 2
			s = randf_range(22.0, 30.0)
			col = (leaf.lerp(Color(0.62, 0.72, 0.32), 0.45) if green else leaf.lightened(0.12)) * randf_range(0.92, 1.08)
		"poplar":
			v = 14 + randi() % 2
			s = randf_range(26.0, 33.0)
			col = (leaf.lerp(Color(0.24, 0.44, 0.20), 0.45) if green else leaf.darkened(0.1)) * randf_range(0.9, 1.06)
		"willow":
			v = 18
			s = randf_range(30.0, 40.0)
			col = (leaf.lerp(Color(0.52, 0.64, 0.34), 0.5) if green else leaf) * randf_range(0.92, 1.08)
		"dead":
			v = 19
			s = randf_range(22.0, 30.0)
			col = Color(0.44, 0.37, 0.30) * randf_range(0.85, 1.1)
		"pine":
			v = 16 + randi() % 2
			s = randf_range(26.0, 36.0)
			col = (tv("conifer_col") as Color).lerp(Color(0.30, 0.42, 0.22), 0.45) * randf_range(0.88, 1.1)
		"conifer":
			v = 4 + randi() % 2
			s = randf_range(22.0, 31.0)
			col = (tv("conifer_col") as Color) * randf_range(0.88, 1.1)
		"palm":
			v = 6 + randi() % 2
			s = randf_range(26.0, 36.0)
			col = (tv("palm_col") as Color) * randf_range(0.88, 1.12)
		"bush":
			v = 8 + randi() % 2
			s = randf_range(13.0, 20.0)
			col = (tv("bush_col") as Color) * randf_range(0.85, 1.12)
		_:
			v = randi() % 4
			s = randf_range(24.0, 36.0)
			var tc: Array = tv("tree_cols")
			col = (tc[randi() % tc.size()] as Color).lerp(tc[randi() % tc.size()], randf() * 0.5) * randf_range(0.9, 1.08)
	col.a = 1.0
	_tp.append(p)
	_ts.append(s * scale)
	_tv.append(float(v))
	_tc.append(col)


func _near_site(p: Vector2, extra: float) -> bool:
	for s in sites:
		var r := (Settlement.CITY_RADIUS if s[1] else Settlement.VILLAGE_RADIUS + 70.0) + extra
		if (s[0] as Vector2).distance_squared_to(p) < r * r:
			return true
	return false


func _tree_ok(p: Vector2) -> bool:
	if p.x < 0.0 or p.y < 0.0 or p.x >= map_size.x or p.y >= map_size.y:
		return false
	return cell_at(p) == GRASS and not _near_site(p, 30.0)


func _hedge_trees() -> void:
	## Drzewa w żywopłotach na granicach działek (te same granice, które rysuje shader).
	var ncx := ceili(map_size.x / FIELD_CELL)
	var ncy := ceili(map_size.y / FIELD_CELL)
	for cy in range(-1, ncy + 1):
		for cx in range(-1, ncx + 1):
			var c0 := Vector2i(cx + 1000, cy + 1000)
			var k0 := _fkind(c0)
			for nb in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
				var c1: Vector2i = c0 + nb
				var k1 := _fkind(c1)
				if k0 == 0 and k1 == 0:
					continue
				var r := randf()
				var dens := 0.03
				if r < 0.2:
					dens = 0.7          # szpaler drzew
				elif r < 0.55:
					dens = 0.16         # pojedyncze dęby w żywopłocie
				var s0 := _fseed(c0)
				var s1 := _fseed(c1)
				var m := (s0 + s1) * 0.5
				var t := (s1 - s0).normalized().orthogonal()
				var k := -FIELD_CELL * 0.6
				while k <= FIELD_CELL * 0.6:
					var q := m + t * k
					k += randf_range(30.0, 52.0)
					if randf() > dens:
						continue
					var nn := _nearest2(q)
					if not ((nn[0] == c0 and nn[1] == c1) or (nn[0] == c1 and nn[1] == c0)):
						continue
					var p := _unwarp(q)
					if _tree_ok(p):
						_add_tree(p, "bush" if randf() < 0.2 else _pick_kind(), 1.08)


func _line_trees() -> void:
	## Aleje przy drogach i drzewa (wierzby, palmy) nad brzegami rzek - odcinkami, nie wszędzie.
	var lines: Array = []
	for rd in roads:
		lines.append([rd, ROAD_WIDTH * 0.5 + 15.0, 0.25, "poplar"])
	for r in rivers:
		lines.append([r[0], float(r[1]) * 0.5 + 42.0, 0.45 if float(_kinds_w.get("palm", 0.0)) > 0.3 else 0.32, "willow"])
	for ln in lines:
		var pts: PackedVector2Array = ln[0]
		var off: float = ln[1]
		var on_p: float = ln[2]
		var fav: String = ln[3]     # ulubiony gatunek: topole w alejach, wierzby nad wodą (tam, gdzie rosną liściaste)
		var fav_p := 0.6 if float(_kinds_w.get("broad", 0.0)) > 0.3 else 0.0
		for side in [-1.0, 1.0]:
			var on := randf() < on_p
			var walked := 0.0
			var next := randf_range(20.0, 50.0)
			for i in pts.size() - 1:
				var a := pts[i]
				var b := pts[i + 1]
				var L := a.distance_to(b)
				if L < 0.01:
					continue
				var dir := (b - a) / L
				var nrm: Vector2 = dir.orthogonal() * side
				var t := 0.0
				while t < L:
					var adv := minf(next, L - t)
					t += adv
					next -= adv
					walked += adv
					if next > 0.0:
						break
					next = randf_range(32.0, 48.0)
					if randf() < 0.06:
						on = randf() < on_p * 1.6
					if not on or randf() < 0.18:
						continue
					var p: Vector2 = a + dir * t + nrm * (off + randf_range(-4.0, 6.0))
					if _tree_ok(p):
						_add_tree(p, fav if randf() < fav_p else (_pick_kind() if randf() < 0.85 else "bush"), 0.95)
						if fav == "willow" and randf() < 0.5:
							_add_plant(p + nrm * randf_range(-22.0, -8.0) + dir * randf_range(-12.0, 12.0), "grass")   # trzciny przy brzegu


func _lone_trees() -> void:
	## Samotne drzewa i kępy drzew/krzewów na łąkach i pastwiskach.
	var count := int(map_size.x * map_size.y / (520.0 * 520.0))
	for k in count:
		var p := Vector2(randf() * map_size.x, randf() * map_size.y)
		var n := 1 + (randi() % 4 if randf() < 0.4 else 0)
		var kind := _pick_kind()
		for j in n:
			var q := p + Vector2(randf_range(-26.0, 26.0), randf_range(-26.0, 26.0)) * (0.0 if j == 0 else 1.0)
			if _tree_ok(q):
				_add_tree(q, kind if randf() < 0.7 else "bush")


func _tree_multimesh(n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = n
	return mm


const CANOPY_SIZE := 24      # korona w pikselach
const CANOPY_CELL := 32      # komórka atlasu (z marginesem, żeby mipmapy nie mieszały wariantów)
const CANOPY_VARIANTS := 26  # 0-3 liściaste, 4-5 świerki, 6-7 palmy, 8-9 krzewy / oliwki, 10-11 dęby, 12-13 brzozy,
# 14-15 topole, 16-17 sosny, 18 wierzba, 19 suche drzewo, 20 paproć, 21 kępa trawy, 22-24 kwiaty, 25 młody świerk
const CANOPY_KINDS := ["broad", "broad", "broad", "broad", "conifer", "conifer", "palm", "palm", "bush", "bush",
	"oak", "oak", "birch", "birch", "poplar", "poplar", "pine", "pine", "willow", "dead",
	"fern", "grass", "flower", "flower", "flower", "sapling"]

const CANOPY_SHADER := """
shader_type canvas_item;
// Korona z atlasu wariantów; tekstura w skali szarości = ton (0 obrys, 1 blask), paleta z koloru instancji.
uniform bool shadow = false;
uniform float variants = 10.0;
uniform float snow = 0.0;
uniform float sway = 1.3;      // kołysanie koron na wietrze: wychylenie brzegu korony w tekselach (0 = bez ruchu)
varying vec4 tint;
varying vec2 luv;
varying float ph;
void vertex() {
	luv = UV;
	ph = INSTANCE_CUSTOM.g;
	UV.x = (UV.x + floor(INSTANCE_CUSTOM.r + 0.5)) / variants;
	tint = COLOR;
}
void fragment() {
	// pień stoi w miejscu, a korona ugina się z wiatrem: im dalej od środka, tym większe wychylenie;
	// każde drzewo we własnym rytmie, z wolnym narastaniem i cichnięciem podmuchu
	float rr = length(luv - 0.5) * 2.0;
	float tt = TIME * 1.7 + ph * 6.2831853;
	float gustk = 0.55 + 0.45 * sin(TIME * 0.4 + ph * 9.0);
	vec2 sw = vec2(0.91, 0.41) * (sin(tt) * 0.6 + sin(tt * 2.3 + 1.0) * 0.4) + vec2(-0.41, 0.91) * sin(tt * 1.3 + 2.0) * 0.35;
	vec2 off = sw * sway * gustk * smoothstep(0.1, 0.85, rr) / 32.0;
	vec4 t = texture(TEXTURE, UV - vec2(off.x / variants, off.y));
	if (shadow) {
		COLOR = vec4(0.0, 0.02, 0.0, t.a * tint.a);
	} else {
		float v = t.r;
		vec3 c = tint.rgb;
		vec3 dark = c * vec3(0.30, 0.38, 0.50);                 // cień w chłodnym, sinym tonie
		vec3 lit = c * 1.28 + vec3(0.07, 0.06, 0.0);             // blask ciepły, żółtawy
		vec3 rgb = v < 0.55 ? mix(dark, c, v / 0.55) : mix(c, lit, (v - 0.55) / 0.45);
		// śnieg na koronach: oświetlone kępy pod białą czapą
		rgb = mix(rgb, vec3(0.86, 0.90, 0.97) * (0.80 + 0.2 * v), snow * step(0.9, v));
		COLOR = vec4(rgb, t.a * tint.a);
	}
}
"""


func _canopy_material(is_shadow: bool) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = CANOPY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("shadow", is_shadow)
	m.set_shader_parameter("variants", float(CANOPY_VARIANTS))
	m.set_shader_parameter("snow", float(tv("tree_snow")))
	return m


func _make_canopy_atlas() -> Texture2D:
	## Pikselowe korony: liściaste (kępy liści), iglaste (gwiaździste świerki), palmy (pióropusz liści),
	## krzewy/oliwki (małe, rzadkie kępki). Ostry obrys, tony od światła z lewej-góry.
	var img := Image.create(CANOPY_CELL * CANOPY_VARIANTS, CANOPY_CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for v in CANOPY_VARIANTS:
		_paint_canopy(img, v * CANOPY_CELL, 11 + v * 17, CANOPY_KINDS[v])
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _paint_canopy(img: Image, ox: int, seed_v: int, kind := "broad") -> void:
	const S := CANOPY_SIZE
	var pad := (CANOPY_CELL - S) / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var c0 := Vector2(S, S) * 0.5
	var mask := PackedFloat32Array()
	mask.resize(S * S)
	var tone := PackedFloat32Array()
	tone.resize(S * S)
	var outline := true      # drobne rośliny (trawa, kwiaty, paprocie, suche gałęzie) bez ciemnego obrysu
	if kind == "broad" or kind == "bush" or kind == "oak" or kind == "birch" or kind == "poplar" or kind == "pine":
		var blobs := []
		var ragged := 0.0     # postrzępienie brzegu kęp (sosna: pęki igieł)
		if kind == "oak":
			# dąb: rozłożysta korona z wielu drobnych kęp
			var nb := rng.randi_range(9, 11)
			for k in nb:
				var a := k * TAU / nb + rng.randf_range(-0.25, 0.25)
				blobs.append([c0 + Vector2.from_angle(a) * rng.randf_range(6.2, 8.0), rng.randf_range(2.8, 3.8)])
			for k in 4:
				blobs.append([c0 + Vector2.from_angle(k * TAU / 4.0 + rng.randf()) * rng.randf_range(2.0, 3.6), rng.randf_range(3.4, 4.4)])
		elif kind == "birch":
			# brzoza: lekka, ażurowa korona - drobne kępki z prześwitami
			var nb := rng.randi_range(8, 10)
			for k in nb:
				var a := k * TAU / nb + rng.randf_range(-0.5, 0.5)
				blobs.append([c0 + Vector2.from_angle(a) * rng.randf_range(3.5, 7.0), rng.randf_range(2.3, 3.1)])
			blobs.append([c0 + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)), rng.randf_range(3.6, 4.4)])
		elif kind == "poplar":
			# topola: wąska kolumna - z góry mała, zwarta korona
			blobs.append([c0, rng.randf_range(4.6, 5.4)])
			for k in 3:
				blobs.append([c0 + Vector2.from_angle(k * TAU / 3.0 + rng.randf()) * rng.randf_range(2.2, 3.0), rng.randf_range(2.8, 3.4)])
		elif kind == "pine":
			# sosna: parasol z kilku pęków igieł o poszarpanym brzegu
			ragged = 0.3
			var nb := rng.randi_range(5, 6)
			for k in nb:
				var a := k * TAU / nb + rng.randf_range(-0.35, 0.35)
				blobs.append([c0 + Vector2.from_angle(a) * rng.randf_range(5.0, 7.0), rng.randf_range(3.0, 4.2)])
			blobs.append([c0, rng.randf_range(3.6, 4.6)])
		elif kind == "broad":
			var nb := rng.randi_range(5, 7)
			for k in nb:
				var a := k * TAU / nb + rng.randf_range(-0.3, 0.3)
				blobs.append([c0 + Vector2.from_angle(a) * rng.randf_range(4.5, 6.0), rng.randf_range(3.6, 5.2)])
			blobs.append([c0 + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), rng.randf_range(5.0, 6.0)])
		else:
			var nb := rng.randi_range(4, 6)
			for k in nb:
				var a := k * TAU / nb + rng.randf_range(-0.5, 0.5)
				blobs.append([c0 + Vector2.from_angle(a) * rng.randf_range(4.0, 7.0), rng.randf_range(2.8, 4.4)])
			blobs.append([c0, rng.randf_range(4.0, 5.0)])
		for y in S:
			for x in S:
				var p := Vector2(x + 0.5, y + 0.5)
				var best := 0.0
				var shade := 0.0
				for b in blobs:
					var local: Vector2 = (p - b[0]) / float(b[1])
					var d := local.length()
					if d < 1.0 - (rng.randf() * ragged if ragged > 0.0 else 0.0):
						best = 1.0
						# każda kępa oświetlona z lewej-góry; bliżej środka korony = wyżej = jaśniej
						var l := 1.0 - clampf((local - Vector2(-0.45, -0.5)).length() * 0.62, 0.0, 1.0)
						shade = maxf(shade, l)
				if best > 0.0:
					var rel := (p - c0) / (S * 0.5)
					shade -= clampf((rel.x + rel.y) * 0.22, -0.15, 0.3)
					shade += rng.randf_range(-0.08, 0.08)
				mask[y * S + x] = best
				tone[y * S + x] = shade
	elif kind == "conifer":
		# świerk z góry: gwiazda gałęzi, kilka pięter (pierścieni) coraz jaśniejszych ku wierzchołkowi
		var arms := rng.randi_range(8, 10)
		var ph := rng.randf() * TAU
		var R := S * 0.5 - 1.0
		for y in S:
			for x in S:
				var p := Vector2(x + 0.5, y + 0.5) - c0
				var r := p.length() / R
				var a := p.angle()
				var spike := pow(absf(cos((a + ph) * arms * 0.5)), 0.6)
				var edge_r := 0.62 + 0.38 * spike + rng.randf_range(-0.05, 0.05)
				if r < edge_r:
					mask[y * S + x] = 1.0
					var ring := fposmod(r * 3.2, 1.0)            # piętra gałęzi
					var l := 1.0 - r * 0.75 - (p.x + p.y) / (S * 1.4)
					l += (0.12 if ring < 0.5 else -0.08) + 0.12 * spike
					tone[y * S + x] = l + rng.randf_range(-0.06, 0.06)
	elif kind == "sapling":
		# młody świerk: mała gwiazdka
		var arms := 6
		var ph := rng.randf() * TAU
		var R := S * 0.24
		for y in S:
			for x in S:
				var p := Vector2(x + 0.5, y + 0.5) - c0
				var r := p.length() / R
				var spike := pow(absf(cos((p.angle() + ph) * arms * 0.5)), 0.6)
				if r < 0.5 + 0.5 * spike:
					mask[y * S + x] = 1.0
					tone[y * S + x] = 1.0 - r * 0.6 - (p.x + p.y) / (S * 0.8)
	elif kind == "dead" or kind == "grass":
		# suche drzewo: nagie konary z rozwidleniami; kępa trawy: krótkie źdźbła z jednego miejsca
		outline = false
		var segs := []
		if kind == "dead":
			for k in rng.randi_range(5, 7):
				var a := k * TAU / 6.0 + rng.randf_range(-0.4, 0.4)
				var tip := c0 + Vector2.from_angle(a) * rng.randf_range(6.0, 10.0)
				segs.append([c0, tip, 0.85])
				var mid := c0.lerp(tip, rng.randf_range(0.45, 0.65))
				segs.append([mid, mid + Vector2.from_angle(a + rng.randf_range(0.5, 0.9) * (1.0 if rng.randf() < 0.5 else -1.0)) * rng.randf_range(2.5, 4.5), 0.55])
		else:
			for k in rng.randi_range(9, 13):
				var a := rng.randf() * TAU
				segs.append([c0 + Vector2.from_angle(a) * 0.5, c0 + Vector2.from_angle(a) * rng.randf_range(3.0, 6.0), 0.5])
		for y in S:
			for x in S:
				var p := Vector2(x + 0.5, y + 0.5)
				for sg in segs:
					var q := Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])
					if p.distance_to(q) < float(sg[2]):
						mask[y * S + x] = 1.0
						var along := (q - c0).length() / 10.0
						tone[y * S + x] = (0.5 + along * 0.5 if kind == "grass" else 0.62 - (p.x + p.y - S) / (S * 2.0)) + rng.randf_range(-0.1, 0.1)
		if kind == "dead":
			for y in S:
				for x in S:
					if (Vector2(x + 0.5, y + 0.5) - c0).length() < 1.6:
						mask[y * S + x] = 1.0
						tone[y * S + x] = 0.25      # pień
	elif kind == "flower":
		# kwiaty na łące: rozsypane pojedyncze główki, kilka ciemniejszych listków
		outline = false
		for k in rng.randi_range(8, 13):
			var q := c0 + Vector2.from_angle(rng.randf() * TAU) * (sqrt(rng.randf()) * 8.5)
			var fx := clampi(int(q.x), 0, S - 1)
			var fy := clampi(int(q.y), 0, S - 1)
			mask[fy * S + fx] = 1.0
			tone[fy * S + fx] = 0.95
			if rng.randf() < 0.45 and fx + 1 < S:
				mask[fy * S + fx + 1] = 1.0
				tone[fy * S + fx + 1] = 0.7
			if rng.randf() < 0.3 and fy + 1 < S:
				mask[(fy + 1) * S + fx] = 1.0
				tone[(fy + 1) * S + fx] = 0.2
	else:
		# palma z góry: pióropusz 7-9 liści, każdy jaśniejszy na grzbiecie, ciemny między liśćmi
		# (wierzba: gęste, zwisające witki; paproć: mała rozeta wąskich liści)
		var nf := rng.randi_range(7, 9)
		var ph := rng.randf() * TAU
		var R := S * 0.5 - 0.5
		var wide := 0.42
		var core := 0.18
		var bend := 0.35
		if kind == "willow":
			nf = rng.randi_range(13, 16)
			wide = 0.46
			core = 0.42
			bend = 0.6
		elif kind == "fern":
			outline = false
			nf = rng.randi_range(6, 8)
			R = S * 0.3
			wide = 0.3
			core = 0.12
			bend = 0.5
		for y in S:
			for x in S:
				var p := Vector2(x + 0.5, y + 0.5) - c0
				var r := p.length() / R
				if r > 1.0:
					continue
				var a := p.angle() + ph + r * bend                 # liście lekko wygięte
				var fa := fposmod(a, TAU / nf) / (TAU / nf) - 0.5    # -0.5..0.5 w poprzek liścia
				var width := wide * (1.0 - r * r) + 0.06
				if absf(fa) < width or r < core:
					mask[y * S + x] = 1.0
					var l := 0.95 - absf(fa) / maxf(width, 0.01) * 0.6 - r * 0.25 - (p.x + p.y) / (S * 1.6)
					if r < core:
						l = 0.5 if kind != "willow" else 0.85 - r * 0.6 - (p.x + p.y) / (S * 1.6)
					tone[y * S + x] = l
	for y in S:
		for x in S:
			if mask[y * S + x] <= 0.0:
				continue
			var edge := false
			for o in ([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)] if outline else []):
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < 0 or ny < 0 or nx >= S or ny >= S or mask[ny * S + nx] <= 0.0:
					edge = true
			var t := tone[y * S + x]
			var v: float
			if edge:
				v = 0.0                                   # ciemny obrys
			elif t > 0.78:
				v = 1.0                                   # blask
			elif t > 0.55:
				v = 0.78
			elif t > 0.3:
				v = 0.55
			else:
				v = 0.28
			# pojedyncze ciemne "dziury" między liśćmi i jasne listki
			if not outline:
				pass
			elif not edge and v >= 0.55 and rng.randf() < 0.07:
				v = 0.28
			elif not edge and v == 0.78 and rng.randf() < 0.12:
				v = 1.0
			img.set_pixel(ox + pad + x, pad + y, Color(v, v, v, 1.0))


# ------------------------------------------------------------------ przezroczyste drzewa nad oddziałami

const TREE_BUCKET := 200.0
const TREE_FADED := 0.28

var _tree_mm: MultiMesh
var tree_shadows: MultiMeshInstance2D  # cienie drzew - ukrywane przy dużym oddaleniu
var _shadow_mm: MultiMesh
var _tree_pos := PackedVector2Array()
var _tree_col := PackedColorArray()
var _tree_grid := {}
var _tree_alpha := {}   # indeks drzewa → bieżąca przezroczystość (tylko te, które nie są w pełni widoczne)


# ------------------------------------------------------------------ kule armatnie w drzewach

var _fallen := {}          # indeks drzewa → przewrócone (nie trafia się go drugi raz)
var _fallen_trunks := {}   # indeks → [podstawa, kierunek, długość widocznego pnia, rozmiar korony]
var _fallen_layer: Node2D  # pnie i karpy pod koronami
var _tree_anim: Array = []  # [indeks, czas, przewraca_się, kierunek, transform wyjściowy, kolor wyjściowy]


func hit_tree(p: Vector2, dir: Vector2, radius := 9.0, force_fall := false) -> int:
	## Kula przelatuje przez koronę: drzewo się trzęsie, a czasem przewraca w kierunku lotu. Zwraca indeks albo -1.
	if _tree_mm == null:
		return -1
	var key := Vector2i(int(p.x / TREE_BUCKET), int(p.y / TREE_BUCKET))
	var best := -1
	var bd := radius * radius
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var k2 := key + Vector2i(dx, dy)
			if not _tree_grid.has(k2):
				continue
			for idx in _tree_grid[k2]:
				if _fallen.has(idx):
					continue
				var d := _tree_pos[idx].distance_squared_to(p)
				if d < bd:
					bd = d
					best = idx
	if best < 0:
		return -1
	for an in _tree_anim:
		if an[0] == best:
			return best   # już się trzęsie
	var fall := force_fall or randf() < 0.55
	if fall:
		_fallen[best] = true
		_ensure_fallen_layer()
	_tree_anim.append([best, 0.0, fall, dir.normalized(), _tree_mm.get_instance_transform_2d(best), _tree_col[best]])
	return best


func tree_fell(idx: int) -> bool:
	return _fallen.has(idx)


func tree_color(idx: int) -> Color:
	return _tree_col[idx] if idx >= 0 and idx < _tree_col.size() else Color(0.3, 0.45, 0.2)


func _ensure_fallen_layer() -> void:
	if _fallen_layer != null:
		return
	_fallen_layer = Node2D.new()
	_fallen_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fallen_layer.draw.connect(_draw_fallen)
	add_child(_fallen_layer)
	if tree_shadows != null:
		move_child(_fallen_layer, tree_shadows.get_index() + 1)   # nad cieniami, pod koronami


const TRUNK_PX := 1.5   # kratka pikselowego pnia (jednostki świata) - jak tekstury drzew i zabudowy


func _px_cell(c: Vector2, col: Color) -> void:
	var q := (c / TRUNK_PX).floor() * TRUNK_PX
	_fallen_layer.draw_rect(Rect2(q, Vector2(TRUNK_PX, TRUNK_PX)), col)


func _draw_fallen() -> void:
	## Leżące pnie w pixel-arcie: kratki z ciemnym obrysem, cień od dołu, jasna kora od światła (lewa-góra),
	## plamki kory, jasny przekrój na złamaniu; karpa z korzeniami i połamane gałęzie też na kratkach.
	var light := Vector2(-0.7, -0.7)
	var outline := Color(0.10, 0.07, 0.04)
	for idx in _fallen_trunks:
		var tr: Array = _fallen_trunks[idx]
		var b0: Vector2 = tr[0]
		var d: Vector2 = tr[1]
		var ln: float = tr[2]
		var q: float = tr[3]
		var hw := clampf(q * 0.045, 1.4, 2.6)          # połowa grubości pnia
		var side := d.orthogonal()
		var lit_sign := 1.0 if side.dot(light) > 0.0 else -1.0
		# karpa: pikselowy krążek ziemi z korzeniami
		var rr := hw * 1.9
		var y := -rr
		while y <= rr:
			var x := -rr
			while x <= rr:
				var o := Vector2(x, y)
				var dd := o.length() / rr
				if dd <= 1.0:
					var col := Color(0.30, 0.21, 0.12) if dd < 0.55 else (Color(0.20, 0.14, 0.08) if dd < 0.85 else outline)
					_px_cell(b0 - d * hw * 0.8 + o, col)
				x += TRUNK_PX
			y += TRUNK_PX
		for k in 5:
			var ra := d.rotated(PI + (k - 2.0) * 0.45)
			var t := 0.0
			while t < rr * 1.5:
				_px_cell(b0 - d * hw * 0.8 + ra * (rr + t), Color(0.24, 0.16, 0.09))
				t += TRUNK_PX
		if ln < 0.5:
			continue
		# pień: wzdłuż osi co kratkę, w poprzek od -hw do +hw; obrys na brzegach, światło po jednej stronie
		var t2 := 0.0
		var step := TRUNK_PX * 0.7
		while t2 <= ln:
			var cpos := b0 + d * t2
			var w := -hw - TRUNK_PX
			while w <= hw + TRUNK_PX:
				var col2: Color
				var aw := absf(w)
				if aw > hw:
					col2 = outline
				else:
					var lt := w * lit_sign / hw          # -1 cień ... +1 światło
					col2 = Color(0.36, 0.25, 0.14).lerp(Color(0.58, 0.44, 0.27), clampf(lt * 0.5 + 0.5, 0.0, 1.0))
					if lt < -0.55:
						col2 = Color(0.24, 0.16, 0.09)
					var hsh := int(absf(t2 * 7.3 + w * 13.1)) % 7   # plamki i bruzdy kory
					if hsh == 0:
						col2 = col2.darkened(0.25)
				_px_cell(cpos + side * w, col2)
				w += TRUNK_PX
			t2 += step
		# złamanie na końcu: jasny przekrój ze słojem
		var tip := b0 + d * ln
		_px_cell(tip, Color(0.82, 0.70, 0.48))
		_px_cell(tip + side * TRUNK_PX, Color(0.76, 0.62, 0.40))
		_px_cell(tip - side * TRUNK_PX, Color(0.70, 0.56, 0.36))
		# połamane gałęzie: krótkie pikselowe odnogi
		for k in 3:
			var bp := b0.lerp(tip, 0.45 + k * 0.17)
			var sg := 1.0 if k % 2 == 0 else -1.0
			var bd := (d * 0.6 + side * sg).normalized()
			var t3 := 0.0
			while t3 < hw * 2.6:
				_px_cell(bp + side * sg * hw + bd * t3, Color(0.30, 0.21, 0.12) if t3 < hw * 1.8 else Color(0.22, 0.15, 0.08))
				t3 += TRUNK_PX


func _animate_hit_trees(dt: float) -> void:
	if _tree_anim.is_empty():
		return
	var keep: Array = []
	for an in _tree_anim:
		var idx: int = an[0]
		an[1] += dt
		var t: float = an[1]
		var xf: Transform2D = an[4]
		var d: Vector2 = an[3]
		var base_col: Color = an[5]
		if an[2]:
			# przewracanie: drzewo pada jak ścięte - korona (bez deformacji) odjeżdża od podstawy po łuku
			# opadania (szybciej pod koniec), odsłaniając leżący pień; na końcu lekko podskakuje i zostaje.
			var e := clampf(t / 1.1, 0.0, 1.0)
			e = e * e   # przyspiesza jak padające drzewo
			var q := xf.x.length()
			var reach := q * 0.62
			var bounce := sin(clampf((t - 1.1) / 0.25, 0.0, 1.0) * PI) * 0.06 if t > 1.1 else 0.0
			var off := d * reach * (e - bounce)
			var sc := 1.0 - 0.08 * e
			var nx := Transform2D(xf.x * sc, xf.y * sc, xf.origin + off)
			_tree_mm.set_instance_transform_2d(idx, nx)
			var fallen_col := base_col.lerp(Color(0.30, 0.30, 0.15, base_col.a), 0.25 * e)
			_tree_mm.set_instance_color(idx, fallen_col)
			_tree_col[idx] = fallen_col
			_shadow_mm.set_instance_transform_2d(idx, Transform2D(nx.x * 1.04, nx.y * 1.04, nx.origin + Vector2(7, 8) * (1.0 - 0.75 * e)))
			_shadow_mm.set_instance_color(idx, Color(0, 0, 0, 0.42 * (1.0 - 0.6 * e)))
			_fallen_trunks[idx] = [xf.origin, d, reach * (e - bounce), q]
			if _fallen_layer != null:
				_fallen_layer.queue_redraw()
			if t < 1.35:
				keep.append(an)
		else:
			# trafienie bez przewrócenia: korona drży i uspokaja się
			var w := sin(t * 38.0) * 1.6 * maxf(0.0, 1.0 - t / 0.55)
			_tree_mm.set_instance_transform_2d(idx, Transform2D(xf.x, xf.y, xf.origin + d.orthogonal() * w))
			if t < 0.55:
				keep.append(an)
			else:
				_tree_mm.set_instance_transform_2d(idx, xf)
	_tree_anim = keep


func update_tree_fade(regs: Array[Regiment]) -> void:
	## Drzewa, pod którymi stoją/idą żołnierze, stają się półprzezroczyste.
	if _tree_mm == null:
		return
	var covered := {}
	for r in regs:
		if r.dead:
			continue
		var c := r.centroid() if r.state == Regiment.State.MELEE or r.state == Regiment.State.ROUTING else r.center
		var fwd := r.forward()
		var right := fwd.orthogonal()
		var hw := r.formation_width() * 0.5 + 30.0
		var depth := r.formation_depth()
		var loose := r.state == Regiment.State.MELEE or r.state == Regiment.State.ROUTING
		var rad := hw + depth + 40.0
		var x0 := int((c.x - rad) / TREE_BUCKET)
		var x1 := int((c.x + rad) / TREE_BUCKET)
		var y0 := int((c.y - rad) / TREE_BUCKET)
		var y1 := int((c.y + rad) / TREE_BUCKET)
		for by in range(y0, y1 + 1):
			for bx in range(x0, x1 + 1):
				var key := Vector2i(bx, by)
				if not _tree_grid.has(key):
					continue
				for idx in _tree_grid[key]:
					var d := _tree_pos[idx] - c
					if loose:
						if d.length() < rad:
							covered[idx] = true
					else:
						var lx := absf(d.dot(right))
						var ly := d.dot(fwd)
						if lx < hw and ly < 35.0 and ly > -depth - 35.0:
							covered[idx] = true
	for idx in covered:
		if not _tree_alpha.has(idx):
			_tree_alpha[idx] = 1.0
	var done := []
	for idx in _tree_alpha:
		var target := TREE_FADED if covered.has(idx) else 1.0
		var a: float = move_toward(_tree_alpha[idx], target, 0.12)
		_tree_alpha[idx] = a
		var col := _tree_col[idx]
		col.a = a
		_tree_mm.set_instance_color(idx, col)
		_shadow_mm.set_instance_color(idx, Color(0, 0, 0, 0.4 * a))
		if a >= 1.0 and target >= 1.0:
			done.append(idx)
	for idx in done:
		_tree_alpha.erase(idx)


func _draw() -> void:
	pass
