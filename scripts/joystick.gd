class_name Joystick
extends Control
## Dynamic on-screen movement joystick. The base appears wherever the player first
## touches inside this control (the left half of the screen); the knob follows the drag
## and the normalized vector is emitted. Works with touch and mouse.

signal moved(vec: Vector2)

const RADIUS: float = 95.0
const KNOB: float = 40.0

var _active: bool = false
var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not _active:
			_begin(t.position, t.index)
		elif not t.pressed and t.index == _touch_index:
			_end()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _active and d.index == _touch_index:
			_update(d.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _active:
				_begin(mb.position, -2)
			elif not mb.pressed and _touch_index == -2:
				_end()
	elif event is InputEventMouseMotion:
		if _active and _touch_index == -2:
			_update((event as InputEventMouseMotion).position)


func _begin(pos: Vector2, idx: int) -> void:
	_active = true
	_touch_index = idx
	_origin = pos
	_knob = pos
	queue_redraw()


func _update(pos: Vector2) -> void:
	var d := pos - _origin
	if d.length() > RADIUS:
		d = d.normalized() * RADIUS
	_knob = _origin + d
	moved.emit(d / RADIUS)
	queue_redraw()


func _end() -> void:
	_active = false
	_touch_index = -1
	moved.emit(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(_origin, RADIUS, 0, TAU, 56, Color(1, 1, 1, 0.45), 3.0, true)
	draw_circle(_knob, KNOB, Color(0.95, 0.95, 1.0, 0.65))
	draw_arc(_knob, KNOB, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.0, true)
