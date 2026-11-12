// SoldierKernel - wierne przeniesienie Regiment._update_soldiers (piechota i jazda) do C++.
// Komentarze opisują zachowanie tak jak w regiment.gd; tam też jest wersja zapasowa (np. dla przeglądarki).
#include "soldier_kernel.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <unordered_map>
#include <vector>

using namespace godot;

namespace {

constexpr float PI_F = 3.14159265358979323846f;
constexpr float TAU_F = 6.28318530717958647692f;

inline float angle_diff(float from, float to) {
	float d = std::fmod(to - from, TAU_F);
	return std::fmod(2.0f * d, TAU_F) - d;
}

inline float rotate_toward(float from, float to, float delta) {
	float diff = angle_diff(from, to);
	float ad = std::fabs(diff);
	return from + std::clamp(delta, ad - PI_F, ad) * (diff >= 0.0f ? 1.0f : -1.0f);
}

inline float move_toward_f(float from, float to, float delta) {
	return std::fabs(to - from) <= delta ? to : from + (to > from ? delta : -delta);
}

inline Vector2 move_toward_v(const Vector2 &from, const Vector2 &to, float delta) {
	Vector2 vd = to - from;
	float len = vd.length();
	return (len <= delta || len < 1e-5f) ? to : from + vd / len * delta;
}

inline Vector2 limit_len(const Vector2 &v, float m) {
	float l = v.length();
	return (l > m && l > 0.0f) ? v * (m / l) : v;
}

inline float fposmod_f(float x, float y) {
	float v = std::fmod(x, y);
	if ((v < 0.0f && y > 0.0f) || (v > 0.0f && y < 0.0f)) {
		v += y;
	}
	return v;
}

inline float file_x(int k, int f) {
	// miejsce w szeregu liczone od środka na boki (0, +1, -1, +2, ...), jak Regiment.file_x
	if (f % 2 == 1) {
		return float((k + 1) / 2) * (k % 2 == 1 ? 1.0f : -1.0f);
	}
	return (k % 2 == 1) ? (0.5f + float(k / 2)) : (-0.5f - float(k / 2));
}

inline float randf_range(float a, float b) {
	return (float)UtilityFunctions::randf_range(a, b);
}

inline float randf() {
	return (float)UtilityFunctions::randf();
}

// tablice żołnierzy wrogiego pułku (tylko do odczytu w tym przebiegu)
struct Foe {
	Object *obj = nullptr;
	PackedVector2Array pos;
	PackedFloat32Array hp;
	bool dead = false;
};

} // namespace

void SoldierKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_terrain", "d"), &SoldierKernel::set_terrain);
	ClassDB::bind_method(D_METHOD("set_constants", "d"), &SoldierKernel::set_constants);
	ClassDB::bind_method(D_METHOD("cell_at", "p"), &SoldierKernel::cell_at);
	ClassDB::bind_method(D_METHOD("update", "reg", "prm"), &SoldierKernel::update);
	ClassDB::bind_method(D_METHOD("separate", "reg", "min_d"), &SoldierKernel::separate);
	ClassDB::bind_method(D_METHOD("separate_horses", "reg"), &SoldierKernel::separate_horses);
	ClassDB::bind_method(D_METHOD("separate_pair", "a", "b", "min_d", "share_a", "pad"), &SoldierKernel::separate_pair);
}

void SoldierKernel::set_terrain(const Dictionary &d) {
	feat = d["feat"];
	ford = d["ford"];
	lake = d["lake"];
	mount = d["mount"];
	ravine = d["ravine"];
	swamp = d["swamp"];
	forest = d["forest"];
	w = d["w"];
	h = d["h"];
	fw = d["fw"];
	fh = d["fh"];
	cell = d["cell"];
	feat_sz = d["feat_sz"];
	lake_t = d["lake_t"];
	mount_t = d["mount_t"];
	swamp_t = d["swamp_t"];
	forest_t = d["forest_t"];
	map_size = d["map_size"];
	no_go = d["no_go"];
}

void SoldierKernel::set_constants(const Dictionary &d) {
	soldier_accel = d["SOLDIER_ACCEL"];
	soldier_turn = d["SOLDIER_TURN"];
	soldier_arc = d["SOLDIER_ARC"];
	melee_reach = d["MELEE_REACH"];
	horse_r = d["HORSE_R"];
	horse_pivot = d["HORSE_PIVOT"];
	horse_volte = d["HORSE_VOLTE"];
	horse_max_turn = d["HORSE_MAX_TURN"];
	horse_dress = d["HORSE_DRESS"];
	horse_dress_speed = d["HORSE_DRESS_SPEED"];
	drown_rate = d["DROWN_RATE"];
	step_cycle = d["STEP_CYCLE"];
	gallop_cycle = d["GALLOP_CYCLE"];
	gallop_cycle_charge = d["GALLOP_CYCLE_CHARGE"];
	rider_stuck = d["RIDER_STUCK"];
}

// ------------------------------------------------------------------ teren (jak Terrain.cell_at i spółka)
// GRASS 0, FOREST 1, WATER 2, ROAD 3, MOUNTAIN 4, RAVINE 5, SWAMP 6, FORD 7

int SoldierKernel::cell_at(const Vector2 &p) const {
	int fx = int(p.x / feat_sz);
	int fy = int(p.y / feat_sz);
	if (p.x < 0.0f || p.y < 0.0f || fx < 0 || fy < 0 || fx >= fw || fy >= fh) {
		return 0;
	}
	int fi = (fy * fw + fx) * 4;
	if (feat[fi + 1] > 127) {
		return 3;
	}
	if (feat[fi] > 127) {
		return (!ford.is_empty() && ford[fy * fw + fx] != 0) ? 7 : 2;
	}
	int ci = int(p.y / cell) * w + int(p.x / cell);
	if (ci < 0 || ci >= lake.size()) {
		return 0;
	}
	if (lake[ci] > lake_t * 255.0f) {
		return 2;
	}
	if (mount[ci] > mount_t * 255.0f) {
		return 4;
	}
	if (ravine[fy * fw + fx] > 70) {
		return 5;
	}
	if (swamp[ci] > swamp_t * 255.0f) {
		return 6;
	}
	if (forest[ci] > forest_t * 255.0f) {
		return 1;
	}
	return 0;
}

bool SoldierKernel::is_deep(const Vector2 &p) const {
	if (p.x < 0.0f || p.y < 0.0f || p.x >= map_size.x || p.y >= map_size.y) {
		return false;
	}
	int fi = int(p.y / feat_sz) * fw + int(p.x / feat_sz);
	if (feat[fi * 4 + 1] > 127 || feat[fi * 4] <= 127) {
		return false;
	}
	return ford.is_empty() || ford[fi] == 0;
}

bool SoldierKernel::is_mountain(const Vector2 &p) const {
	if (p.x < 0.0f || p.y < 0.0f || p.x >= map_size.x || p.y >= map_size.y) {
		return false;
	}
	int fx = int(p.x / feat_sz);
	int fy = int(p.y / feat_sz);
	if (feat[(fy * fw + fx) * 4 + 1] > 127) {
		return false; // droga przez przełęcz
	}
	return mount[int(p.y / cell) * w + int(p.x / cell)] > mount_t * 255.0f;
}

bool SoldierKernel::is_water(const Vector2 &p) const {
	int c = cell_at(p);
	return c == 2 || c == 7;
}

// ------------------------------------------------------------------ przebieg żołnierzy

Dictionary SoldierKernel::update(Object *reg, const Dictionary &prm) {
	Dictionary out;
	if (reg == nullptr) {
		return out;
	}
	PackedVector2Array s_pos = reg->get("s_pos");
	PackedVector2Array s_vel = reg->get("s_vel");
	PackedFloat32Array s_aim = reg->get("s_aim");
	PackedFloat32Array s_hp = reg->get("s_hp");
	PackedFloat32Array s_reload = reg->get("s_reload");
	PackedFloat32Array s_cool = reg->get("s_cool");
	PackedVector2Array s_jit = reg->get("s_jit");
	PackedFloat32Array s_block = reg->get("s_block");
	PackedFloat32Array step = reg->get("_step");
	PackedFloat32Array react = reg->get("_react");
	Array s_tgt_reg = reg->get("s_tgt_reg");
	PackedInt32Array s_tgt_idx = reg->get("s_tgt_idx");
	const int n = s_pos.size();
	if (step.size() != n) {
		step.resize(n);
	}
	if (react.size() != n) {
		react.resize(n);
	}
	if (s_block.size() != n) {
		s_block.resize(n);
	}

	const float dt = prm["dt"];
	const bool cav = prm["cav"];
	const bool routing = prm["routing"];
	const bool in_melee = prm["in_melee"];
	const bool charging = prm["charging"];
	const bool moving = prm["moving"];
	const bool idle = prm["idle"];
	const bool retarget = prm["retarget"];
	const bool through = prm["through"];
	const bool disengaging = prm["disengaging"];
	const bool disengage_on = prm["disengage_on"];
	const bool direct = prm["direct"];
	const bool square = prm["square"];
	const Vector2 center = prm["center"];
	const float facing = prm["facing"];
	const float spacing = prm["spacing"];
	const float rank_spacing = prm["rank_spacing"];
	const float jitter_scale = prm["jitter_scale"];
	const int nfiles = std::max(1, (int)prm["nfiles"]);
	const float run_speed = prm["run_speed"];
	const float rout_speed = prm["rout_speed"];
	const float walk_direct = prm["walk_direct"];
	const float disengage_speed = prm["disengage_speed"];
	const float catch_up = prm["catch_up"];
	const Vector2 base_vel = prm["base_vel"];
	const Vector2 reg_vel = prm["reg_vel"];
	const bool reg_block_still = prm["reg_block_still"];
	const Vector2 flee_dir = prm["flee_dir"];
	const PackedFloat32Array mt = prm["mt"];
	const PackedVector2Array slots = prm["slots"];       // gotowe miejsca w szyku (kolumna/czworobok/klin) albo puste
	const PackedFloat32Array slot_aims = prm["slot_aims"]; // kierunki twarzy w czworoboku albo puste
	const bool has_fire = prm["has_fire_target"];
	const Vector2 fire_center = prm["fire_target_center"];
	const int fire_slots = prm["fire_slots"];
	const bool can_fire_kind = prm["inf"];
	const float cycle = cav ? (charging ? gallop_cycle_charge : gallop_cycle) : step_cycle;
	const float edge_m = no_go * 0.75f;
	const PackedVector2Array trail = reg->get("_path_trail");

	const Vector2 fwd = Vector2(std::cos(facing), std::sin(facing));
	const Vector2 rgt = Vector2(-fwd.y, fwd.x);
	const float turn_rate = soldier_turn * (cav ? 1.1f : 1.0f) * dt;

	PackedInt32Array ev_fire, ev_strike_i, ev_strike_j, ev_drown;
	Array ev_strike_reg;

	// --- walka wręcz: wrogowie w zasięgu i licznik "kto kogo atakuje" liczone raz na przebieg
	std::vector<Foe> foes;
	std::unordered_map<Object *, int> foe_index;
	std::vector<Vector2> mt_pos;
	std::vector<int> mt_foe, mt_j;
	std::unordered_map<int64_t, int> busy;
	bool mt_ready = false;
	float cand_reach = cav ? 30.0f : 22.0f;
	auto foe_of = [&](Object *o) -> int {
		auto it = foe_index.find(o);
		if (it != foe_index.end()) {
			return it->second;
		}
		Foe f;
		f.obj = o;
		f.pos = o->get("s_pos");
		f.hp = o->get("s_hp");
		f.dead = o->get("dead");
		foes.push_back(f);
		int k = int(foes.size()) - 1;
		foe_index[o] = k;
		return k;
	};
	auto key_of = [&](int foe, int j) -> int64_t { return (int64_t(foe) << 32) | uint32_t(j); };
	auto melee_prep = [&]() {
		mt_ready = true;
		Array enemies = reg->get("melee_enemies");
		for (int k = 0; k < enemies.size(); k++) {
			Object *e = enemies[k];
			if (e != nullptr && String(e->get("kind")) == String("art")) {
				cand_reach = cav ? 95.0f : 60.0f; // między działami każdy znajdzie swojego kanoniera
				break;
			}
		}
		// prostokąt naszego pułku powiększony o zasięg
		Vector2 mn = n > 0 ? s_pos[0] : center, mx = mn;
		for (int i = 0; i < n; i++) {
			mn = Vector2(std::min(mn.x, s_pos[i].x), std::min(mn.y, s_pos[i].y));
			mx = Vector2(std::max(mx.x, s_pos[i].x), std::max(mx.y, s_pos[i].y));
		}
		mn -= Vector2(cand_reach + 2.0f, cand_reach + 2.0f);
		mx += Vector2(cand_reach + 2.0f, cand_reach + 2.0f);
		for (int k = 0; k < enemies.size(); k++) {
			Object *e = enemies[k];
			if (e == nullptr) {
				continue;
			}
			int fi = foe_of(e);
			const Foe &f = foes[fi];
			if (f.dead) {
				continue;
			}
			for (int j = 0; j < f.pos.size(); j++) {
				const Vector2 q = f.pos[j];
				if (j < f.hp.size() && f.hp[j] > 0.0f && q.x >= mn.x && q.y >= mn.y && q.x <= mx.x && q.y <= mx.y) {
					mt_pos.push_back(q);
					mt_foe.push_back(fi);
					mt_j.push_back(j);
				}
			}
		}
		for (int k = 0; k < n; k++) {
			Object *t = s_tgt_reg[k];
			if (t != nullptr) {
				busy[key_of(foe_of(t), s_tgt_idx[k])] += 1;
			}
		}
	};
	auto find_target = [&](int i) {
		const Vector2 p = s_pos[i];
		float best_d = INFINITY;
		int best_c = -1;
		int64_t old_key = -1;
		Object *old = s_tgt_reg[i];
		if (old != nullptr) {
			old_key = key_of(foe_of(old), s_tgt_idx[i]);
		}
		const float reach_sq = cand_reach * cand_reach;
		for (size_t c = 0; c < mt_pos.size(); c++) {
			float d = p.distance_squared_to(mt_pos[c]);
			if (d > reach_sq) {
				continue; // za daleko: ten żołnierz zostaje w szeregu, nie przebija się przez swoich
			}
			const Foe &f = foes[mt_foe[c]];
			int j = mt_j[c];
			if (j >= f.hp.size() || f.hp[j] <= 0.0f) {
				continue;
			}
			int64_t key = key_of(mt_foe[c], j);
			auto it = busy.find(key);
			int crowd = (it == busy.end() ? 0 : it->second) - (key == old_key ? 1 : 0);
			if (crowd >= 2) {
				d += 900.0f * crowd; // zajęty przeciwnik: szukaj wolnego obok
			}
			if (d < best_d) {
				best_d = d;
				best_c = int(c);
			}
		}
		if (old_key >= 0) {
			busy[old_key] -= 1;
		}
		if (best_c >= 0) {
			busy[key_of(mt_foe[best_c], mt_j[best_c])] += 1;
			s_tgt_reg[i] = foes[mt_foe[best_c]].obj;
			s_tgt_idx.set(i, mt_j[best_c]);
		} else {
			s_tgt_reg[i] = Variant();
			s_tgt_idx.set(i, -1);
		}
	};

	Vector2 *P = s_pos.ptrw();
	Vector2 *V = s_vel.ptrw();
	float *A = s_aim.ptrw();
	float *R = s_reload.ptrw();
	float *C = s_cool.ptrw();
	float *B = s_block.ptrw();
	float *ST = step.ptrw();
	float *RE = react.ptrw();
	const Vector2 *J = s_jit.ptr();
	const float strike_reach = melee_reach + (cav ? 4.0f : 0.0f);

	float cohesion_sum = 0.0f;
	int blocked = 0, wet = 0, fast = 0, alive = 0;

	for (int i = 0; i < n; i++) {
		if (s_hp[i] <= 0.0f) {
			continue;
		}
		R[i] -= dt;
		C[i] -= dt;
		Vector2 p = P[i];
		Vector2 goal = p;
		float spd = run_speed;
		float aim = facing;
		bool free_move = true; // true = idzie samodzielnie do celu; false = trzyma miejsce w szyku
		float accel = soldier_accel * (cav ? 3.0f : 1.0f);
		const Vector2 jit = i < s_jit.size() ? J[i] : Vector2();

		auto formation_goal = [&]() -> Vector2 {
			if (!slots.is_empty() && i < slots.size()) {
				return slots[i];
			}
			float sx = file_x(i % nfiles, nfiles) * spacing + jit.x * jitter_scale;
			float sy = float(i / nfiles) * rank_spacing + jit.y * jitter_scale;
			return center + rgt * sx - fwd * sy;
		};

		if (routing) {
			Vector2 fd = flee_dir + jit * 0.5f;
			if (is_water(p + fd.normalized() * 24.0f) && !is_water(p)) {
				// woda tuż przed nim: biegnie wzdłuż brzegu w stronę bliższą kierunkowi ucieczki
				Vector2 side = Vector2(fd.y, -fd.x);
				fd = !is_water(p + side.normalized() * 24.0f) ? side : -side;
			}
			goal = p + fd * 40.0f;
			spd = rout_speed * (1.0f + jit.x * 0.1f);
			aim = flee_dir.angle();
			accel *= 1.5f;
		} else if (in_melee) {
			accel *= 2.0f;
			Object *er = s_tgt_reg[i];
			int ei = s_tgt_idx[i];
			bool valid = false;
			int fi = -1;
			if (er != nullptr) {
				fi = foe_of(er);
				const Foe &f = foes[fi];
				valid = !f.dead && ei >= 0 && ei < f.pos.size() && ei < f.hp.size() && f.hp[ei] > 0.0f;
			}
			if (retarget || !valid) {
				if (!mt_ready) {
					melee_prep();
				}
				find_target(i);
				er = s_tgt_reg[i];
				ei = s_tgt_idx[i];
				valid = er != nullptr;
				fi = valid ? foe_of(er) : -1;
			}
			if (!valid) {
				// nikogo w zasięgu: trzyma miejsce w szeregu (linia jako całość napiera na wroga)
				free_move = false;
				goal = formation_goal();
			} else {
				const Vector2 ep = foes[fi].pos[ei];
				float d = p.distance_to(ep);
				aim = (ep - p).angle();
				if (d > strike_reach) {
					goal = ep + (p - ep) / std::max(d, 0.001f) * strike_reach * 0.85f; // na długość broni, nie we wroga
					spd = run_speed * 0.8f;
				} else if (C[i] <= 0.0f) {
					// cios: szansę, obrażenia, morale i iskry liczy GDScript (zdarzenie)
					C[i] = randf_range(2.2f, 3.8f);
					ev_strike_i.push_back(i);
					ev_strike_reg.push_back(er);
					ev_strike_j.push_back(ei);
				}
			}
		} else {
			free_move = false;
			goal = formation_goal();
			if (square && i < slot_aims.size()) {
				aim = slot_aims[i];
			}
			if (idle && has_fire && (i < fire_slots || square)) {
				float ta = (fire_center - p).angle();
				aim += std::clamp(angle_diff(aim, ta), -soldier_arc, soldier_arc); // tułów obraca się tylko trochę
				// drobne zamykanie szeregu po stratach nie przerywa ognia - strzela, kto stoi prawie w miejscu
				if (can_fire_kind && R[i] <= 0.0f && V[i].length() < 6.0f && p.distance_squared_to(goal) < 64.0f) {
					ev_fire.push_back(i);
				}
			}
		}

		if (through && C[i] > rider_stuck) {
			// koń ugrzązł w szeregu wroga: nie wraca na miejsce w szyku, staje tam, gdzie uderzył
			free_move = true;
			goal = p;
		}
		if (B[i] > 0.0f) {
			blocked += 1;
			B[i] -= dt;
			if (!free_move) {
				// obejście zbocza: śladem, którym przeszedł środek pułku
				if (trail.is_empty()) {
					goal = center;
				} else {
					int best = 0;
					float bd = INFINITY;
					for (int k = 0; k < trail.size(); k++) {
						float d = p.distance_squared_to(trail[k]);
						if (d < bd) {
							bd = d;
							best = k;
						}
					}
					goal = trail[std::max(0, best - 3)];
				}
			}
		}
		if (direct && !free_move) {
			free_move = true;
			cohesion_sum += p.distance_to(goal);
			spd = walk_direct;
			if (disengage_on) {
				spd = std::max(spd, disengage_speed); // odwrót z walki: biegiem (jazda galopem)
			}
		}
		Vector2 to = goal - p;
		float dist = to.length();
		Vector2 desired;
		float personal = 1.0f + jit.x * (moving ? 0.12f : 0.05f);
		if (free_move) {
			desired = dist < 0.5f ? Vector2() : to / dist * std::min(spd, dist * 1.5f) * personal;
		} else {
			// idzie razem z blokiem + spokojna korekta do swojego miejsca
			cohesion_sum += dist;
			Vector2 corr = to * 0.9f;
			float cl = corr.length();
			if (cl > catch_up * personal) {
				corr = corr / cl * catch_up * personal;
			}
			desired = base_vel + corr;
			if (dist < 0.4f && reg_vel == Vector2()) {
				desired = Vector2();
			}
		}
		// żołnierz chodzi tylko przodem: najpierw obraca się w kierunku ruchu, potem idzie
		float heading = A[i];
		float want_speed = desired.length();
		float want_heading = want_speed > 1.5f ? desired.angle() : aim;
		float speed_now = 0.0f;
		Vector2 v;
		if (cav && !routing && dist < horse_dress && reg_block_still && std::fabs(angle_diff(heading, aim)) < 0.7f) {
			// równanie szeregu: koń tuż przy swoim miejscu dochodzi krokiem, łeb trzyma w stronę frontu
			Vector2 dress = limit_len(desired, horse_dress_speed);
			if (dist < 0.8f) {
				dress = Vector2();
			}
			v = move_toward_v(V[i], dress, accel * dt);
			speed_now = v.length();
			heading = rotate_toward(heading, aim, 1.6f * dt);
		} else {
			if (cav) {
				// koń skręca łukiem (ω = v / R), a stojąc obraca się na zadzie
				float omega = std::clamp(V[i].length() / horse_r, horse_pivot, horse_max_turn);
				if (disengaging) {
					omega = std::max(omega, 3.2f); // odwrót z walki: zawraca konia w miejscu
				}
				heading = rotate_toward(heading, want_heading, omega * dt);
			} else {
				// zwrot po ludzku: własne opóźnienie reakcji i tempo, wyhamowanie pod koniec zwrotu
				bool calm = !routing && !in_melee && !charging;
				float diff = std::fabs(angle_diff(heading, want_heading));
				if (diff < 0.06f) {
					RE[i] = 0.0f;
					heading = rotate_toward(heading, want_heading, turn_rate);
				} else {
					float pace = 0.72f + 0.56f * fposmod_f(jit.y * 5.31f + jit.x * 1.7f, 1.0f);
					if (!calm) {
						RE[i] = 1.0f;
						heading = rotate_toward(heading, want_heading, turn_rate * pace);
					} else {
						if (RE[i] == 0.0f && diff > 0.4f) {
							RE[i] = -(0.03f + fposmod_f(jit.x * 7.31f + jit.y * 3.17f, 1.0f) * 0.6f);
						}
						bool wait = false;
						if (RE[i] < 0.0f) {
							RE[i] += dt;
							if (RE[i] < 0.0f) {
								wait = true;
							} else {
								RE[i] = 1.0f;
							}
						}
						if (!wait) {
							heading = rotate_toward(heading, want_heading, turn_rate * pace * std::clamp(diff / 0.55f, 0.3f, 1.0f));
						}
					}
				}
			}
			float target_speed = 0.0f;
			if (want_speed > 1.5f) {
				float align = std::cos(angle_diff(heading, want_heading));
				if (cav) {
					target_speed = want_speed * std::clamp((align + 0.15f) / 1.15f, 0.12f, 1.0f);
				} else {
					target_speed = want_speed * std::clamp((align - 0.3f) / 0.7f, 0.0f, 1.0f);
				}
			}
			if (cav && !routing && std::fabs(angle_diff(heading, want_heading)) > 0.35f) {
				target_speed = std::max(target_speed, horse_volte); // mała wolta zamiast obrotu w miejscu
			}
			speed_now = move_toward_f(V[i].length(), target_speed, accel * dt);
			v = Vector2(std::cos(heading), std::sin(heading)) * speed_now;
		}
		V[i] = v;
		if (speed_now > 1.0f) {
			ST[i] += speed_now * dt / cycle; // faza kroku = przebyta droga / długość cyklu
		}
		if (speed_now < 0.01f) {
			V[i] = Vector2();
			A[i] = heading;
			continue; // stoi - teren nie ma znaczenia
		}
		int c = cell_at(p);
		if (c == 2 && is_deep(p)) {
			wet += 1;
			// toną ci, którzy wpadli w nurt w panice albo zepchnięci w zwarciu
			if ((routing || in_melee) && randf() < drown_rate * (cav ? 0.6f : 1.0f) * dt) {
				ev_drown.push_back(i);
			}
		}
		Vector2 stp = v * (c < mt.size() ? mt[c] : 1.0f) * dt;
		Vector2 np = p + stp;
		auto blocked_at = [&](const Vector2 &q) -> bool {
			if (!routing) {
				// krawędź mapy (mgła): tylko uciekający mogą tam wbiec
				if (q.x < edge_m || q.y < edge_m || q.x > map_size.x - edge_m || q.y > map_size.y - edge_m) {
					return true;
				}
			}
			return is_mountain(q);
		};
		if (blocked_at(np) && !blocked_at(p)) {
			// góry nie do przejścia: ślizg wzdłuż przeszkody albo stój
			if (!blocked_at(p + Vector2(stp.x, 0.0f))) {
				np = p + Vector2(stp.x, 0.0f);
			} else if (!blocked_at(p + Vector2(0.0f, stp.y))) {
				np = p + Vector2(0.0f, stp.y);
			} else {
				np = p;
				V[i] = Vector2();
			}
			B[i] = 1.5f;
		}
		P[i] = np;
		A[i] = heading;
	}

	if (through) {
		for (int i = 0; i < n; i++) {
			if (s_hp[i] > 0.0f) {
				alive += 1;
				if (V[i].length() > run_speed * 0.45f && C[i] <= rider_stuck) {
					fast += 1;
				}
			}
		}
	}

	reg->set("s_pos", s_pos);
	reg->set("s_vel", s_vel);
	reg->set("s_aim", s_aim);
	reg->set("s_reload", s_reload);
	reg->set("s_cool", s_cool);
	reg->set("s_block", s_block);
	reg->set("_step", step);
	reg->set("_react", react);
	if (in_melee) {
		reg->set("s_tgt_reg", s_tgt_reg);
		reg->set("s_tgt_idx", s_tgt_idx);
	}

	out["fire"] = ev_fire;
	out["strike_i"] = ev_strike_i;
	out["strike_reg"] = ev_strike_reg;
	out["strike_j"] = ev_strike_j;
	out["drown"] = ev_drown;
	out["cohesion_sum"] = cohesion_sum;
	out["blocked"] = blocked;
	out["wet"] = wet;
	out["momentum"] = through ? float(fast) / std::max(1.0f, float(alive)) : 1.0f;
	return out;
}

// ------------------------------------------------------------------ rozpychanie

void SoldierKernel::separate(Object *reg, float min_d) {
	PackedVector2Array s_pos = reg->get("s_pos");
	const int n = s_pos.size();
	Vector2 *P = s_pos.ptrw();
	const float md2 = min_d * min_d;
	for (int i = 0; i < n; i++) {
		for (int j = i + 1; j < n; j++) {
			Vector2 dv = P[i] - P[j];
			float d2 = dv.length_squared();
			if (d2 < md2 && d2 > 0.0001f) {
				float d = std::sqrt(d2);
				Vector2 push = dv / d * (min_d - d) * 0.5f;
				P[i] += push;
				P[j] -= push;
			}
		}
	}
	reg->set("s_pos", s_pos);
}

void SoldierKernel::separate_horses(Object *reg) {
	// koń z góry to wydłużony owal: mocno w bok, słabiej wzdłuż - szereg i kolumna zostają, konie nie zachodzą na siebie
	PackedVector2Array s_pos = reg->get("s_pos");
	PackedFloat32Array s_aim = reg->get("s_aim");
	const int n = s_pos.size();
	Vector2 *P = s_pos.ptrw();
	const float HALF_LEN = 6.6f, HALF_W = 3.4f;
	for (int i = 0; i < n; i++) {
		Vector2 fi = Vector2(std::cos(s_aim[i]), std::sin(s_aim[i]));
		Vector2 oi = Vector2(fi.y, -fi.x);
		Vector2 ci = P[i] + fi * 3.0f;
		for (int j = i + 1; j < n; j++) {
			Vector2 cj = P[j] + Vector2(std::cos(s_aim[j]), std::sin(s_aim[j])) * 3.0f;
			Vector2 dv = ci - cj;
			if (dv.length_squared() > 256.0f) {
				continue;
			}
			float along = dv.dot(fi);
			float across = dv.dot(oi);
			float ox = HALF_LEN * 2.0f - std::fabs(along);
			float oy = HALF_W * 2.0f - std::fabs(across);
			if (ox > 0.0f && oy > 0.0f) {
				Vector2 push;
				if (oy < ox) {
					push = oi * ((std::fabs(across) > 0.01f ? (across > 0 ? 1.0f : -1.0f) : 1.0f) * oy * 0.5f);
				} else {
					push = fi * ((std::fabs(along) > 0.01f ? (along > 0 ? 1.0f : -1.0f) : 1.0f) * ox * 0.5f);
				}
				P[i] += push * 0.5f;
				P[j] -= push * 0.5f;
			}
		}
	}
	reg->set("s_pos", s_pos);
}

void SoldierKernel::separate_pair(Object *a, Object *b, float min_d, float share_a, float pad) {
	// tylko żołnierze w strefie styku dwóch pułków (prostokąty powiększone o pad)
	PackedVector2Array pa = a->get("s_pos");
	PackedFloat32Array ha = a->get("s_hp");
	PackedVector2Array pb = b->get("s_pos");
	PackedFloat32Array hb = b->get("s_hp");
	if (pa.is_empty() || pb.is_empty()) {
		return;
	}
	auto rect = [&](const PackedVector2Array &p, Vector2 &mn, Vector2 &mx) {
		mn = p[0];
		mx = p[0];
		for (int i = 1; i < p.size(); i++) {
			mn = Vector2(std::min(mn.x, p[i].x), std::min(mn.y, p[i].y));
			mx = Vector2(std::max(mx.x, p[i].x), std::max(mx.y, p[i].y));
		}
		mn -= Vector2(pad, pad);
		mx += Vector2(pad, pad);
	};
	Vector2 amn, amx, bmn, bmx;
	rect(pa, amn, amx);
	rect(pb, bmn, bmx);
	Vector2 mn = Vector2(std::max(amn.x, bmn.x), std::max(amn.y, bmn.y));
	Vector2 mx = Vector2(std::min(amx.x, bmx.x), std::min(amx.y, bmx.y));
	if (mn.x >= mx.x || mn.y >= mx.y) {
		return;
	}
	auto inside = [&](const Vector2 &q) { return q.x >= mn.x && q.y >= mn.y && q.x <= mx.x && q.y <= mx.y; };
	std::vector<int> ia, ib;
	for (int i = 0; i < pa.size(); i++) {
		if (i < ha.size() && ha[i] > 0.0f && inside(pa[i])) {
			ia.push_back(i);
		}
	}
	if (ia.empty()) {
		return;
	}
	for (int j = 0; j < pb.size(); j++) {
		if (j < hb.size() && hb[j] > 0.0f && inside(pb[j])) {
			ib.push_back(j);
		}
	}
	if (ib.empty()) {
		return;
	}
	Vector2 *PA = pa.ptrw();
	Vector2 *PB = pb.ptrw();
	const float md2 = min_d * min_d;
	const float share_b = 1.0f - share_a;
	for (int i : ia) {
		Vector2 p = PA[i];
		for (int j : ib) {
			Vector2 dv = p - PB[j];
			float d2 = dv.length_squared();
			if (d2 >= md2 || d2 < 0.0001f) {
				continue;
			}
			float d = std::sqrt(d2);
			Vector2 push = limit_len(dv / d * (min_d - d), 4.0f);
			p += push * share_a;
			PB[j] -= push * share_b;
		}
		PA[i] = p;
	}
	a->set("s_pos", pa);
	b->set("s_pos", pb);
}
