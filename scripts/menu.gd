extends Control
# Меню в стиле старого Minecraft: титульный экран, настройки, пауза.

signal play_pressed
signal new_world_pressed
signal resume_pressed
signal quit_to_menu_pressed
signal quit_game_pressed
signal settings_changed

const Dbg = preload("res://scripts/dbg.gd")

enum { MAIN, SETTINGS, CONFIRM, PAUSE }

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
	"Алмазы внизу!", "Не копай вниз!", "Сто процентов кубов!", "Сделано на Godot!",
]
const RD_NAMES := ["Минимум", "Близко", "Нормально", "Далеко", "Максимум"]

var state := MAIN
var prev_state := MAIN
var cfg := {"rd": 4, "sens": 4, "coords": true}
var has_save := false
var buttons: Array = []
var pressed_idx := -1
var touch_id := -1
var tex: Texture2D
var splash := ""
var t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	splash = SPLASHES[randi() % SPLASHES.size()]
	_make_tex()


func open_main() -> void:
	state = MAIN
	visible = true
	splash = SPLASHES[randi() % SPLASHES.size()]


func open_pause() -> void:
	state = PAUSE
	visible = true


# Возвращает true, если кнопка «назад» обработана меню
func go_back() -> bool:
	if state == SETTINGS:
		state = prev_state
		settings_changed.emit()
		return true
	if state == CONFIRM:
		state = MAIN
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
		queue_redraw()


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var bw := clampf(vs.x * 0.55, 300.0, 560.0)
	var bh := clampf(vs.y * 0.085, 44.0, 66.0)
	var gap := bh * 0.3
	var items: Array = []
	var top := vs.y * 0.4
	if state == MAIN:
		items = [["play", "Играть"], ["new", "Новый мир"], ["settings", "Настройки"], ["quit", "Выйти из игры"]]
	elif state == SETTINGS:
		top = vs.y * 0.27
		var rd: int = cfg["rd"]
		items = [
			["rd", "Дальность прорисовки: " + RD_NAMES[clampi(rd - 2, 0, 4)]],
			["sens", "Чувствительность камеры: %d" % int(cfg["sens"])],
			["coords", "Координаты и FPS: " + ("ВКЛ" if cfg["coords"] else "ВЫКЛ")],
			["back", "Готово"],
		]
	elif state == CONFIRM:
		top = vs.y * 0.42
		items = [["confirm_yes", "Да, создать новый мир"], ["confirm_no", "Отмена"]]
	else:
		top = vs.y * 0.3
		items = [["resume", "Продолжить"], ["settings", "Настройки"], ["to_menu", "Сохранить и выйти в меню"]]
	buttons.clear()
	for i in items.size():
		var r := Rect2((vs.x - bw) * 0.5, top + i * (bh + gap), bw, bh)
		buttons.append({"rect": r, "id": items[i][0], "text": items[i][1]})


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
		elif event.index == touch_id:
			var idx := _hit(p)
			var was := pressed_idx
			pressed_idx = -1
			touch_id = -1
			if idx != -1 and idx == was:
				_activate(str(buttons[idx]["id"]))
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_id:
		var q: Vector2 = event.position
		if _hit(q) != pressed_idx:
			pressed_idx = -1


func _activate(id: String) -> void:
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
	elif id == "coords":
		cfg["coords"] = not cfg["coords"]
		settings_changed.emit()
	elif id == "back":
		state = prev_state
		settings_changed.emit()
	elif id == "quit":
		quit_game_pressed.emit()
	elif id == "resume":
		resume_pressed.emit()
	elif id == "to_menu":
		quit_to_menu_pressed.emit()


# ---------- рисование ----------

func _draw() -> void:
	_layout()
	var vs := get_viewport().get_visible_rect().size
	var font := ThemeDB.fallback_font
	if state == PAUSE:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	else:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, vs), true)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	if state == MAIN:
		_draw_logo(vs)
		_draw_splash(vs, font)
		_text(font, "BlockCraft 1.0", Vector2(14, vs.y - 14), 16, vs.x, HORIZONTAL_ALIGNMENT_LEFT)
	elif state == SETTINGS:
		_text(font, "Настройки", Vector2(0, vs.y * 0.17), 40, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	elif state == CONFIRM:
		_text(font, "Удалить сохранённый мир?", Vector2(0, vs.y * 0.27), 36, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
		_text(font, "Это действие нельзя отменить", Vector2(0, vs.y * 0.27 + 44.0), 22, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_text(font, "Игра приостановлена", Vector2(0, vs.y * 0.17), 40, vs.x, HORIZONTAL_ALIGNMENT_CENTER)
	for i in buttons.size():
		var r: Rect2 = buttons[i]["rect"]
		_draw_button(font, r, str(buttons[i]["text"]), i == pressed_idx)


func _text(font: Font, text: String, pos: Vector2, size: int, width: float, align: HorizontalAlignment, color: Color = Color.WHITE) -> void:
	draw_string(font, pos + Vector2(2, 2), text, align, width, size, Color(0.12, 0.12, 0.12))
	draw_string(font, pos, text, align, width, size, color)


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
	var base_y := r.position.y + r.size.y * 0.5 + fs * 0.35
	var col := Color(1.0, 1.0, 0.65) if down else Color.WHITE
	_text(font, text, Vector2(r.position.x, base_y), fs, r.size.x, HORIZONTAL_ALIGNMENT_CENTER, col)


func _draw_logo(vs: Vector2) -> void:
	var word := "BLOCKCRAFT"
	var u := minf(vs.x * 0.86 / 59.0, vs.y * 0.17 / 7.0)
	var total_w := (word.length() * 6 - 1) * u
	var x0 := (vs.x - total_w) * 0.5
	var y0 := vs.y * 0.08
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
	draw_set_transform(Vector2(vs.x * 0.74, vs.y * 0.34), -0.3, Vector2(s, s))
	_text(font, splash, Vector2(-170, 0), 28, 340.0, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 1.0, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
