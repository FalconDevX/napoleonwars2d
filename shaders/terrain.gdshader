shader_type canvas_item;
// Teren rysowany w całości na GPU: niskorozdzielcze mapy danych + kafelkowany szum detalu.
// Pola: działki (Voronoi z zawirowanymi granicami) dzielone na zagony, gęste przy osadach i drogach,
// rzadkie daleko od ludzi (tam dzikie łąki/wrzosowiska). Haszowanie pcg2d jest lustrzane w terrain.gd,
// więc CPU zna te same granice działek (drzewa w żywopłotach).

uniform sampler2D ground_tex : filter_linear;
uniform sampler2D forest_tex : filter_linear;
uniform sampler2D lake_tex : filter_linear;
uniform sampler2D mount_tex : filter_linear;
uniform sampler2D swamp_tex : filter_linear;
uniform sampler2D ravine_tex : filter_linear;
uniform sampler2D feat_tex : filter_linear;        // R = rzeka, G = droga, B = brzeg
uniform sampler2D ford_tex : filter_linear;        // płycizna (bród) przy mostach
uniform sampler2D farm_tex : filter_nearest;       // R = uprawy, G = kierunek zagonów (kąt/2π), B = rdzeń osady
uniform sampler2D farm_lin : filter_linear;        // ta sama mapa, wygładzona (przejścia pikseli)
uniform sampler2D detail_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 map_size = vec2(12000.0, 8000.0);
uniform vec2 data_texel = vec2(0.00133, 0.002);
uniform vec2 farm_scale = vec2(0.0000833, 0.000125);
uniform float forest_t = 0.64;
uniform float lake_t = 0.82;
uniform float mount_t = 0.74;
uniform float swamp_t = 0.80;
uniform int field_seed = 0;
uniform float field_cell = 470.0;
uniform vec4 warp_ph = vec4(0.0);
// Styl lekko pikselowy: teren próbkowany na siatce "pikseli" zakotwiczonej w świecie (nie pływa przy przesuwaniu).
// pix = rozmiar piksela w jednostkach świata — ustawiany z kamery (potęga dwójki ~2 piksele ekranu).
uniform float pix = 2.0;
uniform float color_levels = 32.0;   // posteryzacja kolorów (mniej = bardziej "retro")

// --- paleta motywu (teatr wojny / pora roku)
uniform vec3 grass_dark = vec3(0.25, 0.38, 0.16);
uniform vec3 grass_light = vec3(0.37, 0.48, 0.21);
uniform vec3 grass_dry = vec3(0.53, 0.56, 0.29);
uniform vec3 grass_wet = vec3(0.20, 0.36, 0.15);
uniform vec3 heath_c = vec3(0.38, 0.38, 0.21);
uniform float flowers = 1.0;
uniform vec3 flower_a = vec3(0.95, 0.88, 0.45);
uniform vec3 flower_b = vec3(0.88, 0.86, 0.95);
uniform vec3 crop_wheat = vec3(0.77, 0.66, 0.33);
uniform vec3 crop_plough = vec3(0.45, 0.34, 0.22);
uniform vec3 crop_veg = vec3(0.28, 0.45, 0.17);
uniform vec3 crop_hay = vec3(0.63, 0.62, 0.35);
uniform vec3 crop_pasture = vec3(0.33, 0.47, 0.19);
uniform vec4 crop_cum = vec4(0.32, 0.54, 0.68, 0.84);   // skumulowane udziały: pszenica, orka, warzywa, siano (reszta pastwisko)
uniform vec3 hedge_c = vec3(0.16, 0.29, 0.11);
uniform vec3 floor_a = vec3(0.12, 0.21, 0.08);
uniform vec3 floor_b = vec3(0.22, 0.20, 0.11);
uniform vec3 water_a = vec3(0.36, 0.55, 0.50);
uniform vec3 water_b = vec3(0.17, 0.38, 0.43);
uniform vec3 water_c = vec3(0.08, 0.22, 0.31);
uniform vec3 road_a = vec3(0.52, 0.43, 0.30);
uniform vec3 road_b = vec3(0.62, 0.53, 0.38);
uniform vec3 sand_c = vec3(0.63, 0.58, 0.42);
uniform float snow = 0.0;
uniform float desert = 0.0;
uniform float mud = 0.0;
uniform vec3 grade = vec3(1.0);
uniform float sat = 0.96;

float dlod(float scale) {
	// jawny poziom mipmapy: próbkowanie ze skokami (siatka pikseli) psuje automatyczny wybór → szwy
	return max(0.0, log2(pix * 512.0 / scale));
}

float detail(vec2 wp, float scale) {
	return textureLod(detail_tex, wp / scale, dlod(scale)).r;
}

// wygładzona wersja (wyższy poziom mipmapy): duże płaty bez postrzępionego "pieprzu" na krawędziach
float detail_s(vec2 wp, float scale) {
	return textureLod(detail_tex, wp / scale, dlod(scale) + 2.5).r;
}

float ridges_at(vec2 p) {
	return detail(p, 220.0) * 0.7 + detail(p, 80.0) * 0.3;
}

float bayer4(vec2 cell) {
	// macierz Bayera 4x4 → próg ditheringu 0..1
	ivec2 c = ivec2(mod(cell, 4.0));
	int i = c.x + c.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> uvec2(16u));
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> uvec2(16u));
	return v;
}

vec2 hcell(ivec2 c, int salt) {
	uvec2 h = pcg2d(uvec2(c + ivec2(field_seed, salt)));
	return vec2(h) * (1.0 / 4294967296.0);
}

vec2 fwarp(vec2 p) {
	return vec2(sin(p.y * 0.0041 + warp_ph.x) * 40.0 + sin(p.x * 0.0107 + warp_ph.y) * 14.0,
	            sin(p.x * 0.0037 + warp_ph.z) * 40.0 + sin(p.y * 0.0113 + warp_ph.w) * 14.0);
}

// Voronoi działek: zwraca odległość do granicy (w jednostkach świata), id komórki i jej środek.
float fvor(vec2 q, out ivec2 cid, out vec2 seed) {
	vec2 p = q / field_cell;
	vec2 n = floor(p);
	vec2 f = p - n;
	ivec2 ni = ivec2(n) + ivec2(1000);
	vec2 mr = vec2(0.0);
	ivec2 mg = ivec2(0);
	vec2 mo = vec2(0.5);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			ivec2 g = ivec2(i, j);
			vec2 o = hcell(ni + g, 0) * 0.9 + 0.05;
			vec2 r = vec2(g) + o - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; mo = o; }
		}
	}
	float edge = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			ivec2 g = mg + ivec2(i, j);
			vec2 o = hcell(ni + g, 0) * 0.9 + 0.05;
			vec2 r = vec2(g) + o - f;
			vec2 dd = r - mr;
			if (dot(dd, dd) > 0.00001) {
				edge = min(edge, dot(0.5 * (mr + r), normalize(dd)));
			}
		}
	}
	cid = ni + mg;
	seed = (n + vec2(mg) + mo) * field_cell;
	return edge * field_cell;
}

float lum3(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec2 wp_raw = UV * map_size;
	vec2 cell = floor(wp_raw / pix);
	vec2 wp = (cell + 0.5) * pix;          // środek "piksela" w świecie
	vec2 uv = wp / map_size;
	float d_big = detail(wp, 1400.0);
	float d_mid = detail(wp, 160.0);
	float d_fine = detail(wp, 24.0);
	float d_grain = detail(wp, 6.0);
	// ile jednostek świata przypada na piksel: drobne detale (kwiaty, trzciny, iskry) gasną z daleka
	float px = max(fwidth(wp_raw.x), pix * 0.5);
	float near = 1.0 - smoothstep(0.8, 2.5, px);
	float aa = smoothstep(2.5, 6.0, pix);    // wygaszenie drobnych wzorów z daleka (bez moiré)

	vec4 ft = texture(feat_tex, uv);
	float lake = texture(lake_tex, uv).r + (d_mid - 0.5) * 0.012;
	float sw = texture(swamp_tex, uv).r + (d_mid - 0.5) * 0.04;
	float mh = texture(mount_tex, uv).r + (d_mid - 0.5) * 0.03 + (d_fine - 0.5) * 0.015;
	vec4 farm_px = texture(farm_lin, uv * map_size * farm_scale);

	// --- dzika trawa: wilgotne niziny przy wodzie, suchsze płaty na wzniesieniach, wrzosowiska z dala od wsi
	float g = texture(ground_tex, uv).r;
	float wet = clamp(smoothstep(lake_t - 0.24, lake_t - 0.03, lake) + smoothstep(0.05, 0.6, ft.b) * 0.8
		+ smoothstep(swamp_t - 0.22, swamp_t, sw) * 0.6, 0.0, 1.0);
	float dry = smoothstep(0.42, mount_t - 0.03, mh);
	vec2 wq = wp + vec2(d_mid - 0.5, detail(wp + vec2(700.0, 300.0), 190.0) - 0.5) * 110.0;                 // zawirowanie → nieregularne płaty
	float pn = detail_s(wq + vec2(5000.0, 2100.0), 3200.0);
	float dryp = smoothstep(0.60, 0.66, pn);
	float lushp = smoothstep(0.40, 0.34, pn);
	vec3 col = mix(grass_dark, grass_light, clamp(g * 0.75 + d_big * 0.35 - 0.05, 0.0, 1.0));
	col = mix(col, grass_dry, max(dryp * 0.5, dry * 0.55));
	col = mix(col, grass_wet, clamp(wet * 0.75 + lushp * 0.4, 0.0, 1.0));
	float heath = (1.0 - smoothstep(0.02, 0.3, farm_px.r)) * smoothstep(0.54, 0.60, detail_s(wq + vec2(1300.0, 90.0), 2200.0));
	col = mix(col, heath_c * (0.85 + 0.3 * step(0.55, detail(wp + vec2(7.0, 3.0), 5.0))), heath * 0.6);
	col *= 0.90 + 0.20 * d_mid;
	col *= 0.93 + 0.14 * d_fine;
	// kępy trawy: ostre ciemne kępki i jasne źdźbła (z bliska)
	float tuft = step(0.63, detail(wp + vec2(71.0, 13.0), 9.0));
	col *= mix(1.0, 1.0 - 0.12 * tuft, near * 0.9 + 0.1);
	col *= mix(1.0, 0.94 + 0.12 * d_grain, near);
	// pustynia: zmarszczki wydm i rzadkie kępki suchych krzewinek
	float dune = sin(dot(wp, vec2(0.6, 0.8)) * 0.07 + d_mid * 16.0 + d_big * 9.0);
	col *= 1.0 + desert * 0.07 * dune * (1.0 - wet);
	float scrub = step(0.80, detail(wp + vec2(11.0, 500.0), 7.0)) * desert * (1.0 - aa * 0.5);
	col = mix(col, mix(vec3(0.40, 0.40, 0.22), vec3(0.30, 0.30, 0.17), d_grain), scrub * 0.75);
	// polne kwiaty w skupiskach
	float fl = detail(wp + vec2(333.0, 777.0), 2.4);
	float fpatch = smoothstep(0.58, 0.66, detail_s(wp + vec2(900.0), 900.0));
	float flower = step(0.78, fl) * fpatch * near * flowers;
	vec3 flower_c = mix(flower_a, flower_b, step(0.5, fract(fl * 37.0)));
	col = mix(col, flower_c, flower * 0.6);

	// --- działki i zagony
	vec2 q = wp + fwarp(wp);
	ivec2 cid;
	vec2 seed;
	float ed = fvor(q, cid, seed) + (d_fine - 0.5) * 3.0;
	vec2 hs = hcell(cid, 1);
	vec2 hs2 = hcell(cid, 2);
	vec4 fmc = texture(farm_tex, seed * farm_scale);
	float farm = fmc.r;
	float cultiv = step(hs.y, farm * 1.15 - 0.14);
	float enclosed = max(cultiv, step(hs.y, farm * 1.3 + 0.03));
	float in_core = smoothstep(0.4, 0.6, farm_px.b + (detail(wp + vec2(222.0, 0.0), 420.0) - 0.5) * 1.1 + (d_mid - 0.5) * 0.4 + (d_fine - 0.5) * 0.2);       // w obrębie zabudowy bez pól (zagrody rysuje osada)
	enclosed *= 1.0 - in_core;
	cultiv *= 1.0 - in_core;
	float ang = fmc.g * 6.2831853 + (hs.x - 0.5) * 0.7;
	vec2 fdir = vec2(cos(ang), sin(ang));                     // długa oś zagonów
	vec2 fnrm = vec2(-fdir.y, fdir.x);
	float strip_w = mix(24.0, 66.0, hs2.x) * mix(2.2, 1.0, farm);
	if (hs2.y < 0.28) { strip_w = 100000.0; }                // całe pole bez podziału
	float s = dot(q - seed, fnrm);
	float k = floor(s / strip_w);
	float fs = (s / strip_w - k) * strip_w;
	vec2 hk = hcell(cid + ivec2(int(k) * 17, int(k) * 31), 3);
	int crop = 4;
	if (cultiv > 0.5) {
		crop = hk.x < crop_cum.x ? 0 : (hk.x < crop_cum.y ? 1 : (hk.x < crop_cum.z ? 2 : (hk.x < crop_cum.w ? 3 : 4)));
	} else {
		crop = hs2.x < 0.4 ? 3 : 4;
	}
	float t_across = dot(q, fnrm);
	float t_along = dot(q, fdir);
	float tone = 0.93 + 0.14 * hk.y;                          // każdy zagon trochę inny
	vec3 fcol;
	if (crop == 0) {          // zboże: złote rzędy
		float rows = mix(step(0.5, fract(t_across / 5.0)), 0.5, aa);
		fcol = crop_wheat * tone * (0.88 + 0.16 * rows) * (0.94 + 0.12 * d_fine);
		fcol = mix(fcol, crop_wheat * 1.12, step(0.86, d_grain) * near * 0.5);
	} else if (crop == 1) {   // orka: ciemne i jasne bruzdy
		float rows = mix(step(0.5, fract(t_across / 6.0)), 0.5, aa);
		fcol = crop_plough * tone * (0.78 + 0.30 * rows) * (0.92 + 0.16 * d_fine);
		float puddle = smoothstep(0.70, 0.74, detail(wp + vec2(400.0, 60.0), 40.0)) * mud;
		fcol = mix(fcol, water_a * 0.8, puddle * 0.7);
	} else if (crop == 2) {   // warzywa: zielone rzędy kępek na ciemnej ziemi
		vec2 rc = vec2(fract(t_across / 9.0), fract(t_along / 7.0 + hk.y * 3.0));
		float plant = step(length((rc - 0.5) * vec2(1.0, 1.2)), 0.36);
		plant = mix(plant, 0.6, aa);
		vec3 soil = crop_plough * 0.95;
		fcol = mix(soil, crop_veg * (0.9 + 0.25 * d_fine) * tone, plant);
	} else if (crop == 3) {   // łąka kośna / siano: szerokie pasy pokosów
		float swath = mix(step(0.5, fract(t_across / 22.0 + hk.y)), 0.5, aa);
		fcol = crop_hay * tone * (0.94 + 0.09 * swath) * (0.92 + 0.16 * d_fine);
		fcol = mix(fcol, crop_hay * 0.8, step(0.82, detail(wp + vec2(3.0, 9.0), 4.0)) * near * 0.4);
	} else {                  // pastwisko: zielone, z ciemniejszymi kępami
		fcol = crop_pasture * tone * (0.88 + 0.22 * d_mid) * (0.92 + 0.14 * d_fine);
		fcol *= 1.0 - 0.12 * step(0.66, detail(wp + vec2(9.0, 51.0), 8.0));
		fcol = mix(fcol, flower_c, flower * 0.5);
	}
	// miedza między zagonami: wąski pas trawy
	float baulk = (1.0 - step(2.2, fs)) * step(strip_w, 9999.0) * cultiv * (1.0 - aa * 0.6);
	fcol = mix(fcol, mix(grass_light, crop_pasture, 0.5) * 0.92, baulk * 0.85);
	// skraj pola przy granicy: pas niekoszonej trawy
	fcol = mix(fcol, mix(col, grass_light, 0.3), (1.0 - smoothstep(5.0, 9.0, ed)) * 0.7);
	col = mix(col, fcol, enclosed);

	// --- żywopłoty z pojedynczych krzewów (ciemny obrys, światło z lewej-góry); w lukach płot z żerdzi
	float bn = detail(wp + vec2(41.0, 7.0), 11.0);
	float bn_l = detail(wp + vec2(38.0, 4.0), 11.0);
	float gap = step(detail(wp + vec2(300.0, 120.0), 170.0), 0.36);
	float hr = max(3.5 + 8.0 * bn, pix * 0.7) * (1.0 - gap);
	float outline_w = max(pix, 1.2) * (1.0 - aa);
	float hedge_in = step(ed, hr) * enclosed;
	float hedge_ol = step(ed, hr + outline_w) * enclosed * (1.0 - gap);
	float lit = clamp((bn - bn_l) * 9.0 + 0.5, 0.0, 1.0);
	float round_t = clamp((hr - ed) / max(hr, 0.1), 0.0, 1.0);
	vec3 hcol = hedge_c * (0.70 + 0.55 * lit) * (0.85 + 0.3 * round_t);
	hcol = mix(hcol, hedge_c * 1.5 + vec3(0.04, 0.04, 0.0), step(0.8, d_grain) * near * 0.4 * lit);
	col = mix(col, hedge_c * 0.45, hedge_ol * (1.0 - hedge_in));
	col = mix(col, hcol, hedge_in * (1.0 - step(hr, 0.01)));
	// płot w lukach żywopłotu: cienka żerdź i słupki
	float fence = gap * enclosed * (1.0 - step(1.1, ed)) * near;
	float post = gap * enclosed * (1.0 - step(2.0, ed)) * step(0.85, fract((q.x - q.y) / 15.0)) * near;
	col = mix(col, vec3(0.36, 0.27, 0.17), max(fence * 0.8, post));
	float hedge_mask = max(hedge_ol, fence);

	// --- poszycie lasu: mech i ściółka; trawa przy skraju lasu w cieniu koron
	float f = texture(forest_tex, uv).r + (d_mid - 0.5) * 0.05 + (d_fine - 0.5) * 0.03;
	float fm = smoothstep(forest_t - 0.012, forest_t + 0.012, f);
	float edge_shade = smoothstep(forest_t - 0.07, forest_t - 0.005, f) * (1.0 - fm);
	col *= 1.0 - 0.22 * edge_shade;
	vec3 floor_c = mix(floor_a, floor_b, smoothstep(0.45, 0.7, d_fine));
	floor_c *= 0.75 + 0.45 * d_mid;
	col = mix(col, floor_c, fm);

	// --- bagna: oliwkowa ziemia, zielonkawe zastoiska (nie niebieskie), kępy trzcin z jasnymi kitami
	float swm = smoothstep(swamp_t - 0.015, swamp_t + 0.015, sw);
	vec3 swamp_c = mix(grass_wet * vec3(1.1, 0.9, 1.0), grass_wet * vec3(1.4, 1.1, 1.2), d_fine);
	float puddle = smoothstep(0.60, 0.65, d_mid * 0.6 + d_fine * 0.5);
	vec3 pud_c = mix(water_b * vec3(1.0, 0.75, 0.55), water_a * vec3(0.8, 0.7, 0.6), detail(wp + vec2(TIME * 2.0), 40.0));
	swamp_c = mix(swamp_c, pud_c, puddle * 0.9);
	float reedn = detail(wp + vec2(57.0, 3.0), 7.0);
	swamp_c = mix(swamp_c, grass_wet * 0.8, smoothstep(0.58, 0.68, reedn) * (1.0 - puddle) * 0.75);
	swamp_c = mix(swamp_c, vec3(0.62, 0.58, 0.34), step(0.80, d_grain) * (1.0 - puddle) * 0.45 * near);
	col = mix(col, swamp_c, swm);

	// --- drogi: pobocze (wydeptana trawa), nawierzchnia z koleinami i kałużami (motyw błotnisty)
	float roadv = ft.g + (d_fine - 0.5) * 0.15;
	float road = smoothstep(0.30, 0.55, roadv);
	float verge = smoothstep(0.12, 0.30, roadv) * (1.0 - road);
	col = mix(col, col * vec3(0.92, 0.90, 0.80) + vec3(0.03, 0.02, 0.0), verge * 0.7);
	vec3 road_c = mix(road_a, road_b, d_fine) * (0.92 + 0.12 * d_grain);
	float rut = smoothstep(0.86, 0.9, roadv) * (1.0 - smoothstep(0.93, 0.97, roadv));
	road_c *= 1.0 - 0.10 * rut;
	road_c = mix(road_c, road_a * 0.75, smoothstep(0.62, 0.7, detail(wp + vec2(17.0, 90.0), 30.0)) * 0.35);
	float rpud = smoothstep(0.70, 0.74, detail(wp + vec2(800.0, 3.0), 26.0)) * mud * step(0.6, roadv);
	road_c = mix(road_c, mix(water_a, vec3(0.62, 0.66, 0.66), 0.4), rpud * 0.75);
	col = mix(col, road_c, road * 0.95);

	// --- śnieg: przykrywa łąki i pola (wzór bruzd prześwituje), żywopłoty i drogi zostają ciemniejsze
	if (snow > 0.0) {
		float l0 = lum3(col);
		// cień zasp: łagodne fałdy z szumu + wzór bruzd pól (bez drobnego "pieprzu" z kępek trawy)
		float drift = clamp(0.62 + (d_mid - 0.5) * 0.7 + (d_big - 0.5) * 0.4, 0.0, 1.0);
		float furrow = enclosed * clamp((lum3(fcol) - lum3(crop_pasture)) * 1.2, -0.25, 0.25);
		vec3 snow_c = mix(vec3(0.70, 0.76, 0.87), vec3(0.95, 0.96, 0.99), clamp(drift + furrow, 0.0, 1.0));
		float bare = smoothstep(0.66, 0.70, detail_s(wq + vec2(77.0, 4410.0), 2600.0));
		float cover = snow * (1.0 - bare * 0.45) * (1.0 - hedge_mask * mix(0.5, 0.15, aa)) * (1.0 - road * 0.45) * (1.0 - fm);
		col = mix(col, snow_c, cover);
	}


	// --- wąwozy (styl pikselowy): ostre progi zamiast rozmytej plamy; oświetlony dolny-prawy stok
	// (zwrócony ku światłu z lewej-góry), zacieniony górny-lewy stok z odsłoniętą skałą/ziemią,
	// ciemniejsze dno z kamykami, krawędź z kamieniami i krzakami. Szerokość meandruje (szum).
	float rv = texture(ravine_tex, uv).r;
	if (rv > 0.03) {
		float rv_l = texture(ravine_tex, uv + vec2(-12.0, -12.0) / map_size).r;
		float rv_r = texture(ravine_tex, uv + vec2(12.0, 12.0) / map_size).r;
		float rvn = rv + (detail_s(wp + vec2(31.0, 7.0), 500.0) - 0.5) * 0.24 + (d_fine - 0.5) * 0.05;
		float rsl = (rv_r - rv_l) * 3.0;
		float rim_m = step(0.09, rvn) - step(0.22, rvn);
		float floor_m = step(0.62, rvn);
		float bank_m = step(0.22, rvn) - floor_m;
		vec3 earth = mix(road_a * 0.85, sand_c * 0.8, desert);
		vec3 rockc = mix(vec3(0.47, 0.45, 0.41), vec3(0.62, 0.52, 0.38), desert);
		float rocky = step(0.58, detail(wp + vec2(5.0, 80.0), 7.0));
		float lit_b = step(rsl, -0.05);
		float shd_b = step(0.05, rsl);
		vec3 bank_c = mix(earth, rockc, rocky * 0.7);
		bank_c *= mix(0.86, 1.22, lit_b) * mix(1.0, 0.55, shd_b);
		vec3 floor_c2 = earth * 0.68 * (0.9 + 0.2 * d_fine);
		floor_c2 = mix(floor_c2, rockc * 0.9, step(0.82, d_grain) * near);
		vec3 rim_c = col * 0.88;
		rim_c = mix(rim_c, rockc * (0.8 + 0.4 * step(0.5, d_grain)), step(0.76, detail(wp + vec2(60.0, 2.0), 5.0)));
		rim_c = mix(rim_c, hedge_c * 1.1, step(0.74, detail(wp + vec2(9.0, 33.0), 10.0)) * (1.0 - desert * 0.6));
		if (snow > 0.0) {
			vec3 sn = vec3(0.90, 0.93, 0.98);
			bank_c = mix(bank_c, sn * mix(0.84, 1.03, lit_b), snow * (1.0 - shd_b * 0.72) * (1.0 - rocky * shd_b * 0.25));
			floor_c2 = mix(floor_c2, sn * 0.80 * (0.95 + 0.08 * d_fine), snow * 0.9);
			rim_c = mix(rim_c, sn * 0.95, snow * 0.6 * (1.0 - step(0.76, detail(wp + vec2(60.0, 2.0), 5.0))));
		}
		vec3 rcol = col;
		rcol = mix(rcol, rim_c, rim_m);
		rcol = mix(rcol, bank_c, bank_m);
		rcol = mix(rcol, floor_c2, floor_m);
		// ciemny obrys górnej krawędzi stoku (jak w pixel-arcie)
		float edge_l = step(0.22, rvn) * (1.0 - step(0.22 + 0.03 * max(pix, 1.0) / 2.0, rvn));
		rcol = mix(rcol, earth * 0.35, edge_l * 0.8);
		col = rcol;
	}

	// --- góry: cieniowanie rzeźby z mapy wysokości, skały, śnieg na szczytach
	float hx = texture(mount_tex, uv + vec2(data_texel.x, 0.0)).r - texture(mount_tex, uv - vec2(data_texel.x, 0.0)).r;
	float hy = texture(mount_tex, uv + vec2(0.0, data_texel.y)).r - texture(mount_tex, uv - vec2(0.0, data_texel.y)).r;
	// rzeźba: duże zbocza z mapy wysokości + drobne żebra skalne z szumu (pochodne w przestrzeni świata)
	float ridges = ridges_at(wp);
	float gstep = max(pix, 2.0);
	vec2 wgrad = vec2(ridges_at(wp + vec2(gstep, 0.0)) - ridges, ridges_at(wp + vec2(0.0, gstep)) - ridges) / gstep;
	float fine_relief = clamp(-(wgrad.x + wgrad.y) * 22.0, -0.35, 0.35);
	float relief = clamp(0.55 - (hx + hy) * 22.0, 0.05, 1.3);
	relief = clamp(relief + fine_relief * smoothstep(mount_t - 0.03, mount_t + 0.05, mh), 0.0, 1.4);
	float foot = smoothstep(mount_t - 0.12, mount_t, mh);
	float rock = smoothstep(mount_t - 0.006, mount_t + 0.006, mh);
	vec3 hill_c = col * (0.75 + 0.5 * relief);
	col = mix(col, hill_c, foot);
	vec3 rock_c = mix(vec3(0.42, 0.39, 0.35), vec3(0.58, 0.55, 0.50), d_fine) * (0.55 + 0.75 * relief);
	rock_c = mix(rock_c, rock_c * vec3(1.25, 1.1, 0.85), desert * 0.6);     // piaskowiec na pustyni
	rock_c *= 0.9 + 0.2 * d_grain;
	// zima: śnieg na łagodnych/oświetlonych zboczach, ciemna skała tylko na stromych zacienionych
	rock_c = mix(rock_c, vec3(0.90, 0.92, 0.97) * (0.72 + 0.3 * relief), snow * smoothstep(0.35, 0.7, relief + (d_fine - 0.5) * 0.3) * 0.9);
	float snowcap = smoothstep(mount_t + 0.13 - snow * 0.1, mount_t + 0.16 - snow * 0.1, mh + (d_fine - 0.5) * 0.04);
	rock_c = mix(rock_c, vec3(0.93, 0.94, 0.97) * (0.75 + 0.3 * relief), snowcap);
	col = mix(col, rock_c, rock);
	col = mix(col, col * 0.6, (1.0 - smoothstep(0.0, 0.008, abs(mh - mount_t))) * 0.6);  // krawędź skał

	// --- brzegi: bujniejsza trawa i trzciny nad wodą, wąski pas mokrego piasku/mułu tuż przy linii wody
	float rv_f = ft.r + (d_mid - 0.5) * 0.05 + (d_fine - 0.5) * 0.03;
	float bankb = max(smoothstep(0.2, 0.7, ft.b), smoothstep(lake_t - 0.07, lake_t - 0.03, lake)) * (1.0 - road);
	col = mix(col, col * vec3(0.82, 1.0, 0.78), bankb * 0.45 * (1.0 - snow));
	float reed = smoothstep(0.60, 0.70, detail(wp + vec2(91.0, 17.0), 6.0)) * bankb * (1.0 - snow * 0.85);
	vec3 reed_c = mix(vec3(0.30, 0.40, 0.16), vec3(0.62, 0.56, 0.36), snow * 0.7);
	col = mix(col, reed_c * (0.85 + 0.3 * d_grain), reed * 0.6);
	col = mix(col, vec3(0.66, 0.62, 0.38), reed * step(0.78, d_grain) * near * 0.5);
	float sand = max(smoothstep(0.22, 0.44, rv_f), smoothstep(lake_t - 0.03, lake_t - 0.004, lake)) * (1.0 - road);
	vec3 sand_col = mix(sand_c, sand_c * 0.68, smoothstep(0.55, 1.0, sand)) * (0.9 + 0.2 * d_fine);
	col = mix(col, sand_col, sand * 0.85);

	// --- woda: płycizna (widać dno), głębia ciemna; fale z cieniowaniem, odbicie nieba, iskry słońca
	float river = smoothstep(0.44, 0.50, rv_f);
	float lake_w = smoothstep(lake_t - 0.004, lake_t + 0.004, lake);
	float w = max(river, lake_w);
	float ford = smoothstep(0.05, 0.9, texture(ford_tex, uv).r) * river;
	float depth = max(smoothstep(0.48, 0.95, ft.r) * (1.0 - ford * 0.85), smoothstep(lake_t, lake_t + 0.07, lake));
	vec3 water = mix(water_a, water_b, smoothstep(0.0, 0.4, depth));
	water = mix(water, water_c, smoothstep(0.4, 1.0, depth));
	// dno w płyciźnie: piasek i kamyki prześwitujące przez wodę
	float bottom = 1.0 - smoothstep(0.0, 0.4, depth);
	vec3 bed = mix(sand_c * 0.9, sand_c * 0.72, smoothstep(0.4, 0.7, d_mid)) * (0.92 + 0.16 * d_fine);
	water = mix(water, bed, bottom * 0.38);
	vec2 flow = vec2(TIME * 0.010, TIME * 0.016);
	float h1 = textureLod(detail_tex, wp / 110.0 + flow, dlod(110.0)).r;
	float h2 = textureLod(detail_tex, wp / 38.0 - flow * 1.7, dlod(38.0)).r;
	float h1o = textureLod(detail_tex, (wp + vec2(3.0)) / 110.0 + flow, dlod(110.0)).r;
	float h2o = textureLod(detail_tex, (wp + vec2(3.0)) / 38.0 - flow * 1.7, dlod(38.0)).r;
	float slope = (h1 - h1o) * 0.65 + (h2 - h2o) * 0.35;
	water *= 1.0 + clamp(slope * 7.0, -0.08, 0.08);                                   // światło z lewej-góry na falach
	water = mix(water, vec3(0.58, 0.70, 0.76), smoothstep(0.55, 0.9, detail(wp + vec2(TIME * 3.0), 900.0)) * 0.13);
	float spark = smoothstep(0.80, 0.88, h1 * h2 * 1.65) * smoothstep(0.15, 0.5, depth);
	water += vec3(0.32, 0.32, 0.28) * spark * mix(0.5, 1.0, near) * (1.0 - snow * 0.6);
	// piana: przy linii brzegu i na kamieniach w brodzie
	float foam_n = smoothstep(0.60, 0.80, textureLod(detail_tex, wp / 20.0 + vec2(TIME * 0.03, -TIME * 0.02), dlod(20.0)).r);
	float rim = w * (1.0 - smoothstep(0.0, 0.07, depth));
	water = mix(water, vec3(0.84, 0.89, 0.86), (rim * 0.22 + ford * 0.10) * foam_n * mix(0.4, 1.0, near));
	// zima: kra i lód przy brzegach
	float ice = snow * max(rim * 1.4, smoothstep(0.72, 0.75, detail(wp + vec2(TIME * 0.6, TIME * 1.1), 70.0)) * 0.55 * (1.0 - smoothstep(0.3, 0.8, depth)));
	water = mix(water, vec3(0.80, 0.86, 0.92) * (0.9 + 0.15 * d_fine), clamp(ice, 0.0, 0.85));
	col = mix(col, water, w);

	// --- grading w stylu ilustracji: nasycone, głębokie kolory, ciepłe światło
	col *= grade;
	float lum = lum3(col);
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * 1.06 + 0.49;
	// --- posteryzacja z ditheringiem na siatce pikseli (lekko pikselowy wygląd)
	col = floor(col * color_levels + bayer4(cell)) / color_levels;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
