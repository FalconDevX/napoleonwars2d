class_name Net
extends Node
## Gra sieciowa: bitwy drużynowe do 8 graczy (Francja kontra Wielka Brytania), ENet/UDP.
## Host (gracz albo serwer dedykowany bez okna) liczy całą bitwę i ~10 razy na sekundę rozsyła stan (snapshot);
## pozostali tylko wyświetlają (płynnie interpolując ruch) i odsyłają rozkazy dla SWOICH pułków.
## Każdy gracz lokalnie widzi swoją stronę jako drużynę 0 — gracze strony 1 zamieniają drużyny przy odczycie.
## Przed bitwą działa lobby: lista graczy, wybór strony, gotowość.

const PORT := 24567
const SNAP_EVERY := 0.1
const MAX_PLAYERS := 8
const LOBBY_AFTER := 20.0     # serwer dedykowany: po tylu sekundach od końca bitwy wraca do lobby

enum Role { NONE, HOST, CLIENT }

static var inst: Net
static var dedicated_args := false   # uruchomiono z --server

var role := Role.NONE
var dedicated := false      # host bez lokalnego gracza (serwer)
var connected := false      # gość: połączony z hostem
var in_match := false       # trwa bitwa sieciowa
var status := ""
var battle: Battle
var players := {}           # id -> {"name", "team", "ready"}   (team: drużyna z punktu widzenia hosta)
var settings := {}          # ustawienia bitwy hosta (do wyświetlenia w lobby)
var my_team := 0            # gość: moja drużyna wg hosta
var host_nations := [0, 1]   # nacje drużyn 0 i 1 (z punktu widzenia hosta)
var ev: Array = []          # zdarzenia efektów/dźwięków do wysłania z najbliższym snapshotem
var _snap_acc := 0.0
var _snap_age := 0.0
var _first_snap := true
var _swap := false          # gość strony 1: zamiana drużyn przy odczycie
var _end_t := -1.0
var _countdown := -1.0
var my_name := ""


static func ensure(tree: SceneTree) -> void:
	if inst == null:
		inst = Net.new()
		inst.name = "Net"
		tree.root.add_child.call_deferred(inst)


static func active() -> bool:
	## Trwa bitwa sieciowa (w lobby gra lokalna działa normalnie).
	return inst != null and inst.role != Role.NONE and inst.in_match and (inst.role == Role.HOST or inst.connected)


static func is_host() -> bool:
	return active() and inst.role == Role.HOST


static func is_client() -> bool:
	return active() and inst.role == Role.CLIENT


static func my_id() -> int:
	if inst == null or inst.role == Role.NONE or inst.multiplayer.multiplayer_peer == null:
		return 1
	return inst.multiplayer.get_unique_id()


static func record(e: Array) -> void:
	if is_host():
		inst.ev.append(e)


static func server_idle() -> bool:
	## Serwer dedykowany w lobby: nie liczy żadnej bitwy.
	return inst != null and inst.role == Role.HOST and inst.dedicated and not inst.in_match


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)
	my_name = OS.get_environment("USERNAME")
	if my_name == "":
		my_name = "Player %d" % (randi() % 1000)


func _log(t: String) -> void:
	status = t
	if dedicated:
		print("[server] ", t)


# ------------------------------------------------------------------ łączenie

func host_game(as_server := false, port := PORT) -> void:
	stop()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(port, MAX_PLAYERS)
	if err != OK:
		status = "Could not open port %d (error %d)" % [port, err]
		print(status)
		return
	multiplayer.multiplayer_peer = p
	role = Role.HOST
	dedicated = as_server
	players.clear()
	if not dedicated:
		players[1] = {"name": my_name, "team": 0, "ready": true}
	_update_settings()
	_log("Lobby open on port %d.  Your IP: %s" % [port, ", ".join(local_ips())])
	_broadcast_lobby()


func join_game(ip: String, port := PORT) -> void:
	stop()
	ip = ip.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	if ":" in ip:
		var parts := ip.split(":")
		ip = parts[0]
		port = int(parts[1])
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port)
	if err != OK:
		status = "Could not connect (error %d)" % err
		return
	multiplayer.multiplayer_peer = p
	role = Role.CLIENT
	status = "Connecting to %s:%d..." % [ip, port]


func stop() -> void:
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	role = Role.NONE
	connected = false
	in_match = false
	dedicated = false
	players.clear()
	status = ""
	ev.clear()


static func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out


func _update_settings() -> void:
	settings = {"size": Battle.chosen_size, "map": Battle.chosen_map, "scenario": Battle.chosen_scenario, "theme": Battle.chosen_theme,
		"nations": [int(Battle.side_nation[0]), int(Battle.side_nation[1])]}
	host_nations = settings["nations"]


func _on_peer_connected(id: int) -> void:
	if role != Role.HOST:
		return
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# nowy gracz: na stronę, gdzie jest mniej ludzi
	var cnt := [0, 0]
	for p in players.values():
		cnt[p["team"]] += 1
	players[id] = {"name": "Player %d" % (players.size() + 1), "team": 0 if cnt[0] < cnt[1] or (dedicated and cnt[0] == cnt[1]) else 1, "ready": false}
	_log("%s connected (%d players)" % [players[id]["name"], players.size()])
	_broadcast_lobby()


func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST or not players.has(id):
		return
	var p: Dictionary = players[id]
	players.erase(id)
	_log("%s left (%d players)" % [p["name"], players.size()])
	if in_match and battle != null:
		battle.player_left(id, p["team"], p["name"])
		if players.is_empty() or (not dedicated and players.size() == 1):
			# nie ma już z kim grać — host gra dalej sam z AI / serwer wraca do lobby
			if dedicated:
				end_match()
				return
			in_match = false
	_broadcast_lobby()


func _on_connected() -> void:
	connected = true
	status = "Connected - lobby"
	_r_hello.rpc_id(1, my_name)


func _on_failed() -> void:
	stop()
	status = "Connection failed - check the address and that UDP port %d is open on the host" % PORT


func _on_server_lost() -> void:
	var was := in_match
	stop()
	status = "Host disconnected"
	if was and battle != null and battle.result_text == "":
		battle.result_text = "DISCONNECTED"


# ------------------------------------------------------------------ lobby

@rpc("any_peer", "call_remote", "reliable")
func _r_hello(pname: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if role == Role.HOST and players.has(id):
		players[id]["name"] = pname.strip_edges().left(20) if pname.strip_edges() != "" else players[id]["name"]
		_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _r_side(team: int) -> void:
	_set_side(multiplayer.get_remote_sender_id(), team)


@rpc("any_peer", "call_remote", "reliable")
func _r_ready(on: bool) -> void:
	var id := multiplayer.get_remote_sender_id()
	if role == Role.HOST and players.has(id) and not in_match:
		players[id]["ready"] = on
		_broadcast_lobby()


func _set_side(id: int, team: int) -> void:
	if role != Role.HOST or not players.has(id) or in_match or (id == 1 and not dedicated):
		return
	players[id]["team"] = clampi(team, 0, 1)
	players[id]["ready"] = id == 1 and not dedicated
	_broadcast_lobby()


func choose_side(team: int) -> void:
	## Wybór strony w lobby (drużyna hosta 0 albo 1). Gracz-host zawsze dowodzi drużyną 0
	## (nacje obu stron wybiera w zakładce New Battle).
	if role == Role.CLIENT and connected:
		_r_side.rpc_id(1, team)


func set_ready(on: bool) -> void:
	if role == Role.CLIENT and connected:
		_r_ready.rpc_id(1, on)


func my_lobby_entry() -> Dictionary:
	return players.get(multiplayer.get_unique_id() if role != Role.NONE else 1, {})


func _broadcast_lobby() -> void:
	if role != Role.HOST:
		return
	_update_settings()
	_r_lobby.rpc(players, settings, in_match)


@rpc("authority", "call_remote", "reliable")
func _r_lobby(p: Dictionary, s: Dictionary, running: bool) -> void:
	players = p
	settings = s
	host_nations = s.get("nations", [0, 1])
	if not running and in_match:
		in_match = false   # bitwa się skończyła — wracamy do lobby (świeża scena z otwartym lobby)
		Battle.open_lobby = true
		if battle != null:
			battle.get_tree().reload_current_scene()
	if running and not in_match:
		status = "Battle in progress - you will join the next one"
	elif not running:
		status = "Connected - lobby"


func nation_of_team(team: int) -> int:
	return int(host_nations[clampi(team, 0, 1)])


func lobby_tick(delta: float) -> void:
	## Host: odliczanie startu na serwerze dedykowanym, powrót do lobby po bitwie.
	if role != Role.HOST:
		return
	if in_match:
		if dedicated and battle != null and battle.result_text != "":
			if _end_t < 0.0:
				_end_t = 0.0
				_log("Battle over: %s. Back to lobby in %d s" % [battle.result_text, int(LOBBY_AFTER)])
			_end_t += delta
			if _end_t >= LOBBY_AFTER:
				end_match()
		return
	if not dedicated or players.is_empty():
		_countdown = -1.0
		return
	var all_ready := true
	var fr := 0
	for p in players.values():
		all_ready = all_ready and p["ready"]
		if p["team"] == 0:
			fr += 1
	if all_ready and fr > 0:
		if _countdown < 0.0:
			_countdown = 3.0
			_log("All players ready - starting in 3 s")
		_countdown -= delta
		if _countdown <= 0.0:
			_countdown = -1.0
			start_match()
	else:
		_countdown = -1.0


func end_match() -> void:
	in_match = false
	_end_t = -1.0
	for id in players:
		players[id]["ready"] = false
	_broadcast_lobby()
	if battle != null:
		battle.get_tree().reload_current_scene()


# ------------------------------------------------------------------ start bitwy

func start_match() -> void:
	## Host: losuje ziarno mapy i startuje u wszystkich bitwę z tymi samymi ustawieniami.
	if role != Role.HOST:
		return
	if players.is_empty() or (not dedicated and players.size() < 2):
		status = "Need at least one more player"
		return
	_update_settings()
	var params := settings.duplicate()
	params["seed"] = randi()
	params["players"] = players.duplicate(true)
	in_match = true
	_end_t = -1.0
	_r_start.rpc(params)
	_apply_start(params)
	_log("Battle started: %s, %s, %s - %d players" % [params["scenario"], params["map"], params["size"], players.size()])


@rpc("authority", "call_remote", "reliable")
func _r_start(params: Dictionary) -> void:
	players = params["players"]
	if not players.has(multiplayer.get_unique_id()):
		return   # dołączył w trakcie — czeka na następną bitwę
	in_match = true
	_apply_start(params)


func _apply_start(params: Dictionary) -> void:
	Battle.net_seed = int(params["seed"])
	Battle.chosen_size = str(params["size"])
	Battle.chosen_map = str(params["map"])
	Battle.chosen_theme = str(params.get("theme", Battle.chosen_theme))
	Battle.chosen_scenario = str(params["scenario"])
	host_nations = params["nations"]
	players = params["players"]
	if role == Role.CLIENT:
		my_team = int(players[multiplayer.get_unique_id()]["team"])
		_swap = my_team == 1
		Battle.side_nation = [int(host_nations[my_team]), int(host_nations[1 - my_team])]
	else:
		my_team = 0
		_swap = false
		Battle.side_nation = [int(host_nations[0]), int(host_nations[1])]
	Battle.first_launch = false
	ev.clear()
	_snap_acc = 0.0
	_first_snap = true
	get_tree().reload_current_scene()


func team_players(team: int) -> Array:
	## Identyfikatory graczy danej drużyny (wg hosta), posortowane.
	var out: Array = []
	for id in players:
		if players[id]["team"] == team:
			out.append(id)
	out.sort()
	return out


func player_name(id: int) -> String:
	return players[id]["name"] if players.has(id) else "AI"


# ------------------------------------------------------------------ czat

var chat_log: Array = []   # [czas ms, imię, tekst, drużyna, tylko_drużyna]


func send_chat(text: String, team_only := false) -> void:
	## Wiadomość czatu: zawsze przez hosta, który rozsyła ją wszystkim (albo tylko sojusznikom).
	text = text.strip_edges().left(160)
	if text == "":
		return
	if is_host():
		_deliver_chat(1, text, team_only)
	elif is_client():
		_r_chat.rpc_id(1, text, team_only)


@rpc("any_peer", "call_remote", "reliable")
func _r_chat(text: String, team_only: bool) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		_deliver_chat(sender, str(text).strip_edges().left(160), team_only)


func _deliver_chat(sender: int, text: String, team_only: bool) -> void:
	if not players.has(sender) or text == "":
		return
	var pname: String = players[sender]["name"]
	var team: int = players[sender]["team"]
	for id in players:
		if team_only and players[id]["team"] != team:
			continue
		if id == 1:
			_add_chat(pname, text, team, team_only)
		else:
			_r_chat_msg.rpc_id(id, pname, text, team, team_only)


@rpc("authority", "call_remote", "reliable")
func _r_chat_msg(pname: String, text: String, team: int, team_only: bool) -> void:
	_add_chat(pname, text, team, team_only)


func _add_chat(pname: String, text: String, team: int, team_only: bool) -> void:
	chat_log.append([Time.get_ticks_msec(), pname, text, team, team_only])
	if chat_log.size() > 60:
		chat_log.pop_front()
	UiSound.play("click")


# ------------------------------------------------------------------ rozkazy graczy

func cmd(c: Array) -> void:
	if is_client():
		_r_cmd.rpc_id(1, c)


func _own(r: Regiment, sender: int) -> bool:
	return r != null and not r.dead and r.commander == sender


@rpc("any_peer", "call_remote", "reliable")
func _r_cmd(c: Array) -> void:
	if not is_host() or battle == null or c.is_empty():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	var b := battle
	match str(c[0]):
		"move":
			var r := b.reg_by_id(int(c[1]))
			if _own(r, sender):
				r.order_move(c[2], float(c[3]), int(c[4]), float(c[5]) if c.size() > 5 else -1.0)
		"attack":
			var r := b.reg_by_id(int(c[1]))
			var t := b.reg_by_id(int(c[2]))
			if _own(r, sender) and t != null and t.team != r.team:
				r.order_attack(t)
		"halt":
			var r := b.reg_by_id(int(c[1]))
			if _own(r, sender):
				r.order_halt()
		"square":
			var r := b.reg_by_id(int(c[1]))
			if _own(r, sender):
				r.order_square(bool(c[2]))
		"wedge":
			var r := b.reg_by_id(int(c[1]))
			if _own(r, sender):
				r.order_wedge(bool(c[2]))
		"fire":
			var r := b.reg_by_id(int(c[1]))
			if _own(r, sender):
				r.order_fire_at_will(bool(c[2]))
		"recruit":
			var i := int(c[1])
			var team: int = players[sender]["team"]
			if i >= 0 and i < b.settlements.size() and b.settlements[i].faction == team and Battle.UNIT_TYPES.has(str(c[2])):
				b.recruit(b.settlements[i], str(c[2]), sender)


# ------------------------------------------------------------------ host: wysyłanie stanu

func host_tick(delta: float) -> void:
	if not is_host() or battle == null:
		return
	_snap_acc += delta
	if _snap_acc < SNAP_EVERY:
		return
	_snap_acc = 0.0
	var raw := var_to_bytes(_build_snapshot())
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	_r_snap.rpc(raw.size(), packed)
	ev.clear()


static func _rid(r: Regiment) -> int:
	return r.net_id if r != null and not r.dead else -1


func _build_snapshot() -> Array:
	var b := battle
	var regs: Array = []
	for r in b.regiments:
		var n := r.s_pos.size()
		var pos := PackedByteArray()
		pos.resize(n * 4)
		var aim := PackedByteArray()
		aim.resize(n)
		var hp := PackedByteArray()
		hp.resize(n)
		for i in n:
			var p := r.s_pos[i]
			pos.encode_u16(i * 4, clampi(int(p.x * 2.0), 0, 65535))
			pos.encode_u16(i * 4 + 2, clampi(int(p.y * 2.0), 0, 65535))
			aim[i] = int(fposmod(r.s_aim[i], TAU) / TAU * 255.0) & 255
			hp[i] = clampi(int(r.s_hp[i]), 0, 255)
		var flags := (1 if r._in_column else 0) | (2 if r.square else 0) | (4 if r.garrisoned else 0) | (8 if r.march_mode else 0)
		regs.append([r.net_id, r.team, r.unit_key, r.reg_name, r.center, r.facing, int(r.state), r.morale, flags,
			r.limber_u, r.base_files, r.initial_count, _rid(r.fire_target), _rid(r.attack_target), r.move_target,
			PackedVector2Array(r.waypoints), r.in_water_ratio, r.surround_mask, r.flanked_until - b.sim_time,
			pos, aim, hp, r._gun_ang, r.move_facing, int(r._needs_limber), r.commander, r.stamina])
	var setts: Array = []
	for s in b.settlements:
		setts.append([s.faction, s.capture, s.capture_team, s.contested, s.queue])
	var balls: Array = []
	for bl in b.balls:
		balls.append([bl["pos"], bl["lift"]])
	var winner := -1
	if b.result_text == "VICTORY":
		winner = 0
	elif b.result_text == "DEFEAT":
		winner = 1
	return [b.sim_time, b.gold, b.income, b.upkeep, b.stats, winner, balls, ev, regs, setts]


# ------------------------------------------------------------------ gość: odbiór stanu

func _sw(t: int) -> int:
	return t if t < 0 or not _swap else 1 - t


func _swa(a: Array) -> Array:
	return [a[1], a[0]] if _swap else [a[0], a[1]]


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _r_snap(size: int, packed: PackedByteArray) -> void:
	if not is_client() or battle == null:
		return
	var raw := packed.decompress(size, FileAccess.COMPRESSION_DEFLATE)
	var d: Variant = bytes_to_var(raw)
	if not (d is Array):
		return
	_apply_snapshot(d)


func _apply_snapshot(d: Array) -> void:
	var b := battle
	b.sim_time = d[0]
	b.gold = _swa(d[1])
	b.income = _swa(d[2])
	b.upkeep = _swa(d[3])
	var st: Dictionary = d[4]
	for k in st:
		if st[k] is Array and (st[k] as Array).size() == 2:
			b.stats[k] = _swa(st[k])
	var winner: int = d[5]
	if winner >= 0 and b.result_text == "":
		b.result_text = "VICTORY" if _sw(winner) == 0 else "DEFEAT"
	b.balls.clear()
	for bl in d[6]:
		b.balls.append({"pos": bl[0], "lift": bl[1]})
	for e in d[7]:
		_replay(e)
	var seen := {}
	var pending: Array = []
	for e in d[8]:
		var id: int = e[0]
		seen[id] = true
		var r := b.reg_by_id(id)
		if r == null:
			r = b.spawn_remote(id, _sw(e[1]), e[2], e[3], e[4], e[5])
		_apply_reg(r, e)
		pending.append([r, e[12], e[13]])
	for p in pending:
		var r: Regiment = p[0]
		r.fire_target = b.reg_by_id(p[1]) if p[1] >= 0 else null
		r.attack_target = b.reg_by_id(p[2]) if p[2] >= 0 else null
	for i in range(b.regiments.size() - 1, -1, -1):
		var r := b.regiments[i]
		if not seen.has(r.net_id):
			r.dead = true
			r.visible = false
			b.selected.erase(r)
			b.regiments.remove_at(i)
	var ss: Array = d[9]
	for i in mini(ss.size(), b.settlements.size()):
		var s := b.settlements[i]
		var e: Array = ss[i]
		var f := _sw(e[0])
		if f != s.faction:
			if not _first_snap:
				if f == 0:
					b.message("Captured %s" % s.s_name)
				elif s.faction == 0:
					b.message("%s has fallen to the enemy!" % s.s_name)
			s.set_faction(f)
		s.capture = e[1]
		s.capture_team = _sw(e[2])
		s.contested = e[3]
		s.queue = e[4]
	_snap_age = 0.0
	_first_snap = false


func _apply_reg(r: Regiment, e: Array) -> void:
	var hp: PackedByteArray = e[21]
	var n := hp.size()
	r.net_fit(n)
	r.net_c0 = r.center if r.net_next.size() > 0 else e[4]
	r.net_c1 = e[4]
	r.center = r.net_c0
	r.facing = e[5]
	r.state = e[6]
	r.morale = e[7]
	var flags: int = e[8]
	r._in_column = flags & 1 != 0
	r.square = flags & 2 != 0
	r.garrisoned = flags & 4 != 0
	r.march_mode = flags & 8 != 0
	r.limber_u = e[9]
	r.base_files = e[10]
	r.initial_count = e[11]
	r.move_target = e[14]
	r.waypoints.assign(Array(e[15]))
	r.in_water_ratio = e[16]
	r.surround_mask = e[17]
	r.flanked_until = battle.sim_time + float(e[18])
	var pos: PackedByteArray = e[19]
	var aim: PackedByteArray = e[20]
	var nxt := PackedVector2Array()
	nxt.resize(n)
	for i in n:
		nxt[i] = Vector2(pos.decode_u16(i * 4), pos.decode_u16(i * 4 + 2)) * 0.5
		r.s_aim[i] = aim[i] / 255.0 * TAU
		r.s_hp[i] = hp[i]
	if r.s_pos.size() == n and r.net_next.size() == n:
		r.net_prev = r.s_pos.duplicate()
	else:
		r.net_prev = nxt
		r.s_pos = nxt.duplicate()
	r.net_next = nxt
	r._gun_ang = e[22]
	r.move_facing = e[23]
	r._needs_limber = e[24] != 0
	r.commander = e[25]
	if e.size() > 26:
		r.stamina = e[26]
	r._rest_key = Vector3(INF, INF, INF)


func client_tick(delta: float) -> void:
	## Płynny ruch między snapshotami.
	if not is_client() or battle == null:
		return
	_snap_age += delta
	battle.sim_time += delta
	var a := clampf(_snap_age / SNAP_EVERY, 0.0, 1.0)
	for r in battle.regiments:
		var nx := r.net_next
		var pv := r.net_prev
		var n := r.s_pos.size()
		if nx.size() != n or pv.size() != n:
			continue
		for i in n:
			r.s_pos[i] = pv[i].lerp(nx[i], a)
		r.center = r.net_c0.lerp(r.net_c1, a)


# ------------------------------------------------------------------ efekty i dźwięki

func _replay(e: Array) -> void:
	var b := battle
	match int(e[0]):
		0: b.effects.add_shot(e[1], e[2])
		1: b.effects.add_cannon_smoke(e[1], e[2])
		2: b.effects.add_impact(e[1])
		3: b.effects.add_explosion(e[1], e[2])
		4: b.effects.add_spark(e[1])
		5: b.effects.add_splash(e[1])
		6: b.effects.add_hit_blood(e[1], e[2], e[3])
		7: b.corpses.add_corpse(e[1], e[2], e[3], e[4], e[5] if e.size() > 5 else "")
		8: b.sfx.musket(e[1])
		9: b.sfx.cannon(e[1])
