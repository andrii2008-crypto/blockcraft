extends Control

const GAP := 8.0

var player = null
var slot_rects: Array[Rect2] = []
var jump_rect := Rect2()
var pause_rect := Rect2()
var show_info := true
var age := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	age += delta
	queue_redraw()


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var ss := clampf(s.y * 0.11, 44.0, 90.0)
	var total := 8.0 * ss + 7.0 * GAP
	var x0 := (s.x - total) * 0.5
	slot_rects.clear()
	for i in 8:
		slot_rects.append(Rect2(x0 + i * (ss + GAP), s.y - ss - 14.0, ss, ss))
	var js := ss * 1.5
	jump_rect = Rect2(s.x - js - 40.0, s.y - js - ss - 50.0, js, js)
	pause_rect = Rect2(s.x - 84.0, 14.0, 68.0, 68.0)


func hit_test(p: Vector2) -> String:
	_layout()
	if pause_rect.has_point(p):
		return "pause"
	if jump_rect.has_point(p):
		return "jump"
	for i in slot_rects.size():
		if slot_rects[i].has_point(p):
			return "slot" + str(i)
	return ""


func _draw() -> void:
	_layout()
	var vs := get_viewport().get_visible_rect().size
	var c := vs * 0.5
	if player != null and player.head_water:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.3, 0.7, 0.35))
	draw_line(c - Vector2(10, 0), c + Vector2(10, 0), Color(1, 1, 1, 0.85), 2.0)
	draw_line(c - Vector2(0, 10), c + Vector2(0, 10), Color(1, 1, 1, 0.85), 2.0)
	if player == null:
		return
	var font := ThemeDB.fallback_font
	if show_info:
		var pp: Vector3 = player.position
		draw_string(font, Vector2(16, 28), "XYZ: %d %d %d   FPS: %d" % [int(pp.x), int(pp.y), int(pp.z), Engine.get_frames_per_second()], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
	if show_info and not player.world.use_tex:
		draw_string(font, Vector2(16, 54), "NO TEXTURES: " + player.world.tex_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.4, 0.4, 0.95))
	if player.loading:
		draw_string(font, Vector2(c.x - 90.0, c.y - 60.0), "Loading world...", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.95))
	# кнопка паузы
	draw_rect(pause_rect, Color(0, 0, 0, 0.35))
	var bx := pause_rect.position.x + pause_rect.size.x * 0.3
	var by := pause_rect.position.y + pause_rect.size.y * 0.25
	var bw := pause_rect.size.x * 0.14
	var bh := pause_rect.size.y * 0.5
	draw_rect(Rect2(bx, by, bw, bh), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(bx + bw * 2.2, by, bw, bh), Color(1, 1, 1, 0.85))
	if player.move_id != -1:
		var o: Vector2 = player.move_origin
		var v: Vector2 = player.move_vec
		draw_arc(o, 90.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(o + v * 90.0, 34.0, Color(1, 1, 1, 0.35))
	var pressed: bool = player.jump_id != -1
	var jc := jump_rect.get_center()
	draw_circle(jc, jump_rect.size.x * 0.5, Color(1, 1, 1, 0.4 if pressed else 0.2))
	var r := jump_rect.size.x * 0.22
	draw_colored_polygon(PackedVector2Array([
		jc + Vector2(0, -r), jc + Vector2(r, r * 0.7), jc + Vector2(-r, r * 0.7)
	]), Color(1, 1, 1, 0.75))
	for i in slot_rects.size():
		var rc: Rect2 = slot_rects[i]
		var b: int = player.hotbar[i]
		var wd = player.world
		var tl: int = wd.block_tile(b, 0)
		if tl == 0:
			tl = wd.block_tile(b, 1)
		draw_rect(rc, Color(0, 0, 0, 0.45))
		if tl > 0 and wd.use_tex:
			draw_texture_rect_region(wd.atlas, rc.grow(-8.0), wd.tile_src(tl))
		else:
			var col: Color = wd.pal[b][0]
			draw_rect(rc.grow(-10.0), col)
		if i == player.selected:
			draw_rect(rc, Color.WHITE, false, 4.0)
