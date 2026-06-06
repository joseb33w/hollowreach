class_name Player
extends CharacterBody3D
## Local Knight: camera-relative movement with a SpringArm follow-camera, AnimationTree
## locomotion (idle/walk/run by speed), one-shot melee + emote, and health.

signal health_changed(cur: float, maxv: float)
signal died()
signal respawned()
signal melee_landed(target: Node)
signal attacked()
signal emoted()

const WALK_SPEED: float = 3.4
const RUN_SPEED: float = 7.0
const ACCEL: float = 14.0
const GRAVITY: float = 20.0
const LOOK_SENS: float = 0.005
const TURN_SPEED: float = 12.0
const MELEE_RANGE: float = 2.6
const MELEE_ARC_DOT: float = 0.25
const MELEE_DAMAGE: float = 34.0
const MAX_HP: float = 100.0
const MODEL_YAW_OFFSET: float = 0.0

var joy_vec: Vector2 = Vector2.ZERO
var hp: float = MAX_HP
var dead: bool = false
var input_enabled: bool = true

var rig: CharacterRig
var camera: Camera3D
var display_name: String = "You"

var _cam_yaw: Node3D
var _cam_pitch: Node3D
var _yaw: float = 0.0
var _pitch: float = -0.35
var _face_yaw: float = PI
var _attack_cooldown: float = 0.0
var _hit_done: bool = true
var _spawn: Vector3 = Vector3.ZERO


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)

	rig = CharacterRig.new()
	rig.build("res://models/kk_Knight.glb", false)
	add_child(rig)

	_cam_yaw = Node3D.new()
	_cam_yaw.position = Vector3(0, 1.65, 0)
	add_child(_cam_yaw)
	_cam_pitch = Node3D.new()
	_cam_yaw.add_child(_cam_pitch)
	var arm := SpringArm3D.new()
	arm.spring_length = 7.2
	arm.margin = 0.3
	arm.collision_mask = 1
	arm.shape = SphereShape3D.new()
	(arm.shape as SphereShape3D).radius = 0.35
	_cam_pitch.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 64.0
	arm.add_child(camera)
	camera.make_current()

	_spawn = global_position
	_apply_cam()


func set_spawn(p: Vector3) -> void:
	_spawn = p
	global_position = p


func add_look(dx: float, dy: float) -> void:
	_yaw -= dx * LOOK_SENS
	_pitch = clampf(_pitch - dy * LOOK_SENS, -1.1, 0.35)
	_apply_cam()


func attack() -> void:
	if dead or not input_enabled or _attack_cooldown > 0.0:
		return
	_attack_cooldown = maxf(rig.attack_length, 0.6)
	_hit_done = false
	rig.play_attack()
	attacked.emit()


func emote() -> void:
	if dead or not input_enabled:
		return
	rig.play_emote()
	emoted.emit()


func take_damage(amount: float) -> void:
	if dead:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, MAX_HP)
	if hp <= 0.0:
		_die()
	else:
		rig.play_hit()


func heal_full() -> void:
	hp = MAX_HP
	health_changed.emit(hp, MAX_HP)


func get_facing() -> float:
	return _face_yaw


func get_speed01() -> float:
	return clampf(Vector2(velocity.x, velocity.z).length() / RUN_SPEED, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if not _hit_done and rig.attack_length > 0.0 and _attack_cooldown <= rig.attack_length * 0.5:
		_hit_done = true
		_do_melee()

	var wish := Vector2.ZERO
	if input_enabled and not dead:
		wish = _keyboard_vector() + joy_vec
		if wish.length() > 1.0:
			wish = wish.normalized()

	var want_speed := wish.length() * RUN_SPEED
	var basis := Basis(Vector3.UP, _yaw)
	var dir: Vector3 = basis * Vector3(wish.x, 0, wish.y)
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
		_face_yaw = atan2(dir.x, dir.z)

	var horiz := Vector3(velocity.x, 0, velocity.z)
	var target := dir * want_speed
	horiz = horiz.move_toward(target, ACCEL * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	if rig != null:
		rig.set_locomotion(get_speed01())
		var goal := _face_yaw + MODEL_YAW_OFFSET
		rig.rotation.y = lerp_angle(rig.rotation.y, goal, clampf(TURN_SPEED * delta, 0, 1))


func _do_melee() -> void:
	var origin := global_position + Vector3(0, 0.9, 0)
	var forward := Vector3(sin(_face_yaw), 0, cos(_face_yaw))
	for grp: String in ["enemy", "remote_player"]:
		for node: Node in get_tree().get_nodes_in_group(grp):
			if not (node is Node3D):
				continue
			var n3 := node as Node3D
			var to: Vector3 = n3.global_position - origin
			to.y = 0
			if to.length() <= MELEE_RANGE and forward.dot(to.normalized()) >= MELEE_ARC_DOT:
				melee_landed.emit(node)


func _die() -> void:
	dead = true
	input_enabled = false
	rig.play_death()
	died.emit()
	var t := get_tree().create_timer(2.4)
	t.timeout.connect(_respawn)


func _respawn() -> void:
	global_position = _spawn
	velocity = Vector3.ZERO
	hp = MAX_HP
	dead = false
	input_enabled = true
	rig.revive()
	health_changed.emit(hp, MAX_HP)
	respawned.emit()


func _apply_cam() -> void:
	if _cam_yaw != null:
		_cam_yaw.rotation.y = _yaw
	if _cam_pitch != null:
		_cam_pitch.rotation.x = _pitch


func _keyboard_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v
