extends Node3D
# Cart Runner — game loop prototype (build 2).
# Grab groceries on the road. The fuller the cart, the faster it goes and the
# harder it steers. Bumps and hard swerves spill items. Score = what's still in
# the cart when you crash.

const ROAD_LEN := 30.0
const ROAD_W := 8.0
const NUM_CHUNKS := 8
const SLOPE_DEG := 8.0
const WALL_H := 0.7
const MAX_ITEMS := 80

enum State { READY, RUNNING, CRASHED }

var slope := deg_to_rad(SLOPE_DEG)
var fwd := Vector3.ZERO
var up_n := Vector3.ZERO

var chunks: Array = []
var next_s := 0.0
var pickups: Array[Node3D] = []
var crates: Array[Node3D] = []

var cart: RigidBody3D
var boy_visual: Node3D
var boy_body: RigidBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var items: Array[RigidBody3D] = []

var hud: Label
var msg: Label
var debug_lbl: Label

var state := State.READY
var touching := false
var touch_x := 0.0
var crash_t := 0.0
var prev_fwd_speed := 0.0
var run_time := 0.0
var frame := 0
var autotest := false
var mats := {}

var cart_load := 0
var collected := 0
var best := 0
var final_score := 0
var crash_reason := ""

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

func add_box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := add_box_mesh(parent, size, pos, c, rot)
	add_box_shape(parent, size, pos, rot)
	return mi

func road_point(s: float, x := 0.0, h := 0.0) -> Vector3:
	return fwd * s + Vector3(x, 0, 0) + up_n * h

func grocery_mesh(kind: int) -> Mesh:
	if kind == 0:
		var b := BoxMesh.new()
		b.size = Vector3(0.28, 0.28, 0.28)
		return b
	elif kind == 1:
		var m := SphereMesh.new()
		m.radius = 0.15
		m.height = 0.3
		m.radial_segments = 12
		m.rings = 6
		return m
	var c := CylinderMesh.new()
	c.top_radius = 0.11
	c.bottom_radius = 0.11
	c.height = 0.34
	c.radial_segments = 10
	return c

func grocery_color() -> Color:
	return Color.from_hsv(randf(), 0.75, 0.95)

# ---------- setup ----------

func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
	randomize()
	fwd = Vector3(0, -sin(slope), -cos(slope))
	up_n = Vector3(0, cos(slope), -sin(slope))
	load_best()

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
		place_chunk(chunks[i], next_s, i)
		next_s += ROAD_LEN

	make_cart()

	cam = Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.global_position = cart.global_position - fwd * 6.5 + Vector3(0, 3.2, 0)

	make_hud()
	if autotest:
		start_run()
	else:
		cart.freeze = true
		msg.text = "CART RUNNER\n\nhold left / right to steer\ngrab groceries, don't spill\n\ntap to start"

func place_chunk(entry: Dictionary, s: float, index: int) -> void:
	var ch: StaticBody3D = entry["node"]
	entry["s"] = s
	for c in ch.get_children():
		c.queue_free()
	ch.rotation = Vector3(-slope, 0, 0)
	ch.position = road_point(s + ROAD_LEN * 0.5)
	add_box(ch, Vector3(ROAD_W, 1.0, ROAD_LEN + 0.4), Vector3(0, -0.5, 0), Color(0.33, 0.33, 0.36))
	for sx in [-1, 1]:
		add_box_mesh(ch, Vector3(0.18, 0.02, ROAD_LEN), Vector3(sx * (ROAD_W * 0.5 - 0.35), 0.01, 0), Color(0.95, 0.95, 0.9))
		add_box_shape(ch, Vector3(0.3, 1.2, ROAD_LEN), Vector3(sx * (ROAD_W * 0.5 + 0.15), 0.6, 0))
	for k in 5:
		add_box_mesh(ch, Vector3(0.15, 0.02, 2.5), Vector3(0, 0.01, -ROAD_LEN * 0.5 + 3 + k * 6), Color(0.95, 0.85, 0.3))
	for sx in [-1, 1]:
		add_box_mesh(ch, Vector3(3.0, 0.3, ROAD_LEN), Vector3(sx * (ROAD_W * 0.5 + 1.5), 0.15, 0), Color(0.7, 0.66, 0.6))
		var z := -ROAD_LEN * 0.5 + 4.0
		while z < ROAD_LEN * 0.5 - 3:
			var w := randf_range(4, 7)
			var h := randf_range(4, 12)
			var col := Color.from_hsv(randf_range(0.02, 0.12), randf_range(0.25, 0.5), randf_range(0.7, 0.95))
			add_box_mesh(ch, Vector3(5, h, w - 0.5), Vector3(sx * (ROAD_W * 0.5 + 5.5), h * 0.5, z + w * 0.5), col)
			z += w

	# difficulty grows with distance
	var lvl := clampf(s / 600.0, 0.0, 1.0)
	var lanes := [-2.4, 0.0, 2.4]

	# pickups: a line of groceries in one lane (local z: +half is uphill/start)
	if index >= 1:
		var groups := 2
		for g in groups:
			var lane: float = lanes[randi() % 3] + randf_range(-0.5, 0.5)
			var z0 := ROAD_LEN * 0.5 - 3.0 - g * 14.0
			var count := randi_range(3, 6)
			for k in count:
				add_pickup(ch, Vector3(lane, 0.6, z0 - k * 1.6))
	if index < 2:
		return
	# crates — sometimes guarding a pickup lane (risk/reward)
	var n_crates := randi_range(1, 2 + int(lvl * 2))
	for k in n_crates:
		var cx: float = lanes[randi() % 3] + randf_range(-0.6, 0.6)
		var cz := randf_range(-ROAD_LEN * 0.5 + 2, ROAD_LEN * 0.5 - 2)
		var cr := add_box(ch, Vector3(1.0, 1.0, 1.0), Vector3(cx, 0.5, cz), Color(0.6, 0.42, 0.22))
		crates.append(cr)
	if randf() < 0.5 + lvl * 0.3:
		var bz := randf_range(-ROAD_LEN * 0.5 + 3, ROAD_LEN * 0.5 - 3)
		# rounded speed bump: a fat cylinder mostly sunk into the road, so wheels
		# roll up it and get kicked into the air (spilling groceries)
		var r := 0.45
		var bump_y := -r + 0.14
		var cyl_shape := CylinderShape3D.new()
		cyl_shape.radius = r
		cyl_shape.height = ROAD_W - 1.0
		var bcs := CollisionShape3D.new()
		bcs.shape = cyl_shape
		bcs.position = Vector3(0, bump_y, bz)
		bcs.rotation = Vector3(0, 0, PI * 0.5)
		ch.add_child(bcs)
		var cyl_mesh := CylinderMesh.new()
		cyl_mesh.top_radius = r
		cyl_mesh.bottom_radius = r
		cyl_mesh.height = ROAD_W - 1.0
		cyl_mesh.radial_segments = 16
		add_mesh(ch, cyl_mesh, Vector3(0, bump_y, bz), Color(0.95, 0.7, 0.1), Vector3(0, 0, PI * 0.5))

func add_pickup(parent: Node3D, pos: Vector3) -> void:
	var kind := randi() % 3
	var p := add_mesh(parent, grocery_mesh(kind), pos, grocery_color())
	p.scale = Vector3.ONE * 1.6
	p.set_meta("kind", kind)
	pickups.append(p)

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
	add_child(cart)
	cart.rotation = Vector3(-slope, 0, 0)
	cart.global_position = road_point(6.0, 0, 0.02)

	var metal := Color(0.75, 0.76, 0.8)
	var red := Color(0.85, 0.15, 0.12)
	add_box_shape(cart, Vector3(1.3, 0.2, 1.9), Vector3(0, 0.4, 0))
	for wx in [-0.5, 0.5]:
		for wz in [-0.75, 0.75]:
			var wcs := CollisionShape3D.new()
			var sph := SphereShape3D.new()
			sph.radius = 0.14
			wcs.shape = sph
			wcs.position = Vector3(wx, 0.14, wz)
			cart.add_child(wcs)
	add_box_mesh(cart, Vector3(1.3, 0.1, 1.9), Vector3(0, 0.45, 0), metal)
	var t := 0.1
	var y := 0.5 + WALL_H * 0.5
	add_box(cart, Vector3(1.3, WALL_H, t), Vector3(0, y, -0.95 + t * 0.5), red)
	add_box(cart, Vector3(1.3, WALL_H, t), Vector3(0, y, 0.95 - t * 0.5), red)
	add_box(cart, Vector3(t, WALL_H, 1.9), Vector3(-0.65 + t * 0.5, y, 0), red)
	add_box(cart, Vector3(t, WALL_H, 1.9), Vector3(0.65 - t * 0.5, y, 0), red)
	for wx in [-0.5, 0.5]:
		for wz in [-0.75, 0.75]:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.14
			cy.bottom_radius = 0.14
			cy.height = 0.1
			add_mesh(cart, cy, Vector3(wx, 0.14, wz), Color(0.1, 0.1, 0.1), Vector3(0, 0, PI * 0.5))
	add_box_mesh(cart, Vector3(1.3, 0.06, 0.06), Vector3(0, 1.35, 1.15), metal)

	# boy standing on the back rail (visual while riding)
	boy_visual = Node3D.new()
	boy_visual.position = Vector3(0, 0, 1.45)
	cart.add_child(boy_visual)
	build_boy(boy_visual)

func build_boy(parent: Node3D) -> void:
	var body := CapsuleMesh.new()
	body.radius = 0.25
	body.height = 1.1
	add_mesh(parent, body, Vector3(0, 1.05, 0), Color(0.2, 0.45, 0.85))
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	add_mesh(parent, head, Vector3(0, 1.85, 0), Color(0.85, 0.65, 0.5))
	for sx in [-1, 1]:
		add_box_mesh(parent, Vector3(0.1, 0.1, 0.45), Vector3(sx * 0.3, 1.3, -0.25), Color(0.2, 0.45, 0.85))

func spawn_item(kind: int) -> void:
	if items.size() >= MAX_ITEMS:
		return
	var it := RigidBody3D.new()
	it.mass = 0.3
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.15
	it.physics_material_override = pm
	it.continuous_cd = true
	var cs := CollisionShape3D.new()
	if kind == 0:
		var s := BoxShape3D.new()
		s.size = Vector3(0.28, 0.28, 0.28)
		cs.shape = s
	elif kind == 1:
		var s := SphereShape3D.new()
		s.radius = 0.15
		cs.shape = s
	else:
		var s := CylinderShape3D.new()
		s.radius = 0.11
		s.height = 0.34
		cs.shape = s
	it.add_child(cs)
	add_mesh(it, grocery_mesh(kind), Vector3.ZERO, grocery_color())
	add_child(it)
	# drop in from just above the cart, matching its speed
	var local := Vector3(randf_range(-0.4, 0.4), 1.5 + randf() * 0.3, randf_range(-0.6, 0.6))
	it.global_position = cart.to_global(local)
	it.linear_velocity = cart.linear_velocity
	items.append(it)

func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(20, 20)
	hud.add_theme_font_size_override("font_size", 34)
	hud.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	hud.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	hud.add_theme_constant_override("outline_size", 6)
	layer.add_child(hud)

	debug_lbl = Label.new()
	debug_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	debug_lbl.position = Vector2(12, -40)
	debug_lbl.add_theme_font_size_override("font_size", 20)
	debug_lbl.add_theme_color_override("font_color", Color(0, 0, 0, 0.6))
	layer.add_child(debug_lbl)

	msg = Label.new()
	msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 44)
	msg.add_theme_color_override("font_color", Color(0.15, 0.1, 0.1))
	msg.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	msg.add_theme_constant_override("outline_size", 10)
	layer.add_child(msg)

# ---------- save ----------

func load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://save.cfg") == OK:
		best = int(cf.get_value("score", "best", 0))

func save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("score", "best", best)
	cf.save("user://save.cfg")

# ---------- flow ----------

func start_run() -> void:
	state = State.RUNNING
	cart.freeze = false
	msg.text = ""
	run_time = 0.0

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		touching = ev.pressed
		touch_x = ev.position.x
		if ev.pressed:
			if state == State.READY:
				start_run()
			elif state == State.CRASHED and crash_t > 1.2:
				get_tree().reload_current_scene()
	elif ev is InputEventScreenDrag:
		touch_x = ev.position.x

func get_steer() -> float:
	if autotest:
		return bot_steer()
	var s := 0.0
	if touching:
		var w := get_viewport().get_visible_rect().size.x
		s = clamp((touch_x / w - 0.5) * 2.6, -1.0, 1.0)
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		s = -1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		s = 1.0
	return s

# simple bot for headless testing: chase the nearest pickup ahead, dodge crates
func bot_steer() -> float:
	var cs := cart_s()
	var cx := cart.global_position.x
	var target_x := 0.0
	var best_d := 1e9
	for p in pickups:
		if not is_instance_valid(p):
			continue
		var d := p.global_position.dot(fwd) - cs
		if d > 2.0 and d < 25.0 and d < best_d:
			best_d = d
			target_x = p.global_position.x
	for c in crates:
		if not is_instance_valid(c):
			continue
		var d := c.global_position.dot(fwd) - cs
		if d > 0.0 and d < 14.0 and abs(c.global_position.x - target_x) < 1.3:
			target_x = c.global_position.x + (2.0 if target_x >= c.global_position.x else -2.0)
	target_x = clampf(target_x, -3.2, 3.2)
	return clampf((target_x - cx) * 0.6, -1.0, 1.0)

# ---------- loop ----------

func cart_s() -> float:
	return cart.global_position.dot(fwd)

func items_in_cart() -> int:
	var n := 0
	for it in items:
		var l := cart.to_local(it.global_position)
		if abs(l.x) < 0.7 and abs(l.z) < 1.0 and l.y > 0.4 and l.y < 2.6:
			n += 1
	return n

func _physics_process(delta: float) -> void:
	if state == State.CRASHED:
		crash_t += delta
		return
	if state != State.RUNNING:
		return
	run_time += delta
	cart_load = items_in_cart()

	var v := cart.linear_velocity
	var fwd_speed := v.dot(fwd)
	# heavier cart = faster downhill, lazier steering
	var target: float = minf(10.0 + run_time * 0.3, 22.0) + cart_load * 0.12
	if fwd_speed < target:
		cart.apply_central_force(fwd * cart.mass * (target - fwd_speed) * 1.2)
	var grip := 5.0 / (1.0 + cart_load * 0.035)
	var max_lat := 7.0 - cart_load * 0.03
	var desired_x := get_steer() * max_lat
	cart.apply_central_force(Vector3(1, 0, 0) * cart.mass * (desired_x - v.x) * grip)

	# collect pickups the cart drives through
	var cpos := cart.global_position + up_n * 0.6
	for i in range(pickups.size() - 1, -1, -1):
		var p := pickups[i]
		if not is_instance_valid(p):
			pickups.remove_at(i)
			continue
		if p.global_position.distance_to(cpos) < 1.25:
			spawn_item(int(p.get_meta("kind")))
			collected += 1
			p.queue_free()
			pickups.remove_at(i)

	var tipped := cart.global_transform.basis.y.dot(up_n) < 0.45
	var height := (cart.global_position - road_point(cart_s())).dot(up_n)
	var slammed := prev_fwd_speed - fwd_speed > 5.0
	if tipped or height < -1.5 or slammed:
		crash_reason = "tipped" if tipped else ("slammed" if slammed else "fell")
		crash()
	prev_fwd_speed = fwd_speed

	var cs := cart_s()
	for entry in chunks:
		if entry["s"] + ROAD_LEN < cs - ROAD_LEN:
			place_chunk(entry, next_s, 99)
			next_s += ROAD_LEN

	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		if it.global_position.dot(fwd) < cs - 25.0:
			it.queue_free()
			items.remove_at(i)

	for i in range(crates.size() - 1, -1, -1):
		if not is_instance_valid(crates[i]):
			crates.remove_at(i)

func crash() -> void:
	state = State.CRASHED
	crash_t = 0.0
	final_score = items_in_cart()
	var new_best := final_score > best
	if new_best:
		best = final_score
		save_best()
	# launch the boy as a floppy two-part ragdoll
	var vel := cart.linear_velocity
	var xf := boy_visual.global_transform
	boy_visual.visible = false
	boy_body = RigidBody3D.new()
	boy_body.mass = 3.0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.1
	cs.shape = cap
	cs.position = Vector3(0, 1.05, 0)
	boy_body.add_child(cs)
	var body := CapsuleMesh.new()
	body.radius = 0.25
	body.height = 1.1
	add_mesh(boy_body, body, Vector3(0, 1.05, 0), Color(0.2, 0.45, 0.85))
	add_child(boy_body)
	boy_body.global_transform = xf
	boy_body.linear_velocity = vel + up_n * 4.0 + fwd * 2.0
	boy_body.angular_velocity = Vector3(randf_range(6, 10), randf_range(-3, 3), randf_range(-4, 4))

	var head_body := RigidBody3D.new()
	head_body.mass = 0.8
	var hs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.2
	hs.shape = sph
	head_body.add_child(hs)
	var head := SphereMesh.new()
	head.radius = 0.2
	head.height = 0.4
	add_mesh(head_body, head, Vector3.ZERO, Color(0.85, 0.65, 0.5))
	add_child(head_body)
	head_body.global_position = xf * Vector3(0, 1.85, 0)
	head_body.linear_velocity = boy_body.linear_velocity
	var joint := PinJoint3D.new()
	add_child(joint)
	joint.global_position = xf * Vector3(0, 1.62, 0)
	joint.node_a = joint.get_path_to(boy_body)
	joint.node_b = joint.get_path_to(head_body)

	# groceries keep their momentum and fly out
	for it in items:
		it.apply_central_impulse((up_n * randf_range(0.5, 1.2) + Vector3(randf_range(-0.5, 0.5), 0, 0)) * 0.5)

	msg.text = "CRASH!\n\nScore: %d\n%s\nBest: %d\n\ntap to restart" % [
		final_score, ("NEW BEST!" if new_best else ""), best]

func _process(delta: float) -> void:
	frame += 1
	var focus := cart.global_position
	if state == State.CRASHED and is_instance_valid(boy_body):
		focus = focus.lerp(boy_body.global_position, 0.5)
	var target_pos := focus - fwd * 6.5 + Vector3(0, 3.2, 0)
	cam.global_position = cam.global_position.lerp(target_pos, clamp(delta * 6.0, 0.0, 1.0))
	cam.look_at(focus + fwd * 6.0 + Vector3(0, 0.6, 0), Vector3.UP)

	for p in pickups:
		if is_instance_valid(p):
			p.rotate_y(delta * 2.5)

	var dist := int(maxf(cart_s() - 6.0, 0.0))
	if state != State.READY:
		var shown := final_score if state == State.CRASHED else cart_load
		hud.text = "In cart: %d\nBest: %d\n%d m" % [shown, best, dist]
	else:
		hud.text = "Best: %d" % best
	debug_lbl.text = "fps %d · speed %d km/h · items %d" % [
		Engine.get_frames_per_second(), int(maxf(cart.linear_velocity.dot(fwd), 0) * 3.6), items.size()]

	if autotest:
		if frame % 100 == 0:
			print("f=", frame, " state=", state, " load=", cart_load, " collected=", collected, " dist=", dist,
				" speed=", int(cart.linear_velocity.dot(fwd) * 3.6), " reason=", crash_reason)
		if frame in [150, 400, 700]:
			var p := "user://shot_%d.png" % frame
			get_viewport().get_texture().get_image().save_png(p)
		if state == State.CRASHED and crash_t > 0.6 and not has_meta("crash_shot"):
			set_meta("crash_shot", true)
			get_viewport().get_texture().get_image().save_png("user://shot_crash.png")
			print("CRASH at dist=", dist, " score=", final_score, " collected=", collected, " reason=", crash_reason)
		if frame >= 900 or (state == State.CRASHED and crash_t > 1.0):
			print("DONE")
			get_tree().quit()
