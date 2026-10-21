extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const Dbg = preload("res://scripts/dbg.gd")

const R := 0.3
const H := 1.8
const EYE := 1.62
const GRAVITY := 28.0
const JUMP_V := 9.0
const SPEED := 4.6
const REACH := 5.0
const SENS := 0.004
const JOY_R := 90.0

var world: WorldScript
var hud = null
var cam: Camera3D
var highlight: MeshInstance3D
var vel := Vector3.ZERO
var on_floor := false
var pitch := 0.0
var selected := 0
var hotbar: Array[int] = [
	WorldScript.GRASS, WorldScript.DIRT, WorldScript.STONE, WorldScript.WOOD,
	WorldScript.PLANKS, WorldScript.LEAVES, WorldScript.SAND, WorldScript.BRICK,
]
var target := {}

var move_id := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO
var look_id := -1
var look_start := Vector2.ZERO
var look_time := 0.0
var look_moved := false
var hold_acted := false
var repeat_timer := 0.0
var jump_id := -1
var needs_spawn := true
var dbg_n := 0
var proc_ms := 0.0
var loading := true
var in_water := false
var head_water := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, EYE, 0)
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = WorldScript.RD * 16.0 + 32.0
	add_child(cam)
	highlight = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.006
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.25)
	box.material = m
	highlight.mesh = box
	highlight.top_level = true
	highlight.visible = false
	add_child(highlight)


func _input(event: InputEvent) -> void:
	if dbg_n < 14:
		dbg_n += 1
		Dbg.put("event " + event.as_text())
	if hud == null:
		return
	var size := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			var hit: String = hud.hit_test(p)
			if dbg_n < 30:
				dbg_n += 1
				Dbg.put("touch down %s hit=%s loading=%s" % [str(p), hit, str(loading)])
			if hit == "jump":
				jump_id = event.index
			elif hit.begins_with("slot"):
				selected = int(hit.substr(4))
			elif p.x < size.x * 0.4:
				if move_id == -1:
					move_id = event.index
					move_origin = p
					move_vec = Vector2.ZERO
			elif look_id == -1:
				look_id = event.index
				look_start = p
				look_time = 0.0
				look_moved = false
				hold_acted = false
				repeat_timer = 0.0
		else:
			if event.index == move_id:
				move_id = -1
				move_vec = Vector2.ZERO
			elif event.index == jump_id:
				jump_id = -1
			elif event.index == look_id:
				if not look_moved and not hold_acted and look_time < 0.35:
					place_block()
				look_id = -1
	elif event is InputEventScreenDrag:
		var pos: Vector2 = event.position
		if event.index == move_id:
			move_vec = ((pos - move_origin) / JOY_R).limit_length(1.0)
		elif event.index == look_id:
			var d: Vector2 = event.relative
			rotation.y -= d.x * SENS
			pitch = clampf(pitch - d.y * SENS, -1.5, 1.5)
			if (pos - look_start).length() > 24.0:
				look_moved = true


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	proc_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _tick(delta: float) -> void:
	cam.rotation.x = pitch
	world.focus = position
	if needs_spawn:
		var sx := world.spawn_xz.x
		var sz := world.spawn_xz.y
		if not world.ready_at(Vector3(sx, 0.0, sz)):
			loading = true
			return
		var sp := world.clear_spawn(sx, sz)
		position = Vector3(sp.x + 0.5, world.surface_y(sp.x, sp.y) + 0.01, sp.y + 0.5)
		vel = Vector3.ZERO
		needs_spawn = false
	if not world.ready_at(position):
		loading = true
		return
	loading = false
	var dt := minf(delta, 0.1)
	while dt > 0.0:
		var step := minf(dt, 1.0 / 60.0)
		_simulate(step)
		dt -= step
	if position.y < -30.0:
		needs_spawn = true
		return
	_update_target()
	if look_id != -1:
		look_time += delta
		if not look_moved and look_time > 0.4:
			repeat_timer -= delta
			if repeat_timer <= 0.0:
				break_block()
				hold_acted = true
				repeat_timer = 0.25


func _simulate(dt: float) -> void:
	in_water = world.get_block(floori(position.x), floori(position.y + 0.5), floori(position.z)) == WorldScript.WATER
	head_water = world.get_block(floori(position.x), floori(position.y + EYE), floori(position.z)) == WorldScript.WATER
	var dir := basis.x * move_vec.x + basis.z * move_vec.y
	var spd := SPEED * (0.6 if in_water else 1.0)
	vel.x = dir.x * spd
	vel.z = dir.z * spd
	if in_water:
		var tv := 3.5 if jump_id != -1 else -2.0
		vel.y = move_toward(vel.y, tv, 25.0 * dt)
	else:
		vel.y = maxf(vel.y - GRAVITY * dt, -30.0)
		if jump_id != -1 and on_floor:
			vel.y = JUMP_V
	var can_step := on_floor or in_water
	on_floor = false
	_move_h(0, vel.x * dt, can_step)
	_move_h(2, vel.z * dt, can_step)
	_move_y(vel.y * dt)


func _move_h(axis: int, amount: float, can_step: bool) -> void:
	if amount == 0.0:
		return
	var np := position
	np[axis] += amount
	if not _collides(np):
		position = np
		return
	if can_step and vel.y < JUMP_V * 0.5:
		var up := np
		up.y += 1.05
		if not _collides(up):
			vel.y = JUMP_V * 0.9


func _move_y(amount: float) -> void:
	var np := position
	np.y += amount
	if _collides(np):
		if amount < 0.0:
			position.y = floorf(np.y) + 1.001
			on_floor = true
		else:
			position.y = floorf(np.y + H) - H - 0.001
		vel.y = 0.0
	else:
		position = np


func _collides(p: Vector3) -> bool:
	var x0 := floori(p.x - R)
	var x1 := floori(p.x + R - 0.0001)
	var y0 := floori(p.y)
	var y1 := floori(p.y + H - 0.0001)
	var z0 := floori(p.z - R)
	var z1 := floori(p.z + R - 0.0001)
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				if world.is_solid(x, y, z):
					return true
	return false


func _update_target() -> void:
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	target = world.raycast(origin, dir, REACH)
	if target.is_empty():
		highlight.visible = false
	else:
		var p: Vector3i = target["pos"]
		highlight.global_position = Vector3(p) + Vector3(0.5, 0.5, 0.5)
		highlight.visible = true


func break_block() -> void:
	if dbg_n < 40:
		dbg_n += 1
		Dbg.put("break_block target=" + str(target))
	if target.is_empty():
		return
	var p: Vector3i = target["pos"]
	if world.get_block(p.x, p.y, p.z) == WorldScript.BEDROCK:
		return
	world.set_block(p, WorldScript.AIR)


func place_block() -> void:
	if dbg_n < 40:
		dbg_n += 1
		Dbg.put("place_block target=" + str(target))
	if target.is_empty():
		return
	var n: Vector3i = target["normal"]
	if n == Vector3i.ZERO:
		return
	var tp: Vector3i = target["pos"]
	var p: Vector3i = tp + n
	var cur := world.get_block(p.x, p.y, p.z)
	if cur != WorldScript.AIR and cur != WorldScript.WATER:
		return
	if _overlaps(p):
		return
	world.set_block(p, hotbar[selected])


func _overlaps(p: Vector3i) -> bool:
	return (position.x + R > p.x and position.x - R < p.x + 1
		and position.y + H > p.y and position.y < p.y + 1
		and position.z + R > p.z and position.z - R < p.z + 1)
