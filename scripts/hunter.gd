extends Node3D
## LARS — pracownik nocnej zmiany. Wysoki, chudy, zamiast głowy abażur świecący na czerwono.

enum S { DORMANT, PATROL, CHASE, SEARCH }

var main: Node
var level: Level
var player: CharacterBody3D
var state := S.DORMANT
var path: Array[Vector3] = []
var repath_t := 0.0
var last_seen := Vector3.ZERO
var search_t := 0.0
var lost_t := 0.0
var sees := false
var saw_hide := false
var walk_t := 0.0
var speed := 0.0
var light: OmniLight3D
var shade: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var audio: AudioStreamPlayer3D
var face_light: OmniLight3D


func _mat(c: Color, emit := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func build() -> void:
	var skin := _mat(Color(0.75, 0.7, 0.62), 0.0, 0.5)
	var shirt := _mat(Color(0.55, 0.45, 0.08))
	var pants := _mat(Color(0.06, 0.07, 0.1))
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(sx * 0.13, 1.15, 0)
		add_child(leg)
		_part(leg, _box(Vector3(0.13, 1.15, 0.13)), Vector3(0, -0.575, 0), pants)
		if sx < 0: leg_l = leg
		else: leg_r = leg
	_part(self, _box(Vector3(0.42, 0.25, 0.24)), Vector3(0, 1.22, 0), pants)
	_part(self, _box(Vector3(0.5, 0.75, 0.26)), Vector3(0, 1.7, 0), shirt)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.045
	neck.bottom_radius = 0.06
	neck.height = 0.5
	_part(self, neck, Vector3(0, 2.3, 0), skin)
	for sx in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(sx * 0.31, 2.02, 0)
		add_child(arm)
		_part(arm, _box(Vector3(0.08, 1.35, 0.08)), Vector3(0, -0.67, 0), shirt)
		var hand := _part(arm, _box(Vector3(0.1, 0.32, 0.05)), Vector3(0, -1.48, 0), skin)
		hand.rotation.x = 0.2
		for f in 3:
			_part(arm, _box(Vector3(0.015, 0.22, 0.015)), Vector3(-0.035 + f * 0.035, -1.72, 0.02), skin)
		if sx < 0: arm_l = arm
		else: arm_r = arm
	# abażur
	var cm := CylinderMesh.new()
	cm.top_radius = 0.17
	cm.bottom_radius = 0.4
	cm.height = 0.5
	cm.radial_segments = 20
	var shade_mat := _mat(Color(1.0, 0.35, 0.18), 1.6, 0.9)
	shade = _part(self, cm, Vector3(0, 2.62, 0), shade_mat)
	var eye := SphereMesh.new()
	eye.radius = 0.045
	eye.height = 0.09
	for sx in [-0.1, 0.1]:
		_part(self, eye, Vector3(sx, 2.5, -0.31), _mat(Color(1, 1, 0.9), 6.0))
	var mouth := _box(Vector3(0.22, 0.05, 0.02))
	_part(self, mouth, Vector3(0, 2.4, -0.36), _mat(Color(0.02, 0.0, 0.0)))
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.16, 0.08)
	light.omni_range = 11.0
	light.light_energy = 3.0
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 2.5
	light.position = Vector3(0, 2.3, -0.2)
	add_child(light)
	var tag := Label3D.new()
	tag.text = "LARS\nJak mogę pomóc?"
	tag.font_size = 22
	tag.pixel_size = 0.003
	tag.modulate = Color(1, 0.9, 0.3)
	tag.position = Vector3(0.12, 1.85, -0.14)
	tag.rotation.y = PI
	add_child(tag)
	audio = AudioStreamPlayer3D.new()
	audio.stream = main.sfx.s["buzz"]
	audio.unit_size = 5.0
	audio.max_distance = 30.0
	audio.volume_db = -2.0
	audio.position.y = 2.2
	add_child(audio)


func activate() -> void:
	state = S.PATROL
	audio.play()


func can_see_player() -> bool:
	if player.hiding:
		return false
	var eye := global_position + Vector3(0, 2.4, 0)
	var target: Vector3 = player.cam.global_position
	var to := target - eye
	var dist := to.length()
	if dist > 28.0:
		return false
	var fwd := -global_basis.z
	var flat := Vector3(to.x, 0, to.z).normalized()
	var in_fov := fwd.dot(flat) > 0.15 or dist < 3.5
	var shined: bool = player.light_on and dist < 24.0 and (-player.cam.global_basis.z).dot(-to.normalized()) > 0.93
	if not (in_fov or shined):
		return false
	if dist > 12.0 and not player.light_on and not level.is_lit_by_lamp(target):
		return false
	return main.los(eye, target)


func _go(target: Vector3) -> void:
	path = level.path_points(global_position, target)


func _physics_process(d: float) -> void:
	if state == S.DORMANT or main.g != main.G.PLAY:
		return
	if saw_hide and not player.hiding:
		saw_hide = false
	sees = can_see_player()
	var ppos: Vector3 = player.global_position
	var dist := Vector2(ppos.x - global_position.x, ppos.z - global_position.z).length()
	if sees:
		last_seen = ppos
		lost_t = 0.0
		if state != S.CHASE:
			state = S.CHASE
			main.on_hunter_spotted()
	match state:
		S.PATROL:
			speed = 2.0
			if not player.hiding and player.noise > dist:
				state = S.SEARCH
				last_seen = ppos
				_go(last_seen)
			elif path.is_empty():
				var c: Vector2i
				if randf() < 0.45:
					var pc := level.world_to_cell(ppos)
					c = Vector2i(clampi(pc.x + randi_range(-2, 2), 0, Level.GW - 1), clampi(pc.y + randi_range(-2, 2), 0, Level.GH - 1))
				else:
					c = Vector2i(randi() % Level.GW, randi() % Level.GH)
				_go(level.cell_center(c))
		S.CHASE:
			speed = 4.4
			if not sees:
				lost_t += d
				if saw_hide:
					last_seen = ppos
				elif lost_t > 3.5:
					state = S.SEARCH
					search_t = 0.0
					_go(last_seen)
			repath_t -= d
			if repath_t <= 0.0:
				repath_t = 0.35
				if (sees or saw_hide) and dist < Level.CELL * 0.9 and main.los(global_position + Vector3(0, 1, 0), ppos + Vector3(0, 1, 0)):
					path = [Vector3(last_seen.x, 0, last_seen.z)]
				else:
					_go(last_seen)
		S.SEARCH:
			speed = 3.0
			if not player.hiding and player.noise > dist:
				last_seen = ppos
				_go(last_seen)
			if path.is_empty():
				search_t += d
				rotation.y += d * 1.6 * sin(search_t * 1.3)
				if search_t > 4.5:
					state = S.PATROL
					search_t = 0.0
	# ruch po ścieżce
	var moving := false
	if not path.is_empty():
		var wp: Vector3 = path[0]
		var to := Vector3(wp.x - global_position.x, 0, wp.z - global_position.z)
		var l := to.length()
		if l < 0.3:
			path.pop_front()
		else:
			moving = true
			var step := minf(speed * d, l)
			global_position += to / l * step
			var want := atan2(-to.x, -to.z)
			rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-8.0 * d))
	# animacja
	if moving:
		walk_t += d * speed * 1.6
	var sw := sin(walk_t) * 0.5 * (1.0 if moving else 0.0)
	leg_l.rotation.x = sw
	leg_r.rotation.x = -sw
	var reach := -1.3 if state == S.CHASE else 0.0
	arm_l.rotation.x = lerpf(arm_l.rotation.x, reach - sw * 0.6, 0.15)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, reach + sw * 0.6, 0.15)
	shade.rotation.z = sin(walk_t * 0.5) * 0.12
	light.light_energy = (3.0 if state != S.CHASE else 4.5) * (0.75 + 0.25 * randf())
	audio.pitch_scale = 1.3 if state == S.CHASE else 1.0
	# łapanie
	if player.hiding:
		if saw_hide and dist < 1.6:
			main.caught(self)
	elif dist < 1.15:
		main.caught(self)


func on_player_hide() -> void:
	if state == S.CHASE and sees and Vector3(player.global_position - global_position).length() < 9.0:
		saw_hide = true
	else:
		saw_hide = false
		if state == S.CHASE:
			state = S.SEARCH
			search_t = 0.0
			_go(last_seen)
