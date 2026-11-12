// SoldierKernel: szybka pętla żołnierzy pułku (ruch, zwrot, walka wręcz, teren, rozpychanie).
// Logika gry, która potrzebuje reszty świata (strzał, cios, utonięcie), wraca do GDScript jako lista zdarzeń.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class SoldierKernel : public RefCounted {
	GDCLASS(SoldierKernel, RefCounted)

	// teren (kopie tablic z Terrain, ustawiane raz na bitwę)
	PackedByteArray feat, ford, lake, mount, ravine, swamp, forest;
	int w = 0, h = 0, fw = 0, fh = 0;
	float cell = 16.0f, feat_sz = 8.0f;
	float lake_t = 0.82f, mount_t = 0.78f, swamp_t = 0.8f, forest_t = 0.64f;
	Vector2 map_size;
	float no_go = 285.0f;

	// stałe z regiment.gd (ustawiane raz)
	float soldier_accel = 16.0f, soldier_turn = 4.0f, soldier_arc = 0.61f, melee_reach = 7.0f;
	float horse_r = 9.0f, horse_pivot = 0.75f, horse_volte = 6.5f, horse_max_turn = 2.6f;
	float horse_dress = 11.0f, horse_dress_speed = 8.0f, drown_rate = 0.035f;
	float step_cycle = 16.0f, gallop_cycle = 22.0f, gallop_cycle_charge = 13.0f, rider_stuck = 0.3f;

protected:
	static void _bind_methods();

public:
	void set_terrain(const Dictionary &d);
	void set_constants(const Dictionary &d);

	int cell_at(const Vector2 &p) const;
	bool is_deep(const Vector2 &p) const;
	bool is_mountain(const Vector2 &p) const;
	bool is_water(const Vector2 &p) const;

	// Jeden przebieg żołnierzy pułku (piechota / jazda). reg = obiekt Regiment, prm = parametry pułku na ten krok.
	Dictionary update(Object *reg, const Dictionary &prm);
	// Rozpychanie wewnątrz pułku (zwarcie / ucieczka) i owalne konie w marszu.
	void separate(Object *reg, float min_d);
	void separate_horses(Object *reg);
	// Rozpychanie dwóch wrogich pułków w strefie styku.
	void separate_pair(Object *a, Object *b, float min_d, float share_a, float pad);
};

} // namespace godot
