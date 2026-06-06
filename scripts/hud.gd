class_name GameHUD
extends CanvasLayer
## Mobile + desktop HUD with a true MULTITOUCH input router: a dynamic joystick (left),
## a drag-look region (right) and the attack / emote / talk buttons are all driven from a
## single index-keyed router, so each finger acts independently — you can move, look and
## tap buttons at the same time without one input stealing another. Also: the player
## health bar, room info, toast, and the LLM NPC chat panel.

signal talk_pressed()

const MOUSE_ID: int = -1
const TOP_MARGIN_FRAC: float = 0.16

var player: Player
var nearest_npc_getter: Callable

var _root: Control
var _joystick: Joystick
var _atk_btn: Button
var _emote_btn: Button
var _talk_btn: Button
var _hp_fill: ColorRect
var _hp_label: Label
var _room_label: Label
var _toast: Label

var _chat_panel: Control
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _chat_title: Label
var _thinking: Label
var _chat_npc: NPC

# Multitouch routing: pointer id (touch index, or MOUSE_ID) -> role string.
var _touches: Dictionary = {}
var _touch_mode: bool = false


func build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_joystick = Joystick.new()
	_joystick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_joystick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick.moved.connect(_on_joy)
	_root.add_child(_joystick)

	_build_buttons()
	_build_health()
	_build_room_info()
	_build_toast()
	_build_chat()


func set_health(cur: float, maxv: float) -> void:
	var ratio: float = clampf(cur / maxv, 0.0, 1.0) if maxv > 0.0 else 0.0
	if _hp_fill != null:
		_hp_fill.anchor_right = ratio
		_hp_fill.color = Color(0.85, 0.2, 0.2).lerp(Color(0.3, 0.85, 0.35), ratio)
	if _hp_label != null:
		_hp_label.text = "%s   %d/%d" % [player.display_name if player != null else "You", int(round(cur)), int(maxv)]


func set_room_info(room: String, knights: int) -> void:
	if _room_label != null:
		var others := maxi(knights - 1, 0)
		var who := "alone - share the link to invite a friend" if others == 0 else ("%d other knight%s here" % [others, "" if others == 1 else "s"])
		_room_label.text = "Room %s  -  %s" % [room, who]


func set_status(text: String) -> void:
	if _room_label != null:
		_room_label.text = text


func toast(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.8)


func open_chat(npc: NPC) -> void:
	if npc == null:
		return
	if _chat_npc != null:
		_disconnect_npc(_chat_npc)
	_chat_npc = npc
	_chat_title.text = npc.npc_name
	_chat_log.clear()
	for m: Dictionary in npc.history:
		_append_line(str(m.get("role", "")), str(m.get("content", "")))
	if npc.history.is_empty():
		_chat_log.append_text("[i][color=#9aa]Walk up and say hello...[/color][/i]\n")
	npc.thinking.connect(_on_npc_thinking)
	npc.replied.connect(_on_npc_replied)
	npc.failed.connect(_on_npc_failed)
	_thinking.visible = false
	_chat_panel.visible = true
	if player != null:
		player.input_enabled = false
	_release_all_pointers()
	_chat_input.grab_focus()


func close_chat() -> void:
	_chat_panel.visible = false
	if _chat_npc != null:
		_disconnect_npc(_chat_npc)
		_chat_npc = null
	if player != null:
		player.input_enabled = true


func _process(_delta: float) -> void:
	if _talk_btn == null:
		return
	if _chat_panel.visible:
		_talk_btn.visible = false
		return
	var npc: Variant = nearest_npc_getter.call() if nearest_npc_getter.is_valid() else null
	_talk_btn.visible = npc != null


# ---- multitouch input router -------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if _chat_panel != null and _chat_panel.visible:
		return

	if event is InputEventScreenTouch:
		if not _touch_mode:
			_touch_mode = true
			_release_all_pointers()
		var t := event as InputEventScreenTouch
		if t.pressed:
			_begin_pointer(t.index, t.position)
		else:
			_end_pointer(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag_pointer(d.index, d.position, d.relative)
	elif event is InputEventMouseButton and not _touch_mode:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_pointer(MOUSE_ID, mb.position)
			else:
				_end_pointer(MOUSE_ID)
	elif event is InputEventMouseMotion and not _touch_mode:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drag_pointer(MOUSE_ID, mm.position, mm.relative)


func _begin_pointer(id: int, pos: Vector2) -> void:
	var btn := _hit_button(pos)
	if btn != "":
		_touches[id] = btn
		_fire_button(btn)
		return

	var size := _vp_size()
	if pos.y < size.y * TOP_MARGIN_FRAC:
		return

	if pos.x < size.x * 0.5:
		if not _role_active("joy"):
			_touches[id] = "joy"
			_joystick.begin(pos)
	else:
		if not _role_active("look"):
			_touches[id] = "look"


func _drag_pointer(id: int, pos: Vector2, rel: Vector2) -> void:
	var role: String = str(_touches.get(id, ""))
	if role == "joy":
		_joystick.drag(pos)
	elif role == "look":
		player.add_look(rel.x, rel.y)


func _end_pointer(id: int) -> void:
	var role: String = str(_touches.get(id, ""))
	if role == "joy":
		_joystick.end()
	_touches.erase(id)


func _release_all_pointers() -> void:
	_touches.clear()
	_joystick.end()


func _role_active(role: String) -> bool:
	return _touches.values().has(role)


func _hit_button(pos: Vector2) -> String:
	if _talk_btn != null and _talk_btn.visible and _talk_btn.get_global_rect().has_point(pos):
		return "talk"
	if _atk_btn != null and _atk_btn.visible and _atk_btn.get_global_rect().has_point(pos):
		return "atk"
	if _emote_btn != null and _emote_btn.visible and _emote_btn.get_global_rect().has_point(pos):
		return "emote"
	return ""


func _fire_button(role: String) -> void:
	match role:
		"atk":
			if player != null:
				player.attack()
			_flash(_atk_btn)
		"emote":
			if player != null:
				player.emote()
			_flash(_emote_btn)
		"talk":
			talk_pressed.emit()
			_flash(_talk_btn)


func _flash(btn: Button) -> void:
	if btn == null:
		return
	btn.pivot_offset = btn.size * 0.5
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2(0.88, 0.88), 0.06)
	tw.tween_property(btn, "scale", Vector2.ONE, 0.12)


func _vp_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _on_joy(vec: Vector2) -> void:
	if player != null:
		player.joy_vec = vec


# ---- build -------------------------------------------------------------------

func _build_buttons() -> void:
	_atk_btn = _round_button("ATK", 132, Color(0.78, 0.24, 0.22))
	_atk_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atk_btn.add_theme_font_size_override("font_size", 40)
	_atk_btn.anchor_left = 1.0
	_atk_btn.anchor_top = 1.0
	_atk_btn.anchor_right = 1.0
	_atk_btn.anchor_bottom = 1.0
	_atk_btn.offset_left = -156
	_atk_btn.offset_top = -160
	_atk_btn.offset_right = -24
	_atk_btn.offset_bottom = -28
	_root.add_child(_atk_btn)

	_emote_btn = _round_button("WAVE", 92, Color(0.2, 0.45, 0.7))
	_emote_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emote_btn.add_theme_font_size_override("font_size", 22)
	_emote_btn.anchor_left = 1.0
	_emote_btn.anchor_top = 1.0
	_emote_btn.anchor_right = 1.0
	_emote_btn.anchor_bottom = 1.0
	_emote_btn.offset_left = -270
	_emote_btn.offset_top = -150
	_emote_btn.offset_right = -178
	_emote_btn.offset_bottom = -58
	_root.add_child(_emote_btn)

	_talk_btn = _round_button("Talk", 80, Color(0.25, 0.6, 0.4))
	_talk_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_talk_btn.anchor_left = 0.5
	_talk_btn.anchor_right = 0.5
	_talk_btn.anchor_top = 1.0
	_talk_btn.anchor_bottom = 1.0
	_talk_btn.offset_left = -90
	_talk_btn.offset_right = 90
	_talk_btn.offset_top = -96
	_talk_btn.offset_bottom = -28
	_talk_btn.add_theme_font_size_override("font_size", 30)
	_talk_btn.visible = false
	_root.add_child(_talk_btn)


func _build_health() -> void:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16
	panel.offset_top = 14
	panel.offset_right = 300
	panel.offset_bottom = 78
	panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.09, 0.13, 0.82), 10))
	_root.add_child(panel)

	var track := ColorRect.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.color = Color(0.05, 0.05, 0.07, 0.9)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.offset_left = 12
	track.offset_top = 34
	track.offset_right = -12
	track.offset_bottom = -10
	panel.add_child(track)

	_hp_fill = ColorRect.new()
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_fill.color = Color(0.3, 0.85, 0.35)
	_hp_fill.anchor_left = 0.0
	_hp_fill.anchor_top = 0.0
	_hp_fill.anchor_right = 1.0
	_hp_fill.anchor_bottom = 1.0
	track.add_child(_hp_fill)

	_hp_label = Label.new()
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.text = "You   100/100"
	_hp_label.add_theme_font_size_override("font_size", 18)
	_hp_label.position = Vector2(14, 8)
	panel.add_child(_hp_label)


func _build_room_info() -> void:
	_room_label = Label.new()
	_room_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_room_label.offset_top = 16
	_room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_label.add_theme_font_size_override("font_size", 18)
	_room_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_room_label.add_theme_constant_override("outline_size", 6)
	_room_label.text = "Connecting..."
	_root.add_child(_room_label)


func _build_toast() -> void:
	_toast = Label.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_top = 96
	_toast.offset_left = -260
	_toast.offset_right = 260
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	_root.add_child(_toast)


func _build_chat() -> void:
	_chat_panel = Control.new()
	_chat_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_chat_panel.visible = false
	_root.add_child(_chat_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chat_panel.add_child(dim)

	var box := Panel.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -340
	box.offset_right = 340
	box.offset_top = -300
	box.offset_bottom = 300
	box.add_theme_stylebox_override("panel", _box(Color(0.10, 0.11, 0.16, 0.98), 16))
	_chat_panel.add_child(box)

	_chat_title = Label.new()
	_chat_title.text = "Villager"
	_chat_title.add_theme_font_size_override("font_size", 28)
	_chat_title.position = Vector2(24, 18)
	box.add_child(_chat_title)

	var close := _round_button("X", 56, Color(0.4, 0.2, 0.2))
	close.anchor_left = 1.0
	close.anchor_right = 1.0
	close.offset_left = -76
	close.offset_top = 16
	close.offset_right = -20
	close.offset_bottom = 72
	close.pressed.connect(close_chat)
	box.add_child(close)

	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chat_log.offset_left = 22
	_chat_log.offset_top = 72
	_chat_log.offset_right = -22
	_chat_log.offset_bottom = -150
	_chat_log.add_theme_font_size_override("normal_font_size", 21)
	box.add_child(_chat_log)

	var chips := HBoxContainer.new()
	chips.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	chips.offset_left = 22
	chips.offset_right = -22
	chips.offset_top = -140
	chips.offset_bottom = -100
	chips.add_theme_constant_override("separation", 8)
	box.add_child(chips)
	for preset: String in ["Hello!", "What's wrong?", "Tell me about the dungeon"]:
		var chip := Button.new()
		chip.text = preset
		chip.add_theme_font_size_override("font_size", 17)
		chip.add_theme_stylebox_override("normal", _box(Color(0.18, 0.2, 0.28, 1), 10))
		chip.add_theme_stylebox_override("hover", _box(Color(0.24, 0.27, 0.36, 1), 10))
		chip.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.34, 0.44, 1), 10))
		chip.pressed.connect(_send_text.bind(preset))
		chips.add_child(chip)

	_thinking = Label.new()
	_thinking.text = "..."
	_thinking.add_theme_font_size_override("font_size", 26)
	_thinking.position = Vector2(26, 540)
	_thinking.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_thinking.offset_left = 24
	_thinking.offset_top = -96
	_thinking.visible = false
	box.add_child(_thinking)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 22
	row.offset_right = -22
	row.offset_top = -84
	row.offset_bottom = -22
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Say something..."
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.add_theme_font_size_override("font_size", 22)
	_chat_input.max_length = 200
	_chat_input.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_chat_input)

	var send := Button.new()
	send.text = "Send"
	send.custom_minimum_size = Vector2(110, 0)
	send.add_theme_font_size_override("font_size", 22)
	send.add_theme_stylebox_override("normal", _box(Color(0.25, 0.55, 0.4, 1), 10))
	send.add_theme_stylebox_override("hover", _box(Color(0.3, 0.62, 0.46, 1), 10))
	send.add_theme_stylebox_override("pressed", _box(Color(0.2, 0.48, 0.36, 1), 10))
	send.pressed.connect(_send)
	row.add_child(send)


func _send() -> void:
	_send_text(_chat_input.text)


func _send_text(text: String) -> void:
	var msg := text.strip_edges()
	if msg == "" or _chat_npc == null:
		return
	_chat_input.text = ""
	_append_line("user", msg)
	_chat_npc.ask(msg)


func _append_line(role: String, content: String) -> void:
	if role == "user":
		_chat_log.append_text("[color=#7ec8ff]You:[/color] %s\n" % content)
	else:
		_chat_log.append_text("[color=#ffd27e]%s:[/color] %s\n" % [_chat_title.text, content])


func _on_npc_thinking() -> void:
	_thinking.visible = true


func _on_npc_replied(text: String) -> void:
	_thinking.visible = false
	_append_line("assistant", text)


func _on_npc_failed(_reason: String) -> void:
	_thinking.visible = false
	_chat_log.append_text("[i][color=#c88]%s seems lost in thought...[/color][/i]\n" % _chat_title.text)


func _disconnect_npc(npc: NPC) -> void:
	if npc.thinking.is_connected(_on_npc_thinking):
		npc.thinking.disconnect(_on_npc_thinking)
	if npc.replied.is_connected(_on_npc_replied):
		npc.replied.disconnect(_on_npc_replied)
	if npc.failed.is_connected(_on_npc_failed):
		npc.failed.disconnect(_on_npc_failed)


func _round_button(text: String, dia: int, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(dia, dia)
	b.add_theme_font_size_override("font_size", int(dia * 0.4))
	b.add_theme_stylebox_override("normal", _box(color, dia / 2))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.1), dia / 2))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.18), dia / 2))
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	return b


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
