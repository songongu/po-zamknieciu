extends Node3D
## PO ZAMKNIĘCIU — horror w sklepie meblowym nocą.

enum G { MENU, PLAY, PAUSE, DYING, DEAD, WON }
const KEYS_NEEDED := 6
const HunterScript := preload("res://scripts/hunter.gd")
const MannequinScript := preload("res://scripts/mannequin.gd")
const PlayerScript := preload("res://scripts/player.gd")
const SfxScript := preload("res://scripts/sfx.gd")

const CREEPY := ["NIE ODWRACAJ SIĘ", "ZOSTAŃ", "ON CIĘ WIDZI", "ZŁÓŻ SIĘ", "0,00 zł", "TU ŚPISZ",
	"GDZIE WYJŚCIE?", "JESTEŚ EKSPOZYCJĄ", "DLACZEGO BIEGNIESZ", "SKRĘĆ W LEWO. NIE.", "HEJ HEJ HEJ", "BRAK W MAGAZYNIE"]
const PA_RANDOM := [
	"Hot-dog za złotówkę. Hot-dog za złotówkę. Hot-dog za złotówkę. Hot-dog za złotów—",
	"Rodzic małego Oskara proszony jest o... nie. Oskar już nie czeka.",
	"Przypominamy, że w sklepie obowiązuje zakaz patrzenia za siebie.",
	"Nasze meble są gotowe do samodzielnego złożenia. Ty również.",
	"Dziękujemy, że wybrali Państwo nasz sklep. Nie wybierzecie już innego.",
	"Klient bez paragonu proszony jest o pozostanie na ekspozycji.",
	"Dział reklamacji jest czynny całą noc. Lars już idzie.",
	"Uwaga: manekiny nie są na sprzedaż. Manekiny kupują same.",
]

var g := G.MENU
var level: Level
var player: CharacterBody3D
var hunter: Node3D
var mannequins: Array = []
var pickups: Array = []
var sfx: Node
var env: Environment
var post_mat: ShaderMaterial
var args := {}
var rng := RandomNumberGenerator.new()

var t_play := 0.0
var sanity := 100.0
var keys := 0
var danger := 0.0
var flash := 0.0
var hurt := 0.0
var madness := 0.1
var madness_override := -1.0
var dying_t := 0.0
var dying_by: Node3D
var death_text := ""
var pa_queue: Array = []
var next_random_pa := 120.0
var hallu_t := 12.0
var heart_t := 0.0
var msg_t := 0.0
var sub_t := 0.0
var blackout_t := 0.0
var corrupt_t := 0.0
var phantom: Node3D
var phantom_t := 0.0
var hunter_active := false
var frames := 0

var players: Array[AudioStreamPlayer] = []
var player_idx := 0
var drone: AudioStreamPlayer
var whisper_pl: AudioStreamPlayer

# UI
var ui_root: Control
var bars := {}
var keys_lbl: Label
var prompt_lbl: Label
var sub_lbl: Label
var msg_lbl: Label
var menu: Control
var end_panel: Control
var end_title: Label
var end_text: Label
var pause_panel: Control
var hide_overlay: Control
var crosshair: ColorRect


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	rng.randomize()
	_setup_input()
	sfx = SfxScript.new()
	add_child(sfx)
	var seed_v := int(args.get("seed", str(rng.randi())))
	level = Level.new()
	add_child(level)
	level.generate(seed_v)
	_setup_env()
	# gracz
	player = PlayerScript.new()
	player.main = self
	add_child(player)
	player.global_position = level.cell_center(level.start_cell) + Vector3(0, 0.1, -1.0)
	var look := 0.0
	for side in [1, 3, 2]:
		var dv: Vector2i = Level.SIDE_DIR[side]
		if level.in_bounds(level.start_cell + dv) and not level.blocked(level.start_cell, level.start_cell + dv):
			look = atan2(-float(dv.x), -float(dv.y))
			break
	player.set_look(look, 0.0)
	_spawn_things()
	_build_ui()
	_setup_audio()
	if args.has("shot"):
		_apply_test_args()


func _setup_input() -> void:
	var map := {
		"fwd": [KEY_W], "back": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"sprint": [KEY_SHIFT], "light": [KEY_F], "use": [KEY_E, KEY_SPACE],
		"look_l": [KEY_LEFT, KEY_Q], "look_r": [KEY_RIGHT], "look_u": [KEY_UP], "look_d": [KEY_DOWN],
		"restart": [KEY_R], "start": [KEY_ENTER, KEY_KP_ENTER], "pause": [KEY_ESCAPE, KEY_P],
	}
	for a: String in map:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in map[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)


func _setup_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.2, 0.38)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color(0.55, 0.5, 0.7)
	env.volumetric_fog_emission = Color(0.012, 0.004, 0.02)
	env.volumetric_fog_length = 48.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.1
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _spawn_things() -> void:
	var key_cells := level.pick_cells(KEYS_NEEDED, 3, 3, [level.start_cell])
	for c in key_cells:
		_make_pickup("key", level.cell_center(c))
	var bat_cells := level.pick_cells(9, 1, 2, key_cells)
	for c in bat_cells:
		_make_pickup("battery", level.cell_center(c) + Vector3(0.0, 0, 1.0))
	var used: Array = key_cells.duplicate()
	used.append(level.start_cell)
	for c in level.pick_cells(10, 3, 2, used, true):
		var m := MannequinScript.new()
		m.main = self
		m.level = level
		m.player = player
		add_child(m)
		m.global_position = level.cell_center(c) + Vector3(1.3 if rng.randf() < 0.5 else -1.3, 0, 0)
		m.rotation.y = rng.randf() * TAU
		m.build()
		mannequins.append(m)
	hunter = HunterScript.new()
	hunter.main = self
	hunter.level = level
	hunter.player = player
	add_child(hunter)
	hunter.build()
	hunter.global_position = level.cell_center(level.random_cell_far_from(player.global_position, 9))
	# halucynacja — sylwetka
	phantom = Node3D.new()
	add_child(phantom)
	var pm := CapsuleMesh.new()
	pm.radius = 0.3
	pm.height = 2.6
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position.y = 1.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	phantom.add_child(mi)
	for sx in [-0.1, 0.1]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.04
		sm.height = 0.08
		e.mesh = sm
		e.position = Vector3(sx, 2.3, -0.28)
		var em := StandardMaterial3D.new()
		em.albedo_color = Color(1, 0.1, 0.1)
		em.emission_enabled = true
		em.emission = Color(1, 0.1, 0.1)
		em.emission_energy_multiplier = 8.0
		e.material_override = em
		phantom.add_child(e)
	phantom.visible = false


func _make_pickup(kind: String, pos: Vector3) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos + Vector3(0, 1.0, 0)
	var light := OmniLight3D.new()
	light.omni_range = 3.0
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.metallic = 0.8
	mat.roughness = 0.25
	if kind == "key":
		mat.albedo_color = Color(1.0, 0.8, 0.2)
		mat.emission = Color(1.0, 0.7, 0.1)
		mat.emission_energy_multiplier = 3.0
		var a := MeshInstance3D.new()
		var am := CylinderMesh.new()
		am.top_radius = 0.04
		am.bottom_radius = 0.04
		am.height = 0.5
		am.radial_segments = 6
		a.mesh = am
		a.material_override = mat
		n.add_child(a)
		var b := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.04
		bm.bottom_radius = 0.04
		bm.height = 0.2
		bm.radial_segments = 6
		b.mesh = bm
		b.material_override = mat
		b.rotation.z = PI / 2
		b.position = Vector3(0.08, 0.25, 0)
		n.add_child(b)
		light.light_color = Color(1.0, 0.75, 0.2)
		light.light_energy = 1.5
	else:
		mat.albedo_color = Color(0.2, 0.9, 0.4)
		mat.emission = Color(0.1, 0.9, 0.35)
		mat.emission_energy_multiplier = 2.0
		var a := MeshInstance3D.new()
		var am := CylinderMesh.new()
		am.top_radius = 0.06
		am.bottom_radius = 0.06
		am.height = 0.25
		a.mesh = am
		a.material_override = mat
		n.add_child(a)
		light.light_color = Color(0.2, 1.0, 0.4)
		light.light_energy = 0.8
	n.add_child(light)
	pickups.append({"node": n, "kind": kind, "base": n.global_position})


func _setup_audio() -> void:
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	drone = AudioStreamPlayer.new()
	drone.stream = sfx.s["drone"]
	drone.volume_db = -6.0
	add_child(drone)
	drone.play()
	whisper_pl = AudioStreamPlayer.new()
	whisper_pl.stream = sfx.s["whisper"]
	add_child(whisper_pl)
	var n := 0
	for l in level.lamps:
		if l.get("hum", false) and n < 14:
			n += 1
			var a := AudioStreamPlayer3D.new()
			a.stream = sfx.s["hum"]
			a.unit_size = 2.5
			a.max_distance = 14.0
			a.volume_db = -12.0
			l.light.add_child(a)
			a.play()


func play(name: String, vol := 0.0, pitch := 1.0) -> void:
	var p := players[player_idx]
	player_idx = (player_idx + 1) % players.size()
	p.stream = sfx.s[name]
	p.volume_db = vol
	p.pitch_scale = pitch
	p.play()


# ---------------------------------------------------------------- UI

func _lbl(parent: Control, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _build_ui() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 1
	add_child(post_layer)
	var pr := ColorRect.new()
	pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	pr.material = post_mat
	post_layer.add_child(pr)

	var hud := CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ui_root)

	hide_overlay = Control.new()
	hide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hide_overlay)
	for side in [0, 1]:
		var r := ColorRect.new()
		r.color = Color(0.03, 0.02, 0.01)
		r.anchor_top = 0.0
		r.anchor_bottom = 1.0
		r.anchor_left = 0.0 if side == 0 else 0.535
		r.anchor_right = 0.465 if side == 0 else 1.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hide_overlay.add_child(r)
	hide_overlay.visible = false

	crosshair = ColorRect.new()
	crosshair.color = Color(1, 1, 1, 0.35)
	crosshair.size = Vector2(4, 4)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-2, -2)
	ui_root.add_child(crosshair)

	var y := -130.0
	for b in [["sanity", "UMYSŁ", Color(0.75, 0.4, 1.0)], ["battery", "LATARKA", Color(1.0, 0.85, 0.3)], ["stamina", "ODDECH", Color(0.5, 0.85, 1.0)]]:
		var box := Control.new()
		box.anchor_top = 1.0
		box.anchor_bottom = 1.0
		box.position = Vector2(30, y)
		ui_root.add_child(box)
		var t := _lbl(box, 16, b[2], HORIZONTAL_ALIGNMENT_LEFT)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		t.text = b[1]
		t.position = Vector2(0, -4)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		bg.position = Vector2(95, 2)
		bg.size = Vector2(220, 12)
		box.add_child(bg)
		var fg := ColorRect.new()
		fg.color = b[2]
		fg.position = Vector2(97, 4)
		fg.size = Vector2(216, 8)
		box.add_child(fg)
		bars[b[0]] = fg
		y += 32.0

	keys_lbl = _lbl(ui_root, 26, Color(1.0, 0.82, 0.25), HORIZONTAL_ALIGNMENT_RIGHT)
	keys_lbl.anchor_left = 1.0
	keys_lbl.anchor_right = 1.0
	keys_lbl.offset_left = -420
	keys_lbl.offset_right = -30
	keys_lbl.offset_top = 24

	prompt_lbl = _lbl(ui_root, 24, Color(1, 1, 1))
	prompt_lbl.anchor_left = 0.2
	prompt_lbl.anchor_right = 0.8
	prompt_lbl.anchor_top = 0.62
	prompt_lbl.anchor_bottom = 0.62

	sub_lbl = _lbl(ui_root, 24, Color(1.0, 0.92, 0.6))
	sub_lbl.anchor_left = 0.15
	sub_lbl.anchor_right = 0.85
	sub_lbl.anchor_top = 0.82
	sub_lbl.anchor_bottom = 0.82

	msg_lbl = _lbl(ui_root, 34, Color(1, 0.9, 0.8))
	msg_lbl.anchor_left = 0.1
	msg_lbl.anchor_right = 0.9
	msg_lbl.anchor_top = 0.25
	msg_lbl.anchor_bottom = 0.25

	menu = _panel(Color(0.0, 0.0, 0.02, 0.82))
	var title := _lbl(menu, 92, Color(1.0, 0.82, 0.2))
	title.text = "PO ZAMKNIĘCIU"
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.anchor_top = 0.12
	var st := _lbl(menu, 22, Color(0.85, 0.75, 1.0))
	st.anchor_left = 0.18
	st.anchor_right = 0.82
	st.anchor_top = 0.3
	st.text = "Zasnąłeś na łóżku z ekspozycji. Jest 23:47. Sklep jest zamknięty.\nWejście zablokowane roletą. Jedyna droga to WYJŚCIE EWAKUACYJNE na końcu Magazynu Samoobsługowego — ale zamek trzyma sześć śrub.\n\nZnajdź 6 kluczy imbusowych. Idź za strzałkami. Nie ufaj strzałkom.\n\nManekiny ruszają się, gdy na nie nie patrzysz — albo gdy jest ciemno.\nLars z nocnej zmiany cię szuka. Schowaj się w szafie, zanim cię dogoni.\nCiemność zżera umysł."
	var ctr := _lbl(menu, 20, Color(0.9, 0.9, 0.9))
	ctr.anchor_left = 0.2
	ctr.anchor_right = 0.8
	ctr.anchor_top = 0.66
	ctr.text = "WASD — ruch   •   mysz / strzałki — rozglądanie   •   SHIFT — bieg\nF — latarka   •   E / SPACJA — schowaj się / wyjdź z szafy   •   ESC — pauza"
	var go := _lbl(menu, 30, Color(1, 1, 1))
	go.anchor_left = 0.0
	go.anchor_right = 1.0
	go.anchor_top = 0.82
	go.text = "[ ENTER lub kliknij, aby wejść głębiej ]"

	pause_panel = _panel(Color(0, 0, 0, 0.7))
	var pt := _lbl(pause_panel, 60, Color(1, 0.85, 0.3))
	pt.anchor_right = 1.0
	pt.anchor_top = 0.4
	pt.text = "PAUZA\n[ ENTER / klik — wróć ]   [ R — nowy sklep ]"
	pause_panel.visible = false

	end_panel = _panel(Color(0, 0, 0, 0.85))
	end_title = _lbl(end_panel, 96, Color(1, 0.2, 0.15))
	end_title.anchor_right = 1.0
	end_title.anchor_top = 0.28
	end_text = _lbl(end_panel, 28, Color(0.95, 0.9, 0.85))
	end_text.anchor_left = 0.15
	end_text.anchor_right = 0.85
	end_text.anchor_top = 0.52
	end_panel.visible = false


func _panel(c: Color) -> Control:
	var p := ColorRect.new()
	p.color = c
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(p)
	return p


func show_msg(t: String, dur := 3.5) -> void:
	msg_lbl.text = t
	msg_t = dur


func announce(t: String) -> void:
	pa_queue.append(t)


# ---------------------------------------------------------------- stan gry

func _start() -> void:
	g = G.PLAY
	menu.visible = false
	pause_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if t_play == 0.0:
		announce("Drodzy Klienci. Sklep jest już zamknięty. Prosimy o niezwłoczne... o pozostanie na miejscu.")
		show_msg("Znajdź 6 imbusów.\nWyjście: Magazyn Samoobsługowy.", 5.0)


func _input(e: InputEvent) -> void:
	var click: bool = e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	match g:
		G.MENU:
			if click or e.is_action_pressed("start"):
				_start()
		G.PLAY:
			if e.is_action_pressed("pause"):
				g = G.PAUSE
				pause_panel.visible = true
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif click and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		G.PAUSE:
			if click or e.is_action_pressed("start") or e.is_action_pressed("pause"):
				_start()
			elif e.is_action_pressed("restart"):
				get_tree().reload_current_scene()
		G.DEAD, G.WON:
			if e.is_action_pressed("restart") or e.is_action_pressed("start"):
				get_tree().reload_current_scene()


func los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func is_lit(p: Vector3) -> bool:
	var cp: Vector3 = player.cam.global_position
	var to := p - cp
	var d := to.length()
	if d < 2.2:
		return true
	if player.light_on and player.flash.light_energy > 1.5 and d < 22.0:
		if (-player.cam.global_basis.z).dot(to / d) > cos(deg_to_rad(player.flash.spot_angle + 4.0)):
			return true
	return level.is_lit_by_lamp(p)


func on_player_hide() -> void:
	hunter.on_player_hide()


func on_hunter_spotted() -> void:
	play("screech", -14.0, 0.6)
	flash = maxf(flash, 0.15)


func caught(by: Node3D) -> void:
	if g != G.PLAY:
		return
	g = G.DYING
	dying_t = 0.0
	dying_by = by
	if player.hiding:
		player.unhide()
	player.frozen = true
	play("screech", 2.0)
	var fwd: Vector3 = -player.cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	by.global_position = player.global_position + fwd * 0.85 + Vector3(0, -0.85, 0)
	by.rotation.y = atan2(fwd.x, fwd.z)
	player.pitch = 0.0
	death_text = "Lars odprowadził cię do działu reklamacji.\nTwój paragon nie przetrwał."


func mannequin_touch(m: Node3D) -> void:
	sanity -= 34.0
	hurt = 1.0
	flash = 0.6
	play("screech", -2.0, 1.4)
	m.cooldown = 4.0
	m.global_position = level.cell_center(level.random_cell_far_from(player.global_position, 5)) + Vector3(1.3, 0, 0)
	m.path.clear()
	show_msg(CREEPY[rng.randi() % CREEPY.size()], 2.0)


func _die_sanity() -> void:
	g = G.DEAD
	_end("ZAGUBIONY", "Stałeś się częścią ekspozycji.\nCena: 0,00 zł. Stan: jak nowy.", Color(0.75, 0.4, 1.0))


func _end(title: String, text: String, col: Color) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	end_panel.visible = true
	end_title.text = title
	end_title.add_theme_color_override("font_color", col)
	var mm := int(t_play) / 60
	var ss := int(t_play) % 60
	end_text.text = text + "\n\nCzas: %d:%02d   •   Imbusy: %d/%d\n\n[ R — nowy sklep ]" % [mm, ss, keys, KEYS_NEEDED]


func _process(d: float) -> void:
	frames += 1
	var t := Time.get_ticks_msec() / 1000.0
	if g == G.PLAY:
		_update_play(d)
	elif g == G.DYING:
		_update_dying(d)
	_update_fx(d, t)
	_update_hud(d)
	if args.has("shot") and Time.get_ticks_msec() / 1000.0 >= float(args.get("secs", "3")) and frames > 5:
		print("madness=", madness, " danger=", danger, " sanity=", sanity, " hstate=", hunter.state)
		print("g=", g, " keys=", keys, " pickups=", pickups.size())
		var img := get_viewport().get_texture().get_image()
		img.save_png(args["shot"])
		get_tree().quit()


func _update_play(d: float) -> void:
	t_play += d
	if args.has("autowin") and frames % 40 == 0:
		if not pickups.is_empty():
			player.global_position = pickups[0].base - Vector3(0, 0.9, 0)
		else:
			player.global_position = level.exit_pos + Vector3(0, 0.1, -0.5)
	# komunikaty
	if t_play > 12.0 and mannequins.size() > 0 and not mannequins[0].active:
		for m in mannequins:
			m.active = true
	if t_play > 30.0 and not hunter_active:
		hunter_active = true
		hunter.activate()
		announce("Pracownik nocnej zmiany rozpoczyna obchód. Prosimy nie biegać. On słyszy.")
	if t_play > next_random_pa:
		next_random_pa = t_play + rng.randf_range(60.0, 110.0)
		announce(PA_RANDOM[rng.randi() % PA_RANDOM.size()])
	if sub_t <= 0.0 and not pa_queue.is_empty():
		sub_lbl.text = "🔊 " + pa_queue.pop_front()
		sub_t = 7.0
		play("chime", -6.0, 1.0 - madness * 0.25)
	# znajdźki
	var pp: Vector3 = player.global_position
	for p in pickups.duplicate():
		var n: Node3D = p.node
		n.rotation.y += d * 1.8
		n.global_position = p.base + Vector3(0, sin(t_play * 2.0 + p.base.x) * 0.12, 0)
		if Vector2(pp.x - n.global_position.x, pp.z - n.global_position.z).length() < 1.3 and not player.hiding:
			pickups.erase(p)
			n.queue_free()
			if p.kind == "key":
				keys += 1
				sanity = minf(sanity + 10.0, 100.0)
				play("pickup", -2.0, 1.0 - keys * 0.04)
				if keys >= KEYS_NEEDED:
					show_msg("Wszystkie imbusy. Wyjście czeka. Szkoda.", 4.0)
					announce("Wyjście ewakuacyjne zostało odblokowane. Szkoda. Było nam tak dobrze razem.")
				else:
					show_msg("Imbus %d/%d" % [keys, KEYS_NEEDED], 2.0)
					if keys == 3:
						announce("Ktoś zbiera nasze klucze. Lars, proszę udać się do magazynu.")
						hunter.last_seen = pp
						if hunter.state == hunter.S.PATROL:
							hunter.state = hunter.S.SEARCH
							hunter._go(pp)
			else:
				player.battery = minf(player.battery + 45.0, 100.0)
				play("battery", -4.0)
				show_msg("Bateria", 1.2)
	# wyjście
	var ed := Vector2(pp.x - level.exit_pos.x, pp.z - level.exit_pos.z).length()
	if ed < 2.4:
		if keys >= KEYS_NEEDED:
			g = G.WON
			play("win", 0.0)
			_end("WYSZEDŁEŚ", "Chłodne nocne powietrze. Parking jest pusty.\nW kieszeni znajdujesz paragon. Jest na nim twoje imię.", Color(0.4, 1.0, 0.5))
			return
		elif msg_t <= 0.0:
			play("locked", -4.0)
			show_msg("Zamknięte. Brakuje imbusów: %d" % (KEYS_NEEDED - keys), 2.0)
	# umysł
	var lit_here: bool = player.light_on or level.is_lit_by_lamp(pp)
	var hd := Vector3(hunter.global_position - pp).length()
	var dv := 0.0
	if not lit_here and not player.hiding:
		dv -= 2.4
	elif player.hiding:
		dv += 1.2
	else:
		dv += 0.35
	if hunter_active:
		if hd < 9.0:
			dv -= 3.0
		var hp: Vector3 = hunter.global_position + Vector3(0, 2.0, 0)
		if player.cam.is_position_in_frustum(hp) and hd < 22.0 and los(player.cam.global_position, hp):
			dv -= 5.0
	sanity = clampf(sanity + dv * d, 0.0, 100.0)
	if sanity <= 0.0:
		_die_sanity()
		return
	# zagrożenie
	var target_danger := 0.0
	if hunter_active:
		if hunter.state == hunter.S.CHASE:
			target_danger = clampf(1.0 - hd / 25.0, 0.0, 1.0) * 0.7 + 0.3
		else:
			target_danger = clampf(1.0 - hd / 14.0, 0.0, 1.0) * 0.6
	danger = lerpf(danger, target_danger, 1.0 - exp(-3.0 * d))
	heart_t -= d
	if danger > 0.12 and heart_t <= 0.0:
		heart_t = lerpf(1.3, 0.38, danger)
		play("heart", lerpf(-14.0, 0.0, danger))
	# halucynacje
	_hallucinate(d)
	# prompt
	if player.hiding:
		prompt_lbl.text = "[E] Wyjdź z szafy"
	elif player.focus:
		prompt_lbl.text = "[E] Schowaj się w szafie"
	elif ed < 4.0 and keys < KEYS_NEEDED:
		prompt_lbl.text = "Drzwi trzyma %d śrub" % KEYS_NEEDED
	else:
		prompt_lbl.text = ""


func _hallucinate(d: float) -> void:
	hallu_t -= d
	if blackout_t > 0.0:
		blackout_t -= d
	if corrupt_t > 0.0:
		corrupt_t -= d
		if corrupt_t <= 0.0:
			for l in level.labels:
				l.node.text = l.text
	if phantom.visible:
		phantom_t -= d
		var hp := phantom.global_position + Vector3(0, 1.5, 0)
		if phantom_t <= 0.0 or (player.cam.is_position_in_frustum(hp) and phantom_t < 1.2):
			phantom.visible = false
			play("whisper", -10.0, 0.7)
	if hallu_t > 0.0 or madness < 0.35:
		return
	hallu_t = rng.randf_range(7.0, 16.0) * (1.4 - madness)
	match rng.randi() % 4:
		0:
			whisper_pl.pitch_scale = rng.randf_range(0.7, 1.2)
			whisper_pl.volume_db = -8.0 + madness * 6.0
			whisper_pl.play()
			if rng.randf() < 0.5:
				show_msg("...%s..." % CREEPY[rng.randi() % CREEPY.size()].to_lower(), 1.5)
		1:
			blackout_t = rng.randf_range(0.8, 2.0)
			play("click", -8.0, 0.5)
		2:
			corrupt_t = 4.0
			for l in level.labels:
				if rng.randf() < 0.6:
					l.node.text = CREEPY[rng.randi() % CREEPY.size()]
		3:
			# sylwetka w oddali, w kierunku patrzenia
			var cp: Vector3 = player.cam.global_position
			var fwd: Vector3 = -player.cam.global_basis.z
			fwd.y = 0
			fwd = fwd.normalized()
			for dist in [14.0, 11.0, 8.0]:
				var p: Vector3 = cp + fwd * dist
				if los(cp, p + Vector3(0, 0.0, 0)):
					phantom.global_position = Vector3(p.x, 0, p.z)
					phantom.rotation.y = atan2(fwd.x, fwd.z)
					phantom.visible = true
					phantom_t = 1.6
					break


func _update_dying(d: float) -> void:
	dying_t += d
	var head: Vector3 = dying_by.global_position + Vector3(0, 2.45, 0)
	var cp: Vector3 = player.cam.global_position
	var to := head - cp
	var want_yaw := atan2(-to.x, -to.z)
	player.yaw = lerp_angle(player.yaw, want_yaw, 0.3)
	player.pitch = lerpf(player.pitch, atan2(to.y, Vector2(to.x, to.z).length()), 0.3)
	player.cam.position.x = randf_range(-0.04, 0.04) * (1.5 - dying_t)
	dying_by.global_position += (Vector3(cp.x, dying_by.global_position.y, cp.z) - dying_by.global_position) * d * 1.5
	flash = maxf(flash, 0.5 - dying_t * 0.4)
	danger = 1.0
	if dying_t > 1.5:
		g = G.DEAD
		_end("ZŁAPANY", death_text, Color(1, 0.2, 0.15))


func _update_fx(d: float, t: float) -> void:
	flash = maxf(flash - d * 1.8, 0.0)
	hurt = maxf(hurt - d * 1.2, 0.0)
	var target := 0.12 + keys * 0.035 + pow(1.0 - sanity / 100.0, 1.3) * 0.85 + danger * 0.25
	if g == G.DYING:
		target = 1.0
	madness = lerpf(madness, clampf(target, 0.0, 1.0), 1.0 - exp(-1.5 * d))
	var m := madness_override if madness_override >= 0.0 else madness
	RenderingServer.global_shader_parameter_set("madness", m)
	post_mat.set_shader_parameter("madness", m)
	post_mat.set_shader_parameter("danger", danger)
	post_mat.set_shader_parameter("flash", flash)
	post_mat.set_shader_parameter("hurt", hurt)
	post_mat.set_shader_parameter("t", t)
	env.volumetric_fog_albedo = Color.from_hsv(fmod(0.72 + t * 0.02 * m, 1.0), 0.3 + m * 0.5, 0.6)
	env.volumetric_fog_emission = Color.from_hsv(fmod(0.8 + t * 0.03, 1.0), 0.8, 0.02 + m * 0.05) if m > 0.3 else Color(0.012, 0.004, 0.02)
	drone.pitch_scale = 1.0 - m * 0.2
	drone.volume_db = -8.0 + m * 6.0
	# lampy
	for l in level.lamps:
		var on := true
		if l.flicker:
			on = fmod(t * 7.3 + l.pos.x, 5.0) > 0.4 and randf() > 0.04 + m * 0.1
		if blackout_t > 0.0:
			on = false
		l.on = on
		var light: Light3D = l.light
		light.light_energy = (l.energy if on else 0.0)
		if m > 0.4:
			light.light_color = l.col.lerp(Color.from_hsv(fmod(t * 0.07 + l.pos.x * 0.01, 1.0), 0.7, 1.0), (m - 0.4) * 1.2)
		else:
			light.light_color = l.col
		var mm: MeshInstance3D = l.mesh
		mm.visible = true
		if mm.material_override is StandardMaterial3D:
			(mm.material_override as StandardMaterial3D).emission_energy_multiplier = 2.5 if on else 0.05
	for s in level.screens:
		var sm: StandardMaterial3D = s.material_override
		sm.emission_energy_multiplier = randf_range(0.2, 1.0) * (0.5 + m * 2.0)
	# przyczajenie w szafie
	hide_overlay.visible = player.hiding != null


func _update_hud(d: float) -> void:
	msg_t -= d
	sub_t -= d
	msg_lbl.modulate.a = clampf(msg_t, 0.0, 1.0)
	sub_lbl.modulate.a = clampf(sub_t, 0.0, 1.0)
	var show := g == G.PLAY
	keys_lbl.visible = show
	crosshair.visible = show and not player.hiding
	keys_lbl.text = "IMBUSY  %d / %d" % [keys, KEYS_NEEDED]
	if keys >= KEYS_NEEDED:
		keys_lbl.text = "IMBUSY  %d / %d — DO WYJŚCIA" % [keys, KEYS_NEEDED]
	bars.sanity.size.x = 216.0 * sanity / 100.0
	bars.battery.size.x = 216.0 * player.battery / 100.0
	bars.stamina.size.x = 216.0 * player.stamina / 100.0
	for b in bars.values():
		b.get_parent().visible = show
	if not show:
		prompt_lbl.text = ""


# ---------------------------------------------------------------- test

func _apply_test_args() -> void:
	if args.get("menu", "0") == "1":
		return
	_start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if args.has("noui"):
		ui_root.visible = false
	if args.has("cell"):
		var p: PackedStringArray = args["cell"].split(",")
		player.global_position = level.cell_center(Vector2i(int(p[0]), int(p[1]))) + Vector3(0, 0.1, 0)
	if args.has("exit"):
		player.global_position = level.exit_pos + Vector3(0, 0.1, -5.0)
		player.set_look(0.0 + PI, 0.0)
	if args.has("yaw"):
		player.set_look(float(args["yaw"]), float(args.get("pitch", "0")))
	if args.has("madness"):
		madness_override = float(args["madness"])
	if args.has("hunter"):
		var fwd: Vector3 = -player.global_basis.z
		hunter.global_position = player.global_position + fwd * float(args["hunter"])
		hunter.global_position.y = 0
		hunter.rotation.y = atan2(fwd.x, fwd.z)
		hunter.activate()
		hunter_active = true
	if args.has("dark"):
		player.light_on = false
	if args.has("mann"):
		var mp: Vector3 = mannequins[0].global_position
		var dirs := [Vector3(3.5, 0, 0), Vector3(-3.5, 0, 0), Vector3(0, 0, 3.5), Vector3(0, 0, -3.5)]
		for dv in dirs:
			if los(mp + Vector3(0, 1, 0), mp + dv + Vector3(0, 1, 0)):
				player.global_position = mp + dv + Vector3(0, 0.1, 0)
				player.set_look(atan2(dv.x, dv.z), -0.1)
				break
	if args.has("t0"):
		t_play = float(args["t0"])
	if args.has("hide") and level.wardrobes.size() > 0:
		player.hide_in(level.wardrobes[0])
