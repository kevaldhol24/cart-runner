extends Node3D
# Cart Runner — city version (build 5).
# Same loop as build 3 (grab groceries, weight vs control, spills, crash), now on
# a colourful Indian street with a curved world, toon shading and real models.

const ROAD_LEN := 30.0
const ROAD_W := 12.0
const LANES := [-4.0, 0.0, 4.0]
const BUILDINGS := ["res://assets/city/Building_Small_1.gltf", "res://assets/city/Building_Medium_2_001.gltf", "res://assets/city/Building_Large_2.gltf"]
const NUM_CHUNKS := 8
const SLOPE_DEG := 8.0
const WALL_H := 0.7
const MAX_ITEMS := 80
const NUM_VARIANTS := 6

enum State { LOADING, READY, RUNNING, CRASHED }

const PAINTS := [
	Color(0.98, 0.55, 0.65), Color(0.35, 0.82, 0.8), Color(1.0, 0.82, 0.35), Color(0.62, 0.9, 0.55),
	Color(1.0, 0.62, 0.35), Color(0.72, 0.62, 0.98), Color(0.45, 0.72, 1.0), Color(0.98, 0.9, 0.78)]
const AWNINGS := [
	[Color(0.95, 0.2, 0.2), Color(1, 1, 1)], [Color(0.1, 0.45, 0.9), Color(1, 1, 1)],
	[Color(0.1, 0.65, 0.3), Color(1, 0.9, 0.2)], [Color(1, 0.5, 0.1), Color(1, 0.95, 0.6)],
	[Color(0.6, 0.2, 0.7), Color(1, 0.85, 0.95)]]
const FLAG_COLS := [Color(1, 0.55, 0.1), Color(1, 1, 1), Color(0.1, 0.65, 0.25), Color(1, 0.25, 0.5), Color(1, 0.85, 0.1), Color(0.2, 0.5, 1)]

# groceries: model, visual size, collider
const FOODS := [
	{"path": "res://assets/food/Apple.glb", "size": 0.32, "axis": 1, "shape": "sphere"},
	{"path": "res://assets/food/Orange.glb", "size": 0.32, "axis": 1, "shape": "sphere"},
	{"path": "res://assets/food/Tomato.glb", "size": 0.3, "axis": 1, "shape": "sphere"},
	{"path": "res://assets/food/Banana.glb", "size": 0.42, "axis": 0, "shape": "box"},
	{"path": "res://assets/food/Carrot.glb", "size": 0.42, "axis": 1, "shape": "box"},
	{"path": "res://assets/food/SodaCan.glb", "size": 0.32, "axis": 1, "shape": "cyl"},
	{"path": "res://assets/food/Milkshake.glb", "size": 0.38, "axis": 1, "shape": "cyl"}]

var slope := deg_to_rad(SLOPE_DEG)
var fwd := Vector3.ZERO
var up_n := Vector3.ZERO

var chunks: Array = []
var next_s := 0.0
var variants: Array = []
var bld_info: Array = []   # [{scene, xmin, xmax, zmin}]
var street_scene: PackedScene
var prop_scenes := {}
var pickups: Array[Node3D] = []
var crates: Array[Node3D] = []
var bumps: Array[Node3D] = []
var shake := 0.0
var crash_ms := 0

var cart: RigidBody3D
var boy_visual: Node3D
var boy_anim: AnimationPlayer
var boy_body: RigidBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var items: Array[RigidBody3D] = []
var pop_fx: Array[CPUParticles3D] = []
var pop_i := 0
var crash_fx: CPUParticles3D

var hud: Label
var msg: Label
var debug_lbl: Label

var state := State.LOADING
var touching := false
var touch_x := 0.0
var crash_t := 0.0
var prev_fwd_speed := 0.0
var run_time := 0.0
var frame := 0
var autotest := false

var cart_load := 0
var collected := 0
var spilled := 0
var best := 0
var final_score := 0
var crash_reason := ""

# ---------- helpers ----------

func add_box_shape(parent: Node3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.position = pos
	cs.rotation = rot
	parent.add_child(cs)

func road_point(s: float, x := 0.0, h := 0.0) -> Vector3:
	return fwd * s + Vector3(x, 0, 0) + up_n * h

# ---------- setup ----------

func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
	Engine.time_scale = 1.0
	randomize()
	fwd = Vector3(0, -sin(slope), -cos(slope))
	up_n = Vector3(0, cos(slope), -sin(slope))
	load_best()
	Art.init()
	make_hud()
	msg.text = "loading..."

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.5, 0.95)
	sky_mat.sky_horizon_color = Color(0.7, 0.87, 1.0)
	sky_mat.ground_horizon_color = Color(0.7, 0.87, 1.0)
	sky_mat.ground_bottom_color = Color(0.7, 0.87, 1.0)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.83, 1.0)
	e.ambient_light_energy = 0.6
	e.fog_enabled = true
	e.fog_light_color = Color(0.72, 0.87, 1.0)
	e.fog_density = 0.004
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 38, 0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.7
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

	load_city()
	if autotest:
		var vc := 0
		for vv in variants:
			vc += (vv["env"] as ArrayMesh).surface_get_array_len(0)
		print("VERTS per chunk avg=", vc / NUM_VARIANTS, " tris=", vc / NUM_VARIANTS / 3)

	for i in NUM_CHUNKS:
		var ch := StaticBody3D.new()
		add_child(ch)
		chunks.append({"node": ch, "s": 0.0})
		place_chunk(chunks[i], next_s, i)
		next_s += ROAD_LEN

	make_cart()
	make_fx()

	cam = Camera3D.new()
	cam.fov = 68
	add_child(cam)
	cam.global_position = cart.global_position - fwd * 6.5 + Vector3(0, 3.4, 0)
	update_curve()

	if autotest:
		start_run()
	else:
		state = State.READY
		cart.freeze = true
		msg.text = "CART RUNNER\n\nhold left / right to steer\ngrab groceries, don't spill\n\ntap to start"

# ---------- street dressing (pre-baked variants, one draw call each) ----------

func build_variant(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var mb := Art.MB.new()
	var sm := Art.MB.new()
	var L := ROAD_LEN
	var hw := ROAD_W * 0.5
	var front := hw + 2.5
	# road surface + markings
	mb.bx(Vector3(0, -0.05, 0), Vector3(ROAD_W, 0.1, L + 0.4), Color(0.36, 0.37, 0.44))
	for lx in [-1.2, 1.2]:
		for k in 5:
			mb.bx(Vector3(lx, 0.006, -L * 0.5 + 3 + k * 6), Vector3(0.14, 0.02, 2.6), Color(0.97, 0.97, 0.97))
	for sx in [-1, 1]:
		mb.bx(Vector3(sx * (hw - 0.25), 0.006, 0), Vector3(0.14, 0.02, L), Color(1.0, 0.85, 0.2))
		var segs := 15
		for k in segs:
			var cz := -L * 0.5 + (k + 0.5) * L / segs
			var cc := Color(0.12, 0.12, 0.13) if k % 2 == 0 else Color(1.0, 0.85, 0.15)
			mb.bx(Vector3(sx * (hw + 0.12), 0.12, cz), Vector3(0.24, 0.24, L / segs), cc)
		mb.bx(Vector3(sx * (hw + 1.35), 0.1, 0), Vector3(2.3, 0.2, L + 0.4), Color(0.84, 0.78, 0.74))
		var z := L * 0.5
		while z > -L * 0.5 + 0.5:
			var w := minf(rng.randf_range(4.0, 6.5), z + L * 0.5)
			build_shop(mb, sm, rng, sx, front, z - w * 0.5, w)
			z -= w
		# taller pale skyline behind
		var z2 := L * 0.5
		while z2 > -L * 0.5:
			var w2 := rng.randf_range(5.0, 9.0)
			var h2 := rng.randf_range(11.0, 20.0)
			var pc: Color = (PAINTS[rng.randi() % PAINTS.size()] as Color).lerp(Color(0.85, 0.9, 1.0), 0.45)
			mb.bx(Vector3(sx * (front + 9.0), h2 * 0.5, z2 - w2 * 0.5), Vector3(6.0, h2, w2 - 0.3), pc)
			z2 -= w2
	# overhead electric wires
	for k in 3:
		var zc := rng.randf_range(-L * 0.5 + 1, L * 0.5 - 1)
		add_sag_line(mb, front, 9.0 + k * 0.25, zc, 0.6, Color(0.12, 0.12, 0.14), 0.04)
	# festival bunting
	for k in rng.randi_range(1, 2):
		var zc := rng.randf_range(-L * 0.5 + 2, L * 0.5 - 2)
		var pts := add_sag_line(mb, front, 8.2, zc, 0.5, Color(0.9, 0.9, 0.9), 0.03)
		var fi := rng.randi() % FLAG_COLS.size()
		for p in range(1, pts.size() - 1, 1):
			var a: Vector3 = pts[p]
			var b: Vector3 = pts[p + 1] if p + 1 < pts.size() else a + Vector3(0.3, 0, 0)
			var dir := (b - a)
			var mid := a + dir * 0.5 + Vector3(0, -0.42, 0)
			mb.flag(a, a + dir * 0.9, mid, FLAG_COLS[(fi + p) % FLAG_COLS.size()])
	return {"env": mb.commit(), "signs": sm.commit()}

# a sagging line across the street; returns points used
func add_sag_line(mb: Art.MB, front: float, y: float, z: float, sag: float, col: Color, th: float) -> Array:
	var pts := []
	var n := 28
	for i in n + 1:
		var x := -front + 2.0 * front * i / n
		var t := x / front
		pts.append(Vector3(x, y - sag * (1.0 - t * t), z))
	for i in n:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := b - a
		var ang := atan2(d.y, d.x)
		mb.bx((a + b) * 0.5, Vector3(d.length() + 0.01, th, th), col, Vector3(0, 0, ang))
	return pts

func build_shop(mb: Art.MB, sm: Art.MB, rng: RandomNumberGenerator, sx: int, front: float, zc: float, w: float) -> void:
	var floors := rng.randi_range(2, 4)
	var fh := 2.8
	var H := 3.0 + (floors - 1) * fh + 0.3
	var paint: Color = PAINTS[rng.randi() % PAINTS.size()]
	var trim := paint.darkened(0.28)
	var depth := 5.0
	var ww := w - 0.2
	mb.bx(Vector3(sx * (front + depth * 0.5), H * 0.5, zc), Vector3(depth, H, ww), paint)
	# ground floor shop
	mb.bx(Vector3(sx * (front - 0.02), 1.5, zc), Vector3(0.06, 3.0, ww), trim.lightened(0.15))
	var ow := ww * 0.74
	mb.bx(Vector3(sx * (front - 0.06), 1.15, zc), Vector3(0.06, 2.1, ow), Color(0.3, 0.22, 0.16))
	var cols := int(ow / 0.34)
	for row in 3:
		mb.bx(Vector3(sx * (front - 0.12), 0.28 + row * 0.62, zc), Vector3(0.16, 0.05, ow - 0.1), Color(0.55, 0.38, 0.22))
		for k in cols:
			var gz := zc - ow * 0.5 + 0.2 + k * 0.34
			var gh := 0.22 + rng.randf() * 0.2
			mb.bx(Vector3(sx * (front - 0.16), 0.3 + row * 0.62 + gh * 0.5, gz), Vector3(0.18, gh, 0.26), Color.from_hsv(rng.randf(), 0.7, 0.95))
	mb.bx(Vector3(sx * (front - 0.1), 2.18, zc), Vector3(0.18, 0.2, ow + 0.1), Color(0.62, 0.64, 0.68))
	# striped awning sloping toward the road
	var aw: Array = AWNINGS[rng.randi() % AWNINGS.size()]
	var stripes := 6
	var awl := w * 0.85
	for k in stripes:
		var sz := zc - awl * 0.5 + (k + 0.5) * awl / stripes
		mb.bx(Vector3(sx * (front - 0.68), 2.5, sz), Vector3(1.45, 0.07, awl / stripes), aw[k % 2], Vector3(0, 0, sx * 0.38))
	# shop sign
	var sw := minf(ww * 0.82, 4.4)
	var shh := sw / 4.0
	mb.bx(Vector3(sx * (front - 0.07), 3.35, zc), Vector3(0.1, shh + 0.14, sw + 0.14), Color(0.15, 0.12, 0.1))
	sm.quad(Vector3(sx * (front - 0.125), 3.35, zc), Vector3(-sx, 0, 0), sw, shh, Art.sign_uv(rng.randi() % Art.sign_count))
	# upper floors
	for f in range(1, floors):
		var yb := 3.0 + (f - 1) * fh
		mb.bx(Vector3(sx * (front - 0.05), yb, zc), Vector3(0.12, 0.16, ww), trim)
		for wz in [zc - ww * 0.23, zc + ww * 0.23]:
			mb.bx(Vector3(sx * (front - 0.02), yb + 1.4, wz), Vector3(0.05, 1.45, 1.15), Color(0.97, 0.97, 0.95))
			mb.bx(Vector3(sx * (front - 0.05), yb + 1.4, wz), Vector3(0.05, 1.2, 0.9), Color(0.24, 0.36, 0.5))
			for s2 in [-1, 1]:
				mb.bx(Vector3(sx * (front - 0.06), yb + 1.4, wz + s2 * 0.7), Vector3(0.05, 1.25, 0.26), trim)
		if rng.randf() < 0.45:
			mb.bx(Vector3(sx * (front - 0.45), yb + 0.06, zc), Vector3(0.9, 0.12, ww * 0.62), trim)
			mb.bx(Vector3(sx * (front - 0.88), yb + 0.45, zc), Vector3(0.05, 0.7, ww * 0.62), Color(0.2, 0.2, 0.22))
			if rng.randf() < 0.6:
				for k in 4:
					var cz := zc - ww * 0.25 + k * ww * 0.17
					mb.bx(Vector3(sx * (front - 0.8), yb + 1.05, cz), Vector3(0.04, 0.5, 0.35), Color.from_hsv(rng.randf(), 0.6, 0.95))
		if rng.randf() < 0.5:
			mb.bx(Vector3(sx * (front - 0.25), yb + 0.7, zc + ww * 0.42 * (1 if rng.randf() < 0.5 else -1)), Vector3(0.5, 0.42, 0.7), Color(0.92, 0.92, 0.94))
	mb.bx(Vector3(sx * (front + depth * 0.5 - 0.05), H + 0.15, zc), Vector3(depth + 0.1, 0.3, w - 0.1), trim)
	if rng.randf() < 0.55:
		mb.prim(Art.cyl(0.55, 1.0, 10), Transform3D(Basis(), Vector3(sx * (front + 2.6), H + 0.8, zc + rng.randf_range(-1.0, 1.0))), Color(0.12, 0.12, 0.14))

# ---------- chunks ----------

func load_city() -> void:
	street_scene = load("res://assets/city/Street_4Lane.gltf")
	for path in BUILDINGS:
		var sc: PackedScene = load(path)
		var probe: Node3D = sc.instantiate()
		var b := Art._aabb(probe)
		probe.free()
		bld_info.append({"scene": sc, "xmin": b.position.x, "xmax": b.end.x, "zmin": b.position.z})
	for nm in ["Prop_Planter_Single", "Prop_Bollard", "Prop_ManholeCover"]:
		prop_scenes[nm] = load("res://assets/city/%s.gltf" % nm)

func city_inst(sc: PackedScene) -> Node3D:
	var n: Node3D = sc.instantiate()
	Art.curve_node(n)
	return n

# a node placed in chunk-local space that stands upright in the world
func upright_basis(yaw: float) -> Basis:
	return Basis(Vector3.RIGHT, slope) * Basis(Vector3.UP, yaw)

func place_chunk(entry: Dictionary, s: float, index: int) -> void:
	var ch: StaticBody3D = entry["node"]
	entry["s"] = s
	for c in ch.get_children():
		c.queue_free()
	ch.rotation = Vector3(-slope, 0, 0)
	ch.position = road_point(s + ROAD_LEN * 0.5)
	var hw := ROAD_W * 0.5

	# street tiles: 6 m long each, asphalt surface at local y = 0
	var tiles := int(ROAD_LEN / 6.0)
	for i in tiles + 1:
		var st := city_inst(street_scene)
		st.position = Vector3(0, 0.15, ROAD_LEN * 0.5 - 3.0 - i * 6.0)
		st.rotation.y = PI * 0.5
		ch.add_child(st)
	add_box_shape(ch, Vector3(ROAD_W, 1.0, ROAD_LEN + 0.4), Vector3(0, -0.5, 0))

	for sx in [-1, 1]:
		add_box_shape(ch, Vector3(0.3, 1.2, ROAD_LEN), Vector3(sx * (hw + 0.15), 0.6, 0))
		# buildings fill the side, standing upright on the slope
		var z := ROAD_LEN * 0.5
		var guard := 0
		while z > -ROAD_LEN * 0.5 + 4.0 and guard < 6:
			guard += 1
			var bi: Dictionary = bld_info[randi() % bld_info.size()]
			var span: float = bi["xmax"] - bi["xmin"]
			var b := city_inst(bi["scene"])
			var yaw: float = -sx * PI * 0.5
			# along-street local axis after yaw: z' = x for sx=+1, -x for sx=-1
			var lo: float = float(bi["xmin"]) if sx > 0 else -float(bi["xmax"])
			var zc := z - span - lo
			b.transform = Transform3D(upright_basis(yaw), Vector3(sx * (hw + 3.0), 0.15, zc))
			# stone plinth fills the gap under the downhill end
			var depth: float = -bi["zmin"]
			var plinth := Art.MB.new()
			plinth.bx(Vector3((bi["xmin"] + bi["xmax"]) * 0.5, -1.8, -depth * 0.5), Vector3(span, 3.6, depth), Color(0.58, 0.55, 0.52))
			b.add_child(Art.mesh_node(plinth.commit(), Art.env_mat, false))
			ch.add_child(b)
			z -= span + 0.3
		# sidewalk dressing
		var lamp := Art.model("res://assets/props/Streetlight.glb", 5.5, 1)
		lamp.position = Vector3(sx * (hw + 0.6), 0.15, randf_range(-12, 12))
		lamp.rotation.y = PI * 0.5 * -sx
		ch.add_child(lamp)
		for k in 2:
			var nm: String = ["Prop_Planter_Single", "Prop_Bollard"][randi() % 2]
			var pr := city_inst(prop_scenes[nm])
			pr.transform = Transform3D(upright_basis(0.0), Vector3(sx * (hw + 1.6), 0.15, randf_range(-13, 13)))
			ch.add_child(pr)

	var lvl := clampf(s / 600.0, 0.0, 1.0)
	var lanes: Array = LANES
	if index >= 1:
		for g in 2:
			var lane: float = lanes[randi() % 3] + randf_range(-0.5, 0.5)
			var z0 := ROAD_LEN * 0.5 - 3.0 - g * 14.0
			var food := randi() % FOODS.size()
			for k in randi_range(3, 6):
				add_pickup(ch, Vector3(lane, 0.75, z0 - k * 1.6), food)
	if index < 2:
		return
	var kinds := ["taxi", "car", "car", "cones"]
	for k in randi_range(1, 2 + int(lvl * 2)):
		var cx: float = lanes[randi() % 3]
		var cz := randf_range(-ROAD_LEN * 0.5 + 3, ROAD_LEN * 0.5 - 3)
		add_obstacle(ch, kinds[randi() % kinds.size()], cx, cz)
	if randf() < 0.5 + lvl * 0.3:
		var bz := randf_range(-ROAD_LEN * 0.5 + 3, ROAD_LEN * 0.5 - 3)
		var order := [0, 1, 2]
		order.shuffle()
		var n_bumps := 1 if randf() < 0.6 - lvl * 0.3 else 2
		for k in n_bumps:
			add_bump(ch, Vector3(lanes[order[k]], 0, bz), 3.2)

func add_obstacle(ch: Node3D, kind: String, x: float, z: float) -> void:
	var node: Node3D
	var size := Vector3.ONE
	var yaw := 0.0
	match kind:
		"car":
			node = Art.model("res://assets/props/BasicCar.glb", 4.0, 2)
			size = Vector3(1.9, 1.5, 4.0)
			yaw = 0.0 if randf() < 0.5 else PI
		"cones":
			node = Node3D.new()
			for k in 3:
				var cone := Art.model("res://assets/props/TrafficCone.glb", 0.75, 1, {"Orange": Color(1.0, 0.45, 0.05), "White": Color(0.97, 0.97, 0.97)})
				cone.position = Vector3(-1.1 + k * 1.1, 0, 0)
				node.add_child(cone)
			size = Vector3(3.0, 0.75, 0.6)
		"taxi":
			node = Art.model("res://assets/props/Taxi.glb", 3.6, 2)
			size = Vector3(1.7, 1.5, 3.6)
			yaw = 0.0 if randf() < 0.5 else PI
	node.position = Vector3(x, 0, z)
	node.rotation.y = yaw
	ch.add_child(node)
	add_box_shape(ch, size, Vector3(x, size.y * 0.5, z), Vector3(0, yaw, 0))
	var half_x := absf(cos(yaw)) * size.x * 0.5 + absf(sin(yaw)) * size.z * 0.5
	node.set_meta("hw", half_x)
	crates.append(node)

func add_bump(ch: Node3D, pos: Vector3, width: float) -> void:
	var r := 0.45
	var y := -r + 0.10
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = r
	cyl_shape.height = width
	var bcs := CollisionShape3D.new()
	bcs.shape = cyl_shape
	bcs.position = Vector3(pos.x, y, pos.z)
	bcs.rotation = Vector3(0, 0, PI * 0.5)
	ch.add_child(bcs)
	var mb := Art.MB.new()
	var rot := Basis(Vector3(0, 0, 1), PI * 0.5)
	mb.prim(Art.cyl(r, width, 18), Transform3D(rot, Vector3(0, y, 0)), Color(1.0, 0.78, 0.1))
	for k in 4:
		var sx := -width * 0.5 + width * (k + 0.5) / 4.0
		mb.bx(Vector3(sx, 0.08, 0), Vector3(0.25, 0.06, 0.6), Color(0.12, 0.12, 0.12))
	var mi := Art.mesh_node(mb.commit(), Art.env_mat)
	mi.position = Vector3(pos.x, 0, pos.z)
	ch.add_child(mi)
	bumps.append(mi)

func add_pickup(parent: Node3D, pos: Vector3, food: int) -> void:
	var f: Dictionary = FOODS[food]
	var p := Art.model(f["path"], f["size"] * 1.7, f["axis"])
	p.position = pos
	p.set_meta("food", food)
	p.set_meta("base_y", pos.y)
	parent.add_child(p)
	pickups.append(p)

# ---------- cart + boy ----------

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

	add_box_shape(cart, Vector3(1.3, 0.2, 1.9), Vector3(0, 0.4, 0))
	for wx in [-0.5, 0.5]:
		for wz in [-0.75, 0.75]:
			var wcs := CollisionShape3D.new()
			var sphs := SphereShape3D.new()
			sphs.radius = 0.14
			wcs.shape = sphs
			wcs.position = Vector3(wx, 0.14, wz)
			cart.add_child(wcs)
	var t := 0.1
	var y := 0.5 + WALL_H * 0.5
	add_box_shape(cart, Vector3(1.3, WALL_H, t), Vector3(0, y, -0.95 + t * 0.5))
	add_box_shape(cart, Vector3(1.3, WALL_H, t), Vector3(0, y, 0.95 - t * 0.5))
	add_box_shape(cart, Vector3(t, WALL_H, 1.9), Vector3(-0.65 + t * 0.5, y, 0))
	add_box_shape(cart, Vector3(t, WALL_H, 1.9), Vector3(0.65 - t * 0.5, y, 0))
	cart.add_child(Art.mesh_node(Art.get_cart(), Art.env_mat))

	boy_visual = Art.model("res://assets/anim/UAL1_Standard.glb", 1.72, 1)
	boy_visual.position = Vector3(0, 0, 1.55)
	boy_visual.rotation.y = PI
	cart.add_child(boy_visual)
	boy_anim = Art.play_anim(boy_visual, "Push", 1.0)

func make_fx() -> void:
	for i in 4:
		var p := burst_particles(14, 0.07, 0.4, 2.0, 4.0)
		p.local_coords = true
		p.reparent(cart, false)
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 0.9, 0.2), Color(1, 0.4, 0.6), Color(0.4, 0.9, 1.0), Color(1, 1, 1)])
		g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
		p.color_initial_ramp = g
		pop_fx.append(p)
	crash_fx = burst_particles(40, 0.18, 0.9, 4.0, 9.0)
	var g2 := Gradient.new()
	g2.colors = PackedColorArray([Color(1, 0.95, 0.4), Color(0.95, 0.9, 0.85), Color(1, 0.6, 0.2)])
	g2.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	crash_fx.color_initial_ramp = g2

func burst_particles(amount: int, sz: float, life: float, vmin: float, vmax: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * sz
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = m
	p.mesh = bm
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.angular_velocity_min = -300
	p.angular_velocity_max = 300
	p.local_coords = false
	add_child(p)
	return p

func spawn_item(food: int) -> void:
	if items.size() >= MAX_ITEMS:
		return
	var f: Dictionary = FOODS[food]
	var it := RigidBody3D.new()
	it.mass = 0.3
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.15
	it.physics_material_override = pm
	it.continuous_cd = true
	var cs := CollisionShape3D.new()
	var sz: float = f["size"]
	match f["shape"]:
		"sphere":
			var s := SphereShape3D.new()
			s.radius = sz * 0.5
			cs.shape = s
			cs.position = Vector3(0, sz * 0.5, 0)
		"cyl":
			var s := CylinderShape3D.new()
			s.radius = sz * 0.3
			s.height = sz
			cs.shape = s
			cs.position = Vector3(0, sz * 0.5, 0)
		_:
			var s := BoxShape3D.new()
			s.size = Vector3(sz * 0.35, sz, sz * 0.35) if f["axis"] == 1 else Vector3(sz, sz * 0.35, sz * 0.35)
			cs.shape = s
			cs.position = Vector3(0, s.size.y * 0.5, 0)
	it.add_child(cs)
	it.add_child(Art.model(f["path"], sz, f["axis"]))
	add_child(it)
	var local := Vector3(randf_range(-0.4, 0.4), 1.4 + randf() * 0.3, randf_range(-0.6, 0.6))
	it.global_position = cart.to_global(local)
	it.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	it.linear_velocity = cart.linear_velocity
	items.append(it)

func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(24, 24)
	hud.add_theme_font_size_override("font_size", 40)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.2))
	hud.add_theme_constant_override("outline_size", 12)
	layer.add_child(hud)

	debug_lbl = Label.new()
	debug_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	debug_lbl.position = Vector2(12, -40)
	debug_lbl.add_theme_font_size_override("font_size", 20)
	debug_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	debug_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	debug_lbl.add_theme_constant_override("outline_size", 4)
	layer.add_child(debug_lbl)

	msg = Label.new()
	msg.set_anchors_preset(Control.PRESET_FULL_RECT)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 50)
	msg.add_theme_color_override("font_color", Color(1, 0.9, 0.2))
	msg.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.2))
	msg.add_theme_constant_override("outline_size", 16)
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
			elif state == State.CRASHED and crash_elapsed() > 1.4:
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

# headless test bot: chase the nearest pickup ahead, dodge obstacles and bumps
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
		var hwx: float = c.get_meta("hw", 0.8)
		if d > -1.0 and d < 16.0 and abs(c.global_position.x - target_x) < hwx + 0.9:
			target_x = c.global_position.x + (hwx + 1.2) * (1.0 if target_x >= c.global_position.x else -1.0)
	for b in bumps:
		if "--hitbumps" in OS.get_cmdline_user_args() or not is_instance_valid(b):
			continue
		var d := b.global_position.dot(fwd) - cs
		if d > 0.0 and d < 12.0 and abs(b.global_position.x - target_x) < 1.9:
			target_x = b.global_position.x + (2.4 if target_x >= b.global_position.x else -2.4)
	target_x = clampf(target_x, -5.0, 5.0)
	return clampf((target_x - cx) * 0.6, -1.0, 1.0)

# ---------- loop ----------

func cart_s() -> float:
	return cart.global_position.dot(fwd)

func items_in_cart() -> int:
	var n := 0
	for it in items:
		var l := cart.to_local(it.global_position)
		if abs(l.x) < 0.7 and abs(l.z) < 1.0 and l.y > 0.35 and l.y < 2.6:
			n += 1
	return n

func _physics_process(delta: float) -> void:
	if state == State.CRASHED:
		crash_t += delta
		return
	if state != State.RUNNING:
		return
	run_time += delta
	var prev_load := cart_load
	cart_load = items_in_cart()
	if cart_load < prev_load:
		spilled += prev_load - cart_load

	var v := cart.linear_velocity
	var fwd_speed := v.dot(fwd)
	var target: float = minf(10.0 + run_time * 0.3, 22.0) + cart_load * 0.12
	if fwd_speed < target:
		cart.apply_central_force(fwd * cart.mass * (target - fwd_speed) * 1.2)
	var grip := 5.0 / (1.0 + cart_load * 0.035)
	var max_lat := 8.5 - cart_load * 0.035
	var steer := get_steer()
	var desired_x := steer * max_lat
	cart.apply_central_force(Vector3(1, 0, 0) * cart.mass * (desired_x - v.x) * grip)
	var f := -cart.global_transform.basis.z
	var yaw := -asin(clampf(f.x, -1.0, 1.0))
	var desired_yaw := -steer * 0.12
	var lim := ROAD_W * 0.5 - 0.9
	var px := cart.global_position.x
	if absf(px) > lim:
		var outward := signf(px)
		if cart.linear_velocity.x * outward > 0.0:
			cart.linear_velocity = Vector3(cart.linear_velocity.x * 0.3, cart.linear_velocity.y, cart.linear_velocity.z)
		cart.apply_central_force(Vector3(-outward, 0, 0) * cart.mass * (absf(px) - lim) * 80.0)
		desired_yaw = 0.0
	var av := cart.angular_velocity
	cart.angular_velocity = av + up_n * ((desired_yaw - yaw) * 8.0 - av.dot(up_n))

	var cpos := cart.global_position + up_n * 0.6
	for i in range(pickups.size() - 1, -1, -1):
		var p := pickups[i]
		if not is_instance_valid(p):
			pickups.remove_at(i)
			continue
		if p.global_position.distance_to(cpos) < 1.3:
			spawn_item(int(p.get_meta("food")))
			collected += 1
			var fx := pop_fx[pop_i % pop_fx.size()]
			pop_i += 1
			fx.position = cart.to_local(p.global_position)
			fx.restart()
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
	for i in range(bumps.size() - 1, -1, -1):
		if not is_instance_valid(bumps[i]):
			bumps.remove_at(i)

func crash_elapsed() -> float:
	return (Time.get_ticks_msec() - crash_ms) / 1000.0

func crash() -> void:
	state = State.CRASHED
	crash_t = 0.0
	crash_ms = Time.get_ticks_msec()
	shake = 0.5
	Engine.time_scale = 0.2
	final_score = items_in_cart()
	var new_best := final_score > best
	if new_best:
		best = final_score
		save_best()
	# the boy flies: reparent his model onto a tumbling physics body
	var vel := cart.linear_velocity
	boy_body = RigidBody3D.new()
	boy_body.mass = 3.0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.5
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	boy_body.add_child(cs)
	add_child(boy_body)
	boy_body.global_transform = boy_visual.global_transform
	boy_visual.reparent(boy_body, true)
	boy_body.add_collision_exception_with(cart)
	boy_body.linear_velocity = fwd * maxf(prev_fwd_speed, 10.0) * 0.85 + up_n * 6.5 + Vector3(vel.x, 0, 0)
	boy_body.angular_velocity = Vector3(randf_range(6, 10), randf_range(-3, 3), randf_range(-4, 4))
	if boy_anim:
		boy_anim.play(_anim_named(boy_anim, "Jump_Start"), 0.1, 1.2)

	for it in items:
		it.apply_central_impulse((up_n * randf_range(0.8, 1.8) + fwd * randf_range(0.0, 0.8) + Vector3(randf_range(-0.8, 0.8), 0, 0)) * 0.7)
	cart.apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 6.0)
	cart.apply_central_impulse(up_n * 25.0)
	crash_fx.global_position = cart.global_position + up_n * 1.0 + fwd * 1.0
	crash_fx.restart()

	msg.text = "CRASH!\n\nScore: %d\n%s\nBest: %d\n\ntap to restart" % [
		final_score, ("NEW BEST!" if new_best else ""), best]

func _anim_named(ap: AnimationPlayer, part: String) -> String:
	for a in ap.get_animation_list():
		if part in a:
			return a
	return ap.current_animation

func update_curve() -> void:
	RenderingServer.global_shader_parameter_set("curve_origin", cam.global_position)

func _process(delta: float) -> void:
	frame += 1
	if state == State.LOADING:
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	if state == State.CRASHED:
		var el := crash_elapsed()
		Engine.time_scale = lerpf(0.2, 1.0, clampf((el - 0.25) / 0.9, 0.0, 1.0))
		shake = maxf(shake - real_dt * 0.8, 0.0)
	var focus := cart.global_position
	if state == State.CRASHED and is_instance_valid(boy_body):
		focus = focus.lerp(boy_body.global_position, 0.5)
	var spd := maxf(cart.linear_velocity.dot(fwd), 0.0)
	var target_pos := focus - fwd * 6.8 + Vector3(0, 3.6, 0)
	cam.global_position = cam.global_position.lerp(target_pos, clamp(real_dt * 6.0, 0.0, 1.0))
	cam.look_at(focus + fwd * 7.0 + Vector3(0, 0.4, 0), Vector3.UP)
	cam.fov = lerpf(cam.fov, lerpf(66.0, 78.0, clampf(spd / 30.0, 0.0, 1.0)), clampf(real_dt * 3.0, 0.0, 1.0))
	if shake > 0.0:
		cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.5
	update_curve()

	if state == State.RUNNING and boy_anim:
		boy_anim.speed_scale = clampf(spd / 14.0, 0.8, 1.9)

	var t := Time.get_ticks_msec() / 1000.0
	for p in pickups:
		if is_instance_valid(p):
			p.rotate_y(delta * 2.5)
			p.position.y = float(p.get_meta("base_y")) + sin(t * 4.0 + p.position.z) * 0.12

	var dist := int(maxf(cart_s() - 6.0, 0.0))
	if state == State.RUNNING or state == State.CRASHED:
		var shown := final_score if state == State.CRASHED else cart_load
		hud.text = "CART  %d\nBEST  %d\n%d m" % [shown, best, dist]
	else:
		hud.text = "BEST  %d" % best
	debug_lbl.text = "fps %d · %d km/h · items %d" % [Engine.get_frames_per_second(), int(spd * 3.6), items.size()]

	if autotest:
		if frame % 100 == 0:
			print("f=", frame, " state=", state, " load=", cart_load, " collected=", collected, " spilled=", spilled, " dist=", dist,
				" speed=", int(spd * 3.6), " reason=", crash_reason)
		if frame in [60, 150, 300]:
			get_viewport().get_texture().get_image().save_png("user://shot_%d.png" % frame)
		if state == State.CRASHED and crash_elapsed() > 0.5 and not has_meta("crash_shot"):
			set_meta("crash_shot", true)
			get_viewport().get_texture().get_image().save_png("user://shot_crash.png")
			print("CRASH at dist=", dist, " score=", final_score, " collected=", collected, " reason=", crash_reason)
		if frame >= 700 or (state == State.CRASHED and crash_elapsed() > 2.5):
			print("DONE")
			get_tree().quit()
