class_name Joystick
extends Control
## On-screen movement joystick visual. It does NOT read input itself — the HUD's
## multitouch router (keyed by touch index) drives it via begin/drag/end so that
## moving, looking and tapping buttons all work with independent simultaneous
## fingers. The base appears wherever the move-finger first lands; the knob follows.

signal moved(vec: Vector2)

const RADIUS: float = 95.0
const KNOB: float = 40.0

var _active: bool = false
var _origin: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func begin(pos: Vector2) -> void:
	_active = true
	_origin = pos
	_knob = pos
	moved.emit(Vector2.ZERO)
	queue_redraw()


func drag(pos: Vector2) -> void:
	if not _active:
		return
	var d := pos - _origin
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	_knob = _origin + d
	moved.emit(d / RADIUS)
	queue_redraw()


func end() -> void:
	if not _active:
		return
	_active = false
	moved.emit(Vector2.ZERO)
	queue_redraw()


func is_active() -> bool:
	return _active


func _draw() -> void:
	if not _active:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(_origin, RADIUS, 0, TAU, 56, Color(1, 1, 1, 0.45), 3.0, false)
	draw_circle(_knob, KNOB, Color(0.95, 0.95, 1.0, 0.65))
	draw_arc(_knob, KNOB, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.0, false)
