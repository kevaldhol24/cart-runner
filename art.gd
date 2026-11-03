class_name Art
extends RefCounted
# Visual toolkit: curved-world toon shader, merged-mesh builder, model loading,
# procedural props (auto-rickshaw, fruit cart, shopping cart) and the shop-sign atlas.

const SHADER_CODE := """
shader_type spatial;
render_mode world_vertex_coords, cull_back, specular_disabled;

global uniform vec3 curve_origin;
global uniform float curve_amount;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform float rim_strength = 0.18;

void vertex() {
	// Subway-style curved world: bend everything down with distance from the camera
	float dz = curve_origin.z - VERTEX.z;
	VERTEX.y -= dz * dz * curve_amount;
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_tex) { c *= texture(tex, UV).rgb; }
	if (use_vcol) { c *= COLOR.rgb; }
	ALBEDO = c;
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * rim * rim_strength;
}

void light() {
	// soft two-tone toon shading
	float ndl = dot(NORMAL, LIGHT);
	float t = smoothstep(-0.1, 0.35, ndl);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * mix(0.25, 1.0, t) / PI;
}
"""

static var shader: Shader
static var color_mats := {}
static var std_mats := {}
static var env_mat: ShaderMaterial
static var sign_mat: ShaderMaterial
static var models := {}      # path -> {scene, scale, offset}
static var auto_mesh: ArrayMesh
static var thela_mesh: ArrayMesh
static var cart_mesh: ArrayMesh
static var sign_count := 0

const SIGN_NAMES := [
	"SHARMA KIRANA", "GUPTA SWEETS", "PATEL MOBILE", "JAI AMBE STORES",
	"CHAI POINT", "SAI MEDICAL", "NEW FASHION", "KRISHNA DAIRY",
	"OM SAI GENERAL", "BALAJI FRUITS", "RAJ ELECTRONICS", "MAA DURGA PAN",
	"GANESH HARDWARE", "LUCKY TAILORS", "SHIV BAKERY", "STAR CYBER CAFE"]
const SIGN_COLS := 4
const SIGN_ROWS := 4

static func init() -> void:
	shader = Shader.new()
	shader.code = SHADER_CODE
	env_mat = ShaderMaterial.new()
	env_mat.shader = shader
	env_mat.set_shader_parameter("use_vcol", true)

static func color_mat(c: Color) -> ShaderMaterial:
	if color_mats.has(c):
		return color_mats[c]
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("albedo", c)
	color_mats[c] = m
	return m

static func from_standard(src: Material, tint = null) -> ShaderMaterial:
	var key := [src, tint]
	if std_mats.has(key):
		return std_mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		m.set_shader_parameter("albedo", tint if tint != null else b.albedo_color)
		if b.albedo_texture and tint == null:
			m.set_shader_parameter("tex", b.albedo_texture)
			m.set_shader_parameter("use_tex", true)
	elif tint != null:
		m.set_shader_parameter("albedo", tint)
	std_mats[key] = m
	return m

# Swap every material under `n` for the curved toon shader.
# `recolor` maps original material names (e.g. "Shirt") to new colors.
static func curve_node(n: Node, recolor := {}) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var nm := src.resource_name if src else ""
			var tint = recolor.get(nm, null)
			m.set_surface_override_material(i, from_standard(src, tint))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

static func _aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var node: Node = m
		while node != root and node is Node3D:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

# Load a model, normalised so its `axis` extent equals `size`, centred, sitting on y=0.
static func model(path: String, size: float, axis := 1, recolor := {}) -> Node3D:
	if not models.has(path):
		var scene: PackedScene = load(path)
		var probe: Node3D = scene.instantiate()
		var b := _aabb(probe)
		probe.free()
		var s := size / maxf(b.size[axis], 0.001)
		var c := b.get_center()
		models[path] = {"scene": scene, "scale": s, "offset": Vector3(-c.x * s, -b.position.y * s, -c.z * s)}
	var info: Dictionary = models[path]
	var wrap := Node3D.new()
	var inst: Node3D = info["scene"].instantiate()
	inst.scale = Vector3.ONE * info["scale"]
	inst.position = info["offset"]
	wrap.add_child(inst)
	curve_node(inst, recolor)
	return wrap

static func play_anim(n: Node, name_part: String, speed := 1.0) -> AnimationPlayer:
	for ap_node in n.find_children("*", "AnimationPlayer", true, false):
		var ap := ap_node as AnimationPlayer
		for a in ap.get_animation_list():
			if name_part in a:
				ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				ap.play(a, -1, speed)
				return ap
	return null

# ---------- merged mesh builder ----------

class MB:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func _tri(a: Vector3, b: Vector3, d: Vector3, nn: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2.ZERO, ud := Vector2.ZERO) -> void:
		v.append(a); v.append(b); v.append(d)
		n.append(nn); n.append(nn); n.append(nn)
		c.append(col); c.append(col); c.append(col)
		uv.append(ua); uv.append(ub); uv.append(ud)

	# axis-aligned (in xf space) box
	func box(xf: Transform3D, size: Vector3, col: Color) -> void:
		var h := size * 0.5
		var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
		for nd in dirs:
			var nrm: Vector3 = nd
			var up := Vector3.UP if absf(nrm.y) < 0.5 else Vector3.BACK
			var u := up.cross(nrm)
			var vv := up
			var center := nrm * h
			var hu := (u * h).abs().length()
			var hv := (vv * h).abs().length()
			var p0 := xf * (center - u * hu - vv * hv)
			var p1 := xf * (center + u * hu - vv * hv)
			var p2 := xf * (center + u * hu + vv * hv)
			var p3 := xf * (center - u * hu + vv * hv)
			var wn := (xf.basis * nrm).normalized()
			_tri(p0, p3, p2, wn, col)
			_tri(p0, p2, p1, wn, col)

	func bx(pos: Vector3, size: Vector3, col: Color, rot := Vector3.ZERO) -> void:
		box(Transform3D(Basis.from_euler(rot), pos), size, col)

	# append a primitive mesh (sphere, cylinder...) transformed
	func prim(pm: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arr := pm.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx.size():
			var k := idx[i]
			v.append(xf * verts[k])
			n.append((xf.basis * norms[k]).normalized())
			c.append(col)
			uv.append(Vector2.ZERO)

	# flat triangle visible from both sides (flags)
	func flag(a: Vector3, b: Vector3, d: Vector3, col: Color) -> void:
		var nn := (b - a).cross(d - a).normalized()
		_tri(a, b, d, nn, col)
		_tri(a, d, b, -nn, col)

	# textured quad facing `normal` (for signs)
	func quad(center: Vector3, normal: Vector3, w: float, h: float, uv_rect: Rect2) -> void:
		var up := Vector3.UP
		var u := up.cross(normal).normalized()
		var p0 := center - u * w * 0.5 - up * h * 0.5
		var p1 := center + u * w * 0.5 - up * h * 0.5
		var p2 := center + u * w * 0.5 + up * h * 0.5
		var p3 := center - u * w * 0.5 + up * h * 0.5
		var a := uv_rect.position
		var e := uv_rect.end
		var col := Color.WHITE
		_tri(p0, p3, p2, normal, col, Vector2(a.x, e.y), Vector2(a.x, a.y), Vector2(e.x, a.y))
		_tri(p0, p2, p1, normal, col, Vector2(a.x, e.y), Vector2(e.x, a.y), Vector2(e.x, e.y))

	func empty() -> bool:
		return v.is_empty()

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

static func mesh_node(m: ArrayMesh, material: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func cyl(r: float, h: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func sph(r: float, seg := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 3)
	return s

# ---------- procedural props ----------

# Auto-rickshaw, ~2.6m long, facing -Z, sitting on y=0
static func get_auto() -> ArrayMesh:
	if auto_mesh:
		return auto_mesh
	var mb := MB.new()
	var yellow := Color(1.0, 0.82, 0.12)
	var green := Color(0.1, 0.55, 0.25)
	var black := Color(0.1, 0.1, 0.12)
	var grey := Color(0.55, 0.57, 0.6)
	# lower body (green) and yellow canopy, Delhi style
	mb.bx(Vector3(0, 0.55, 0.25), Vector3(1.35, 0.55, 1.7), green)
	mb.bx(Vector3(0, 0.95, 0.35), Vector3(1.35, 0.3, 1.5), green)
	mb.bx(Vector3(0, 0.6, -0.85), Vector3(0.7, 0.6, 0.6), green)      # nose
	mb.bx(Vector3(0, 1.75, 0.1), Vector3(1.45, 0.12, 2.1), yellow)    # roof
	mb.bx(Vector3(0, 1.6, 0.1), Vector3(1.4, 0.25, 2.0), yellow)
	for sx in [-1, 1]:
		mb.bx(Vector3(sx * 0.66, 1.35, -0.5), Vector3(0.06, 0.8, 0.06), black)  # front pillars
		mb.bx(Vector3(sx * 0.66, 1.3, 1.05), Vector3(0.08, 0.9, 0.12), yellow)   # back pillars
	mb.bx(Vector3(0, 1.3, -0.55), Vector3(1.2, 0.55, 0.04), Color(0.55, 0.8, 0.95))  # windshield
	mb.bx(Vector3(0, 1.3, 1.1), Vector3(1.35, 0.7, 0.08), yellow)       # rear panel
	mb.bx(Vector3(0, 0.95, 1.2), Vector3(1.0, 0.15, 0.05), black)       # number plate band
	mb.bx(Vector3(0, 1.05, -0.4), Vector3(0.5, 0.06, 0.06), grey)       # handlebar
	var wheel := cyl(0.24, 0.16, 14)
	var rot := Basis(Vector3(0, 0, 1), PI * 0.5)
	mb.prim(wheel, Transform3D(rot, Vector3(0, 0.24, -1.0)), black)
	mb.prim(wheel, Transform3D(rot, Vector3(-0.62, 0.24, 0.6)), black)
	mb.prim(wheel, Transform3D(rot, Vector3(0.62, 0.24, 0.6)), black)
	mb.bx(Vector3(0, 0.9, -1.13), Vector3(0.22, 0.14, 0.05), Color(1, 1, 0.8))  # headlight
	auto_mesh = mb.commit()
	return auto_mesh

# Fruit cart (thela), ~2m long, facing -Z
static func get_thela() -> ArrayMesh:
	if thela_mesh:
		return thela_mesh
	var mb := MB.new()
	var wood := Color(0.62, 0.4, 0.2)
	var dark := Color(0.35, 0.22, 0.12)
	mb.bx(Vector3(0, 0.85, 0), Vector3(1.2, 0.12, 2.0), wood)
	for sx in [-1, 1]:
		mb.bx(Vector3(sx * 0.6, 0.95, 0), Vector3(0.06, 0.2, 2.0), dark)
		mb.bx(Vector3(sx * 0.45, 0.5, 1.2), Vector3(0.05, 0.05, 0.8), dark)  # handles
	var wheel := cyl(0.45, 0.08, 14)
	var rot := Basis(Vector3(0, 0, 1), PI * 0.5)
	for sx in [-1, 1]:
		mb.prim(wheel, Transform3D(rot, Vector3(sx * 0.66, 0.45, 0)), dark)
	# pile of fruit
	var cols := [Color(0.95, 0.2, 0.15), Color(1.0, 0.6, 0.1), Color(0.95, 0.85, 0.2), Color(0.4, 0.75, 0.2), Color(0.85, 0.1, 0.3)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 46:
		var p := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.9, 0.9))
		p.y = 1.05 + (0.5 - absf(p.x)) * 0.35 + (0.9 - absf(p.z)) * 0.12 + rng.randf() * 0.05
		mb.prim(sph(0.11, 6), Transform3D(Basis(), p), cols[i % cols.size()])
	# umbrella
	mb.bx(Vector3(0.5, 1.6, 0.8), Vector3(0.04, 1.6, 0.04), dark)
	var umb := CylinderMesh.new()
	umb.top_radius = 0.05
	umb.bottom_radius = 0.9
	umb.height = 0.35
	umb.radial_segments = 10
	mb.prim(umb, Transform3D(Basis(), Vector3(0.5, 2.45, 0.8)), Color(0.95, 0.35, 0.55))
	thela_mesh = mb.commit()
	return thela_mesh

# Chunky shopping cart: wire basket on y 0.5..1.2, facing -Z (front at z=-0.95)
static func get_cart() -> ArrayMesh:
	if cart_mesh:
		return cart_mesh
	var mb := MB.new()
	var red := Color(0.92, 0.16, 0.14)
	var metal := Color(0.82, 0.84, 0.88)
	var black := Color(0.12, 0.12, 0.14)
	var yellow := Color(1.0, 0.8, 0.15)
	var t := 0.05
	var y0 := 0.5
	var y1 := 1.2
	var hx := 0.65
	var hz := 0.95
	# floor tray
	mb.bx(Vector3(0, y0, 0), Vector3(1.3, 0.06, 1.9), metal)
	# rims
	for yy in [y0 + 0.03, (y0 + y1) * 0.5, y1]:
		var th := 0.07 if yy == y1 else t
		mb.bx(Vector3(0, yy, -hz), Vector3(1.3, th, th), red)
		mb.bx(Vector3(0, yy, hz), Vector3(1.3, th, th), red)
		mb.bx(Vector3(-hx, yy, 0), Vector3(th, th, 1.9), red)
		mb.bx(Vector3(hx, yy, 0), Vector3(th, th, 1.9), red)
	# vertical wires
	var steps := 7
	for i in steps + 1:
		var x := -hx + 2.0 * hx * i / steps
		mb.bx(Vector3(x, (y0 + y1) * 0.5, -hz), Vector3(t * 0.7, y1 - y0, t * 0.7), metal)
		mb.bx(Vector3(x, (y0 + y1) * 0.5, hz), Vector3(t * 0.7, y1 - y0, t * 0.7), metal)
	for i in 10:
		var z := -hz + 2.0 * hz * i / 9
		mb.bx(Vector3(-hx, (y0 + y1) * 0.5, z), Vector3(t * 0.7, y1 - y0, t * 0.7), metal)
		mb.bx(Vector3(hx, (y0 + y1) * 0.5, z), Vector3(t * 0.7, y1 - y0, t * 0.7), metal)
	# chassis legs + bottom rack
	for sx in [-1, 1]:
		mb.bx(Vector3(sx * 0.5, 0.3, 0), Vector3(0.06, 0.06, 1.8), metal)
		for sz in [-1, 1]:
			mb.bx(Vector3(sx * 0.5, 0.37, sz * 0.75), Vector3(0.05, 0.2, 0.05), metal)
	# handle
	for sx in [-1, 1]:
		mb.bx(Vector3(sx * 0.6, 1.25, 1.05), Vector3(0.05, 0.12, 0.25), red)
	mb.bx(Vector3(0, 1.3, 1.18), Vector3(1.3, 0.09, 0.09), yellow)
	# caster wheels
	var wheel := cyl(0.13, 0.1, 12)
	var hub := cyl(0.06, 0.12, 8)
	var rot := Basis(Vector3(0, 0, 1), PI * 0.5)
	for wx in [-0.5, 0.5]:
		for wz in [-0.75, 0.75]:
			mb.prim(wheel, Transform3D(rot, Vector3(wx, 0.13, wz)), black)
			mb.prim(hub, Transform3D(rot, Vector3(wx, 0.13, wz)), metal)
	cart_mesh = mb.commit()
	return cart_mesh

# ---------- sign atlas ----------

static func build_sign_atlas(parent: Node) -> void:
	var cell := Vector2i(512, 128)
	var sv := SubViewport.new()
	sv.size = Vector2i(cell.x * SIGN_COLS, cell.y * SIGN_ROWS)
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.transparent_bg = false
	parent.add_child(sv)
	var bgs := [Color(0.85, 0.1, 0.1), Color(0.1, 0.35, 0.8), Color(0.05, 0.55, 0.3), Color(1.0, 0.8, 0.1),
		Color(0.55, 0.15, 0.6), Color(1.0, 0.45, 0.1), Color(0.95, 0.95, 0.92), Color(0.1, 0.1, 0.15)]
	for i in SIGN_NAMES.size():
		var r := ColorRect.new()
		r.position = Vector2((i % SIGN_COLS) * cell.x, (i / SIGN_COLS) * cell.y)
		r.size = Vector2(cell)
		var bg: Color = bgs[i % bgs.size()]
		r.color = bg
		sv.add_child(r)
		var border := ReferenceRect.new()
		border.position = r.position + Vector2(8, 8)
		border.size = Vector2(cell) - Vector2(16, 16)
		border.border_color = Color(1, 1, 1, 0.8) if bg.get_luminance() < 0.6 else Color(0.2, 0.1, 0.05, 0.8)
		border.border_width = 4
		border.editor_only = false
		sv.add_child(border)
		var l := Label.new()
		l.text = SIGN_NAMES[i]
		l.position = r.position
		l.size = Vector2(cell)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 50)
		var dark_text := bg.get_luminance() > 0.6
		l.add_theme_color_override("font_color", Color(0.15, 0.05, 0.05) if dark_text else Color(1, 1, 0.95))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5) if not dark_text else Color(1, 1, 1, 0.4))
		l.add_theme_constant_override("outline_size", 6)
		sv.add_child(l)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	sv.queue_free()
	sign_mat = ShaderMaterial.new()
	sign_mat.shader = shader
	sign_mat.set_shader_parameter("use_tex", true)
	sign_mat.set_shader_parameter("tex", tex)
	sign_mat.set_shader_parameter("rim_strength", 0.0)
	sign_count = SIGN_NAMES.size()

static func sign_uv(i: int) -> Rect2:
	var w := 1.0 / SIGN_COLS
	var h := 1.0 / SIGN_ROWS
	return Rect2((i % SIGN_COLS) * w, (i / SIGN_COLS) * h, w, h)
