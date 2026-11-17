extends CharacterBody3D

const WALK := 3.4
const SPRINT := 6.2
const EYE := 1.62

var main: Node
var cam: Camera3D
var flash: SpotLight3D
var col: CollisionShape3D
var yaw := 0.0
var pitch := 0.0
var stamina := 100.0
var exhausted := false
var battery := 100.0
var light_on := true
var hiding: Node3D = null
var hide_yaw := 0.0
var frozen := false
var noise := 0.0
var sprinting := false
var bob_t := 0.0
var step_acc := 0.0
var focus: Node3D = null
var mouse_sens := 0.0022


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	col.shape = cap
	col.position.y = 0.875
	add_child(col)
	cam = Camera3D.new()
	cam.position.y = EYE
	cam.fov = 78.0
	cam.far = 150.0
	cam.near = 0.05
	add_child(cam)
	cam.current = true
	flash = SpotLight3D.new()
	flash.spot_range = 24.0
	flash.spot_angle = 26.0
	flash.spot_angle_attenuation = 0.9
	flash.light_energy = 7.0
	flash.light_color = Color(1.0, 0.93, 0.8)
	flash.shadow_enabled = true
	flash.light_volumetric_fog_energy = 1.6
	flash.position = Vector3(0.2, -0.18, -0.1)
	cam.add_child(flash)


func set_look(y: float, p: float) -> void:
	yaw = y
	pitch = p
	rotation.y = yaw
	cam.rotation.x = pitch


func _unhandled_input(e: InputEvent) -> void:
	if main.g != main.G.PLAY:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * mouse_sens
		pitch = clampf(pitch - e.relative.y * mouse_sens, -1.4, 1.4)
	elif e.is_action_pressed("light"):
		if battery > 0.0:
			light_on = not light_on
			main.play("click", -6.0)
	elif e.is_action_pressed("use"):
		if hiding:
			unhide()
		elif focus:
			hide_in(focus)


func hide_in(w: Node3D) -> void:
	hiding = w
	col.disabled = true
	var fwd := w.global_basis.z
	global_position = w.global_position + fwd * 0.33
	velocity = Vector3.ZERO
	hide_yaw = w.global_rotation.y + PI
	set_look(hide_yaw, 0.0)
	main.play("creak", -4.0, 0.7)
	main.on_player_hide()


func unhide() -> void:
	if not hiding:
		return
	var fwd := hiding.global_basis.z
	global_position = hiding.global_position + fwd * 1.15
	hiding = null
	col.disabled = false
	main.play("creak", -4.0, 0.6)


func _physics_process(d: float) -> void:
	var playing: bool = main.g == main.G.PLAY
	# rozglądanie klawiaturą
	if playing:
		yaw -= Input.get_axis("look_l", "look_r") * 2.4 * d
		pitch = clampf(pitch + Input.get_axis("look_d", "look_u") * 1.8 * d, -1.4, 1.4)
	if hiding:
		yaw = hide_yaw + clampf(wrapf(yaw - hide_yaw, -PI, PI), -0.6, 0.6)
		pitch = clampf(pitch, -0.4, 0.4)
	rotation.y = yaw
	cam.rotation.x = pitch
	# latarka
	if light_on:
		battery = maxf(battery - 0.55 * d * (1.0 if playing else 0.0), 0.0)
		if battery <= 0.0:
			light_on = false
	var e := 7.0
	if battery < 20.0 and randf() < 0.08 + (20.0 - battery) * 0.01:
		e = randf_range(0.0, 3.0)
	flash.light_energy = lerpf(flash.light_energy, e if light_on else 0.0, 0.5)
	flash.visible = flash.light_energy > 0.05
	if not playing or frozen or hiding:
		velocity = Vector3.ZERO
		noise = 0.0
		focus = null
		if hiding:
			stamina = minf(stamina + 15.0 * d, 100.0)
		return
	# ruch
	var inp := Input.get_vector("left", "right", "fwd", "back")
	var dir := (transform.basis * Vector3(inp.x, 0, inp.y))
	if dir.length() > 1.0:
		dir = dir.normalized()
	sprinting = Input.is_action_pressed("sprint") and inp.length() > 0.1 and not exhausted
	if sprinting:
		stamina -= 17.0 * d
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = true
	else:
		stamina = minf(stamina + 11.0 * d, 100.0)
		if exhausted and stamina > 35.0:
			exhausted = false
	var spd := SPRINT if sprinting else WALK
	if exhausted:
		spd *= 0.8
	var k := 1.0 - exp(-12.0 * d)
	velocity.x = lerpf(velocity.x, dir.x * spd, k)
	velocity.z = lerpf(velocity.z, dir.z * spd, k)
	if not is_on_floor():
		velocity.y -= 20.0 * d
	else:
		velocity.y = -0.5
	move_and_slide()
	# kołysanie głowy + kroki
	var hv := Vector2(velocity.x, velocity.z).length()
	bob_t += d * hv * 2.3
	var amp := minf(hv / WALK, 1.6)
	cam.position.y = EYE + sin(bob_t) * 0.045 * amp
	cam.position.x = cos(bob_t * 0.5) * 0.035 * amp
	step_acc += hv * d
	var stride := 2.0 if sprinting else 1.5
	if step_acc > stride:
		step_acc = 0.0
		main.play("step", -10.0 if not sprinting else -4.0, randf_range(0.85, 1.1))
	noise = 15.0 if sprinting else (4.5 if hv > 0.5 else 0.0)
	# interakcja
	focus = null
	var from := cam.global_position
	var to := from - cam.global_basis.z * 2.6
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider.has_meta("wardrobe"):
		focus = hit.collider.get_meta("wardrobe")
