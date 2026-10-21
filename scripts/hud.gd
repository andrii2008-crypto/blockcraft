extends Control

const GAP := 8.0

var player = null
var slot_rects: Array[Rect2] = []
var jump_rect := Rect2()
var prev_log := ""
var age := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	age += _delta
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


func hit_test(p: Vector2) -> String:
	_layout()
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
	var pp: Vector3 = player.position
	draw_string(font, Vector2(16, 28), "XYZ: %d %d %d" % [int(pp.x), int(pp.y), int(pp.z)], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
	draw_string(font, Vector2(16, vs.y - 130.0), "chunks %d meshed %d pend %d fps %d" % [player.world.chunks.size(), player.world.meshed.size(), player.world.gen_pending.size(), Engine.get_frames_per_second()], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
	if prev_log != "" and age < 40.0:
		var lines := prev_log.strip_edges().split("\n")
		var first := maxi(0, lines.size() - 14)
		for li in range(first, lines.size()):
			draw_string(font, Vector2(16, 60.0 + (li - first) * 20.0), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 0.3, 0.95))
	if player.loading:
		draw_string(font, Vector2(c.x - 90.0, c.y - 60.0), "Loading world...", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.95))
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
		var col: Color = player.world.pal[b][0]
		draw_rect(rc, Color(0, 0, 0, 0.45))
		draw_rect(rc.grow(-10.0), col)
		if i == player.selected:
			draw_rect(rc, Color.WHITE, false, 4.0)
