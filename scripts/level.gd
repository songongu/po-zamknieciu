class_name Level
extends Node3D
## Proceduralny sklep meblowy: labirynt ekspozycji (siatka komórek) + magazyn z regałami.

const GW := 10
const GH := 10
const CELL := 7.0
const WALL_H := 3.3
const RACK_H := 5.0
const CEIL_H := 6.5
const WH_ROWS := 3
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const SIDE_DIR := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

const THEMES := ["SALON", "SYPIALNIA", "KUCHNIA", "BIURO", "DZIECI", "ŁAZIENKA"]
const THEME_SIGNS := {"SALON": "SALONY", "SYPIALNIA": "SYPIALNIE", "KUCHNIA": "KUCHNIE",
	"BIURO": "DOMOWE BIURO", "DZIECI": "POKÓJ DZIECIĘCY", "ŁAZIENKA": "ŁAZIENKI"}
const WALL_PIECES := {
	"SALON": ["sofa", "shelf", "tv", "lamp", "shelf", "sofa", "wardrobe"],
	"SYPIALNIA": ["bed", "wardrobe", "wardrobe", "dresser", "lamp", "bed"],
	"KUCHNIA": ["kitchen", "kitchen", "fridge", "shelf"],
	"BIURO": ["desk", "shelf", "shelf", "wardrobe", "lamp", "desk"],
	"DZIECI": ["kidbed", "toybox", "wardrobe", "shelf"],
	"ŁAZIENKA": ["bath", "sinkcab", "wardrobe", "sinkcab"],
}
const ISLANDS := {
	"SALON": ["coffee", "armchair", "rug"],
	"SYPIALNIA": ["rug"],
	"KUCHNIA": ["dining", "dining"],
	"BIURO": ["rug", "armchair"],
	"DZIECI": ["toys", "rug"],
	"ŁAZIENKA": ["rug"],
	"MAGAZYN": ["pallet", "pallet", "boxes"],
}
const ISLAND_HALF := {"coffee": 0.7, "armchair": 0.5, "rug": 0.0, "dining": 0.95, "toys": 0.0, "pallet": 0.65, "boxes": 0.7}

const FABRIC := [Color(0.22, 0.28, 0.45), Color(0.55, 0.18, 0.2), Color(0.28, 0.4, 0.3), Color(0.7, 0.6, 0.42),
	Color(0.17, 0.17, 0.2), Color(0.48, 0.32, 0.5), Color(0.75, 0.72, 0.65)]
const WOOD := [Color(0.55, 0.4, 0.25), Color(0.85, 0.74, 0.55), Color(0.25, 0.16, 0.1), Color(0.9, 0.9, 0.87), Color(0.12, 0.12, 0.13)]
const WALLS := [Color(0.82, 0.8, 0.74), Color(0.55, 0.62, 0.52), Color(0.72, 0.55, 0.55), Color(0.78, 0.66, 0.38),
	Color(0.3, 0.38, 0.55), Color(0.85, 0.85, 0.85), Color(0.42, 0.3, 0.4)]
const BRIGHT := [Color(0.9, 0.2, 0.15), Color(0.15, 0.5, 0.9), Color(0.95, 0.8, 0.1), Color(0.2, 0.7, 0.3), Color(0.8, 0.3, 0.7)]

const SYL_A := ["BJÖR", "KLÄ", "STRÅ", "NÖT", "GRÄ", "FJÄ", "LUND", "HEM", "SKOG", "MÖRK", "DÖD", "SVÄRT", "TYST", "GLÖM", "KVÄLL", "BLÅ", "EKE", "HÖG", "SÖM", "VÄLK"]
const SYL_B := ["SNÄS", "BY", "VIK", "HULT", "STAD", "LÖV", "ÅS", "RYD", "FORS", "MO", "BERG", "NING", "STA", "HOLM"]

var rng := RandomNumberGenerator.new()
var hwall := {}
var vwall := {}
var astar := AStar2D.new()
var theme := {}
var start_cell := Vector2i(0, 0)
var exit_cell := Vector2i()
var exit_pos := Vector3()
var dist_from_start := {}
var lamps: Array = []      # {light, mesh, pos, radius, energy, flicker, on, col}
var labels: Array = []     # {node, text}
var wardrobes: Array = []
var screens: Array = []
var mats := {}
var wmats := {}
var surf_shader: Shader
var arrow_shader: Shader
var statics: StaticBody3D


# ---------------------------------------------------------------- generacja

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GW and c.y < GH


func is_wh(c: Vector2i) -> bool:
	return c.y >= GH - WH_ROWS


func cid(c: Vector2i) -> int:
	return c.y * GW + c.x


func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / CELL)), 0, GW - 1), clampi(int(floor(p.z / CELL)), 0, GH - 1))


func blocked(a: Vector2i, b: Vector2i) -> bool:
	if b.x == a.x + 1:
		return vwall[Vector2i(a.x + 1, a.y)]
	if b.x == a.x - 1:
		return vwall[a]
	if b.y == a.y + 1:
		return hwall[Vector2i(a.x, a.y + 1)]
	return hwall[a]


func _set_open(a: Vector2i, b: Vector2i) -> void:
	if b.x == a.x + 1:
		vwall[Vector2i(a.x + 1, a.y)] = false
	elif b.x == a.x - 1:
		vwall[a] = false
	elif b.y == a.y + 1:
		hwall[Vector2i(a.x, a.y + 1)] = false
	else:
		hwall[a] = false


func _side_wall(c: Vector2i, side: int) -> bool:
	match side:
		0: return hwall[Vector2i(c.x, c.y)]
		1: return hwall[Vector2i(c.x, c.y + 1)]
		2: return vwall[Vector2i(c.x, c.y)]
		_: return vwall[Vector2i(c.x + 1, c.y)]


func generate(seed_v: int) -> void:
	rng.seed = seed_v
	for x in GW:
		for y in GH + 1:
			hwall[Vector2i(x, y)] = true
	for x in GW + 1:
		for y in GH:
			vwall[Vector2i(x, y)] = true
	# labirynt DFS
	var visited := {Vector2i(0, 0): true}
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var nb: Array[Vector2i] = []
		for d in DIRS:
			var n: Vector2i = c + d
			if in_bounds(n) and not visited.has(n):
				nb.append(n)
		if nb.is_empty():
			stack.pop_back()
			continue
		var n2: Vector2i = nb[rng.randi() % nb.size()]
		_set_open(c, n2)
		visited[n2] = true
		stack.append(n2)
	# pętle — mniej liniowo, magazyn bardziej otwarty
	for x in GW:
		for y in GH:
			var c := Vector2i(x, y)
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + d
				if not in_bounds(n) or not blocked(c, n):
					continue
				var p := 0.2
				if is_wh(c) and is_wh(n):
					p = 0.45 if d.y == 1 else 0.15
				elif is_wh(c) != is_wh(n):
					p = 0.08
				if rng.randf() < p:
					_set_open(c, n)
	# graf
	for x in GW:
		for y in GH:
			var c := Vector2i(x, y)
			astar.add_point(cid(c), Vector2(x, y))
	for x in GW:
		for y in GH:
			var c := Vector2i(x, y)
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + d
				if in_bounds(n) and not blocked(c, n):
					astar.connect_points(cid(c), cid(n))
	dist_from_start = bfs(start_cell)
	var best := -1
	for x in GW:
		var c := Vector2i(x, GH - 1)
		if int(dist_from_start[c]) > best:
			best = dist_from_start[c]
			exit_cell = c
	exit_pos = cell_center(exit_cell) + Vector3(0, 0, CELL / 2.0 - 0.9)
	for x in GW:
		for y in GH:
			var c := Vector2i(x, y)
			theme[c] = "MAGAZYN" if is_wh(c) else THEMES[rng.randi() % THEMES.size()]
	theme[start_cell] = "SYPIALNIA"
	_build()


func bfs(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array[Vector2i] = [from]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if in_bounds(n) and not dist.has(n) and not blocked(c, n):
				dist[n] = int(dist[c]) + 1
				q.append(n)
	return dist


func path_points(from: Vector3, to: Vector3) -> Array[Vector3]:
	var a := world_to_cell(from)
	var b := world_to_cell(to)
	var ids := astar.get_id_path(cid(a), cid(b))
	var out: Array[Vector3] = []
	for k in ids.size():
		if k == 0 and ids.size() > 1:
			continue
		var id: int = ids[k]
		out.append(cell_center(Vector2i(id % GW, id / GW)))
	out.append(Vector3(to.x, 0.0, to.z))
	return out


func pick_cells(n: int, min_start: int, min_sep: int, exclude: Array, showroom_only := false) -> Array[Vector2i]:
	var cands: Array[Vector2i] = []
	for x in GW:
		for y in GH:
			var c := Vector2i(x, y)
			if int(dist_from_start[c]) >= min_start and not exclude.has(c) and c != exit_cell:
				if showroom_only and is_wh(c):
					continue
				cands.append(c)
	var out: Array[Vector2i] = []
	for attempt in 400:
		if out.size() >= n or cands.is_empty():
			break
		var c: Vector2i = cands[rng.randi() % cands.size()]
		var ok := true
		for o in out:
			if absi(o.x - c.x) + absi(o.y - c.y) < min_sep:
				ok = false
				break
		if ok:
			out.append(c)
			cands.erase(c)
	return out


func random_cell_far_from(p: Vector3, min_cells: int) -> Vector2i:
	var pc := world_to_cell(p)
	for i in 200:
		var c := Vector2i(rng.randi() % GW, rng.randi() % GH)
		if absi(c.x - pc.x) + absi(c.y - pc.y) >= min_cells:
			return c
	return Vector2i(GW - 1, GH - 1)


func is_lit_by_lamp(p: Vector3) -> bool:
	for l in lamps:
		if l.on and Vector2(p.x - l.pos.x, p.z - l.pos.z).length() < l.radius:
			return true
	return false


func product_name() -> String:
	return SYL_A[rng.randi() % SYL_A.size()] + SYL_B[rng.randi() % SYL_B.size()]


# ---------------------------------------------------------------- materiały / prymitywy

func _mat(c: Color, emit := 0.0, rough := 0.75, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%f|%f|%f" % [c.to_html(), emit, rough, metal]
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	mats[key] = m
	return m


func _wmat(c: Color, breathe := 1.0, tiles := 0.0) -> ShaderMaterial:
	var key := "%s|%f|%f" % [c.to_html(), breathe, tiles]
	if wmats.has(key):
		return wmats[key]
	var m := ShaderMaterial.new()
	m.shader = surf_shader
	m.set_shader_parameter("base_col", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("breathe", breathe)
	m.set_shader_parameter("tiles", tiles)
	wmats[key] = m
	return m


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	body.add_child(cs)


func _b(g: Node3D, body: StaticBody3D, size: Vector3, pos: Vector3, col: Color, emit := 0.0, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat if mat else _mat(col, emit)
	g.add_child(mi)
	if body:
		_shape(body, size, pos)
	return mi


func _cyl(g: Node3D, rt: float, rb: float, h: float, pos: Vector3, col: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	cm.radial_segments = 16
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(col, emit)
	g.add_child(mi)
	return mi


func label(text: String, pos: Vector3, size: int, col: Color, parent: Node3D, billboard := false, corrupt := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	parent.add_child(l)
	if corrupt:
		labels.append({"node": l, "text": text})
	return l


func _tag(g: Node3D, pos: Vector3) -> void:
	if rng.randf() < 0.55:
		var price := "%d,99 zł" % [rng.randi_range(4, 189) * 10 - 1]
		label(product_name() + "\n" + price, pos, 26, Color(1.0, 0.85, 0.15), g)


func _pick(arr: Array) -> Color:
	return arr[rng.randi() % arr.size()]


func _cardboard() -> Color:
	var v := rng.randf_range(-0.06, 0.06)
	return Color(0.55 + v, 0.4 + v, 0.24 + v * 0.5)


# ---------------------------------------------------------------- budowa

func _build() -> void:
	surf_shader = load("res://shaders/surface.gdshader")
	arrow_shader = load("res://shaders/arrow.gdshader")
	statics = StaticBody3D.new()
	add_child(statics)
	var W := GW * CELL
	var H := GH * CELL
	# podłoga
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, H)
	fm.mesh = pm
	fm.position = Vector3(W / 2.0, 0, H / 2.0)
	fm.material_override = _wmat(Color(0.34, 0.32, 0.3), 0.0, 1.0)
	add_child(fm)
	_shape(statics, Vector3(W, 1, H), Vector3(W / 2.0, -0.5, H / 2.0))
	# sufit
	var cm := MeshInstance3D.new()
	var cp := PlaneMesh.new()
	cp.size = Vector2(W, H)
	cp.flip_faces = true
	cm.mesh = cp
	cm.position = Vector3(W / 2.0, CEIL_H, H / 2.0)
	cm.material_override = _mat(Color(0.04, 0.04, 0.05), 0.0, 1.0)
	add_child(cm)
	# ściany
	for k: Vector2i in hwall:
		if hwall[k]:
			_make_wall(Vector3((k.x + 0.5) * CELL, 0, k.y * CELL), true, k.y == 0 or k.y == GH, Vector2i(k.x, k.y - 1), k)
	for k: Vector2i in vwall:
		if vwall[k]:
			_make_wall(Vector3(k.x * CELL, 0, (k.y + 0.5) * CELL), false, k.x == 0 or k.x == GW, Vector2i(k.x - 1, k.y), k)
	# komórki
	for x in GW:
		for y in GH:
			var c := Vector2i(x, y)
			_furnish(c)
			_ceiling_lamp(c)
			_cell_sign(c)
	_arrows()
	_entrance()
	_exit_door()


func _make_wall(center: Vector3, horiz: bool, outer: bool, a: Vector2i, b: Vector2i) -> void:
	var wa := in_bounds(a) and is_wh(a)
	var wb := in_bounds(b) and is_wh(b)
	if outer:
		_wall_box(center, horiz, CELL + 0.4, CEIL_H, 0.4, Color(0.22, 0.22, 0.26), 0.3)
	elif wa and wb:
		_rack(center, horiz)
	elif wa != wb:
		_wall_box(center, horiz, CELL + 0.3, CEIL_H, 0.3, Color(0.3, 0.3, 0.34), 0.6)
	else:
		var h := absi(int(center.x * 13.0 + center.z * 7.0)) % WALLS.size()
		_wall_box(center, horiz, CELL + 0.2, WALL_H, 0.2, WALLS[h], 1.0)


func _wall_box(center: Vector3, horiz: bool, length: float, h: float, th: float, col: Color, breathe: float) -> void:
	var size := Vector3(length, h, th) if horiz else Vector3(th, h, length)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.subdivide_width = int(size.x * 1.5)
	bm.subdivide_height = int(h * 1.5)
	bm.subdivide_depth = int(size.z * 1.5)
	mi.mesh = bm
	mi.position = center + Vector3(0, h / 2.0, 0)
	mi.material_override = _wmat(col, breathe)
	add_child(mi)
	_shape(statics, size, mi.position)


func _rack(center: Vector3, horiz: bool) -> void:
	var g := Node3D.new()
	g.position = center
	if not horiz:
		g.rotation.y = PI / 2.0
	add_child(g)
	_rack_build(g, CELL - 0.2, 1.0)


func _rack_build(g: Node3D, L: float, D: float) -> void:
	var orange := Color(0.85, 0.4, 0.07)
	var blue := Color(0.12, 0.2, 0.42)
	var grey := Color(0.33, 0.34, 0.36)
	var n := 4
	for i in n:
		var px := -L / 2.0 + i * L / float(n - 1)
		for zs in [-1.0, 1.0]:
			_b(g, null, Vector3(0.1, RACK_H, 0.1), Vector3(px, RACK_H / 2.0, zs * (D / 2.0 - 0.05)), blue)
	for lv in [0.15, 1.55, 2.95, 4.35]:
		for zs in [-1.0, 1.0]:
			_b(g, null, Vector3(L, 0.12, 0.06), Vector3(0, lv, zs * (D / 2.0 - 0.03)), orange)
		_b(g, null, Vector3(L, 0.03, D), Vector3(0, lv + 0.07, 0), grey)
		var x := -L / 2.0 + 0.2
		while x < L / 2.0 - 0.6:
			var bw := rng.randf_range(0.5, 1.3)
			var bh := rng.randf_range(0.4, 1.1)
			var bd := rng.randf_range(0.5, 0.9)
			if x + bw > L / 2.0 - 0.15:
				break
			if rng.randf() < 0.8:
				_b(g, null, Vector3(bw, bh, bd), Vector3(x + bw / 2.0, lv + 0.085 + bh / 2.0, rng.randf_range(-0.05, 0.05)), _cardboard())
			x += bw + rng.randf_range(0.05, 0.4)
	var body := StaticBody3D.new()
	g.add_child(body)
	_shape(body, Vector3(L, RACK_H, D), Vector3(0, RACK_H / 2.0, 0))


func _furnish(c: Vector2i) -> void:
	var th: String = theme[c]
	var depth := [0.0, 0.0, 0.0, 0.0]
	for side in 4:
		if not _side_wall(c, side):
			continue
		depth[side] = 0.2
		if c == exit_cell and side == 1:
			depth[side] = 1.2
			continue
		if c == start_cell and side == 0:
			depth[side] = 0.5
			continue
		var kind: String
		if is_wh(c):
			var n: Vector2i = c + SIDE_DIR[side]
			if in_bounds(n) and is_wh(n):
				depth[side] = 0.55
				continue
			kind = "rack"
		else:
			if rng.randf() < 0.18:
				continue
			var list: Array = WALL_PIECES[th]
			kind = list[rng.randi() % list.size()]
		depth[side] = _place_piece(kind, c, side)
	var isl: Array = ISLANDS[th]
	if isl.is_empty():
		return
	for q in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		if rng.randf() > 0.5:
			continue
		var kind: String = isl[rng.randi() % isl.size()]
		var h: float = ISLAND_HALF[kind]
		var sx := 2 if q.x < 0 else 3
		var sz := 0 if q.y < 0 else 1
		if float(depth[sx]) < 1.75 - h and float(depth[sz]) < 1.75 - h:
			var g := Node3D.new()
			g.position = cell_center(c) + Vector3(q.x * 1.75, 0, q.y * 1.75)
			g.rotation.y = (rng.randi() % 4) * PI / 2.0
			add_child(g)
			var body := StaticBody3D.new()
			g.add_child(body)
			_build_island(kind, g, body)


func _place_piece(kind: String, c: Vector2i, side: int) -> float:
	var g := Node3D.new()
	var cc := cell_center(c)
	var half := CELL / 2.0 - 0.1
	match side:
		0:
			g.position = cc + Vector3(0, 0, -half)
		1:
			g.position = cc + Vector3(0, 0, half)
			g.rotation.y = PI
		2:
			g.position = cc + Vector3(-half, 0, 0)
			g.rotation.y = PI / 2.0
		3:
			g.position = cc + Vector3(half, 0, 0)
			g.rotation.y = -PI / 2.0
	add_child(g)
	var body := StaticBody3D.new()
	g.add_child(body)
	return _build_piece(kind, g, body) + 0.1


func _build_piece(kind: String, g: Node3D, body: StaticBody3D) -> float:
	match kind:
		"sofa":
			var w := 2.2
			var d := 0.95
			var c := _pick(FABRIC)
			_b(g, body, Vector3(w, 0.4, d), Vector3(0, 0.28, d / 2), c)
			_b(g, body, Vector3(w, 0.55, 0.22), Vector3(0, 0.75, 0.11), c)
			_b(g, null, Vector3(0.2, 0.25, d), Vector3(-w / 2 + 0.1, 0.6, d / 2), c.darkened(0.15))
			_b(g, null, Vector3(0.2, 0.25, d), Vector3(w / 2 - 0.1, 0.6, d / 2), c.darkened(0.15))
			for sx in [-1.0, 1.0]:
				_b(g, null, Vector3(w / 2 - 0.25, 0.12, d - 0.3), Vector3(sx * (w / 4 - 0.05), 0.54, 0.22 + (d - 0.3) / 2), c.lightened(0.1))
			_tag(g, Vector3(0.7, 0.95, d + 0.02))
			return d
		"shelf":
			var units := rng.randi_range(1, 3)
			var w := 0.8 * units
			var d := 0.35
			var c := _pick(WOOD)
			_b(g, body, Vector3(w, 2.0, 0.02), Vector3(0, 1.0, 0.01), c)
			for i in units + 1:
				_b(g, null, Vector3(0.03, 2.0, d), Vector3(-w / 2 + i * 0.8, 1.0, d / 2), c)
			for s in 5:
				var y := 0.05 + s * 0.48
				_b(g, null, Vector3(w, 0.03, d), Vector3(0, y, d / 2), c)
				if s < 4:
					for u in units:
						if rng.randf() < 0.7:
							var bw := rng.randf_range(0.2, 0.6)
							_b(g, null, Vector3(bw, rng.randf_range(0.2, 0.32), 0.24), Vector3(-w / 2 + u * 0.8 + 0.06 + bw / 2, y + 0.16, 0.16), _pick(BRIGHT).darkened(0.3))
			_shape(body, Vector3(w, 2.0, d), Vector3(0, 1.0, d / 2))
			_tag(g, Vector3(0, 1.4, d + 0.02))
			return d
		"tv":
			_b(g, body, Vector3(1.8, 0.45, 0.45), Vector3(0, 0.225, 0.225), _pick(WOOD))
			_b(g, null, Vector3(1.3, 0.75, 0.06), Vector3(0, 0.9, 0.12), Color(0.02, 0.02, 0.02))
			var sc := _b(g, null, Vector3(1.2, 0.66, 0.01), Vector3(0, 0.9, 0.155), Color(0.3, 0.4, 0.6), 0.8, _mat(Color(0.3, 0.4, 0.6), 0.8).duplicate())
			screens.append(sc)
			return 0.45
		"lamp":
			_cyl(g, 0.15, 0.15, 0.04, Vector3(0, 0.02, 0.3), Color(0.1, 0.1, 0.1))
			_cyl(g, 0.015, 0.015, 1.5, Vector3(0, 0.77, 0.3), Color(0.1, 0.1, 0.1))
			var on := rng.randf() < 0.4
			var shade := _cyl(g, 0.14, 0.24, 0.3, Vector3(0, 1.6, 0.3), Color(1.0, 0.75, 0.45), 1.5 if on else 0.0)
			_shape(body, Vector3(0.3, 1.7, 0.3), Vector3(0, 0.85, 0.3))
			if on:
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.65, 0.35)
				l.omni_range = 4.0
				l.light_energy = 0.9
				l.position = Vector3(0, 1.5, 0.3)
				g.add_child(l)
				lamps.append({"light": l, "mesh": shade, "pos": g.to_global(l.position), "radius": 2.6, "energy": 0.9, "flicker": rng.randf() < 0.3, "on": true, "col": l.light_color})
			return 0.55
		"bed":
			var w := 1.7
			var d := 2.1
			var c := _pick(WOOD)
			_b(g, body, Vector3(w, 0.3, d), Vector3(0, 0.2, d / 2), c)
			_b(g, null, Vector3(w - 0.1, 0.22, d - 0.15), Vector3(0, 0.46, d / 2 + 0.05), Color(0.88, 0.87, 0.84))
			_b(g, null, Vector3(w - 0.04, 0.06, d * 0.6), Vector3(0, 0.6, d * 0.68), _pick(FABRIC))
			for sx in [-1.0, 1.0]:
				_b(g, null, Vector3(0.6, 0.14, 0.38), Vector3(sx * 0.4, 0.63, 0.35), Color(0.95, 0.95, 0.93))
			_b(g, body, Vector3(w + 0.1, 1.1, 0.08), Vector3(0, 0.55, 0.04), c.darkened(0.1))
			_tag(g, Vector3(0, 1.2, 0.1))
			return d
		"wardrobe":
			var w := 1.6
			var d := 0.65
			var c := _pick(WOOD)
			_b(g, body, Vector3(w, 2.3, d), Vector3(0, 1.15, d / 2), c)
			_b(g, null, Vector3(0.02, 2.15, 0.01), Vector3(0, 1.15, d + 0.005), c.darkened(0.5))
			for sx in [-1.0, 1.0]:
				_b(g, null, Vector3(0.03, 0.3, 0.04), Vector3(sx * 0.09, 1.15, d + 0.02), Color(0.7, 0.7, 0.72))
			body.set_meta("wardrobe", g)
			wardrobes.append(g)
			_tag(g, Vector3(0.45, 1.75, d + 0.02))
			return d
		"dresser":
			var c := _pick(WOOD)
			_b(g, body, Vector3(1.2, 0.8, 0.5), Vector3(0, 0.4, 0.25), c)
			for i in 3:
				_b(g, null, Vector3(1.1, 0.01, 0.01), Vector3(0, 0.25 + i * 0.22, 0.505), c.darkened(0.5))
			_tag(g, Vector3(0, 1.0, 0.3))
			return 0.5
		"kitchen":
			var w := 3.0
			var d := 0.65
			var c := _pick(WOOD)
			_b(g, body, Vector3(w, 0.86, d - 0.05), Vector3(0, 0.43, (d - 0.05) / 2), c)
			_b(g, null, Vector3(w + 0.02, 0.04, d), Vector3(0, 0.88, d / 2), Color(0.15, 0.15, 0.16))
			_b(g, null, Vector3(w, 0.7, 0.35), Vector3(0, 1.85, 0.175), c)
			_b(g, null, Vector3(0.6, 0.02, 0.4), Vector3(0.6, 0.905, 0.33), Color(0.6, 0.6, 0.62), 0.0, _mat(Color(0.6, 0.6, 0.62), 0.0, 0.2, 1.0))
			_b(g, null, Vector3(0.6, 0.55, 0.01), Vector3(-0.8, 0.45, d - 0.045), Color(0.05, 0.05, 0.05))
			for i in 5:
				_b(g, null, Vector3(0.01, 0.6, 0.01), Vector3(-w / 2 + 0.6 * (i + 0.5), 1.85, 0.355), c.darkened(0.5))
			_tag(g, Vector3(-0.2, 1.2, 0.3))
			return d
		"fridge":
			_b(g, body, Vector3(0.75, 1.9, 0.7), Vector3(0, 0.95, 0.35), Color(0.85, 0.86, 0.86), 0.0, _mat(Color(0.85, 0.86, 0.86), 0.0, 0.3, 0.4))
			_b(g, null, Vector3(0.72, 0.01, 0.01), Vector3(0, 1.25, 0.705), Color(0.2, 0.2, 0.2))
			return 0.7
		"desk":
			var c := _pick(WOOD)
			_b(g, null, Vector3(1.4, 0.04, 0.7), Vector3(0, 0.74, 0.35), c)
			for p in [Vector3(-0.66, 0.36, 0.05), Vector3(0.66, 0.36, 0.05), Vector3(-0.66, 0.36, 0.65), Vector3(0.66, 0.36, 0.65)]:
				_b(g, null, Vector3(0.04, 0.72, 0.04), p, Color(0.1, 0.1, 0.1))
			_shape(body, Vector3(1.4, 0.76, 0.7), Vector3(0, 0.38, 0.35))
			var mon := _b(g, null, Vector3(0.6, 0.36, 0.02), Vector3(0, 1.0, 0.15), Color(0.2, 0.5, 0.4), 0.6, _mat(Color(0.2, 0.5, 0.4), 0.6).duplicate())
			screens.append(mon)
			_b(g, body, Vector3(0.5, 0.45, 0.5), Vector3(0, 0.225, 1.05), _pick(FABRIC))
			_b(g, null, Vector3(0.5, 0.55, 0.06), Vector3(0, 0.72, 1.3), _pick(FABRIC))
			return 1.3
		"kidbed":
			var c := _pick(BRIGHT)
			_b(g, body, Vector3(1.0, 0.35, 1.7), Vector3(0, 0.2, 0.85), c)
			_b(g, null, Vector3(0.92, 0.15, 1.6), Vector3(0, 0.45, 0.88), Color(0.9, 0.9, 0.9))
			_b(g, body, Vector3(1.05, 0.9, 0.06), Vector3(0, 0.45, 0.03), c)
			_b(g, null, Vector3(0.4, 0.3, 0.25), Vector3(0.1, 0.65, 0.3), Color(0.55, 0.4, 0.3))  # miś
			_tag(g, Vector3(0, 1.0, 0.1))
			return 1.7
		"toybox":
			_b(g, body, Vector3(1.2, 0.5, 0.5), Vector3(0, 0.25, 0.25), _pick(BRIGHT))
			for i in 4:
				var s := rng.randf_range(0.12, 0.22)
				_b(g, null, Vector3(s, s, s), Vector3(rng.randf_range(-0.5, 0.5), 0.5 + s / 2, rng.randf_range(0.1, 0.4)), _pick(BRIGHT))
			return 0.5
		"bath":
			_b(g, body, Vector3(1.7, 0.55, 0.8), Vector3(0, 0.275, 0.4), Color(0.92, 0.92, 0.9), 0.0, _mat(Color(0.92, 0.92, 0.9), 0.0, 0.2))
			_b(g, null, Vector3(1.5, 0.02, 0.6), Vector3(0, 0.555, 0.4), Color(0.18, 0.02, 0.03), 0.0, _mat(Color(0.18, 0.02, 0.03), 0.0, 0.05))
			return 0.8
		"sinkcab":
			_b(g, body, Vector3(0.8, 0.8, 0.5), Vector3(0, 0.4, 0.25), _pick(WOOD))
			_b(g, null, Vector3(0.62, 0.1, 0.42), Vector3(0, 0.85, 0.25), Color(0.95, 0.95, 0.95))
			_b(g, null, Vector3(0.7, 0.9, 0.02), Vector3(0, 1.6, 0.02), Color(0.8, 0.85, 0.9), 0.0, _mat(Color(0.8, 0.85, 0.9), 0.0, 0.03, 1.0))
			_tag(g, Vector3(0, 1.0, 0.5))
			return 0.5
		"rack":
			var sub := Node3D.new()
			sub.position = Vector3(0, 0, 0.65)
			g.add_child(sub)
			_rack_build(sub, CELL - 1.2, 1.0)
			return 1.15
	return 0.0


func _build_island(kind: String, g: Node3D, body: StaticBody3D) -> void:
	match kind:
		"coffee":
			_b(g, null, Vector3(2.0, 0.01, 1.4), Vector3(0, 0.005, 0), _pick(FABRIC).lightened(0.2))
			_b(g, body, Vector3(1.0, 0.4, 0.6), Vector3(0, 0.2, 0), _pick(WOOD))
			_tag(g, Vector3(0, 0.6, 0.31))
		"armchair":
			var c := _pick(FABRIC)
			_b(g, body, Vector3(0.85, 0.42, 0.85), Vector3(0, 0.25, 0), c)
			_b(g, body, Vector3(0.85, 0.6, 0.18), Vector3(0, 0.75, -0.34), c)
			_tag(g, Vector3(0, 1.2, 0))
		"rug":
			_b(g, null, Vector3(rng.randf_range(1.2, 2.2), 0.012, rng.randf_range(1.0, 2.0)), Vector3(0, 0.006, 0), _pick(FABRIC + BRIGHT))
		"dining":
			var c := _pick(WOOD)
			_b(g, null, Vector3(1.2, 0.04, 0.8), Vector3(0, 0.74, 0), c)
			for p in [Vector3(-0.55, 0.36, -0.35), Vector3(0.55, 0.36, -0.35), Vector3(-0.55, 0.36, 0.35), Vector3(0.55, 0.36, 0.35)]:
				_b(g, null, Vector3(0.05, 0.72, 0.05), p, c.darkened(0.3))
			_shape(body, Vector3(1.2, 0.76, 0.8), Vector3(0, 0.38, 0))
			for sz in [-1.0, 1.0]:
				for sx in [-0.3, 0.3]:
					_b(g, body, Vector3(0.4, 0.45, 0.4), Vector3(sx, 0.225, sz * 0.7), c)
					_b(g, null, Vector3(0.4, 0.5, 0.05), Vector3(sx, 0.7, sz * 0.88), c)
			_tag(g, Vector3(0, 1.0, 0))
		"toys":
			for i in 6:
				var s := rng.randf_range(0.1, 0.25)
				_b(g, null, Vector3(s, s, s), Vector3(rng.randf_range(-0.6, 0.6), s / 2, rng.randf_range(-0.6, 0.6)), _pick(BRIGHT))
		"pallet":
			_b(g, body, Vector3(1.2, 0.15, 1.0), Vector3(0, 0.075, 0), Color(0.6, 0.5, 0.35))
			var y := 0.15
			for i in rng.randi_range(1, 3):
				var h := rng.randf_range(0.35, 0.6)
				_b(g, body, Vector3(1.15, h, 0.95), Vector3(0, y + h / 2, 0), _cardboard())
				y += h
		"boxes":
			for i in rng.randi_range(2, 4):
				var s := Vector3(rng.randf_range(0.4, 0.8), rng.randf_range(0.3, 0.7), rng.randf_range(0.4, 0.8))
				var bx := _b(g, body, s, Vector3(rng.randf_range(-0.35, 0.35), s.y / 2, rng.randf_range(-0.35, 0.35)), _cardboard())
				bx.rotation.y = 0.0


func _ceiling_lamp(c: Vector2i) -> void:
	var p := cell_center(c) + Vector3(0, CEIL_H - 0.9, 0)
	var lit := rng.randf() < 0.28 or c == start_cell
	var col := Color(0.75, 0.95, 0.85)
	if c == exit_cell:
		lit = true
		col = Color(0.3, 1.0, 0.45)
	var g := Node3D.new()
	g.position = p
	add_child(g)
	var tube := _b(g, null, Vector3(1.8, 0.08, 0.3), Vector3.ZERO, col, 2.5 if lit else 0.0, _mat(col, 2.5).duplicate() if lit else _mat(Color(0.25, 0.25, 0.25)))
	for sx in [-0.8, 0.8]:
		_b(g, null, Vector3(0.01, 0.9, 0.01), Vector3(sx, 0.45, 0), Color(0.1, 0.1, 0.1))
	if lit:
		var l := OmniLight3D.new()
		l.light_color = col
		l.omni_range = 9.0
		l.omni_attenuation = 1.3
		l.light_energy = 1.4
		l.light_volumetric_fog_energy = 1.5
		l.position = Vector3(0, -0.2, 0)
		g.add_child(l)
		lamps.append({"light": l, "mesh": tube, "pos": p, "radius": 4.2, "energy": 1.4,
			"flicker": rng.randf() < 0.4 and c != start_cell, "on": true, "col": col, "hum": true})


func _cell_sign(c: Vector2i) -> void:
	var p := cell_center(c) + Vector3(0, 3.9, 0)
	if is_wh(c):
		var n := c.y * GW + c.x
		label("ALEJKA %02d" % n, p, 150, Color(1.0, 0.85, 0.2), self, true)
	elif rng.randf() < 0.45:
		label(THEME_SIGNS[theme[c]], p, 110, Color(0.95, 0.9, 0.7), self, true)


func _arrows() -> void:
	var ids := astar.get_id_path(cid(start_cell), cid(exit_cell))
	for i in ids.size() - 1:
		var a := Vector2i(ids[i] % GW, ids[i] / GW)
		var b := Vector2i(ids[i + 1] % GW, ids[i + 1] / GW)
		var d := Vector3(b.x - a.x, 0, b.y - a.y)
		for f in [0.0, 0.5]:
			var n := Node3D.new()
			n.position = cell_center(a) + d * CELL * f + Vector3(0, 0.015, 0)
			n.rotation.y = atan2(-d.x, -d.z)
			add_child(n)
			var mi := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(1.1, 1.1)
			mi.mesh = qm
			mi.rotation.x = -PI / 2.0
			var m := ShaderMaterial.new()
			m.shader = arrow_shader
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(mi)


func _entrance() -> void:
	var g := Node3D.new()
	g.position = cell_center(start_cell) + Vector3(0, 0, -CELL / 2.0 + 0.25)
	add_child(g)
	_b(g, null, Vector3(4.0, 3.2, 0.08), Vector3(0, 1.6, 0), Color(0.4, 0.42, 0.45), 0.0, _mat(Color(0.4, 0.42, 0.45), 0.0, 0.5, 0.7))
	for i in 16:
		_b(g, null, Vector3(4.0, 0.03, 0.04), Vector3(0, 0.1 + i * 0.2, 0.05), Color(0.25, 0.26, 0.28))
	label("WEJŚCIE\nZAMKNIĘTE", Vector3(0, 3.7, 0.1), 120, Color(1.0, 0.2, 0.15), g, false, false)


func _exit_door() -> void:
	var g := Node3D.new()
	g.position = cell_center(exit_cell) + Vector3(0, 0, CELL / 2.0 - 0.25)
	g.rotation.y = PI
	add_child(g)
	_b(g, null, Vector3(2.8, 2.9, 0.15), Vector3(0, 1.45, 0), Color(0.1, 0.1, 0.1))
	for sx in [-0.66, 0.66]:
		_b(g, null, Vector3(1.25, 2.7, 0.08), Vector3(sx, 1.35, 0.1), Color(0.1, 0.35, 0.18), 0.0, _mat(Color(0.1, 0.35, 0.18), 0.0, 0.4, 0.5))
	_b(g, null, Vector3(2.4, 0.06, 0.08), Vector3(0, 1.1, 0.16), Color(0.7, 0.7, 0.7))
	_b(g, null, Vector3(1.2, 0.35, 0.05), Vector3(0, 3.2, 0.1), Color(0.1, 0.9, 0.3), 3.0)
	label("WYJŚCIE EWAKUACYJNE", Vector3(0, 3.65, 0.12), 90, Color(0.3, 1.0, 0.45), g, false, false)
