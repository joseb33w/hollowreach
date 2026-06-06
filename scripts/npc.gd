class_name NPC
extends Node3D
## A friendly villager backed by a real LLM persona (npc.myapping.com). Idles in the
## world, turns to face a nearby player, and holds its own conversation history so it
## remembers the chat. Networking-free: each player talks to their own copy.

const ENDPOINT: String = "https://npc.myapping.com/chat"
const MODEL_YAW_OFFSET: float = PI
const TALK_RANGE: float = 3.6

signal thinking()
signal replied(text: String)
signal failed(reason: String)

var npc_name: String = "Villager"
var persona: String = ""
var history: Array = []

var rig: CharacterRig
var _http: HTTPRequest
var _player: Node3D
var _busy: bool = false


func setup(spec: Dictionary, player: Node3D) -> void:
	npc_name = str(spec.get("name", "Villager"))
	persona = str(spec.get("persona", ""))
	_player = player
	add_to_group("npc")
	global_position = spec.get("pos", Vector3.ZERO)

	rig = CharacterRig.new()
	rig.build(str(spec.get("model", "res://models/kk_Mage.glb")), false)
	add_child(rig)
	rig.set_locomotion(0.0)

	var label := Label3D.new()
	label.text = npc_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0005
	label.font_size = 48
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.modulate = spec.get("color", Color(1, 1, 1))
	label.position = Vector3(0, 2.9, 0)
	add_child(label)

	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.5
	tm.outer_radius = 1.7
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = spec.get("color", Color(1, 1, 1))
	rmat.emission_enabled = true
	rmat.emission = spec.get("color", Color(1, 1, 1))
	rmat.emission_energy_multiplier = 1.6
	ring.mesh.material = rmat
	ring.position = Vector3(0, 0.06, 0)
	add_child(ring)

	_http = HTTPRequest.new()
	_http.timeout = 30.0
	add_child(_http)
	_http.request_completed.connect(_on_http)


func in_range() -> bool:
	if _player == null:
		return false
	return global_position.distance_to(_player.global_position) <= TALK_RANGE


func ask(text: String) -> void:
	if _busy:
		return
	history.append({"role": "user", "content": text})
	_busy = true
	thinking.emit()
	var payload := {"persona": persona, "messages": history}
	var headers := ["content-type: application/json"]
	var err := _http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_busy = false
		failed.emit("request_error")


func _process(delta: float) -> void:
	if _player != null and in_range():
		var to: Vector3 = _player.global_position - global_position
		to.y = 0
		if to.length() > 0.1:
			var goal := atan2(to.x, to.z) + MODEL_YAW_OFFSET
			rig.rotation.y = lerp_angle(rig.rotation.y, goal, clampf(6.0 * delta, 0, 1))


func _on_http(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if code != 200:
		failed.emit("http_%d" % code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		failed.emit("bad_json")
		return
	var d: Dictionary = parsed
	var reply: String = str(d.get("reply", ""))
	if reply == "":
		failed.emit("empty")
		return
	history.append({"role": "assistant", "content": reply})
	replied.emit(reply)
