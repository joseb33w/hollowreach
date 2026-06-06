class_name Enemy
extends CharacterBody3D
## Skeleton enemy. On the host client it runs full AI (patrol -> chase -> attack -> die)
## and broadcasts authoritative state; on other clients it is a replica that follows the
## broadcast state. PvE damage from any player is applied by the host.

const MAX_HP: float = 70.0
const AGGRO: float = 13.0
const ATTACK_RANGE: float = 2.3
const ATTACK_DMG: float = 9.0
const ATTACK_CD: float = 1.5
const PATROL_SPEED: float = 1.5
const CHASE_SPEED: float = 3.3
const GRAVITY: float = 20.0
const MODEL_YAW_OFFSET: float = 0.0

var eid: String = ""
var host_mode: bool = false
var hp: float = MAX_HP
var state: String = "patrol"
var spawn_pos: Vector3 = Vector3.ZERO

var target_provider: Callable
var damage_player: Callable
var broadcaster: Callable

var rig: CharacterRig
var tag: FloatingTag

var _face_yaw: float = 0.0
var _attack_cd: float = 0.0
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _dead_timer: float = 0.0
var _broadcast_acc: float = 0.0
var _prev_state: String = "patrol"
var _prev_hp: float = MAX_HP
var _target_pos: Vector3 = Vector3.ZERO
var _net_speed: float = 0.0


func setup(id: String, pos: Vector3, is_host: bool) -> void:
	eid = id
	spawn_pos = pos
	host_mode = is_host
	global_position = pos
	_target_pos = pos
	_patrol_target = pos
	add_to_group("enemy")

	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)

	rig = CharacterRig.new()
	rig.build("res://models/kk_Skeleton_Warrior.glb", true)
	add_child(rig)
	tag = FloatingTag.new()
	tag.setup("Skeleton", Color(0.85, 0.2, 0.2), 2.5)
	add_child(tag)


func apply_player_hit(dmg: float) -> void:
	if not host_mode or state == "dead":
		return
	hp = maxf(0.0, hp - dmg)
	if hp <= 0.0:
		state = "dead"
		_dead_timer = 9.0
		rig.play_death()
	else:
		rig.play_hit()
	_force_broadcast()


func apply_state(pos: Vector3, yaw: float, new_hp: float, st: String, speed01: float) -> void:
	_target_pos = pos
	_face_yaw = yaw
	_net_speed = speed01
	if tag != null:
		tag.set_health(new_hp / MAX_HP)
	if st == "attack" and _prev_state != "attack":
		rig.play_attack()
	if new_hp < _prev_hp - 0.5 and st != "dead":
		rig.play_hit()
	if st == "dead" and _prev_state != "dead":
		rig.play_death()
	if st != "dead" and _prev_state == "dead":
		rig.revive()
	_prev_state = st
	_prev_hp = new_hp
	hp = new_hp
	state = st


func _physics_process(delta: float) -> void:
	if host_mode:
		_host_ai(delta)
	else:
		_replica(delta)
	if rig != null:
		var goal := _face_yaw + MODEL_YAW_OFFSET
		rig.rotation.y = lerp_angle(rig.rotation.y, goal, clampf(10.0 * delta, 0, 1))


func _replica(delta: float) -> void:
	global_position = global_position.lerp(_target_pos, clampf(12.0 * delta, 0, 1))
	if rig != null:
		rig.set_locomotion(_net_speed)


func _host_ai(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_broadcast_acc += delta

	if state == "dead":
		_dead_timer -= delta
		velocity = Vector3.ZERO
		if rig != null:
			rig.set_locomotion(0.0)
		if _dead_timer <= 0.0:
			_revive()
		_maybe_broadcast()
		return

	var best := _nearest_target()
	var has_target: bool = best.has("pos")
	var move_dir := Vector3.ZERO
	var speed := 0.0

	if has_target:
		var tpos: Vector3 = best["pos"]
		var to: Vector3 = tpos - global_position
		to.y = 0
		var dist := to.length()
		if dist <= ATTACK_RANGE:
			state = "attack"
			if to.length() > 0.01:
				_face_yaw = atan2(to.x, to.z)
			if _attack_cd <= 0.0:
				_attack_cd = ATTACK_CD
				rig.play_attack()
				if damage_player.is_valid():
					damage_player.call(str(best.get("id", "")), bool(best.get("local", false)), ATTACK_DMG)
				_force_broadcast()
		elif dist <= AGGRO:
			state = "chase"
			move_dir = to.normalized()
			speed = CHASE_SPEED
			_face_yaw = atan2(move_dir.x, move_dir.z)
		else:
			state = "patrol"
	else:
		state = "patrol"

	if state == "patrol":
		_patrol_timer -= delta
		if _patrol_timer <= 0.0 or global_position.distance_to(_patrol_target) < 1.0:
			_patrol_timer = randf_range(2.0, 4.5)
			var a := randf_range(0, TAU)
			_patrol_target = spawn_pos + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 5.0)
		var pdir: Vector3 = _patrol_target - global_position
		pdir.y = 0
		if pdir.length() > 0.2:
			move_dir = pdir.normalized()
			speed = PATROL_SPEED
			_face_yaw = atan2(move_dir.x, move_dir.z)

	velocity.x = move_dir.x * speed
	velocity.z = move_dir.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if rig != null:
		rig.set_locomotion(clampf(speed / CHASE_SPEED, 0.0, 1.0))
	if tag != null:
		tag.set_health(hp / MAX_HP)
	_maybe_broadcast()


func _nearest_target() -> Dictionary:
	if not target_provider.is_valid():
		return {}
	var list: Array = target_provider.call()
	var best: Dictionary = {}
	var best_d: float = INF
	for t: Dictionary in list:
		var p: Vector3 = t.get("pos", Vector3.ZERO)
		var d: float = global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = t
	return best


func _revive() -> void:
	hp = MAX_HP
	state = "patrol"
	global_position = spawn_pos
	if rig != null:
		rig.revive()
	_force_broadcast()


func _maybe_broadcast() -> void:
	if _broadcast_acc >= 0.1:
		_force_broadcast()


func _force_broadcast() -> void:
	_broadcast_acc = 0.0
	if broadcaster.is_valid():
		broadcaster.call({
			"t": "estate",
			"eid": eid,
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z,
			"ry": _face_yaw,
			"hp": hp,
			"st": state,
			"sp": clampf(Vector2(velocity.x, velocity.z).length() / CHASE_SPEED, 0.0, 1.0),
		})
