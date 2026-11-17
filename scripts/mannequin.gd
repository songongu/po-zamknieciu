extends Node3D
## Manekin z ekspozycji. Rusza się tylko, gdy nikt na niego nie patrzy (albo jest ciemno).

var main: Node
var level: Level
var player: CharacterBody3D
var active := false
var path: Array[Vector3] = []
var repath_t := 0.0
var unseen_t := 0.0
var cooldown := 0.0
var creak_t := 0.0
var was_moving := false
var arms: Array[Node3D] = []
var head: MeshInstance3D
var audio: AudioStreamPlayer3D
const SPEED := 3.1

static var _skin: StandardMaterial3D


func build() -> void:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.albedo_color = Color(0.86, 0.8, 0.72)
		_skin.roughness = 0.22
		_skin.clearcoat_enabled = true
	for sx in [-1.0, 1.0]:
		_part(_box(Vector3(0.12, 0.88, 0.13)), Vector3(sx * 0.11, 0.44, 0))
	_part(_box(Vector3(0.34, 0.2, 0.2)), Vector3(0, 0.95, 0))
	var torso := CapsuleMesh.new()
	torso.radius = 0.17
	torso.height = 0.72
	_part(torso, Vector3(0, 1.32, 0))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.045
	neck.bottom_radius = 0.05
	neck.height = 0.16
	_part(neck, Vector3(0, 1.72, 0))
	var hm := SphereMesh.new()
	hm.radius = 0.12
	hm.height = 0.3
	head = _part(hm, Vector3(0, 1.88, 0))
	for sx in [-1.0, 1.0]:
		var a := Node3D.new()
		a.position = Vector3(sx * 0.22, 1.58, 0)
		add_child(a)
		var mi := MeshInstance3D.new()
		mi.mesh = _box(Vector3(0.08, 0.68, 0.08))
		mi.position = Vector3(0, -0.34, 0)
		mi.material_override = _skin
		a.add_child(mi)
		arms.append(a)
	audio = AudioStreamPlayer3D.new()
	audio.stream = main.sfx.s["creak"]
	audio.unit_size = 4.0
	audio.max_distance = 22.0
	audio.position.y = 1.2
	add_child(audio)
	_pose()


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _part(m: Mesh, p: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = p
	mi.material_override = _skin
	add_child(mi)
	return mi


func _pose() -> void:
	for a in arms:
		a.rotation = Vector3(randf_range(-2.6, 0.3), 0, randf_range(-0.5, 0.5))
	head.rotation = Vector3(randf_range(-0.3, 0.4), 0, randf_range(-0.6, 0.6))


func is_seen() -> bool:
	var cam: Camera3D = player.cam
	if player.hiding:
		return true
	for h in [1.85, 1.2, 0.5]:
		var p := global_position + Vector3(0, h, 0)
		if cam.is_position_in_frustum(p) and main.is_lit(p) and main.los(cam.global_position, p):
			return true
	return false


func _physics_process(d: float) -> void:
	if not active or main.g != main.G.PLAY:
		return
	cooldown -= d
	var ppos: Vector3 = player.global_position
	var to_p := Vector3(ppos.x - global_position.x, 0, ppos.z - global_position.z)
	var dist := to_p.length()
	if dist > 26.0 or cooldown > 0.0 or is_seen():
		unseen_t = 0.0
		was_moving = false
		return
	unseen_t += d
	if unseen_t < 0.3:
		return
	if not was_moving:
		was_moving = true
		_pose()
		if dist < 18.0:
			audio.pitch_scale = randf_range(0.8, 1.2)
			audio.play()
	creak_t -= d
	if creak_t <= 0.0 and dist < 14.0:
		creak_t = randf_range(1.2, 2.5)
		audio.pitch_scale = randf_range(0.7, 1.3)
		audio.play()
	repath_t -= d
	if repath_t <= 0.0 or path.is_empty():
		repath_t = 0.5
		if dist < Level.CELL * 0.8 and main.los(global_position + Vector3(0, 1.2, 0), ppos + Vector3(0, 1.2, 0)):
			path = [Vector3(ppos.x, 0, ppos.z)]
		else:
			path = level.path_points(global_position, ppos)
	if not path.is_empty():
		var wp: Vector3 = path[0]
		var to := Vector3(wp.x - global_position.x, 0, wp.z - global_position.z)
		var l := to.length()
		if l < 0.3:
			path.pop_front()
		else:
			global_position += to / l * minf(SPEED * d, l)
	rotation.y = atan2(-to_p.x, -to_p.z) + PI
	if dist < 0.95 and not player.hiding:
		main.mannequin_touch(self)
