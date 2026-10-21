extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const Dbg = preload("res://scripts/dbg.gd")

var world: WorldScript
var player: Node3D
var ready_done := false
var slow_n := 0


func _ready() -> void:
	var prev := Dbg.start()
	Dbg.put("boot")
	Dbg.put("gpu " + RenderingServer.get_video_adapter_name() + " | " + OS.get_name())
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95)
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


func _process(delta: float) -> void:
	if ready_done and delta > 0.4 and slow_n < 12:
		slow_n += 1
		Dbg.put("slow frame %.2fs world=%.0fms player=%.0fms" % [delta, world.work_ms, player.proc_ms])


func _save() -> void:
	if ready_done:
		world.save_world(player.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_CLOSE_REQUEST \
			or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Dbg.put("notification %d" % what)
		_save()
