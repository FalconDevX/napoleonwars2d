# Generuje wpisy UNIT_TYPES dla 39 jednostek Francji z arkusza "Francja – jednostki i statystyki".
# Skale arkusza przeliczane na skale gry (piechota liniowa = 1.0).
import json

# tier, kat, nazwa, licz, koszt, utrz, atak, obr, szarza, cel, zasieg, przel, ogien, morale, szyb, cechy
ROWS = """T1|Piechota|Fizylierzy liniowi|160|600|150|7|7|8|40|100|35|10|8|6|Linia, kolumna, czworobok
T1|Piechota|Lekka piechota (chasseurs)|160|700|170|6|6|7|45|110|40|10|8|7|Szyk luźny, czworobok
T1|Piechota|Woltyżerowie|120|650|160|5|4|5|55|120|45|10|7|8|Szyk luźny, ukrycie w lesie, ogień w ruchu
T1|Piechota|Gwardia Narodowa|160|350|90|4|5|4|30|90|30|9|5|6|+3 morale w obronie miasta
T1|Kawaleria|Szaserzy konni|80|700|180|9|5|18|25|50|20|8|8|15|Zwiad, pościg
T1|Kawaleria|Huzarzy|80|750|190|10|4|20|25|50|20|8|8|16|+5 szarży na uciekających
T1|Kawaleria|Dragoni|80|850|210|9|7|20|35|80|25|10|9|13|Mogą zsiąść i walczyć pieszo
T1|Artyleria|6-funtówki piesze|4|750|200|3|3|0|30|400|20|40|6|4|Kula, kartacz
T1|Artyleria|8-funtówki|4|900|220|3|3|0|32|500|15|55|6|3|Kula, kartacz
T2|Piechota|Grenadierzy liniowi|160|950|230|10|9|11|45|100|38|11|11|6|Szturm: +3 ataku wręcz, odporni na zmęczenie
T2|Piechota|Karabinierzy lekkiej piechoty|120|950|230|9|7|10|55|120|45|11|11|8|Szyk luźny, elita lekkiej piechoty
T2|Piechota|Saperzy|80|700|180|8|8|8|35|90|35|10|9|6|Burzenie umocnień, budowa szańców
T2|Kawaleria|Lansjerzy|80|950|220|9|5|28|0|0|0|0|9|15|+10 szarży vs piechota, łamią czworobok
T2|Kawaleria|Kirasjerzy|70|1300|300|12|10|30|20|40|15|8|11|12|Pancerz: -25% obrażeń od ognia
T2|Kawaleria|Karabinierzy konni|70|1400|320|13|11|30|25|40|15|8|12|12|Pancerz: -25% obrażeń od ognia
T2|Artyleria|12-funtówki|4|1200|260|3|3|0|35|600|12|70|6|3|Kula, kartacz, duży zasięg
T2|Artyleria|Artyleria konna|4|1100|250|4|4|0|30|380|22|40|8|10|Szybkie rozstawienie i zwinięcie
T2|Artyleria|Haubice|4|1000|230|3|3|0|25|450|15|60|6|3|Ogień stromotorowy, granaty zapalające
T3|Piechota|Tyralierzy Młodej Gwardii|160|1100|260|10|9|10|48|110|40|11|12|7|Szyk luźny
T3|Piechota|Fizylierzy-Grenadierzy Gwardii|160|1300|300|11|10|11|50|100|42|11|13|6|Solidna elita
T3|Piechota|Marynarze Gwardii|120|1200|280|11|9|10|48|100|40|11|13|7|Budowa mostów, +3 ataku w mieście
T3|Piechota|Strzelcy Piesi Gwardii|160|1700|380|13|12|12|60|110|48|12|15|6|Ogień plutonowy, nieustraszeni
T3|Piechota|Grenadierzy Pieszy Gwardii|160|1900|420|15|14|14|58|100|45|12|16|6|Nie łamią się; po rozbiciu -3 morale całej armii
T3|Kawaleria|Szaserzy Konni Gwardii|80|1400|320|13|8|24|35|50|22|9|14|16|Eskorta cesarza: +2 morale przy Napoleonie
T3|Kawaleria|Mamelucy|60|1300|300|15|7|24|30|50|20|9|13|16|Bonus wręcz, straszą wroga
T3|Kawaleria|Czerwoni Lansjerzy|80|1450|320|12|7|32|0|0|0|0|14|15|+10 szarży vs piechota, łamią czworobok
T3|Kawaleria|Dragoni Cesarzowej|80|1500|330|13|10|26|40|80|25|10|14|13|Mogą zsiąść i walczyć pieszo
T3|Kawaleria|Grenadierzy Konni Gwardii|70|1900|420|16|12|36|20|40|15|8|16|12|Decydująca szarża: +2 morale sojusznikom po udanej szarży
T3|Kawaleria|Żandarmeria Elitarna|60|1200|280|12|10|22|30|50|20|9|14|13|Aura: brak paniki w pobliżu
T3|Artyleria|Piesza Artyleria Gwardii (12-funt.)|4|1700|380|5|5|0|45|620|15|75|10|3|Wielka bateria: +10% celności z inną baterią obok
T3|Artyleria|Konna Artyleria Gwardii|4|1500|340|6|6|0|40|400|26|45|11|11|Szybkie rozstawienie
W|Specjalne|Pontonierzy|60|600|150|5|6|3|25|90|30|9|7|6|Budowa mostów
W|Specjalne|Latający ambulans Larreya|20|800|200|1|2|0|0|0|0|0|6|10|Leczy: +2% ludzi/min oddziałom w pobliżu
W|Dowódca|Marszałek|20|1500|300|14|12|25|30|40|20|8|15|15|Aura zależna od marszałka (Ney/Davout/Murat)
W|Dowódca|Napoleon|30|2500|500|15|13|28|30|40|20|8|18|15|Globalnie +2 morale; Słońce Austerlitz
S|Kawaleria|Szwoleżerowie polscy|80|1350|300|12|8|28|0|0|0|0|14|16|Somosierra: +10 szarży vs artyleria
S|Piechota|Pułk szwajcarski|160|900|220|9|9|9|45|100|38|11|12|6|+2 obrony i morale w obronie
S|Piechota|Legia Irlandzka|120|800|200|8|7|9|42|100|36|10|10|6|+2 morale vs Anglia
S|Piechota|Piechota westfalska|160|500|130|6|6|7|38|100|33|10|7|6|Tania piechota liniowa"""

# klucz, baza (wygląd/zachowanie), dodatki
META = [
    ("fr_fusiliers", "line", {}),
    ("fr_chasseurs", "light", {}),
    ("fr_voltigeurs", "light", {"look": {"plume": "Color(0.95, 0.85, 0.2)", "facing": "Color(0.95, 0.85, 0.2)"}}),
    ("fr_garde_nat", "militia", {}),
    ("fr_chass_cheval", "hussars", {"look": {"coat": "Color(0.13, 0.32, 0.2)", "hat": "\"shako\"", "hat_col": "Color(0.08, 0.08, 0.09)", "facing": "Color(0.8, 0.15, 0.12)", "plume": "Color(0.15, 0.45, 0.2)"}}),
    ("fr_hussars", "hussars", {"look": {"coat": "Color(0.55, 0.68, 0.85)", "hat": "\"shako\""}}),
    ("fr_dragoons", "dragoons", {"look": {"coat": "Color(0.13, 0.3, 0.18)", "facing": "Color(0.8, 0.15, 0.12)"}}),
    ("fr_art6", "artillery", {}),
    ("fr_art8", "artillery", {}),
    ("fr_grenadiers", "grenadier", {}),
    ("fr_carabiniers", "light", {"look": {"hat": "\"bearskin\"", "hat_col": "Color(0.13, 0.10, 0.08)", "plume": "Color(0.9, 0.1, 0.1)", "facing": "Color(0.9, 0.1, 0.1)"}}),
    ("fr_sappers", "line", {"look": {"plume": "Color(0.85, 0.15, 0.12)", "facing": "Color(0.1, 0.1, 0.12)"}}),
    ("fr_lancers", "lancers", {"look": {"coat": "Color(0.13, 0.3, 0.18)", "hat": "\"helmet\"", "hat_col": "Color(0.85, 0.68, 0.28)", "facing": "Color(0.85, 0.15, 0.12)", "plume": "Color(0.08, 0.06, 0.05)"}}),
    ("fr_cuirassiers", "cuirassiers", {"armor": 0.25}),
    ("fr_carab_cheval", "cuirassiers", {"armor": 0.25, "look": {"coat": "Color(0.93, 0.93, 0.9)", "facing": "Color(0.55, 0.68, 0.85)", "hat_col": "Color(0.85, 0.68, 0.28)", "plume": "Color(0.85, 0.15, 0.12)"}}),
    ("fr_art12", "artillery", {}),
    ("fr_horse_art", "horse_art", {}),
    ("fr_howitzers", "artillery", {"shell": 0.7}),
    ("fr_yg_tirailleurs", "light", {"look": {"plume": "Color(0.85, 0.15, 0.12)", "facing": "Color(0.85, 0.15, 0.12)"}}),
    ("fr_fus_gren", "guard", {"look": {"hat": "\"shako\"", "hat_col": "Color(0.08, 0.08, 0.09)", "big": 1.1}}),
    ("fr_marins", "line", {"look": {"coat": "Color(0.1, 0.14, 0.32)", "facing": "Color(0.95, 0.5, 0.15)", "plume": "Color(0.95, 0.5, 0.15)"}}),
    ("fr_chass_pied", "guard", {"look": {"plume": "Color(0.2, 0.55, 0.25)"}}),
    ("fr_gren_pied", "guard", {"steadfast": True}),
    ("fr_chass_garde", "hussars", {"look": {"coat": "Color(0.13, 0.32, 0.2)", "facing": "Color(0.95, 0.5, 0.15)", "plume": "Color(0.15, 0.45, 0.2)"}}),
    ("fr_mamelukes", "hussars", {"look": {"coat": "Color(0.8, 0.15, 0.13)", "hat": "\"round\"", "hat_col": "Color(0.95, 0.95, 0.92)", "facing": "Color(0.13, 0.42, 0.25)", "plume": "Color(0.95, 0.95, 0.95)", "belts": False}}),
    ("fr_red_lancers", "lancers", {"look": {"coat": "Color(0.82, 0.15, 0.13)", "facing": "Color(0.1, 0.14, 0.4)", "hat_col": "Color(0.82, 0.15, 0.13)"}}),
    ("fr_drag_imp", "dragoons", {"look": {"coat": "Color(0.13, 0.3, 0.18)", "facing": "Color(0.93, 0.93, 0.9)", "plume": "Color(0.85, 0.15, 0.12)"}}),
    ("fr_gren_cheval", "dragoons", {"look": {"hat": "\"bearskin\"", "hat_col": "Color(0.13, 0.10, 0.08)", "coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.95, 0.95, 0.95)", "plume": "Color(0.85, 0.15, 0.12)", "big": 1.15}}),
    ("fr_gendarmes", "dragoons", {"aura": 0.35, "aura_r": 320.0, "look": {"hat": "\"bearskin\"", "hat_col": "Color(0.13, 0.10, 0.08)", "coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.85, 0.15, 0.12)", "plume": "Color(0.85, 0.15, 0.12)"}}),
    ("fr_art_garde", "artillery", {"look": {"hat": "\"bearskin\"", "hat_col": "Color(0.13, 0.10, 0.08)"}}),
    ("fr_horse_art_garde", "horse_art", {}),
    ("fr_pontoniers", "line", {"look": {"plume": "Color(0.85, 0.15, 0.12)", "pack": False}}),
    ("fr_larrey", "line", {"heal": 0.02, "heal_r": 380.0, "unique": 1, "look": {"hat": "\"bicorne\"", "pack": False, "belts": False, "facing": "Color(0.6, 0.12, 0.12)"}}),
    ("fr_marshal", "dragoons", {"aura": 0.4, "aura_r": 520.0, "unique": 3, "names": ["Ney", "Davout", "Murat", "Lannes", "Masséna", "Soult"], "look": {"hat": "\"bicorne\"", "hat_col": "Color(0.08, 0.08, 0.09)", "plume": "Color(0.95, 0.95, 0.95)", "coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.85, 0.68, 0.28)", "big": 1.15}}),
    ("fr_napoleon", "dragoons", {"aura": 0.3, "aura_r": 100000.0, "unique": 1, "fmt": "Napoleon", "look": {"hat": "\"bicorne\"", "hat_col": "Color(0.08, 0.08, 0.09)", "plume": "Color(0, 0, 0, 0)", "coat": "Color(0.55, 0.55, 0.53)", "facing": "Color(0.13, 0.3, 0.18)", "big": 1.2}}),
    ("fr_pol_chevau", "lancers", {"look": {"coat": "Color(0.1, 0.12, 0.3)", "facing": "Color(0.8, 0.12, 0.15)", "hat_col": "Color(0.8, 0.12, 0.15)"}}),
    ("fr_swiss", "line", {"look": {"coat": "Color(0.78, 0.18, 0.14)", "facing": "Color(0.92, 0.75, 0.2)"}}),
    ("fr_irish", "line", {"look": {"coat": "Color(0.13, 0.4, 0.2)", "facing": "Color(0.92, 0.75, 0.2)"}}),
    ("fr_westphal", "line", {"look": {"coat": "Color(0.92, 0.91, 0.86)", "facing": "Color(0.1, 0.12, 0.3)"}}),
]

BASE = {  # spacing, rank_spacing z typu bazowego
    "line": (9.0, 9.0), "light": (10.0, 9.0), "militia": (9.0, 9.0), "grenadier": (9.0, 9.0), "guard": (9.0, 9.0),
    "hussars": (13.0, 15.0), "dragoons": (13.0, 15.0), "lancers": (13.0, 15.0), "cuirassiers": (14.0, 16.0),
    "artillery": (34.0, 7.0), "horse_art": (34.0, 7.0),
}
TIER_AI = {"T1": 1.0, "T2": 0.5, "T3": 0.25, "W": 0.08, "S": 0.4}
TIER_NAME = {"T1": "line", "T2": "elite", "T3": "guard", "W": "support", "S": "allies"}

def gd(v, raw=False):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 3))
    if isinstance(v, list):
        return "[" + ", ".join(gd(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join('"%s": %s' % (k, x if (raw and isinstance(x, str)) else gd(x, k == "look")) for k, x in v.items()) + "}"
    return json.dumps(v, ensure_ascii=False)

lines, order = [], []
for row, (key, base, extra) in zip(ROWS.splitlines(), META):
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
        ranks = 2 if base == "light" else 3
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
        "city_only": not (tier == "T1" or key == "fr_westphal"),
        "charge": (chg / 15.5) if kind == "cav" else (0.6 + chg / 20.0),
        "base": base, "nation": 0, "tier": TIER_NAME[tier], "ai": TIER_AI[tier], "desc": desc, "pl": True,
    }
    if kind == "art":
        t["power"] = fire / 55.0
        t.pop("charge")
    t.update({k: v for k, v in extra.items()})
    order.append(key)
    lines.append('\t"%s": %s,' % (key, gd(t)))

out = "\t# --- Francja: 39 jednostek z arkusza \"Francja – jednostki i statystyki\" (generowane, gen_fr.py)\n" + "\n".join(lines) + "\n"
open(__file__.replace("gen_fr.py", "fr_units.txt"), "w", encoding="utf-8").write(out)
open(__file__.replace("gen_fr.py", "fr_order.txt"), "w", encoding="utf-8").write(gd(order))
print(out[:1500])
print(len(order))
