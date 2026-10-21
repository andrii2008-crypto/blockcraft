extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const MenuScript = preload("res://scripts/menu.gd")
const Dbg = preload("res://scripts/dbg.gd")

const CFG_PATH := "user://settings.cfg"
const SAVE_PATH := "user://world2.dat"

var world: WorldScript
var player: Node3D
var hud = null
var game: Node3D = null
var menu = null
var cfg := {"rd": 4, "sens": 4, "coords": true}
var in_game := false
var paused := false
var slow_n := 0


func _ready() -> void:
	Dbg.start()
	Dbg.put("boot")
	Dbg.put("gpu " + RenderingServer.get_video_adapter_name() + " | " + OS.get_name())
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.75, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_load_cfg()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menu = MenuScript.new()
	layer.add_child(menu)
	menu.cfg = cfg
	menu.has_save = FileAccess.file_exists(SAVE_PATH)
	menu.play_pressed.connect(_start_game.bind(false))
	menu.new_world_pressed.connect(_start_game.bind(true))
	menu.resume_pressed.connect(_resume)
	menu.quit_to_menu_pressed.connect(_to_menu)
	menu.quit_game_pressed.connect(_quit)
	menu.settings_changed.connect(_on_settings)


func _load_cfg() -> void:
	var f := ConfigFile.new()
	if f.load(CFG_PATH) != OK:
		return
	cfg["rd"] = clampi(int(f.get_value("game", "rd", 4)), 2, 6)
	cfg["sens"] = clampi(int(f.get_value("game", "sens", 4)), 1, 8)
	cfg["coords"] = bool(f.get_value("game", "coords", true))


func _save_cfg() -> void:
	var f := ConfigFile.new()
	f.set_value("game", "rd", cfg["rd"])
	f.set_value("game", "sens", cfg["sens"])
	f.set_value("game", "coords", cfg["coords"])
	f.save(CFG_PATH)


func _on_settings() -> void:
	_save_cfg()
	if in_game:
		world.rd = int(cfg["rd"])
		player.sens = int(cfg["sens"]) * 0.001
		player.apply_view()
		hud.show_info = bool(cfg["coords"])


func _start_game(fresh: bool) -> void:
	Dbg.put("start game fresh=%s" % str(fresh))
	menu.visible = false
	game = Node3D.new()
	add_child(game)
	world = WorldScript.new()
	world.rd = int(cfg["rd"])
	world.fresh = fresh
	game.add_child(world)
	world.setup()
	player = PlayerScript.new()
	player.world = world
	player.sens = int(cfg["sens"]) * 0.001
	if world.has_saved_pos:
		player.position = world.saved_pos
		player.needs_spawn = false
	else:
		player.position = Vector3(world.spawn_xz.x, 40.0, world.spawn_xz.y)
	game.add_child(player)
	var layer := CanvasLayer.new()
	game.add_child(layer)
	hud = HudScript.new()
	layer.add_child(hud)
	hud.player = player
	hud.show_info = bool(cfg["coords"])
	player.hud = hud
	player.pause_requested.connect(_open_pause)
	var timer := Timer.new()
	timer.wait_time = 20.0
	timer.autostart = true
	timer.timeout.connect(_save)
	game.add_child(timer)
	in_game = true
	paused = false
	if fresh:
		world.save_world(player.position)


func _open_pause() -> void:
	if not in_game or paused:
		return
	paused = true
	_save()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	menu.open_pause()


func _resume() -> void:
	if not in_game:
		return
	paused = false
	game.process_mode = Node.PROCESS_MODE_INHERIT
	player.reset_touch()
	menu.visible = false


func _to_menu() -> void:
	_save()
	if game != null:
		game.queue_free()
		game = null
	in_game = false
	paused = false
	menu.has_save = FileAccess.file_exists(SAVE_PATH)
	menu.open_main()


func _quit() -> void:
	_save()
	get_tree().quit()


func _process(delta: float) -> void:
	if in_game and not paused and delta > 0.4 and slow_n < 12:
		slow_n += 1
		Dbg.put("slow frame %.2fs world=%.0fms player=%.0fms" % [delta, world.work_ms, player.proc_ms])


func _save() -> void:
	if in_game and world != null and player != null:
		world.save_world(player.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Dbg.put("notification %d" % what)
		_save()
		if in_game and not paused and what == NOTIFICATION_APPLICATION_PAUSED:
			_open_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if in_game:
			if paused:
				_resume()
			else:
				_open_pause()
		elif menu != null and not menu.go_back():
			_quit()
