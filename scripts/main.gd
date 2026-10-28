extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const MenuScript = preload("res://scripts/menu.gd")
const NetScript = preload("res://scripts/net.gd")
const Dbg = preload("res://scripts/dbg.gd")

const CFG_PATH := "user://settings.cfg"
const SAVE_PATH := "user://world2.dat"

var world: WorldScript
var player: Node3D
var hud = null
var game: Node3D = null
var menu = null
var net = null
var cfg := {"rd": 4, "sens": 4, "coords": true, "fps": 0, "servers": [], "last_addr": ""}
var in_game := false
var paused := false
var is_client := false
var slow_n := 0
var join_addr := ""


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
	_apply_perf()
	net = NetScript.new()
	net.name = "Net"
	add_child(net)
	net.joined.connect(_on_joined)
	net.failed.connect(_on_net_failed)
	net.lost.connect(_on_net_lost)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	menu = MenuScript.new()
	layer.add_child(menu)
	menu.cfg = cfg
	menu.has_save = FileAccess.file_exists(SAVE_PATH)
	menu.info_cb = net.info_lines
	menu.play_pressed.connect(_start_game.bind(false))
	menu.new_world_pressed.connect(_start_game.bind(true))
	menu.resume_pressed.connect(_resume)
	menu.quit_to_menu_pressed.connect(_to_menu)
	menu.quit_game_pressed.connect(_quit)
	menu.settings_changed.connect(_on_settings)
	menu.join_requested.connect(_on_join_requested)
	menu.cancel_connect.connect(_on_cancel_connect)
	menu.host_requested.connect(_host_start)
	menu.host_stop_requested.connect(_host_stop)


func _load_cfg() -> void:
	var f := ConfigFile.new()
	if f.load(CFG_PATH) != OK:
		return
	cfg["rd"] = clampi(int(f.get_value("game", "rd", 4)), 2, 6)
	cfg["sens"] = clampi(int(f.get_value("game", "sens", 4)), 1, 8)
	cfg["coords"] = bool(f.get_value("game", "coords", true))
	cfg["fps"] = int(f.get_value("game", "fps", 0))
	cfg["servers"] = f.get_value("game", "servers", [])
	cfg["last_addr"] = str(f.get_value("game", "last_addr", ""))


func _save_cfg() -> void:
	var f := ConfigFile.new()
	f.set_value("game", "rd", cfg["rd"])
	f.set_value("game", "sens", cfg["sens"])
	f.set_value("game", "coords", cfg["coords"])
	f.set_value("game", "fps", cfg["fps"])
	f.set_value("game", "servers", cfg["servers"])
	f.set_value("game", "last_addr", cfg["last_addr"])
	f.save(CFG_PATH)


func _apply_perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(cfg["fps"])


func _on_settings() -> void:
	_save_cfg()
	_apply_perf()
	if in_game:
		world.rd = int(cfg["rd"])
		player.sens = int(cfg["sens"]) * 0.001
		player.apply_view()
		hud.show_info = bool(cfg["coords"])


# ---------- игра ----------

func _start_game(fresh: bool) -> void:
	Dbg.put("start game fresh=%s" % str(fresh))
	_build_game(fresh, -1, {}, false)


func _build_game(fresh: bool, forced_seed: int, mods: Dictionary, client: bool) -> void:
	menu.visible = false
	is_client = client
	game = Node3D.new()
	add_child(game)
	world = WorldScript.new()
	world.rd = int(cfg["rd"])
	world.fresh = fresh
	world.forced_seed = forced_seed
	world.is_client = client
	if client:
		world.net = net
		world.saved = mods
		for k in mods.keys():
			world.modified[k] = true
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
	net.bind_world(world, player, game)
	if fresh and not client:
		world.save_world(player.position)


func _open_pause() -> void:
	if not in_game or paused:
		return
	paused = true
	_save()
	if net.hosting or is_client:
		player.reset_touch()
		player.set_process_input(false)
	else:
		game.process_mode = Node.PROCESS_MODE_DISABLED
	menu.net_mode = 2 if is_client else (1 if net.hosting else 0)
	menu.open_pause()


func _resume() -> void:
	if not in_game:
		return
	paused = false
	game.process_mode = Node.PROCESS_MODE_INHERIT
	player.set_process_input(true)
	player.reset_touch()
	menu.visible = false


func _to_menu() -> void:
	_save()
	net.stop()
	if game != null:
		game.queue_free()
		game = null
	in_game = false
	paused = false
	is_client = false
	menu.net_mode = 0
	menu.has_save = FileAccess.file_exists(SAVE_PATH)
	menu.open_main()


func _quit() -> void:
	_save()
	net.stop()
	get_tree().quit()


# ---------- сеть ----------

func _host_start() -> void:
	if not in_game:
		return
	if net.start_host():
		net.bind_world(world, player, game)
		menu.net_mode = 1
		menu.open_host_info()
	else:
		menu.net_mode = 0
		menu.show_message("Ошибка", ["Не удалось открыть порт %d" % NetScript.PORT], false)
		menu.msg_back = menu.PAUSE


func _host_stop() -> void:
	net.stop()
	net.bind_world(world, player, game)
	net.in_game = true
	menu.net_mode = 0
	menu.open_pause()


func _on_join_requested(addr: String) -> void:
	var host := addr.strip_edges()
	var port := NetScript.PORT
	var ci := host.rfind(":")
	if ci > 0:
		port = int(host.substr(ci + 1))
		host = host.substr(0, ci)
	if host == "" or port <= 0 or port > 65535:
		menu.show_message("Неверный адрес", ["Пример: 192.168.0.5:7777"], true)
		return
	cfg["last_addr"] = addr.strip_edges()
	_save_cfg()
	join_addr = addr.strip_edges()
	menu.show_connecting(join_addr)
	if net.join(host, port) != OK:
		net.stop()
		menu.show_message("Не удалось подключиться", [join_addr], true)


func _on_cancel_connect() -> void:
	net.stop()


func _on_joined(world_seed: int, mods: Dictionary) -> void:
	if in_game:
		return
	Dbg.put("joined seed=%d mods=%d" % [world_seed, mods.size()])
	_build_game(true, world_seed, mods, true)


func _on_net_failed(msg: String) -> void:
	menu.show_message("Не удалось подключиться", [join_addr, msg], true)


func _on_net_lost(msg: String) -> void:
	if in_game:
		_to_menu()
	menu.show_message("Отключено", [msg], false)


func _process(delta: float) -> void:
	if in_game and not paused and delta > 0.4 and slow_n < 12:
		slow_n += 1
		Dbg.put("slow frame %.2fs world=%.0fms player=%.0fms" % [delta, world.work_ms, player.proc_ms])


func _save() -> void:
	if in_game and not is_client and world != null and player != null:
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
				if menu.state == menu.HOST_INFO or menu.state == menu.SETTINGS:
					menu.go_back()
				else:
					_resume()
			else:
				_open_pause()
		elif menu != null and not menu.go_back():
			_quit()
