# Generuje wpisy UNIT_TYPES dla 38 jednostek Wielkiej Brytanii z arkusza "Britain – units and stats".
# Te same przeliczniki co gen_fr.py (piechota liniowa = 1.0), nazwy i opisy po polsku.
import json

# tier, kat, nazwa, licz, koszt, utrz, atak, obr, szarza, cel, zasieg, przel, ogien, morale, szyb, cechy
ROWS = """T1|Piechota|Piechota liniowa (czerwone kurtki)|160|650|160|6|7|7|50|100|42|10|9|6|Linia dwuszeregowa: +15% siły ognia; czworobok
T1|Piechota|Lekka piechota|160|750|180|6|6|7|55|110|44|10|9|7|Szyk luźny, czworobok
T1|Piechota|Milicja|160|350|90|4|5|4|32|90|32|9|5|6|+3 morale w obronie własnego terytorium
T1|Kawaleria|Lekcy dragoni|80|700|180|8|5|18|25|50|20|8|8|15|Zwiad, pościg
T1|Kawaleria|Huzarzy|80|780|190|9|4|20|25|50|20|8|8|16|+5 szarży na uciekających
T1|Artyleria|6-funtówki piesze|4|750|200|3|3|0|32|400|20|40|6|4|Kula, kartacz
T1|Artyleria|9-funtówki piesze|4|950|230|3|3|0|34|520|16|58|7|3|Kula, kartacz, szrapnele
T2|Piechota|Kompania grenadierska|120|950|230|9|9|10|52|100|44|11|11|6|Szturm: +3 ataku wręcz
T2|Piechota|95. Strzelcy|120|1200|280|5|5|5|70|160|30|13|10|8|Karabin Bakera: +20% obrażeń vs oficerowie i obsługa dział; szyk luźny
T2|Piechota|60. Strzelcy (5. batalion)|120|1100|260|5|5|5|66|150|30|12|10|8|Gwintówki, szyk luźny, ukrycie w lesie
T2|Piechota|Górale szkoccy|160|1050|250|11|8|13|50|100|42|11|13|6|+3 ataku wręcz; dudy: +1 morale sojusznikom w pobliżu
T2|Piechota|Królewska Piechota Morska|120|900|220|8|8|8|52|100|42|10|11|7|Desant, +3 ataku w mieście
T2|Piechota|Królewscy Saperzy i Minerzy|80|700|180|7|8|7|38|90|36|10|9|6|Burzenie umocnień, budowa szańców
T2|Kawaleria|Ciężcy dragoni|80|1100|260|11|8|28|30|50|18|8|10|13|Ciężka szarża
T2|Kawaleria|Gwardia Dragonów|80|1200|280|12|9|29|30|50|18|8|11|13|Ciężka szarża
T2|Kawaleria|Royal Scots Greys|80|1250|290|12|8|32|30|50|18|8|12|14|Niszczycielska szarża; potem niekontrolowany pościg (trudno odwołać)
T2|Artyleria|Królewska Artyleria Konna|4|1200|270|5|5|0|36|400|28|42|10|12|Najszybsze rozstawienie w grze
T2|Artyleria|Haubice 5,5 cala|4|1000|230|3|3|0|28|450|15|60|6|3|Ogień stromotorowy, szrapnele
T2|Artyleria|Rakiety Congreve'a|4|700|160|3|3|0|15|700|25|50|6|8|Niecelne; -2 morale celu, straszą kawalerię
T3|Piechota|Gwardia Coldstream|160|1600|360|12|12|12|60|100|50|12|15|6|Utrzymać linię: +3 obrony w miejscu
T3|Piechota|1. Pułk Gwardii Pieszej|160|1800|400|13|13|13|62|100|52|12|16|6|Salwa z bliska: +25% obrażeń poniżej 50 m
T3|Piechota|3. Pułk Gwardii Pieszej (Szkoci)|160|1650|370|13|12|13|60|100|50|12|15|6|Umocnienie budynków: +4 obrony w budynkach
T3|Piechota|Lekkie kompanie Gwardii|120|1300|300|10|9|10|62|110|50|12|14|7|Szyk luźny; Hougoumont: +5 obrony w budynkach
T3|Kawaleria|Life Guards|70|1700|380|15|12|34|25|40|15|8|15|13|Elitarna ciężka jazda
T3|Kawaleria|Royal Horse Guards (Blues)|70|1650|370|14|12|33|25|40|15|8|15|13|Elitarna ciężka jazda
T3|Artyleria|Chestnut Troop RHA|4|1500|330|6|6|0|40|420|30|45|12|12|Weterańska bateria konna: +10% celności
W|Specjalne|Chirurdzy pułkowi|20|800|200|1|2|0|0|0|0|0|6|10|Leczą: +2% ludzi/min oddziałom w pobliżu
W|Specjalne|Tabor intendentury|20|600|150|1|2|0|0|0|0|0|5|6|Zaopatrzenie: -20% utrzymania w regionie, uzupełnia amunicję
W|Dowódca|Generał|20|1400|300|13|11|24|30|40|20|8|14|15|Aura dowodzenia (np. Picton: piechota, Uxbridge: kawaleria)
W|Dowódca|Wellington|30|2500|500|14|13|26|30|40|20|8|18|15|Odwrotny stok: oddziały ukryte za grzbietem; +2 morale wszystkim w obronie
S|Piechota|Piechota liniowa KGL|160|900|220|8|8|9|50|100|42|11|12|6|Weterańska piechota liniowa
S|Piechota|Lekka piechota KGL|120|1100|260|8|8|8|64|140|32|12|13|7|Gwintówki; +4 obrony w budynkach
S|Kawaleria|Huzarzy KGL|80|1050|240|11|6|22|30|50|20|8|12|16|Zdyscyplinowani: bez niekontrolowanego pościgu
S|Kawaleria|Karabinierzy holendersko-belgijscy|70|1100|260|11|9|27|25|40|15|8|9|12|Ciężka jazda, niższe morale
S|Piechota|Czarni Brunszwiczanie|160|850|210|9|7|10|46|100|40|10|12|6|+2 ataku vs Francja
S|Kawaleria|Huzarzy brunszwiccy|80|850|200|10|5|20|25|50|20|8|11|16|+2 morale vs Francja
S|Piechota|Caçadores portugalscy|120|700|170|6|6|6|55|120|40|10|9|8|Szyk luźny, tania lekka piechota
S|Piechota|Portugalska piechota liniowa|160|550|140|6|6|7|44|100|38|10|8|6|Tania piechota liniowa"""

ART_COAT = {"coat": "Color(0.1, 0.12, 0.28)", "facing": "Color(0.8, 0.15, 0.12)"}   # granatowe mundury Royal Artillery
GUARD_SHAKO = {"hat": "\"shako\"", "hat_col": "Color(0.08, 0.08, 0.09)", "plume": "Color(0.95, 0.95, 0.95)", "big": 1.1}

# klucz, baza (wygląd/zachowanie), dodatki
META = [
    ("gb_line", "line", {}),
    ("gb_light", "light", {}),
    ("gb_militia", "militia", {}),
    ("gb_light_drag", "hussars", {"look": {"coat": "Color(0.1, 0.12, 0.3)", "hat": "\"shako\"", "hat_col": "Color(0.08, 0.08, 0.09)", "facing": "Color(0.8, 0.15, 0.12)", "plume": "Color(0.95, 0.95, 0.95)"}}),
    ("gb_hussars", "hussars", {"look": {"coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.93, 0.93, 0.9)"}}),
    ("gb_art6", "artillery", {"gun": {"len": 0.82, "bore": 0.85}, "look": ART_COAT}),
    ("gb_art9", "artillery", {"gun": {"len": 1.08, "bore": 1.08}, "look": ART_COAT}),
    ("gb_grenadiers", "grenadier", {"look": {"hat": "\"shako\"", "hat_col": "Color(0.08, 0.08, 0.09)", "plume": "Color(0.95, 0.95, 0.95)"}}),
    ("gb_95th", "rifles", {"fmt": "%s batalion 95. Strzelców"}),
    ("gb_60th", "rifles", {"fmt": "%s batalion 60. Strzelców", "look": {"facing": "Color(0.7, 0.12, 0.12)"}}),
    ("gb_highlanders", "line", {"aura": 0.15, "aura_r": 220.0, "look": {"hat": "\"bearskin\"", "hat_col": "Color(0.07, 0.07, 0.07)", "facing": "Color(0.1, 0.12, 0.3)", "plume": "Color(0.85, 0.12, 0.12)"}}),
    ("gb_marines", "line", {"look": {"hat": "\"round\"", "facing": "Color(0.1, 0.12, 0.3)"}}),
    ("gb_sappers", "line", {"look": {"facing": "Color(0.1, 0.12, 0.3)", "pack": False}}),
    ("gb_heavy_drag", "dragoons", {}),
    ("gb_drag_guards", "dragoons", {"look": {"facing": "Color(0.1, 0.12, 0.3)"}}),
    ("gb_scots_greys", "dragoons", {"fmt": "%s szwadron Royal Scots Greys", "look": {"hat": "\"bearskin\"", "hat_col": "Color(0.08, 0.07, 0.06)", "facing": "Color(0.1, 0.12, 0.3)", "plume": "Color(0.95, 0.95, 0.95)", "big": 1.1}}),
    ("gb_rha", "horse_art", {"gun": {"len": 0.85, "bore": 0.9}, "look": ART_COAT}),
    ("gb_howitzers", "artillery", {"shell": 0.7, "gun": {"len": 0.55, "bore": 1.55, "how": True}, "look": ART_COAT}),
    ("gb_rockets", "artillery", {"shell": 0.6, "gun": {"len": 1.3, "bore": 0.45}, "look": ART_COAT}),
    ("gb_coldstream", "guard", {"fmt": "%s batalion Gwardii Coldstream", "look": GUARD_SHAKO}),
    ("gb_1st_guards", "guard", {"fmt": "%s batalion 1. Pułku Gwardii", "look": GUARD_SHAKO}),
    ("gb_3rd_guards", "guard", {"fmt": "%s batalion 3. Pułku Gwardii", "look": GUARD_SHAKO}),
    ("gb_guards_light", "light", {"look": {"plume": "Color(0.95, 0.95, 0.95)", "facing": "Color(0.1, 0.12, 0.3)"}}),
    ("gb_life_guards", "dragoons", {"fmt": "%s pułk Life Guards", "look": {"facing": "Color(0.1, 0.12, 0.3)", "hat_col": "Color(0.75, 0.75, 0.78)", "plume": "Color(0.95, 0.95, 0.95)", "big": 1.1}}),
    ("gb_blues", "dragoons", {"fmt": "%s szwadron Royal Horse Guards", "look": {"coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.8, 0.15, 0.12)", "hat_col": "Color(0.75, 0.75, 0.78)", "plume": "Color(0.85, 0.12, 0.12)", "big": 1.1}}),
    ("gb_chestnut", "horse_art", {"unique": 1, "fmt": "Chestnut Troop RHA", "gun": {"len": 0.88, "bore": 0.92, "polish": True}, "look": ART_COAT}),
    ("gb_surgeons", "line", {"heal": 0.02, "heal_r": 380.0, "unique": 2, "look": {"hat": "\"bicorne\"", "pack": False, "belts": False, "coat": "Color(0.12, 0.12, 0.14)"}}),
    ("gb_commissariat", "line", {"unique": 2, "look": {"hat": "\"round\"", "pack": False, "belts": False, "coat": "Color(0.1, 0.12, 0.3)"}}),
    ("gb_general", "dragoons", {"aura": 0.4, "aura_r": 520.0, "unique": 3, "names": ["Picton", "Uxbridge", "Hill", "Ponsonby", "Somerset", "Maitland"], "look": {"hat": "\"bicorne\"", "hat_col": "Color(0.08, 0.08, 0.09)", "plume": "Color(0.95, 0.95, 0.95)", "facing": "Color(0.85, 0.68, 0.28)", "big": 1.15}}),
    ("gb_wellington", "dragoons", {"aura": 0.3, "aura_r": 100000.0, "unique": 1, "fmt": "Wellington", "look": {"hat": "\"bicorne\"", "hat_col": "Color(0.08, 0.08, 0.09)", "plume": "Color(0, 0, 0, 0)", "coat": "Color(0.12, 0.13, 0.2)", "facing": "Color(0.93, 0.93, 0.9)", "big": 1.2}}),
    ("gb_kgl_line", "line", {"look": {"facing": "Color(0.1, 0.12, 0.3)"}}),
    ("gb_kgl_light", "rifles", {}),
    ("gb_kgl_hussars", "hussars", {"look": {"coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.8, 0.15, 0.12)"}}),
    ("gb_nl_carab", "dragoons", {"look": {"coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.8, 0.15, 0.12)", "hat_col": "Color(0.85, 0.68, 0.28)"}}),
    ("gb_brunswick", "line", {"look": {"coat": "Color(0.08, 0.08, 0.09)", "facing": "Color(0.45, 0.6, 0.8)", "plume": "Color(0.05, 0.05, 0.05)", "hat_col": "Color(0.05, 0.05, 0.05)"}}),
    ("gb_brunswick_hus", "hussars", {"look": {"coat": "Color(0.08, 0.08, 0.09)", "facing": "Color(0.45, 0.6, 0.8)", "plume": "Color(0.05, 0.05, 0.05)"}}),
    ("gb_cacadores", "light", {"look": {"coat": "Color(0.4, 0.28, 0.17)", "facing": "Color(0.08, 0.08, 0.08)", "plume": "Color(0.2, 0.4, 0.2)"}}),
    ("gb_port_line", "line", {"look": {"coat": "Color(0.12, 0.16, 0.38)", "facing": "Color(0.93, 0.93, 0.9)"}}),
]

BASE = {  # spacing, rank_spacing z typu bazowego
    "line": (9.0, 9.0), "light": (10.0, 9.0), "rifles": (11.0, 10.0), "militia": (9.0, 9.0), "grenadier": (9.0, 9.0), "guard": (9.0, 9.0),
    "hussars": (13.0, 15.0), "dragoons": (13.0, 15.0), "lancers": (13.0, 15.0), "cuirassiers": (14.0, 16.0),
    "artillery": (34.0, 7.0), "horse_art": (34.0, 7.0),
}
TIER_AI = {"T1": 1.0, "T2": 0.5, "T3": 0.25, "W": 0.08, "S": 0.4}
TIER_NAME = {"T1": "line", "T2": "elite", "T3": "guard", "W": "support", "S": "allies"}


def gd(v, raw=False):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 3))
    if isinstance(v, list):
        return "[" + ", ".join(gd(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (k, x if (raw and isinstance(x, str)) else gd(x, k == "look")) for k, x in v.items()) + "}"
    return json.dumps(v, ensure_ascii=False)


lines, order = [], []
rows = ROWS.splitlines()
assert len(rows) == len(META) == 38, (len(rows), len(META))
for row, (key, base, extra) in zip(rows, META):
    f = row.split("|")
    tier, cat, name = f[0], f[1], f[2]
    n, cost, upk, atk, df, chg, acc, rng, rel, fire, mor, spd = [int(x) for x in f[3:15]]
    desc = f[15]
    kind = {"Piechota": "inf", "Specjalne": "inf", "Kawaleria": "cav", "Dowódca": "cav", "Artyleria": "art"}[cat]
    if kind == "art":
        count, files = 16, 4
        accuracy = acc / 32.0
        frange = rng * 1.4
        reload = 14.0 * 15.0 / rel
        walk = 4.0 + 1.6 * spd
        run = walk * 1.35
    elif kind == "cav":
        count = max(8, round(n * 0.375))
        files = max(4, round(count / 2))
        accuracy, frange, reload = 1.0, 0.0, 1.0
        walk, run = 2.2 * spd, 4.6 * spd
    else:
        count = max(8, round(n * 0.3375))
        ranks = 2 if base in ("light", "rifles") else 3
        files = max(4, round(count / ranks))
        accuracy = max(0.05, acc / 40.0 * fire / 10.0)
        frange = rng * 2.1
        reload = 9.0 * 35.0 / rel if rel > 0 else 1.0
        walk, run = 13.0 + (spd - 6), 28.0 + 2.0 * (spd - 6)
    gcost = int(round(cost * 0.225 / 5.0) * 5)
    t = {
        "name": name, "kind": kind, "count": count, "files": files, "accuracy": accuracy,
        "melee": atk / 7.0, "defense": df / 7.0, "discipline": 0.4 + mor * 0.075,
        "spacing": BASE[base][0], "rank_spacing": BASE[base][1], "walk": walk, "run": run,
        "range": frange, "reload": reload, "cost": gcost, "upkeep": upk / 600.0,
        "time": float(round(12 + gcost * 0.1)),
        "city_only": not (tier == "T1" or key == "gb_port_line"),
        "charge": (chg / 15.5) if kind == "cav" else (0.6 + chg / 20.0),
        "base": base, "nation": 1, "tier": TIER_NAME[tier], "ai": TIER_AI[tier], "desc": desc, "pl": True,
    }
    if kind == "art":
        t["power"] = fire / 55.0
        t.pop("charge")
    extra = dict(extra)
    if "look" in extra:
        extra["look"] = dict(extra["look"])
    t.update(extra)
    order.append(key)
    lines.append('\t"%s": %s,' % (key, gd(t)))

out = "\t# --- Wielka Brytania: 38 jednostek z arkusza \"Britain – units and stats\" (generowane, gen_gb.py)\n" + "\n".join(lines) + "\n"
open(__file__.replace("gen_gb.py", "gb_units.txt"), "w", encoding="utf-8").write(out)
open(__file__.replace("gen_gb.py", "gb_order.txt"), "w", encoding="utf-8").write(gd(order))
print(out[:1200])
print(len(order))
