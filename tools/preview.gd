extends Node3D
# Asset preview: lays every model in a grid, prints size + animations, saves a screenshot.
var paths := [
	"res://assets/char/boy.glb", "res://assets/char/cow.glb",
	"res://assets/food/Apple.glb", "res://assets/food/Banana.glb", "res://assets/food/Carrot.glb",
	"res://assets/food/Orange.glb", "res://assets/food/Tomato.glb", "res://assets/food/SodaCan.glb",
	"res://assets/food/Donut.glb", "res://assets/food/Milkshake.glb",
	"res://assets/props/TrafficCone.glb", "res://assets/props/Taxi.glb", "res://assets/props/BasicCar.glb",
	"res://assets/props/Bicycle.glb", "res://assets/props/Streetlight.glb"]
var frame := 0
func aabb_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := mi.global_transform * mi.get_aabb()
		if first:
			box = b; first = false
		else:
			box = box.merge(b)
	return box
func _ready():
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.6, 0.8, 1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.6
	env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); add_child(sun)
	var i := 0
	for p in paths:
		var res = load(p)
		if res == null:
			print("FAIL ", p); continue
		var inst: Node3D = res.instantiate()
		add_child(inst)
		var b := aabb_of(inst)
		var s := 2.0 / maxf(b.size.x, maxf(b.size.y, b.size.z))
		inst.scale = Vector3.ONE * s
		inst.position = Vector3((i % 5) * 3.0 - 6.0, 0, -(i / 5) * 3.5)
		var anims := []
		for ap in inst.find_children("*", "AnimationPlayer", true, false):
			anims = (ap as AnimationPlayer).get_animation_list()
			if anims.size() > 0:
				var pick = anims[0]
				for a in anims:
					if "Run" in a: pick = a
				(ap as AnimationPlayer).play(pick)
		print("OK ", p.get_file(), " size=", b.size, " anims=", anims)
		i += 1
	var cam := Camera3D.new(); add_child(cam)
	cam.position = Vector3(0, 4.5, 5.5); cam.look_at(Vector3(0, 0, -3.5))
func _process(_d):
	frame += 1
	if frame == 30:
		get_viewport().get_texture().get_image().save_png("user://preview.png"); get_tree().quit()
