class_name FloatingTag
extends Node3D
## Billboarded name label + health bar that floats above an actor's head.

const BAR_W: float = 1.1
const BAR_H: float = 0.14

var _label: Label3D
var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D


func setup(text: String, fill_color: Color, height: float = 2.7) -> void:
	position = Vector3(0, height, 0)

	_label = Label3D.new()
	_label.text = text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.00045
	_label.modulate = Color(1, 1, 1)
	_label.outline_modulate = Color(0, 0, 0, 0.9)
	_label.outline_size = 12
	_label.font_size = 48
	_label.position = Vector3(0, 0.32, 0)
	add_child(_label)

	var bg := MeshInstance3D.new()
	bg.mesh = _quad(BAR_W + 0.06, BAR_H + 0.06)
	bg.material_override = _bar_mat(Color(0.05, 0.05, 0.07))
	add_child(bg)

	_fill = MeshInstance3D.new()
	_fill.mesh = _quad(BAR_W, BAR_H)
	_fill_mat = _bar_mat(fill_color)
	_fill.material_override = _fill_mat
	add_child(_fill)
	set_health(1.0)


func set_health(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if _fill == null:
		return
	_fill.scale.x = maxf(ratio, 0.001)
	_fill.position.x = -BAR_W * 0.5 + BAR_W * ratio * 0.5
	_fill_mat.albedo_color = Color(0.85, 0.2, 0.2).lerp(Color(0.3, 0.85, 0.35), ratio)


func set_label(text: String) -> void:
	if _label != null:
		_label.text = text


func _quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


func _bar_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.render_priority = 2
	return m
