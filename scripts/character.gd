class_name CharacterRig
extends Node3D
## Wraps a staged KayKit character (.glb) and drives it with an AnimationTree:
## a BlendSpace1D for Idle->Walk->Run by speed, plus one-shots for attack /
## emote / hit / death. Shared by the player, remote players, enemies and NPCs.

var model: Node3D
var anim_tree: AnimationTree
var attack_length: float = 0.8

var _player: AnimationPlayer
var _dead: bool = false


func build(model_path: String, skeleton_mode: bool = false) -> void:
	var ps: PackedScene = load(model_path)
	model = ps.instantiate()
	add_child(model)
	_player = _find_player(model)

	var idle_clip: String = "Skeletons_Idle" if skeleton_mode else "Idle_A"
	var walk_clip: String = "Skeletons_Walking" if skeleton_mode else "Walking_C"
	var run_clip: String = "Skeletons_Walking" if skeleton_mode else "Running_A"
	var attack_clip: String = "Melee_1H_Attack_Chop" if skeleton_mode else "Melee_1H_Attack_Slice_Diagonal"
	var emote_clip: String = "Skeletons_Taunt" if skeleton_mode else "Waving"
	var hit_clip: String = "Hit_A"
	var death_clip: String = "Skeletons_Death" if skeleton_mode else "Death_A"

	for c: String in [idle_clip, walk_clip, run_clip]:
		_set_loop(c, true)
	for c: String in [attack_clip, emote_clip, hit_clip, death_clip]:
		_set_loop(c, false)
	if _player != null and _player.has_animation(attack_clip):
		attack_length = _player.get_animation(attack_clip).length

	var tree := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 1.0
	loco.add_blend_point(_anim_node(idle_clip), 0.0)
	loco.add_blend_point(_anim_node(walk_clip), 0.5)
	loco.add_blend_point(_anim_node(run_clip), 1.0)
	tree.add_node("loco", loco, Vector2(0, 200))

	_chain_oneshot(tree, "atk", attack_clip, "loco", Vector2(250, 200))
	_chain_oneshot(tree, "emo", emote_clip, "atk", Vector2(500, 200))
	_chain_oneshot(tree, "hit", hit_clip, "emo", Vector2(750, 200))
	_chain_oneshot(tree, "die", death_clip, "hit", Vector2(1000, 200))
	tree.connect_node("output", 0, "die")

	anim_tree = AnimationTree.new()
	anim_tree.tree_root = tree
	model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(_player)
	anim_tree.active = true


func set_locomotion(speed01: float) -> void:
	if anim_tree != null:
		anim_tree.set("parameters/loco/blend_position", clampf(speed01, 0.0, 1.0))


func play_attack() -> void:
	_fire("atk")


func play_emote() -> void:
	_fire("emo")


func play_hit() -> void:
	if not _dead:
		_fire("hit")


func play_death() -> void:
	_dead = true
	_fire("die")


func revive() -> void:
	_dead = false
	if anim_tree != null:
		anim_tree.set("parameters/die/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func is_attacking() -> bool:
	if anim_tree == null:
		return false
	return bool(anim_tree.get("parameters/atk/active"))


func _fire(node: String) -> void:
	if anim_tree != null:
		anim_tree.set("parameters/%s/request" % node, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _chain_oneshot(tree: AnimationNodeBlendTree, nid: String, clip: String, src: String, pos: Vector2) -> void:
	var os := AnimationNodeOneShot.new()
	os.fadein_time = 0.06
	os.fadeout_time = 0.18
	tree.add_node(nid, os, pos)
	tree.add_node(nid + "_anim", _anim_node(clip), pos + Vector2(-40, 120))
	tree.connect_node(nid, 0, src)
	tree.connect_node(nid, 1, nid + "_anim")


func _anim_node(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a


func _set_loop(clip: String, looped: bool) -> void:
	if _player != null and _player.has_animation(clip):
		var anim: Animation = _player.get_animation(clip)
		anim.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c: Node in n.get_children():
		var r: AnimationPlayer = _find_player(c)
		if r != null:
			return r
	return null
