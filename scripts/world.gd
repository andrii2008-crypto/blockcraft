extends Node3D
# Бесконечный мир: биомы, океаны, реки, горы, пещеры, руды, деревья.
# Чанки генерируются и строятся в фоновых потоках.

const CS := 16
const SY := 64
const SEA := 22
const VOL := CS * SY * CS      # в байте [VOL] хранится максимальная высота чанка
const RD := 4                  # дальность прорисовки в чанках
const MAX_GEN := 3
const MAX_MESH := 3
const SAVE_PATH := "user://world2.dat"
const Dbg = preload("res://scripts/dbg.gd")

enum { AIR, GRASS, DIRT, STONE, WOOD, LEAVES, PLANKS, SAND, BRICK, WATER, BEDROCK, GRAVEL, SNOW, CACTUS, SPRUCE_LEAVES, COAL, IRON, GOLD, DIAMOND }
enum { B_OCEAN, B_BEACH, B_PLAINS, B_FOREST, B_DESERT, B_SNOWY, B_MOUNTAIN }

const CORNERS := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
const SHADE := [0.8, 0.8, 1.0, 0.5, 0.65, 0.65]
const FACE_PAL := [1, 1, 0, 2, 1, 1]   # 0 = верх, 1 = бок, 2 = низ

var seed_val := 0
var chunks := {}          # Vector2i -> PackedByteArray
var meshes := {}
var meshed := {}
var mesh_ver := {}
var gen_pending := {}
var mesh_pending := {}
var modified := {}
var saved := {}
var gen_results: Array = []
var mesh_results: Array = []
var mutex := Mutex.new()
var material: StandardMaterial3D
var water_material: StandardMaterial3D
var pal: Array = []
var focus := Vector3.ZERO
var spawn_xz := Vector2i.ZERO
var has_saved_pos := false
var saved_pos := Vector3.ZERO
var sched_timer := 0.0
var unload_timer := 0.0
var n_gen := 0
var n_mesh := 0
var n_req := 0
var n_mreq := 0


func setup() -> void:
	_init_palette()
	material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_material = StandardMaterial3D.new()
	water_material.vertex_color_use_as_albedo = true
	water_material.vertex_color_is_srgb = true
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not load_world():
		seed_val = randi() % 1000000
	spawn_xz = find_spawn()
	if has_saved_pos:
		focus = saved_pos
	else:
		focus = Vector3(spawn_xz.x, 0.0, spawn_xz.y)


func _init_palette() -> void:
	var dirt := Color(0.47, 0.34, 0.22)
	var stone := Color(0.5, 0.5, 0.53)
	var wood_side := Color(0.4, 0.3, 0.18)
	var wood_end := Color(0.66, 0.53, 0.32)
	var leaves := Color(0.2, 0.5, 0.15)
	var sleaves := Color(0.12, 0.33, 0.2)
	var planks := Color(0.72, 0.56, 0.32)
	var sand := Color(0.86, 0.8, 0.55)
	var brick := Color(0.6, 0.25, 0.2)
	var water := Color(0.2, 0.4, 0.85, 0.55)
	var bedrock := Color(0.17, 0.17, 0.18)
	var gravel := Color(0.55, 0.53, 0.52)
	var snow := Color(0.95, 0.97, 1.0)
	var cactus := Color(0.15, 0.45, 0.18)
	pal.resize(19)
	pal[AIR] = [Color.BLACK, Color.BLACK, Color.BLACK]
	pal[GRASS] = [Color(0.36, 0.65, 0.22), dirt, dirt]
	pal[DIRT] = [dirt, dirt, dirt]
	pal[STONE] = [stone, stone, stone]
	pal[WOOD] = [wood_end, wood_side, wood_end]
	pal[LEAVES] = [leaves, leaves, leaves]
	pal[PLANKS] = [planks, planks, planks]
	pal[SAND] = [sand, sand, sand]
	pal[BRICK] = [brick, brick, brick]
	pal[WATER] = [water, water, water]
	pal[BEDROCK] = [bedrock, bedrock, bedrock]
	pal[GRAVEL] = [gravel, gravel, gravel]
	pal[SNOW] = [snow, snow, snow]
	pal[CACTUS] = [Color(0.2, 0.52, 0.2), cactus, cactus]
	pal[SPRUCE_LEAVES] = [sleaves, sleaves, sleaves]
	pal[COAL] = [Color(0.12, 0.12, 0.14), Color(0.12, 0.12, 0.14), Color(0.12, 0.12, 0.14)]
	pal[IRON] = [Color(0.82, 0.62, 0.5), Color(0.82, 0.62, 0.5), Color(0.82, 0.62, 0.5)]
	pal[GOLD] = [Color(0.98, 0.82, 0.15), Color(0.98, 0.82, 0.15), Color(0.98, 0.82, 0.15)]
	pal[DIAMOND] = [Color(0.3, 0.92, 0.92), Color(0.3, 0.92, 0.92), Color(0.3, 0.92, 0.92)]


# ---------- доступ к блокам ----------

func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return STONE
	if y >= SY:
		return AIR
	var c: PackedByteArray = chunks.get(Vector2i(x >> 4, z >> 4), PackedByteArray())
	if c.is_empty():
		return STONE   # чанк ещё не создан: считаем стеной
	return c[((y << 4) + (z & 15)) * 16 + (x & 15)]


func is_solid(x: int, y: int, z: int) -> bool:
	var b := get_block(x, y, z)
	return b != AIR and b != WATER


func ready_at(p: Vector3) -> bool:
	var k := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
	return chunks.has(k) and meshed.has(k)


func surface_y(x: int, z: int) -> int:
	for y in range(SY - 1, -1, -1):
		var b := get_block(x, y, z)
		if b == AIR or b == LEAVES or b == SPRUCE_LEAVES or b == WOOD or b == CACTUS:
			continue
		return y + 1
	return SY


func set_block(p: Vector3i, b: int) -> void:
	if p.y < 0 or p.y >= SY:
		return
	var key := Vector2i(p.x >> 4, p.z >> 4)
	var arr: PackedByteArray = chunks.get(key, PackedByteArray())
	if arr.is_empty():
		return
	arr[(p.y * CS + (p.z & 15)) * CS + (p.x & 15)] = b
	if b != AIR and p.y > arr[VOL]:
		arr[VOL] = p.y
	chunks[key] = arr
	modified[key] = true
	_remesh(key)
	var lx := p.x & 15
	var lz := p.z & 15
	if lx == 0:
		_remesh(key + Vector2i(-1, 0))
	if lx == 15:
		_remesh(key + Vector2i(1, 0))
	if lz == 0:
		_remesh(key + Vector2i(0, -1))
	if lz == 15:
		_remesh(key + Vector2i(0, 1))


func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var pos := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for i in 3:
		if dir[i] > 0.0:
			step[i] = 1
			t_delta[i] = 1.0 / dir[i]
			t_max[i] = (pos[i] + 1 - origin[i]) / dir[i]
		elif dir[i] < 0.0:
			step[i] = -1
			t_delta[i] = -1.0 / dir[i]
			t_max[i] = (pos[i] - origin[i]) / dir[i]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var b := get_block(pos.x, pos.y, pos.z)
		if b != AIR and b != WATER:
			return {"pos": pos, "normal": normal}
		var axis := 0
		if t_max.y < t_max[axis]:
			axis = 1
		if t_max.z < t_max[axis]:
			axis = 2
		t = t_max[axis]
		pos[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}


# ---------- шум и генерация ----------

func _hash(x: int, y: int, z: int, s: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + z * 1274126177 + (s + seed_val) * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


func _make_noise(s: int, freq: float, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_val + s * 101
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = oct
	return n


func _noises() -> Array:
	return [
		_make_noise(1, 0.006, 3),   # материки
		_make_noise(2, 0.02, 4),    # холмы
		_make_noise(3, 0.012, 2),   # горные хребты
		_make_noise(4, 0.006, 1),   # реки
		_make_noise(5, 0.007, 1),   # температура
		_make_noise(6, 0.007, 1),   # влажность
	]


# Возвращает Vector2i(высота, биом) для колонки (x, z)
func _column(n: Array, x: int, z: int) -> Vector2i:
	var cn: FastNoiseLite = n[0]
	var hn: FastNoiseLite = n[1]
	var rn: FastNoiseLite = n[2]
	var vn: FastNoiseLite = n[3]
	var tn: FastNoiseLite = n[4]
	var un: FastNoiseLite = n[5]
	var c := cn.get_noise_2d(x, z)
	var hill := hn.get_noise_2d(x, z)
	var ridge := 1.0 - absf(rn.get_noise_2d(x, z))
	var land := smoothstep(-0.2, 0.12, c)
	var mtn := clampf((c - 0.28) * 3.0, 0.0, 1.0)
	var hf := SEA + c * 12.0 + hill * 4.5 * (0.4 + land) + mtn * mtn * 20.0 * (0.4 + 0.6 * ridge)
	var river := absf(vn.get_noise_2d(x, z))
	var w := clampf(1.0 - river / 0.035, 0.0, 1.0) * land * (1.0 - mtn)
	hf = lerpf(hf, SEA - 2.5, w)
	var h := clampi(int(hf), 3, SY - 10)
	var t := tn.get_noise_2d(x, z)
	var hu := un.get_noise_2d(x, z)
	var biome: int = B_PLAINS
	if h < SEA:
		biome = B_OCEAN
	elif h <= SEA + 1:
		biome = B_BEACH
	elif h >= SEA + 20:
		biome = B_MOUNTAIN
	elif t > 0.3 and hu < 0.1:
		biome = B_DESERT
	elif t < -0.3:
		biome = B_SNOWY
	elif hu > 0.12:
		biome = B_FOREST
	return Vector2i(h, biome)


func find_spawn() -> Vector2i:
	var n := _noises()
	for r in range(0, 1600, 16):
		for a in 12:
			var ang := a * TAU / 12.0
			var x := int(cos(ang) * r)
			var z := int(sin(ang) * r)
			var info := _column(n, x, z)
			if info.x >= SEA + 2 and (info.y == B_PLAINS or info.y == B_FOREST or info.y == B_DESERT):
				return Vector2i(x, z)
	return Vector2i.ZERO


func _put(out: PackedByteArray, x0: int, z0: int, x: int, y: int, z: int, b: int, only_air: bool) -> void:
	var lx := x - x0
	var lz := z - z0
	if lx < 0 or lx >= CS or lz < 0 or lz >= CS or y < 0 or y >= SY:
		return
	var i := (y * CS + lz) * CS + lx
	if only_air and out[i] != AIR:
		return
	out[i] = b
	if y > out[VOL]:
		out[VOL] = y


func _gen_chunk(cx: int, cz: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(VOL + 1)
	var n := _noises()
	var cave_a := _make_noise(20, 0.025, 1)
	var cave_b := _make_noise(21, 0.025, 1)
	var x0 := cx * CS
	var z0 := cz * CS
	var w := CS + 4
	var hs := PackedInt32Array()
	var bs := PackedInt32Array()
	hs.resize(w * w)
	bs.resize(w * w)
	for lz in w:
		for lx in w:
			var info := _column(n, x0 + lx - 2, z0 + lz - 2)
			hs[lz * w + lx] = info.x
			bs[lz * w + lx] = info.y
	var top := 0
	for lz in CS:
		for lx in CS:
			var k := (lz + 2) * w + lx + 2
			var h: int = hs[k]
			var biome: int = bs[k]
			var x := x0 + lx
			var z := z0 + lz
			var top_b: int = GRASS
			var fill_b: int = DIRT
			if biome == B_OCEAN:
				top_b = SAND if h >= SEA - 6 else GRAVEL
				fill_b = top_b
			elif biome == B_BEACH or biome == B_DESERT:
				top_b = SAND
				fill_b = SAND
			elif biome == B_SNOWY:
				top_b = SNOW
			elif biome == B_MOUNTAIN:
				top_b = SNOW if h >= SEA + 26 else STONE
				fill_b = STONE
			for y in range(h + 1):
				var b: int = STONE
				if y == h:
					b = top_b
				elif y >= h - 3:
					b = fill_b
				if y == 0:
					b = BEDROCK
				elif y < 4 and _hash(x, y, z, 9) < 0.5:
					b = BEDROCK
				elif y >= 4 and y <= h - 2:
					var yf := y * 1.5
					if absf(cave_a.get_noise_3d(x, yf, z)) < 0.07 and absf(cave_b.get_noise_3d(x, yf, z)) < 0.07:
						b = AIR
					elif b == STONE:
						var hc := _hash(x >> 1, y >> 1, z >> 1, 3)
						var oc: int = AIR
						if hc < 0.018:
							oc = COAL
						elif hc < 0.028 and y < 40:
							oc = IRON
						elif hc < 0.0325 and y < 24:
							oc = GOLD
						elif hc < 0.0345 and y < 14:
							oc = DIAMOND
						if oc != AIR and _hash(x, y, z, 7) < 0.7:
							b = oc
				if b != AIR:
					out[(y * CS + lz) * CS + lx] = b
			if h < SEA:
				for y in range(h + 1, SEA + 1):
					out[(y * CS + lz) * CS + lx] = WATER
				top = maxi(top, SEA)
			else:
				top = maxi(top, h)
	out[VOL] = top
	# деревья и кактусы (с запасом 2 блока за границей чанка, чтобы кроны не обрезались)
	for lz in w:
		for lx in w:
			var k := lz * w + lx
			var biome: int = bs[k]
			var h: int = hs[k]
			if h < SEA + 2:
				continue
			var p := 0.0
			if biome == B_FOREST:
				p = 0.03
			elif biome == B_PLAINS:
				p = 0.004
			elif biome == B_SNOWY:
				p = 0.012
			elif biome == B_DESERT:
				p = 0.004
			if p == 0.0:
				continue
			var wx := x0 + lx - 2
			var wz := z0 + lz - 2
			if _hash(wx, wz, 0, 11) >= p:
				continue
			var r2 := _hash(wx, wz, 1, 12)
			if biome == B_DESERT:
				var ch := 1 + int(r2 * 3.0)
				for i in range(1, ch + 1):
					_put(out, x0, z0, wx, h + i, wz, CACTUS, false)
			elif biome == B_SNOWY:
				var th := 5 + int(r2 * 3.0)
				for i in range(1, th + 1):
					_put(out, x0, z0, wx, h + i, wz, WOOD, false)
				var topy := h + th + 1
				for y in range(h + 3, topy + 1):
					var d := topy - y
					var r := 0 if d == 0 else 1 + (d % 2)
					for dx in range(-r, r + 1):
						for dz in range(-r, r + 1):
							if r == 2 and absi(dx) == 2 and absi(dz) == 2:
								continue
							_put(out, x0, z0, wx + dx, y, wz + dz, SPRUCE_LEAVES, true)
			else:
				var th := 4 + int(r2 * 3.0)
				for i in range(1, th + 1):
					_put(out, x0, z0, wx, h + i, wz, WOOD, false)
				var ty := h + th
				for dy in range(-2, 2):
					var r := 2 if dy < 0 else 1
					for dx in range(-r, r + 1):
						for dz in range(-r, r + 1):
							if absi(dx) == r and absi(dz) == r:
								if dy >= 0 or _hash(wx + dx, ty + dy, wz + dz, 13) < 0.4:
									continue
							_put(out, x0, z0, wx + dx, ty + dy, wz + dz, LEAVES, true)
	return out


# ---------- построение мешей ----------

func _quad(v: PackedVector3Array, cl: PackedColorArray, ix: PackedInt32Array, pos: Vector3, f: int, b: int, jit: float, lower: bool) -> void:
	var base := v.size()
	var shade: float = SHADE[f] + jit
	var fp: int = FACE_PAL[f]
	var corners: Array = CORNERS[f]
	var ore := b >= COAL and b <= DIAMOND
	for k in 4:
		var c: Vector3 = corners[k]
		var cy := c.y
		if lower and cy > 0.5:
			cy = 0.9
		v.append(pos + Vector3(c.x, cy, c.z))
		var col: Color = pal[b][fp]
		if b == GRASS and fp == 1 and c.y > 0.5:
			col = pal[b][0]
		elif ore and (k & 1) == 0:
			col = pal[STONE][0]
		cl.append(Color(col.r * shade, col.g * shade, col.b * shade, col.a))
	ix.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _pack(v: PackedVector3Array, cl: PackedColorArray, ix: PackedInt32Array):
	if v.is_empty():
		return null
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_COLOR] = cl
	a[Mesh.ARRAY_INDEX] = ix
	return a


func _mesh_data(ox: int, oz: int, c: PackedByteArray, px: PackedByteArray, nx: PackedByteArray, pz: PackedByteArray, nz: PackedByteArray) -> Array:
	var sv := PackedVector3Array()
	var sc := PackedColorArray()
	var si := PackedInt32Array()
	var wv := PackedVector3Array()
	var wc := PackedColorArray()
	var wi := PackedInt32Array()
	var top: int = c[VOL]
	for y in range(0, mini(top + 2, SY)):
		for lz in CS:
			for lx in CS:
				var i := (y * CS + lz) * CS + lx
				var b: int = c[i]
				if b == AIR:
					continue
				var n0: int = c[i + 1] if lx < 15 else px[i - 15]
				var n1: int = c[i - 1] if lx > 0 else nx[i + 15]
				var n2: int = c[i + 256] if y < SY - 1 else AIR
				var n3: int = c[i - 256] if y > 0 else STONE
				var n4: int = c[i + 16] if lz < 15 else pz[i - 240]
				var n5: int = c[i - 16] if lz > 0 else nz[i + 240]
				var tw: int = -1 if b == WATER else WATER
				var vis := 0
				if n0 == AIR or n0 == tw:
					vis |= 1
				if n1 == AIR or n1 == tw:
					vis |= 2
				if n2 == AIR or n2 == tw:
					vis |= 4
				if n3 == AIR or n3 == tw:
					vis |= 8
				if n4 == AIR or n4 == tw:
					vis |= 16
				if n5 == AIR or n5 == tw:
					vis |= 32
				if vis == 0:
					continue
				var jit := (_hash(ox + lx, y, oz + lz, 5) - 0.5) * 0.1
				var pos := Vector3(lx, y, lz)
				var lower := b == WATER and n2 != WATER
				for f in 6:
					if (vis & (1 << f)) == 0:
						continue
					if b == WATER:
						_quad(wv, wc, wi, pos, f, b, jit, lower)
					else:
						_quad(sv, sc, si, pos, f, b, jit, false)
	return [_pack(sv, sc, si), _pack(wv, wc, wi)]


func _apply(key: Vector2i, res: Array) -> void:
	var mi: MeshInstance3D = meshes.get(key)
	var mesh := ArrayMesh.new()
	var s := 0
	if res[0] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res[0])
		mesh.surface_set_material(s, material)
		s += 1
	if res[1] != null:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res[1])
		mesh.surface_set_material(s, water_material)
		s += 1
	if s == 0:
		if mi != null:
			mi.mesh = null
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.position = Vector3(key.x * CS, 0, key.y * CS)
		add_child(mi)
		meshes[key] = mi
	mi.mesh = mesh


func _remesh(key: Vector2i) -> void:
	var c: PackedByteArray = chunks.get(key, PackedByteArray())
	var px: PackedByteArray = chunks.get(key + Vector2i(1, 0), PackedByteArray())
	var nx: PackedByteArray = chunks.get(key + Vector2i(-1, 0), PackedByteArray())
	var pz: PackedByteArray = chunks.get(key + Vector2i(0, 1), PackedByteArray())
	var nz: PackedByteArray = chunks.get(key + Vector2i(0, -1), PackedByteArray())
	if c.is_empty() or px.is_empty() or nx.is_empty() or pz.is_empty() or nz.is_empty():
		return
	mesh_ver[key] = int(mesh_ver.get(key, 0)) + 1
	_apply(key, _mesh_data(key.x * CS, key.y * CS, c, px, nx, pz, nz))
	meshed[key] = true


# ---------- подгрузка чанков (без потоков: одно задание за кадр) ----------

var want: Array[Vector2i] = []
var work_ms := 0.0
var toggle := false


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	sched_timer -= delta
	if sched_timer <= 0.0:
		sched_timer = 0.15
		_update_want()
	toggle = not toggle
	if toggle:
		if not _do_gen():
			_do_mesh()
	else:
		if not _do_mesh():
			_do_gen()
	unload_timer -= delta
	if unload_timer <= 0.0:
		unload_timer = 1.5
		_unload()
	work_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _update_want() -> void:
	var fc := Vector2i(floori(focus.x / 16.0), floori(focus.z / 16.0))
	want.clear()
	for dz in range(-RD, RD + 1):
		for dx in range(-RD, RD + 1):
			if dx * dx + dz * dz <= RD * RD:
				want.append(fc + Vector2i(dx, dz))
	want.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - fc).length_squared() < (b - fc).length_squared())


func _do_gen() -> bool:
	for k in want:
		if chunks.has(k):
			continue
		var s: Variant = saved.get(k)
		if s != null:
			chunks[k] = s
		else:
			chunks[k] = _gen_chunk(k.x, k.y)
		n_gen += 1
		if n_gen <= 6 or n_gen % 25 == 0:
			Dbg.put("gen %d %s" % [n_gen, str(k)])
		return true
	return false


func _do_mesh() -> bool:
	for k in want:
		if meshed.has(k) or not chunks.has(k):
			continue
		if chunks.has(k + Vector2i(1, 0)) and chunks.has(k + Vector2i(-1, 0)) and chunks.has(k + Vector2i(0, 1)) and chunks.has(k + Vector2i(0, -1)):
			_remesh(k)
			n_mesh += 1
			if n_mesh <= 6 or n_mesh % 25 == 0:
				Dbg.put("mesh %d %s" % [n_mesh, str(k)])
			return true
	return false


func _unload() -> void:
	var fc := Vector2i(floori(focus.x / 16.0), floori(focus.z / 16.0))
	var lim := (RD + 3) * (RD + 3)
	for kv in chunks.keys():
		var k: Vector2i = kv
		if (k - fc).length_squared() <= lim:
			continue
		if modified.has(k):
			saved[k] = chunks[k]
		chunks.erase(k)
		meshed.erase(k)
		mesh_ver.erase(k)
		if meshes.has(k):
			var mi: MeshInstance3D = meshes[k]
			mi.queue_free()
			meshes.erase(k)


func _top_block(x: int, z: int) -> int:
	for y in range(SY - 1, -1, -1):
		var b := get_block(x, y, z)
		if b != AIR:
			return b
	return AIR


# Ближайшая к (x, z) колонка без дерева/кактуса/воды, чтобы не появиться внутри ствола
func clear_spawn(x: int, z: int) -> Vector2i:
	for r in range(0, 9):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var cx := x + dx
				var cz := z + dz
				if not chunks.has(Vector2i(cx >> 4, cz >> 4)):
					continue
				var tb := _top_block(cx, cz)
				if tb != WOOD and tb != LEAVES and tb != SPRUCE_LEAVES and tb != CACTUS and tb != WATER:
					return Vector2i(cx, cz)
	return Vector2i(x, z)


# ---------- сохранение ----------

func save_world(pos: Vector3) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	var d := {}
	for kv in modified.keys():
		var k: Vector2i = kv
		if chunks.has(k):
			d[k] = chunks[k]
		elif saved.has(k):
			d[k] = saved[k]
	f.store_var({"seed": seed_val, "pos": pos, "chunks": d})
	f.close()


func load_world() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var v: Variant = f.get_var()
	f.close()
	if typeof(v) != TYPE_DICTIONARY or not v.has("seed") or not v.has("chunks"):
		return false
	seed_val = int(v["seed"])
	saved_pos = v["pos"]
	has_saved_pos = true
	var d: Dictionary = v["chunks"]
	for kv in d.keys():
		var k: Vector2i = kv
		saved[k] = d[k]
		modified[k] = true
	return true
