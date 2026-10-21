extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const Dbg = preload("res://scripts/dbg.gd")

var world: WorldScript
var player: Node3D
var ready_done := false


func _ready() -> void:
	var prev := Dbg.start()
	Dbg.put("boot")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95)
	env.fog_enabled = true
	env.fog_light_color = env.background_color
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	world = WorldScript.new()
	add_child(world)
	world.setup()
	Dbg.put("setup ok spawn=%s seed=%d" % [str(world.spawn_xz), world.seed_val])

	player = PlayerScript.new()
	player.world = world
	add_child(player)
	if world.has_saved_pos:
		player.position = world.saved_pos
		player.needs_spawn = false
	else:
		player.position = Vector3(world.spawn_xz.x, 40.0, world.spawn_xz.y)

	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := HudScript.new()
	layer.add_child(hud)
	hud.player = player
	player.hud = hud
	hud.prev_log = prev
	Dbg.put("player+hud ok")

	var timer := Timer.new()
	timer.wait_time = 20.0
	timer.autostart = true
	timer.timeout.connect(_save)
	add_child(timer)
	ready_done = true


func _save() -> void:
	if ready_done:
		world.save_world(player.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Dbg.put("notification %d" % what)
		_save()
