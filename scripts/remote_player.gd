class_name RemotePlayer
extends Node3D
## A networked peer's Knight: interpolates toward the latest broadcast transform,
## shows a name tag + health bar, and plays attack/emote/hit/death one-shots.

const MODEL_YAW_OFFSET: float = PI
const LERP_POS: float = 12.0
const LERP_ROT: float = 12.0

var peer_id: String = ""
var last_seen: float = 0.0

var rig: CharacterRig
var tag: FloatingTag

var _target_pos: Vector3 = Vector3.ZERO
var _target_yaw: float = 0.0
var _speed01: float = 0.0
var _dead: bool = false


func setup(id: String, display_name: String) -> void:
	peer_id = id
	add_to_group("remote_player")
	rig = CharacterRig.new()
	rig.build("res://models/kk_Knight.glb", false)
	add_child(rig)
	tag = FloatingTag.new()
	tag.setup(display_name, Color(0.3, 0.85, 0.35), 2.7)
	add_child(tag)
	_target_pos = global_position


func apply_state(pos: Vector3, yaw: float, speed01: float, hp_ratio: float) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_speed01 = speed01
	if tag != null:
		tag.set_health(hp_ratio)


func play_attack() -> void:
	if rig != null:
		rig.play_attack()


func play_emote() -> void:
	if rig != null:
		rig.play_emote()


func play_hit() -> void:
	if rig != null:
		rig.play_hit()


func play_death() -> void:
	if rig != null:
		rig.play_death()


func revive() -> void:
	if rig != null:
		rig.revive()


func set_dead(d: bool) -> void:
	if d and not _dead:
		play_death()
	elif not d and _dead:
		revive()
	_dead = d


func is_dead() -> bool:
	return _dead


func _process(delta: float) -> void:
	global_position = global_position.lerp(_target_pos, clampf(LERP_POS * delta, 0, 1))
	if rig != null:
		rig.set_locomotion(_speed01)
		var goal := _target_yaw + MODEL_YAW_OFFSET
		rig.rotation.y = lerp_angle(rig.rotation.y, goal, clampf(LERP_ROT * delta, 0, 1))
