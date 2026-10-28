extends Control
# Меню в стиле старого Minecraft: титульный экран, сервера, настройки, пауза.

const Dbg = preload("res://scripts/dbg.gd")

signal play_pressed
signal new_world_pressed
signal resume_pressed
signal quit_to_menu_pressed
signal quit_game_pressed
signal settings_changed
signal join_requested(addr: String)
signal cancel_connect
signal host_requested
signal host_stop_requested

enum { MAIN, SETTINGS, CONFIRM, PAUSE, SERVERS, ADD_SERVER, DIRECT, CONNECTING, HOST_INFO, MESSAGE }

const GLYPHS := {
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
}
const SPLASHES := [
	"Тапни по экрану!", "Копай глубже!", "Бесконечный мир!", "Теперь с пещерами!",
	"Алмазы внизу!", "Не копай вниз!", "Сто процентов кубов!", "Играй с друзьями!",
]
const RD_NAMES := ["Минимум", "Близко", "Нормально", "Далеко", "Максимум"]
const FPS_OPTS := [0, 30, 60, 90, 120]

var state := MAIN
var prev_state := MAIN
var cfg := {"rd": 4, "sens": 4, "coords": true, "fps": 0, "servers": [], "last_addr": ""}
var has_save := false
var net_mode := 0                  # 0 одиночная, 1 мир открыт для друзей, 2 подключены к серверу
var buttons: Array = []
var pressed_idx := -1
var touch_id := -1
var tex: Texture2D
var splash := ""
var t := 0.0
var sel := -1
var list_off := 0.0
var list_rect := Rect2()
var row_h := 60.0
var drag_list := false
var msg_title := ""
var msg_lines: Array = []
var msg_back := MAIN
var connect_addr := ""
var info_cb := Callable()
var le_name: LineEdit
var le_addr: LineEdit


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	splash = SPLASHES[randi() % SPLASHES.size()]
	_make_tex()
	le_name = _make_edit("Мой сервер")
	le_addr = _make_edit("192.168.0.5:7777")


func _make_edit(ph: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = 64
	le.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.6, 0.6, 0.62)
	sb.set_content_margin_all(10)
	le.add_theme_stylebox_override("normal", sb)
	var sf := sb.duplicate() as StyleBoxFlat
	sf.border_color = Color.WHITE
	le.add_theme_stylebox_override("focus", sf)
	le.visible = false
	add_child(le)
	return le


func open_main() -> void:
	state = MAIN
	visible = true
	splash = SPLASHES[randi() % SPLASHES.size()]


func open_pause() -> void:
	state = PAUSE
	visible = true


func open_host_info() -> void:
	state = HOST_INFO
	visible = true


func show_connecting(addr: String) -> void:
	connect_addr = addr
	state = CONNECTING
	visible = true


func show_message(title: String, lines: Array, back_to_servers: bool) -> void:
	msg_title = title
	msg_lines = lines
	msg_back = SERVERS if back_to_servers else MAIN
	state = MESSAGE
	visible = true


# Возвращает true, если кнопка «назад» обработана меню
func go_back() -> bool:
	if state == SETTINGS:
		state = prev_state
		settings_changed.emit()
		return true
	if state == CONFIRM or state == SERVERS:
		state = MAIN
		return true
	if state == ADD_SERVER or state == DIRECT:
		state = SERVERS
		return true
	if state == CONNECTING:
		cancel_connect.emit()
		state = SERVERS
		return true
	if state == MESSAGE:
		state = msg_back
		return true
	if state == HOST_INFO:
		resume_pressed.emit()
		return true
	return false


func _make_tex() -> void:
	var im := Dbg.load_image("res://textures/dirt_tile.bytes")
	if im != null:
		tex = ImageTexture.create_from_image(im)
		return
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for by in 16:
		for bx in 16:
			var hsh := ((bx * 73856093) ^ (by * 19349663)) & 255
			var k := 0.75 + 0.25 * (hsh / 255.0)
			img.fill_rect(Rect2i(bx * 8, by * 8, 8, 8), Color(0.47 * k, 0.34 * k, 0.22 * k))
	tex = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	t += delta
	if visible:
		_update_edits()
		queue_redraw()
	elif le_name.visible or le_addr.visible:
		le_name.visible = false
		le_addr.visible = false


func _update_edits() -> void:
	var vs := get_viewport().get_visible_rect().size
	var bw := clampf(vs.x * 0.55, 300.0, 560.0)
	var x := (vs.x - bw) * 0.5
	var show_name := state == ADD_SERVER
	var show_addr := state == ADD_SERVER or state == DIRECT
	if show_addr and not le_addr.visible:
		if state == ADD_SERVER:
			le_name.text = ""
			le_addr.text = ""
		else:
			le_addr.text = str(cfg.get("last_addr", ""))
	if not show_addr and le_addr.visible:
		le_addr.release_focus()
		le_name.release_focus()
		DisplayServer.virtual_keyboard_hide()
	le_name.visible = show_name
	le_addr.visible = show_addr
	le_name.position = Vector2(x, vs.y * 0.27)
	le_name.size = Vector2(bw, 56.0)
	var ay := vs.y * 0.45 if state == ADD_SERVER else vs.y * 0.32
	le_addr.position = Vector2(x, ay)
	le_addr.size = Vector2(bw, 56.0)


func _servers() -> Array:
	return cfg["servers"]


func _stack(items: Array, top: float, bw: float, bh: float, gap: float, vs: Vector2) -> void:
	for i in items.size():
		var r := Rect2((vs.x - bw) * 0.5, top + i * (bh + gap), bw, bh)
		buttons.append({"rect": r, "id": items[i][0], "text": items[i][1], "style": "btn"})


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var bw := clampf(vs.x * 0.55, 300.0, 560.0)
	var bh := clampf(vs.y * 0.085, 44.0, 66.0)
	var gap := bh * 0.3
	buttons.clear()
	list_rect = Rect2()
	if state == MAIN:
		_stack([["play", "Играть"], ["new", "Новый мир"], ["servers", "Сервера"], ["settings", "Настройки"], ["quit", "Выйти из игры"]], vs.y * 0.37, bw, bh, gap, vs)
	elif state == SETTINGS:
		var rd: int = cfg["rd"]
		var fps: int = int(cfg["fps"])
		_stack([
			["rd", "Дальность прорисовки: " + str(RD_NAMES[clampi(rd - 2, 0, 4)])],
			["sens", "Чувствительность камеры: %d" % int(cfg["sens"])],
			["fps", "Лимит FPS: " + ("Без лимита" if fps == 0 else str(fps))],
			["coords", "Координаты и FPS: " + ("ВКЛ" if cfg["coords"] else "ВЫКЛ")],
			["back", "Готово"],
		], vs.y * 0.25, bw, bh, gap, vs)
	elif state == CONFIRM:
		_stack([["confirm_yes", "Да, создать новый мир"], ["confirm_no", "Отмена"]], vs.y * 0.42, bw, bh, gap, vs)
	elif state == PAUSE:
		var items: Array = [["resume", "Продолжить"]]
		if net_mode == 0:
			items.append(["host", "Открыть для друзей"])
		elif net_mode == 1:
			items.append(["host_info", "Адрес для друзей"])
			items.append(["host_stop", "Закрыть доступ"])
		items.append(["settings", "Настройки"])
		items.append(["to_menu", "Отключиться" if net_mode == 2 else "Сохранить и выйти в меню"])
		_stack(items, vs.y * 0.27, bw, bh, gap, vs)
	elif state == SERVERS:
		var x0 := (vs.x - bw) * 0.5
		var half := (bw - gap) * 0.5
		var ly := vs.y * 0.2
		row_h = bh * 1.1
		list_rect = Rect2(x0, ly, bw, row_h * 3.0)
		var lst := _servers()
		var first := int(list_off)
		for i in 3:
			var idx := first + i
			if idx >= lst.size():
				break
			var e: Array = lst[idx]
			buttons.append({"rect": Rect2(x0, ly + i * row_h, bw, row_h - 6.0), "id": "row:%d" % idx, "text": str(e[0]), "sub": str(e[1]), "style": "row", "sel": idx == sel})
		var by := ly + row_h * 3.0 + gap
		buttons.append({"rect": Rect2(x0, by, half, bh), "id": "srv_connect", "text": "Подключиться", "style": "btn"})
		buttons.append({"rect": Rect2(x0 + half + gap, by, half, bh), "id": "srv_add", "text": "Добавить сервер", "style": "btn"})
		by += bh + gap
		buttons.append({"rect": Rect2(x0, by, half, bh), "id": "srv_direct", "text": "Прямое подключение", "style": "btn"})
		buttons.append({"rect": Rect2(x0 + half + gap, by, half, bh), "id": "srv_del", "text": "Удалить", "style": "btn"})
		by += bh + gap
		buttons.append({"rect": Rect2(x0, by, bw, bh), "id": "srv_back", "text": "Назад", "style": "btn"})
	elif state == ADD_SERVER:
		_stack([["add_save", "Сохранить"], ["add_cancel", "Отмена"]], vs.y * 0.6, bw, bh, gap, vs)
	elif state == DIRECT:
		_stack([["direct_go", "Подключиться"], ["direct_cancel", "Отмена"]], vs.y * 0.48, bw, bh, gap, vs)
	elif state == CONNECTING:
		_stack([["conn_cancel", "Отмена"]], vs.y * 0.55, bw, bh, gap, vs)
	elif state == HOST_INFO:
		_stack([["host_ok", "Продолжить игру"], ["host_stop", "Закрыть доступ"]], vs.y * 0.66, bw, bh, gap, vs)
	elif state == MESSAGE:
		_stack([["msg_ok", "Назад"]], vs.y * 0.6, bw, bh, gap, vs)


func _hit(p: Vector2) -> int:
	_layout()
	for i in buttons.size():
		var r: Rect2 = buttons[i]["rect"]
		if r.has_point(p):
			return i
	return -1


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			pressed_idx = _hit(p)
			touch_id = event.index
			drag_list = state == SERVERS and list_rect.has_point(p)
		elif event.index == touch_id:
			var idx := _hit(p)
			var was := pressed_idx
			pressed_idx = -1
			touch_id = -1
			drag_list = false
			if idx != -1 and idx == was:
				_activate(str(buttons[idx]["id"]))
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_id:
		var q: Vector2 = event.position
		var rel: Vector2 = event.relative
		if drag_list:
			var maxoff := maxf(0.0, _servers().size() - 3.0)
			list_off = clampf(list_off - rel.y / row_h, 0.0, maxoff)
			if absf(rel.y) > 2.0:
				pressed_idx = -1
		elif _hit(q) != pressed_idx:
			pressed_idx = -1


func _leave_edits() -> void:
	le_name.release_focus()
	le_addr.release_focus()
	DisplayServer.virtual_keyboard_hide()


func _activate(id: String) -> void:
	_leave_edits()
	if id.begins_with("row:"):
		sel = int(id.substr(4))
		return
	if id == "play":
		play_pressed.emit()
	elif id == "new":
		if has_save:
			state = CONFIRM
		else:
			new_world_pressed.emit()
	elif id == "confirm_yes":
		new_world_pressed.emit()
	elif id == "confirm_no":
		state = MAIN
	elif id == "servers":
		state = SERVERS
		list_off = 0.0
		sel = 0 if _servers().size() > 0 else -1
	elif id == "settings":
		prev_state = state
		state = SETTINGS
	elif id == "rd":
		var rd: int = cfg["rd"] + 1
		cfg["rd"] = 2 if rd > 6 else rd
		settings_changed.emit()
	elif id == "sens":
		cfg["sens"] = int(cfg["sens"]) % 8 + 1
		settings_changed.emit()
	elif id == "fps":
		var i := FPS_OPTS.find(int(cfg["fps"]))
		cfg["fps"] = FPS_OPTS[(i + 1) % FPS_OPTS.size()]
		settings_changed.emit()
	elif id == "coords":
		cfg["coords"] = not cfg["coords"]
		settings_changed.emit()
	elif id == "back":
		state = prev_state
		settings_changed.emit()
	elif id == "quit":
		quit_game_pressed.emit()
	elif id == "resume" or id == "host_ok":
		resume_pressed.emit()
	elif id == "to_menu":
		quit_to_menu_pressed.emit()
	elif id == "srv_back":
		state = MAIN
	elif id == "srv_connect":
		var lst := _servers()
		if sel >= 0 and sel < lst.size():
			var e: Array = lst[sel]
			join_requested.emit(str(e[1]))
	elif id == "srv_add":
		state = ADD_SERVER
	elif id == "srv_direct":
		state = DIRECT
	elif id == "srv_del":
		var lst2 := _servers()
		if sel >= 0 and sel < lst2.size():
			lst2.remove_at(sel)
			sel = -1
			settings_changed.emit()
	elif id == "add_save":
		var addr := le_addr.text.strip_edges()
		if addr != "":
			var nm := le_name.text.strip_edges()
			if nm == "":
				nm = addr
			_servers().append([nm, addr])
			sel = _servers().size() - 1
			settings_changed.emit()
			state = SERVERS
	elif id == "add_cancel" or id == "direct_cancel":
		state = SERVERS
	elif id == "direct_go":
		var addr2 := le_addr.text.strip_edges()
		if addr2 != "":
			join_requested.emit(addr2)
	elif id == "conn_cancel":
		cancel_connect.emit()
		state = SERVERS
	elif id == "msg_ok":
		state = msg_back
	elif id == "host":
		host_requested.emit()
	elif id == "host_info":
		state = HOST_INFO
	elif id == "host_stop":
		host_stop_requested.emit()


# ---------- рисование ----------

func _draw() -> void:
	_layout()
	var vs := get_viewport().get_visible_rect().size
	var font := ThemeDB.fallback_font
	if state == PAUSE or state == HOST_INFO:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	else:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, vs), true)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	var C := HORIZONTAL_ALIGNMENT_CENTER
	if state == MAIN:
		_draw_logo(vs)
		_draw_splash(vs, font)
		_text(font, "BlockCraft 1.0", Vector2(14, vs.y - 14), 16, vs.x, HORIZONTAL_ALIGNMENT_LEFT)
	elif state == SETTINGS:
		_text(font, "Настройки", Vector2(0, vs.y * 0.17), 40, vs.x, C)
	elif state == CONFIRM:
		_text(font, "Удалить сохранённый мир?", Vector2(0, vs.y * 0.27), 36, vs.x, C)
		_text(font, "Это действие нельзя отменить", Vector2(0, vs.y * 0.27 + 44.0), 22, vs.x, C)
	elif state == PAUSE:
		_text(font, "Игра приостановлена", Vector2(0, vs.y * 0.15), 40, vs.x, C)
		if net_mode == 1:
			_text(font, "Мир открыт для друзей", Vector2(0, vs.y * 0.15 + 38.0), 20, vs.x, C, Color(0.6, 1.0, 0.6))
		elif net_mode == 2:
			_text(font, "Вы играете на сервере", Vector2(0, vs.y * 0.15 + 38.0), 20, vs.x, C, Color(0.6, 1.0, 0.6))
	elif state == SERVERS:
		_text(font, "Сервера", Vector2(0, vs.y * 0.14), 40, vs.x, C)
		if _servers().is_empty():
			_text(font, "Список пуст. Добавь сервер", list_rect.position + Vector2(0, 46), 22, list_rect.size.x, C, Color(0.8, 0.8, 0.8))
			_text(font, "или подключись по адресу.", list_rect.position + Vector2(0, 78), 22, list_rect.size.x, C, Color(0.8, 0.8, 0.8))
	elif state == ADD_SERVER:
		_text(font, "Добавить сервер", Vector2(0, vs.y * 0.15), 40, vs.x, C)
		_text(font, "Название", Vector2(le_name.position.x, le_name.position.y - 10.0), 20, 400.0, HORIZONTAL_ALIGNMENT_LEFT, Color(0.8, 0.8, 0.8))
		_text(font, "Адрес (IP:порт)", Vector2(le_addr.position.x, le_addr.position.y - 10.0), 20, 400.0, HORIZONTAL_ALIGNMENT_LEFT, Color(0.8, 0.8, 0.8))
	elif state == DIRECT:
		_text(font, "Прямое подключение", Vector2(0, vs.y * 0.15), 40, vs.x, C)
		_text(font, "Адрес сервера (IP:порт)", Vector2(le_addr.position.x, le_addr.position.y - 10.0), 20, 500.0, HORIZONTAL_ALIGNMENT_LEFT, Color(0.8, 0.8, 0.8))
	elif state == CONNECTING:
		_text(font, "Подключение...", Vector2(0, vs.y * 0.3), 40, vs.x, C)
		_text(font, connect_addr, Vector2(0, vs.y * 0.3 + 44.0), 24, vs.x, C, Color(0.8, 0.8, 0.8))
	elif state == HOST_INFO:
		_text(font, "Мир открыт для друзей", Vector2(0, vs.y * 0.15), 38, vs.x, C)
		var lines: Array = []
		if info_cb.is_valid():
			lines = info_cb.call()
		for i in lines.size():
			_text(font, str(lines[i]), Vector2(0, vs.y * 0.27 + i * 34.0), 24, vs.x, C)
		_text(font, "Друг вводит адрес: Сервера → Прямое подключение", Vector2(0, vs.y * 0.27 + lines.size() * 34.0 + 14.0), 19, vs.x, C, Color(0.8, 0.8, 0.8))
	elif state == MESSAGE:
		_text(font, msg_title, Vector2(0, vs.y * 0.25), 38, vs.x, C)
		for i in msg_lines.size():
			_text(font, str(msg_lines[i]), Vector2(0, vs.y * 0.25 + 48.0 + i * 32.0), 22, vs.x, C, Color(0.85, 0.85, 0.85))
	for i in buttons.size():
		var b: Dictionary = buttons[i]
		var r: Rect2 = b["rect"]
		if b["style"] == "row":
			_draw_row(font, r, str(b["text"]), str(b["sub"]), bool(b["sel"]), i == pressed_idx)
		else:
			_draw_button(font, r, str(b["text"]), i == pressed_idx)


func _text(font: Font, text: String, pos: Vector2, size: int, width: float, align: HorizontalAlignment, color: Color = Color.WHITE) -> void:
	draw_string(font, pos + Vector2(2, 2), text, align, width, size, Color(0.12, 0.12, 0.12))
	draw_string(font, pos, text, align, width, size, color)


func _draw_row(font: Font, r: Rect2, name_text: String, addr: String, selected: bool, down: bool) -> void:
	draw_rect(r, Color(0, 0, 0, 0.55))
	var border := Color.WHITE if selected else Color(0.45, 0.45, 0.47)
	draw_rect(r, border, false, 3.0)
	if down:
		draw_rect(r.grow(-3.0), Color(1, 1, 1, 0.12))
	_text(font, name_text, Vector2(r.position.x + 16.0, r.position.y + r.size.y * 0.45), 26, r.size.x - 32.0, HORIZONTAL_ALIGNMENT_LEFT)
	_text(font, addr, Vector2(r.position.x + 16.0, r.position.y + r.size.y * 0.82), 18, r.size.x - 32.0, HORIZONTAL_ALIGNMENT_LEFT, Color(0.7, 0.7, 0.7))


func _draw_button(font: Font, r: Rect2, text: String, down: bool) -> void:
	var base := Color(0.44, 0.44, 0.46)
	if down:
		base = Color(0.36, 0.4, 0.64)
	var light := Color(0.7, 0.7, 0.74)
	var dark := Color(0.25, 0.25, 0.28)
	draw_rect(r, Color.BLACK)
	var inner := r.grow(-3.0)
	draw_rect(inner, base)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 3.0)), light)
	draw_rect(Rect2(inner.position, Vector2(3.0, inner.size.y)), light)
	draw_rect(Rect2(inner.position + Vector2(0.0, inner.size.y - 4.0), Vector2(inner.size.x, 4.0)), dark)
	draw_rect(Rect2(inner.position + Vector2(inner.size.x - 4.0, 0.0), Vector2(4.0, inner.size.y)), dark)
	var fs := int(r.size.y * 0.4)
	if text.length() > 18 and r.size.x < 300.0:
		fs = int(r.size.y * 0.3)
	var base_y := r.position.y + r.size.y * 0.5 + fs * 0.35
	var col := Color(1.0, 1.0, 0.65) if down else Color.WHITE
	_text(font, text, Vector2(r.position.x, base_y), fs, r.size.x, HORIZONTAL_ALIGNMENT_CENTER, col)


func _draw_logo(vs: Vector2) -> void:
	var word := "BLOCKCRAFT"
	var u := minf(vs.x * 0.86 / 59.0, vs.y * 0.15 / 7.0)
	var total_w := (word.length() * 6 - 1) * u
	var x0 := (vs.x - total_w) * 0.5
	var y0 := vs.y * 0.07
	for ci in word.length():
		var g: Array = GLYPHS[word[ci]]
		for ry in 7:
			var row: String = g[ry]
			for rx in 5:
				if row[rx] != "1":
					continue
				var p := Vector2(x0 + (ci * 6 + rx) * u, y0 + ry * u)
				draw_rect(Rect2(p + Vector2(u * 0.2, u * 0.2), Vector2(u, u)), Color(0, 0, 0, 0.45))
				draw_rect(Rect2(p, Vector2(u, u)), Color(0.28, 0.28, 0.3))
				draw_rect(Rect2(p, Vector2(u * 0.88, u * 0.88)), Color(0.6, 0.6, 0.62))
				draw_rect(Rect2(p, Vector2(u * 0.88, u * 0.14)), Color(0.82, 0.82, 0.85))
				draw_rect(Rect2(p, Vector2(u * 0.14, u * 0.88)), Color(0.78, 0.78, 0.8))


func _draw_splash(vs: Vector2, font: Font) -> void:
	var s := 1.0 + 0.06 * sin(t * 6.0)
	draw_set_transform(Vector2(vs.x * 0.74, vs.y * 0.3), -0.3, Vector2(s, s))
	_text(font, splash, Vector2(-170, 0), 28, 340.0, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 1.0, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
