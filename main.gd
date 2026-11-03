extends Node3D
# Cart Runner — performance stress test.
# Endless downhill road, a cart full of physics groceries, fps HUD.
# Drag left/right (or A/D / arrows) to steer. Hit crates or tip over = crash.

const ROAD_LEN := 30.0
const ROAD_W := 8.0
const NUM_CHUNKS := 8
const SLOPE_DEG := 8.0
const START_ITEMS := 30

var slope := deg_to_rad(SLOPE_DEG)
var fwd := Vector3.ZERO      # downhill direction along the road surface
var up_n := Vector3.ZERO     # road surface normal

var chunks: Array = []       # [{node, s}]
var next_s := 0.0

var cart: RigidBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var items: Array[RigidBody3D] = []

var hud: Label
var msg: Label
var shadow_btn: Button

var touching := false
var touch_x := 0.0
var crashed := false
var crash_t := 0.0
var prev_fwd_speed := 0.0
var run_time := 0.0
var frame := 0
var autotest := false
var mats := {}
var fps_min := 999.0
var fps_samples: Array[float] = []

# ---------- helpers ----------

func mat(c: Color) -> StandardMaterial3D:
	if mats.has(c):
		return mats[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	mats[c] = m
	return m

func add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func add_box_mesh(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return add_mesh(parent, b, pos, c, rot)

func add_box_shape(parent: Node3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	cs.rotation = rot
	parent.add_child(cs)

func add_box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	add_box_mesh(parent, size, pos, c, rot)
	add_box_shape(parent, size, pos, rot)

func road_point(s: float, x := 0.0, h := 0.0) -> Vector3:
	return fwd * s + Vector3(x, 0, 0) + up_n * h

# ---------- setup ----------

func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
	randomize()
	fwd = Vector3(0, -sin(slope), -cos(slope))
	up_n = Vector3(0, cos(slope), -sin(slope))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.99, 0.83, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.95, 0.9)
	e.ambient_light_energy = 0.65
	e.fog_enabled = true
	e.fog_light_color = Color(0.99, 0.83, 0.62)
	e.fog_density = 0.012
	env.environment = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 35.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

	for i in NUM_CHUNKS:
		var ch := StaticBody3D.new()
		add_child(ch)
		chunks.append({"node": ch, "s": 0.0})
		place_chunk(chunks[i], next_s, i < 2)
		next_s += ROAD_LEN

	make_cart()
	for i in START_ITEMS:
		spawn_item(i)

	cam = Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.global_position = cart.global_position - fwd * 7 + Vector3(0, 3.5, 0)

	make_hud()

func place_chunk(entry: Dictionary, s: float, empty: bool) -> void:
	var ch: StaticBody3D = entry["node"]
	entry["s"] = s
	for c in ch.get_children():
		c.queue_free()
	ch.rotation = Vector3(-slope, 0, 0)
	ch.position = road_point(s + ROAD_LEN * 0.5)
	# road surface: top at local y = 0
	add_box(ch, Vector3(ROAD_W, 1.0, ROAD_LEN + 0.4), Vector3(0, -0.5, 0), Color(0.33, 0.33, 0.36))
	# edge lines + dashed centre
	for sx in [-1, 1]:
		add_box_mesh(ch, Vector3(0.18, 0.02, ROAD_LEN), Vector3(sx * (ROAD_W * 0.5 - 0.35), 0.01, 0), Color(0.95, 0.95, 0.9))
		# curb wall: keeps the cart on the road, bounces it back
		add_box_shape(ch, Vector3(0.3, 1.2, ROAD_LEN), Vector3(sx * (ROAD_W * 0.5 + 0.15), 0.6, 0))
	for k in 5:
		add_box_mesh(ch, Vector3(0.15, 0.02, 2.5), Vector3(0, 0.01, -ROAD_LEN * 0.5 + 3 + k * 6), Color(0.95, 0.85, 0.3))
	# sidewalks + buildings (visual only)
	for sx in [-1, 1]:
		add_box_mesh(ch, Vector3(3.0, 0.3, ROAD_LEN), Vector3(sx * (ROAD_W * 0.5 + 1.5), 0.15, 0), Color(0.7, 0.66, 0.6))
		var z := -ROAD_LEN * 0.5 + 4.0
		while z < ROAD_LEN * 0.5 - 3:
			var w := randf_range(4, 7)
			var h := randf_range(4, 12)
			var col := Color.from_hsv(randf_range(0.02, 0.12), randf_range(0.25, 0.5), randf_range(0.7, 0.95))
			add_box_mesh(ch, Vector3(5, h, w - 0.5), Vector3(sx * (ROAD_W * 0.5 + 5.5), h * 0.5, z + w * 0.5), col)
			z += w
	if empty:
		return
	# obstacles: crates (crash) and speed bumps (spill)
	for k in randi_range(1, 3):
		var cx := randf_range(-ROAD_W * 0.5 + 1.0, ROAD_W * 0.5 - 1.0)
		var cz := randf_range(-ROAD_LEN * 0.5 + 2, ROAD_LEN * 0.5 - 2)
		add_box(ch, Vector3(1.0, 1.0, 1.0), Vector3(cx, 0.5, cz), Color(0.6, 0.42, 0.22))
	if randf() < 0.7:
		var bz := randf_range(-ROAD_LEN * 0.5 + 3, ROAD_LEN * 0.5 - 3)
		add_box(ch, Vector3(ROAD_W - 1.0, 0.22, 0.9), Vector3(0, 0.11, bz), Color(0.95, 0.7, 0.1))

func make_cart() -> void:
	cart = RigidBody3D.new()
	cart.mass = 8.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.05
	cart.physics_material_override = pm
	cart.linear_damp = 0.05
	cart.angular_damp = 2.5
	cart.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	cart.center_of_mass = Vector3(0, 0.15, 0)
	cart.continuous_cd = true
	cart.contact_monitor = true
	cart.max_contacts_reported = 4
	add_child(cart)
	cart.rotation = Vector3(-slope, 0, 0)
	cart.global_position = road_point(6.0, 0, 0.02)

	var metal := Color(0.75, 0.76, 0.8)
	var red := Color(0.85, 0.15, 0.12)
	# chassis collision (touches road) + floor
	add_box_shape(cart, Vector3(1.3, 0.2, 1.9), Vector3(0, 0.4, 0))
	# sphere wheels are the only ground contact: they roll over road seams
	for wx in [-0.5, 0.5]:
		for wz in [-0.75, 0.75]:
			var wcs := CollisionShape3D.new()
			var sph := SphereShape3D.new()
			sph.radius = 0.14
			wcs.shape = sph
			wcs.position = Vector3(wx, 0.14, wz)
			cart.add_child(wcs)
	add_box_mesh(cart, Vector3(1.3, 0.1, 1.9), Vector3(0, 0.45, 0), metal)
	# walls
	var t := 0.1
	var h := 0.9
	var y := 0.5 + h * 0.5
	add_box(cart, Vector3(1.3, h, t), Vector3(0, y, -0.95 + t * 0.5), red)
	add_box(cart, Vector3(1.3, h, t), Vector3(0, y, 0.95 - t * 0.5), red)
	add_box(cart, Vector3(t, h, 1.9), Vector3(-0.65 + t * 0.5, y, 0), red)
	add_box(cart, Vector3(t, h, 1.9), Vector3(0.65 - t * 0.5, y, 0), red)
	# wheels (visual)
	for wx in [-0.5, 0.5]:
		for wz in [-0.75, 0.75]:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.14
			cy.bottom_radius = 0.14
			cy.height = 0.1
			add_mesh(cart, cy, Vector3(wx, 0.14, wz), Color(0.1, 0.1, 0.1), Vector3(0, 0, PI * 0.5))
	# handle + boy (visual only for now)
	add_box_mesh(cart, Vector3(1.3, 0.06, 0.06), Vector3(0, 1.35, 1.15), metal)
	var body := CapsuleMesh.new()
	body.radius = 0.25
	body.height = 1.1
	add_mesh(cart, body, Vector3(0, 1.05, 1.55), Color(0.2, 0.45, 0.85))
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	add_mesh(cart, head, Vector3(0, 1.85, 1.55), Color(0.85, 0.65, 0.5))

func spawn_item(i: int) -> void:
	var it := RigidBody3D.new()
	it.mass = 0.3
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.15
	it.physics_material_override = pm
	it.continuous_cd = true
	var col := Color.from_hsv(randf(), 0.75, 0.95)
	var kind := i % 3
	var cs := CollisionShape3D.new()
	if kind == 0:
		var s := BoxShape3D.new()
		s.size = Vector3(0.28, 0.28, 0.28)
		cs.shape = s
		add_box_mesh(it, s.size, Vector3.ZERO, col)
	elif kind == 1:
		var s := SphereShape3D.new()
		s.radius = 0.15
		cs.shape = s
		var m := SphereMesh.new()
		m.radius = 0.15
		m.height = 0.3
		m.radial_segments = 12
		m.rings = 6
		add_mesh(it, m, Vector3.ZERO, col)
	else:
		var s := CylinderShape3D.new()
		s.radius = 0.11
		s.height = 0.34
		cs.shape = s
		var m := CylinderMesh.new()
		m.top_radius = 0.11
		m.bottom_radius = 0.11
		m.height = 0.34
		m.radial_segments = 10
		add_mesh(it, m, Vector3.ZERO, col)
	it.add_child(cs)
	add_child(it)
	var layer := items.size() / 15
	var local := Vector3(randf_range(-0.4, 0.4), 0.75 + layer * 0.32, randf_range(-0.7, 0.7))
	it.global_position = cart.to_global(local)
	it.linear_velocity = cart.linear_velocity
	items.append(it)

func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(20, 20)
	hud.add_theme_font_size_override("font_size", 30)
	hud.add_theme_color_override("font_color", Color.BLACK)
	layer.add_child(hud)

	msg = Label.new()
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 56)
	msg.add_theme_color_override("font_color", Color(0.7, 0.05, 0.05))
	msg.position = Vector2(-300, -100)
	msg.size = Vector2(600, 200)
	layer.add_child(msg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-250, 20)
	box.size = Vector2(230, 0)
	layer.add_child(box)
	shadow_btn = Button.new()
	shadow_btn.text = "Shadows: ON"
	shadow_btn.add_theme_font_size_override("font_size", 26)
	shadow_btn.pressed.connect(func():
		sun.shadow_enabled = not sun.shadow_enabled
		shadow_btn.text = "Shadows: " + ("ON" if sun.shadow_enabled else "OFF"))
	box.add_child(shadow_btn)
	var more := Button.new()
	more.text = "+10 items"
	more.add_theme_font_size_override("font_size", 26)
	more.pressed.connect(func():
		for k in 10:
			spawn_item(items.size()))
	box.add_child(more)
	var reset := Button.new()
	reset.text = "Restart"
	reset.add_theme_font_size_override("font_size", 26)
	reset.pressed.connect(func(): get_tree().reload_current_scene())
	box.add_child(reset)

# ---------- input ----------

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		touching = ev.pressed
		touch_x = ev.position.x
		if ev.pressed and crashed and crash_t > 1.0:
			get_tree().reload_current_scene()
	elif ev is InputEventScreenDrag:
		touch_x = ev.position.x

func get_steer() -> float:
	if autotest:
		return sin(run_time * 1.1) * 0.35
	var s := 0.0
	if touching:
		var w := get_viewport().get_visible_rect().size.x
		s = clamp((touch_x / w - 0.5) * 2.6, -1.0, 1.0)
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		s = -1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		s = 1.0
	return s

# ---------- loop ----------

func cart_s() -> float:
	return cart.global_position.dot(fwd)

func items_in_cart() -> int:
	var n := 0
	for it in items:
		var l := cart.to_local(it.global_position)
		if abs(l.x) < 0.65 and abs(l.z) < 0.95 and l.y > 0.4 and l.y < 2.2:
			n += 1
	return n

func _physics_process(delta: float) -> void:
	if crashed:
		crash_t += delta
		return
	run_time += delta
	var v := cart.linear_velocity
	var fwd_speed := v.dot(fwd)
	var target: float = minf(10.0 + run_time * 0.35, 24.0)
	if fwd_speed < target:
		cart.apply_central_force(fwd * cart.mass * (target - fwd_speed) * 1.2)
	var desired_x := get_steer() * 7.0
	cart.apply_central_force(Vector3(1, 0, 0) * cart.mass * (desired_x - v.x) * 5.0)

	# crash checks
	var tipped := cart.global_transform.basis.y.dot(up_n) < 0.45
	var height := (cart.global_position - road_point(cart_s())).dot(up_n)
	var off_road := height < -1.5
	var slammed := prev_fwd_speed - fwd_speed > 5.0
	if tipped or off_road or slammed:
		if autotest:
			print("CRASH reason tipped=", tipped, " off_road=", off_road, " slammed=", slammed, " dv=", prev_fwd_speed - fwd_speed, " t=", run_time)
		crash()
	prev_fwd_speed = fwd_speed

	# recycle road chunks behind the cart
	var cs := cart_s()
	for entry in chunks:
		if entry["s"] + ROAD_LEN < cs - ROAD_LEN:
			place_chunk(entry, next_s, false)
			next_s += ROAD_LEN

	# drop items left far behind
	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		if it.global_position.dot(fwd) < cs - 25.0 or it.global_position.y < cart.global_position.y - 30.0:
			it.queue_free()
			items.remove_at(i)

func crash() -> void:
	crashed = true
	crash_t = 0.0
	msg.text = "CRASH!\ntap to restart"
	# fling stuff for drama
	for it in items:
		it.apply_central_impulse(Vector3(randf_range(-1, 1), randf_range(1, 2.5), randf_range(-1, 1)) * 0.6)

func _process(delta: float) -> void:
	frame += 1
	var target_pos := cart.global_position - fwd * 6.5 + Vector3(0, 3.2, 0)
	cam.global_position = cam.global_position.lerp(target_pos, clamp(delta * 6.0, 0.0, 1.0))
	cam.look_at(cart.global_position + fwd * 6.0 + Vector3(0, 0.6, 0), Vector3.UP)

	var fps := Engine.get_frames_per_second()
	if frame > 60:
		fps_samples.append(fps)
		fps_min = min(fps_min, fps)
	var dist := cart_s() - 6.0
	hud.text = "FPS: %d  (min %d)\nSpeed: %d km/h\nItems: %d / %d\nDistance: %d m" % [
		fps, int(fps_min if fps_min < 999 else fps), int(max(cart.linear_velocity.dot(fwd), 0) * 3.6),
		items_in_cart(), items.size(), int(dist)]

	if autotest:
		if frame in [20, 60, 120, 240]:
			print("t=", frame, " items_in_cart=", items_in_cart(), " cart_h=", (cart.global_position - road_point(cart_s())).dot(up_n), " crashed=", crashed)
		if frame in [90, 300, 600]:
			var p := "user://shot_%d.png" % frame
			get_viewport().get_texture().get_image().save_png(p)
			print("SHOT ", ProjectSettings.globalize_path(p), " | ", hud.text.replace("\n", " | "), " crashed=", crashed)
		if frame >= 620:
			print("DONE crashed=", crashed, " dist=", int(dist), " items_in_cart=", items_in_cart())
			get_tree().quit()
