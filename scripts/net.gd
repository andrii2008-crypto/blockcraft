extends Node
# Сетевая игра: один игрок открывает мир (хост), остальные подключаются по адресу.
# Мир на всех устройствах генерируется из одного seed; хост рассылает правки блоков и позиции игроков.
# Позже сюда можно добавить выделенный сервер: протокол тот же.

const WorldScript = preload("res://scripts/world.gd")

signal joined(world_seed: int, mods: Dictionary)
signal failed(msg: String)
signal lost(msg: String)

const PORT := 7777

var world = null
var player: Node3D = null
var root: Node3D = null
var hosting := false
var connected := false
var in_game := false
var ext_ip := ""
var ext_status := ""
var upnp = null
var avatars := {}
var names := {}
var next_idx := 1
var peer_pos := {}
var send_t := 0.0
var foci_t := 0.0


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_left)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)


func bind_world(w: Node, p: Node3D, r: Node3D) -> void:
	world = w
	player = p
	root = r
	if not world.block_changed.is_connected(_on_block):
		world.block_changed.connect(_on_block)
	in_game = true


# ---------- хост ----------

func start_host(port: int = PORT) -> bool:
	stop()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, 8) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	hosting = true
	ext_ip = ""
	ext_status = "не удалось определить"
	_try_upnp(port)
	return true


func _try_upnp(port: int) -> void:
	upnp = ClassDB.instantiate("UPNP")
	if upnp == null:
		ext_status = "UPnP недоступен"
		return
	var res: int = upnp.discover(1500, 2, "InternetGatewayDevice")
	if res != 0:
		ext_status = "роутер не найден (нужна Wi-Fi сеть)"
		return
	if upnp.add_port_mapping(port, port, "BlockCraft", "UDP", 0) != 0:
		ext_status = "роутер не открыл порт"
		return
	ext_ip = str(upnp.query_external_address())
	ext_status = "ok" if ext_ip != "" else "адрес не получен"


func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s := str(a)
		var parts := s.split(".")
		if parts.size() == 4 and not s.begins_with("127.") and not s.begins_with("169.254."):
			out.append(s)
	return out


func info_lines() -> Array:
	var lines: Array = []
	var ips := local_ips()
	if ips.is_empty():
		lines.append("В этой сети: адрес не найден")
	for ip in ips:
		lines.append("В этой сети:  %s:%d" % [ip, PORT])
	if ext_status == "ok":
		lines.append("Через интернет:  %s:%d" % [ext_ip, PORT])
	else:
		lines.append("Через интернет: " + ext_status)
	lines.append("Игроков подключено: %d" % multiplayer.get_peers().size())
	return lines


# ---------- клиент ----------

func join(host: String, port: int) -> int:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func stop() -> void:
	if upnp != null and hosting:
		upnp.delete_port_mapping(PORT, "UDP")
	upnp = null
	var p := multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	hosting = false
	connected = false
	in_game = false
	peer_pos.clear()
	for id in avatars.keys():
		var n: Node3D = avatars[id]["node"]
		if is_instance_valid(n):
			n.queue_free()
	avatars.clear()
	names.clear()
	if world != null and is_instance_valid(world):
		world.extra_foci.clear()


func _on_connected() -> void:
	connected = true
	req_join.rpc_id(1)


func _on_conn_failed() -> void:
	stop()
	failed.emit("Сервер не отвечает")


func _on_server_lost() -> void:
	stop()
	lost.emit("Соединение с сервером потеряно")


func _on_peer_left(id: int) -> void:
	peer_pos.erase(id)
	if avatars.has(id):
		var n: Node3D = avatars[id]["node"]
		if is_instance_valid(n):
			n.queue_free()
		avatars.erase(id)


# ---------- RPC ----------

@rpc("any_peer", "reliable")
func req_join() -> void:
	if not hosting or world == null:
		return
	var id := multiplayer.get_remote_sender_id()
	join_info.rpc_id(id, world.seed_val, world.collect_modified())


@rpc("authority", "reliable")
func join_info(world_seed: int, mods: Dictionary) -> void:
	joined.emit(world_seed, mods)


func send_edit(p: Vector3i, b: int) -> void:
	if connected:
		req_edit.rpc_id(1, p, b)


@rpc("any_peer", "reliable")
func req_edit(p: Vector3i, b: int) -> void:
	if not hosting or world == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if b < 0 or b > WorldScript.SPRUCE_WOOD:
		return
	if world.get_block(p.x, p.y, p.z) == WorldScript.BEDROCK:
		return
	if peer_pos.has(id):
		var pp: Vector3 = peer_pos[id]
		if pp.distance_to(Vector3(p) + Vector3(0.5, 0.5, 0.5)) > 12.0:
			return
	world.set_block(p, b)


@rpc("authority", "reliable")
func apply_edit(p: Vector3i, b: int) -> void:
	if world != null:
		world.apply_remote_edit(p, b)


func _on_block(p: Vector3i, b: int) -> void:
	if hosting:
		apply_edit.rpc(p, b)


@rpc("any_peer", "unreliable")
func pos_update(pos: Vector3, yaw: float) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	peer_pos[id] = pos
	_set_remote(id, pos, yaw)
	remote_pos.rpc(id, pos, yaw)


@rpc("authority", "unreliable")
func remote_pos(id: int, pos: Vector3, yaw: float) -> void:
	if id == multiplayer.get_unique_id():
		return
	_set_remote(id, pos, yaw)


# ---------- аватары других игроков ----------

func _set_remote(id: int, pos: Vector3, yaw: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	if not avatars.has(id):
		var n := _make_avatar(id)
		n.position = pos
		root.add_child(n)
		avatars[id] = {"node": n, "target": pos, "yaw": yaw}
	else:
		avatars[id]["target"] = pos
		avatars[id]["yaw"] = yaw


func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	return mi


func _make_avatar(id: int) -> Node3D:
	var n := Node3D.new()
	var shirt := Color.from_hsv(fmod(id * 0.137, 1.0), 0.6, 0.9)
	var skin := Color(0.9, 0.75, 0.6)
	n.add_child(_box(Vector3(0.5, 0.7, 0.26), Vector3(0, 1.05, 0), shirt))
	n.add_child(_box(Vector3(0.46, 0.46, 0.46), Vector3(0, 1.63, 0), skin))
	n.add_child(_box(Vector3(0.23, 0.7, 0.23), Vector3(-0.13, 0.35, 0), Color(0.25, 0.3, 0.6)))
	n.add_child(_box(Vector3(0.23, 0.7, 0.23), Vector3(0.13, 0.35, 0), Color(0.25, 0.3, 0.6)))
	n.add_child(_box(Vector3(0.2, 0.7, 0.2), Vector3(-0.36, 1.05, 0), skin))
	n.add_child(_box(Vector3(0.2, 0.7, 0.2), Vector3(0.36, 1.05, 0), skin))
	var lab := Label3D.new()
	if id == 1:
		lab.text = "Хост"
	else:
		lab.text = "Игрок %d" % next_idx
		next_idx += 1
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.pixel_size = 0.008
	lab.font_size = 48
	lab.outline_size = 12
	lab.no_depth_test = true
	lab.position = Vector3(0, 2.15, 0)
	n.add_child(lab)
	return n


func _process(delta: float) -> void:
	if not in_game or player == null or not is_instance_valid(player):
		return
	if hosting or connected:
		send_t += delta
		if send_t >= 0.05:
			send_t = 0.0
			var pos: Vector3 = player.position
			var yaw: float = player.rotation.y
			if hosting:
				remote_pos.rpc(1, pos, yaw)
			else:
				pos_update.rpc_id(1, pos, yaw)
	var k := 1.0 - exp(-12.0 * delta)
	for id in avatars.keys():
		var n: Node3D = avatars[id]["node"]
		if not is_instance_valid(n):
			continue
		var tp: Vector3 = avatars[id]["target"]
		n.position = n.position.lerp(tp, k)
		n.rotation.y = lerp_angle(n.rotation.y, float(avatars[id]["yaw"]), k)
	if hosting and world != null and is_instance_valid(world):
		foci_t -= delta
		if foci_t <= 0.0:
			foci_t = 0.5
			world.extra_foci.clear()
			for id in avatars.keys():
				var tp2: Vector3 = avatars[id]["target"]
				world.extra_foci.append(tp2)
