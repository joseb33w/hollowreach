extends Node3D
## Hollowreach orchestrator: builds the world, spawns the local Knight, wires the HUD,
## runs the tap-to-start gate, and drives serverless multiplayer (Supabase Realtime
## broadcast via the Net autoload) — peer Knights, host-authoritative skeletons, PvE+PvP.

const MELEE_DAMAGE: float = 34.0
const PEER_TIMEOUT: float = 5.0
const SEND_HZ: float = 12.0
const ENEMY_COUNT: int = 5

var world: World
var player: Player
var hud: GameHUD

var started: bool = false
var am_host: bool = false
var _enemies_spawned: bool = false
var _grace: float = 0.0
var _send_acc: float = 0.0
var _tap_layer: CanvasLayer = null
var _connected_once: bool = false

var _peers: Dictionary = {}     # id -> RemotePlayer
var _peer_seen: Dictionary = {} # id -> last_seen seconds
var _enemies: Dictionary = {}   # eid -> Enemy
var _npcs: Array[NPC] = []


func _ready() -> void:
	world = World.new()
	add_child(world)
	world.build()

	player = Player.new()
	add_child(player)
	player.set_spawn(world.village_center + Vector3(0, 0, 6))
	player.health_changed.connect(_on_player_health)
	player.melee_landed.connect(_on_melee_landed)
	player.attacked.connect(func() -> void: _broadcast({"t": "act", "a": "atk"}))
	player.emoted.connect(func() -> void: _broadcast({"t": "act", "a": "emo"}))
	player.died.connect(func() -> void: _send_pos(true))
	player.respawned.connect(func() -> void: _send_pos(true))
	player.input_enabled = false

	for spec: Dictionary in world.npc_specs:
		var npc := NPC.new()
		add_child(npc)
		npc.setup(spec, player)
		_npcs.append(npc)

	hud = GameHUD.new()
	add_child(hud)
	hud.build()
	hud.player = player
	hud.nearest_npc_getter = _nearest_npc_in_range
	hud.talk_pressed.connect(_on_talk)
	hud.set_health(player.hp, Player.MAX_HP)

	Net.connected.connect(_on_net_connected)
	Net.message.connect(_on_net_message)
	Net.disconnected.connect(_on_net_disconnected)

	if player.display_name == "You" and Net.local_name != "":
		player.display_name = Net.local_name

	_show_tap_to_start()


func _process(delta: float) -> void:
	if not started:
		return
	_grace = maxf(0.0, _grace - delta)

	_send_acc += delta
	if _send_acc >= 1.0 / SEND_HZ:
		_send_acc = 0.0
		_send_pos(false)

	var now := Time.get_ticks_msec() / 1000.0
	var drop: Array = []
	for id: String in _peer_seen.keys():
		if now - float(_peer_seen[id]) > PEER_TIMEOUT:
			drop.append(id)
	if not drop.is_empty():
		for id: String in drop:
			_remove_peer(id)
		_reelect_host()

	if am_host and not _enemies_spawned and _grace <= 0.0:
		_spawn_enemies()


func _show_tap_to_start() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.08, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var title := Label.new()
	title.text = "HOLLOWREACH"
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.position = Vector2(0, -70)
	dim.add_child(title)

	var sub := Label.new()
	sub.text = "Tap to enter the realm"
	sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.position = Vector2(0, 30)
	dim.add_child(sub)

	var tip := Label.new()
	tip.text = "Left side: move    -    Right side: look    -    ATK to attack    -    WAVE to emote    -    Talk to villagers"
	tip.set_anchors_preset(Control.PRESET_FULL_RECT)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 17)
	tip.modulate = Color(0.8, 0.85, 0.95)
	tip.position = Vector2(0, 90)
	dim.add_child(tip)

	_tap_layer = layer
	dim.gui_input.connect(_on_tap_to_start)
	add_child(layer)


func _on_tap_to_start(e: InputEvent) -> void:
	if started:
		return
	if not ((e is InputEventScreenTouch or e is InputEventMouseButton) and e.is_pressed()):
		return
	started = true
	player.input_enabled = true
	_grace = 1.5
	if _tap_layer != null:
		_tap_layer.queue_free()
		_tap_layer = null
	_reelect_host()
	if OS.has_feature("web"):
		if hud != null:
			hud.set_status("Connecting...")
		Net.connect_room()


# ---- networking --------------------------------------------------------------

func _on_net_connected(room: String, you: String) -> void:
	_connected_once = true
	if hud != null:
		hud.set_room_info(room, _peers.size() + 1)
		hud.toast("Joined room %s" % room)
	_reelect_host()
	_broadcast({"t": "hello", "n": player.display_name})


func _on_net_disconnected() -> void:
	if hud != null:
		hud.set_status("Offline - exploring solo")
	if started and OS.has_feature("web"):
		var t := get_tree().create_timer(4.0)
		t.timeout.connect(_retry_connect)


func _retry_connect() -> void:
	if started and OS.has_feature("web") and _peers.is_empty():
		if hud != null and not _connected_once:
			hud.set_status("Connecting...")
		Net.connect_room()


func _on_net_message(data: Dictionary) -> void:
	var from := str(data.get("from", ""))
	if from == "" or from == Net.local_id:
		return
	var t := str(data.get("t", ""))
	match t:
		"pos":
			_touch_peer(from, str(data.get("n", "Knight")))
			var rp: RemotePlayer = _peers.get(from)
			if rp != null:
				rp.apply_state(
					Vector3(data.get("x", 0.0), data.get("y", 0.0), data.get("z", 0.0)),
					float(data.get("ry", 0.0)),
					float(data.get("sp", 0.0)),
					float(data.get("hpr", 1.0)))
				rp.set_dead(bool(data.get("d", false)))
		"hello":
			_touch_peer(from, str(data.get("n", "Knight")))
			_send_pos(true)
		"act":
			var rp2: RemotePlayer = _peers.get(from)
			if rp2 != null:
				if str(data.get("a", "")) == "atk":
					rp2.play_attack()
				else:
					rp2.play_emote()
		"ehit":
			if am_host:
				var e: Enemy = _enemies.get(str(data.get("eid", "")))
				if e != null:
					e.apply_player_hit(float(data.get("dmg", 0.0)))
		"hit":
			if str(data.get("target", "")) == Net.local_id:
				player.take_damage(float(data.get("dmg", 0.0)))
		"estate":
			_on_estate(data)


func _on_estate(data: Dictionary) -> void:
	var eid := str(data.get("eid", ""))
	if eid == "":
		return
	if am_host and _enemies.has(eid):
		return
	var e: Enemy = _enemies.get(eid)
	if e == null:
		e = _make_enemy(eid, Vector3(data.get("x", 0.0), data.get("y", 0.0), data.get("z", 0.0)), false)
	e.apply_state(
		Vector3(data.get("x", 0.0), data.get("y", 0.0), data.get("z", 0.0)),
		float(data.get("ry", 0.0)),
		float(data.get("hp", Enemy.MAX_HP)),
		str(data.get("st", "patrol")),
		float(data.get("sp", 0.0)))


func _touch_peer(id: String, pname: String) -> void:
	_peer_seen[id] = Time.get_ticks_msec() / 1000.0
	if not _peers.has(id):
		var rp := RemotePlayer.new()
		add_child(rp)
		rp.setup(id, pname)
		rp.global_position = player.global_position
		_peers[id] = rp
		if hud != null:
			hud.set_room_info(Net.room, _peers.size() + 1)
			hud.toast("%s entered the realm" % pname)
		_reelect_host()


func _remove_peer(id: String) -> void:
	var rp: RemotePlayer = _peers.get(id)
	if rp != null:
		rp.queue_free()
	_peers.erase(id)
	_peer_seen.erase(id)
	if hud != null:
		hud.set_room_info(Net.room, _peers.size() + 1)


func _reelect_host() -> void:
	var ids: Array = _peers.keys()
	ids.append(Net.local_id)
	ids.sort()
	var new_host: bool = (not ids.is_empty()) and (str(ids[0]) == Net.local_id)
	if new_host == am_host:
		return
	am_host = new_host
	for eid: String in _enemies.keys():
		var e: Enemy = _enemies[eid]
		e.host_mode = am_host
		if am_host:
			_wire_host_enemy(e)
	if am_host and not _enemies.has("e0") and started and _grace <= 0.0:
		_spawn_enemies()


func _spawn_enemies() -> void:
	_enemies_spawned = true
	for i in mini(ENEMY_COUNT, world.enemy_spawns.size()):
		var eid := "e%d" % i
		if _enemies.has(eid):
			continue
		var e := _make_enemy(eid, world.enemy_spawns[i], true)
		_wire_host_enemy(e)


func _make_enemy(eid: String, pos: Vector3, is_host: bool) -> Enemy:
	var e := Enemy.new()
	add_child(e)
	e.setup(eid, pos, is_host)
	_enemies[eid] = e
	return e


func _wire_host_enemy(e: Enemy) -> void:
	e.target_provider = _enemy_targets
	e.damage_player = _enemy_damages_player
	e.broadcaster = _broadcast


func _enemy_targets() -> Array:
	var out: Array = []
	if not player.dead:
		out.append({"id": Net.local_id, "pos": player.global_position, "local": true})
	for id: String in _peers.keys():
		var rp: RemotePlayer = _peers[id]
		if rp != null and not rp.is_dead():
			out.append({"id": id, "pos": rp.global_position, "local": false})
	return out


func _enemy_damages_player(id: String, local: bool, dmg: float) -> void:
	if local:
		player.take_damage(dmg)
	else:
		_broadcast({"t": "hit", "target": id, "dmg": dmg})


func _on_melee_landed(target: Node) -> void:
	if target is Enemy:
		var e := target as Enemy
		if am_host:
			e.apply_player_hit(MELEE_DAMAGE)
		else:
			_broadcast({"t": "ehit", "eid": e.eid, "dmg": MELEE_DAMAGE})
	elif target is RemotePlayer:
		_broadcast({"t": "hit", "target": (target as RemotePlayer).peer_id, "dmg": MELEE_DAMAGE})


func _on_player_health(cur: float, maxv: float) -> void:
	if hud != null:
		hud.set_health(cur, maxv)


func _send_pos(force: bool) -> void:
	if not started or not OS.has_feature("web"):
		return
	_broadcast({
		"t": "pos",
		"n": player.display_name,
		"x": player.global_position.x,
		"y": player.global_position.y,
		"z": player.global_position.z,
		"ry": player.get_facing(),
		"sp": player.get_speed01(),
		"hpr": player.hp / Player.MAX_HP,
		"d": player.dead,
	})


func _broadcast(data: Dictionary) -> void:
	if OS.has_feature("web"):
		Net.send(data)


# ---- npc ---------------------------------------------------------------------

func _nearest_npc_in_range() -> Variant:
	var best: NPC = null
	var best_d := INF
	for npc: NPC in _npcs:
		if npc.in_range():
			var d := npc.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = npc
	return best


func _on_talk() -> void:
	var npc: Variant = _nearest_npc_in_range()
	if npc != null and hud != null:
		hud.open_chat(npc)
