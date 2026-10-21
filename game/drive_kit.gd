extends Node3D
## Shared scene-building helpers. Cars, streets, buildings and vegetation are
## actual supplied Kenney GLBs; original geometry is limited to terrain/details.
const MODEL_ROOT := "res://assets/3d/"
var _scenes: Dictionary = {}

func model(group: String, key: String, owner: Node3D, at: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE, yaw: float = 0.0) -> Node3D:
	var path := MODEL_ROOT + group + "/" + key + ".glb"
	if not _scenes.has(path): _scenes[path] = load(path)
	var result: Node3D = (_scenes[path] as PackedScene).instantiate()
	result.name = key
	owner.add_child(result)
	result.position = at
	result.scale = size
	result.rotation.y = yaw
	return result

func material(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func box(owner: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	mesh.material_override = material(color)
	owner.add_child(mesh)
	mesh.position = at
	return mesh

func cylinder(owner: Node3D, at: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var geometry := CylinderMesh.new()
	geometry.top_radius = radius
	geometry.bottom_radius = radius
	geometry.height = height
	geometry.radial_segments = 10
	mesh.mesh = geometry
	mesh.material_override = material(color)
	owner.add_child(mesh)
	mesh.position = at
	return mesh

func label(owner: Node3D, text: String, at: Vector3, color: Color = Color.WHITE, font_size: int = 42) -> Label3D:
	var result := Label3D.new()
	result.text = text
	result.position = at
	result.modulate = color
	result.font_size = font_size
	result.outline_size = 6
	result.pixel_size = 0.012
	result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	result.no_depth_test = false
	owner.add_child(result)
	return result

func sky_and_sun() -> WorldEnvironment:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("579bb9")
	sky_material.sky_horizon_color = Color("b4ced7")
	sky_material.ground_horizon_color = Color("b4ced7")
	sky_material.ground_bottom_color = Color("63805e")
	sky_material.sun_angle_max = 22.0
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d9ebee")
	environment.ambient_light_energy = 0.20
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("a5c3ce")
	environment.fog_density = 0.0025
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	sun.light_color = Color("fff0c8")
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 75.0
	add_child(sun)
	return world

func car(kind: String, owner: Node3D, traffic_id: int = -1, is_player: bool = false) -> CollisionObject3D:
	var body: CollisionObject3D = CharacterBody3D.new() if is_player else StaticBody3D.new()
	body.name = "PlayerCar" if is_player else "Traffic_%d" % traffic_id
	body.collision_layer = 1 if is_player else 2
	body.collision_mask = 2 if is_player else 0
	body.set_meta("traffic_id", traffic_id)
	owner.add_child(body)
	var visuals := model("cars", kind, body)
	visuals.name = "KenneyCar"
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var geometry := BoxShape3D.new()
	geometry.size = Vector3(1.48, 1.05, 2.55)
	shape.shape = geometry
	shape.position.y = 0.7
	body.add_child(shape)
	return body

func spin_wheels(body: Node3D, distance: float, steering: float = 0.0) -> void:
	for wheel in body.find_children("wheel-*", "MeshInstance3D", true, false):
		wheel.rotation.x -= distance / 0.3
		if "front" in wheel.name: wheel.rotation.y = steering * 0.28

func station(owner: Node3D) -> Node3D:
	var result := Node3D.new()
	result.name = "LittlePineForecourt"
	owner.add_child(result)
	box(result, Vector3(0, -0.045, 0), Vector3(17.0, 0.12, 22.0), Color("b3bca9"))
	model("commercial", "building-a", result, Vector3(3.9, 0, -6.3), Vector3.ONE * 3.4, PI)
	model("commercial", "detail-awning-wide", result, Vector3(3.9, 2.4, -4.55), Vector3.ONE * 3.0, PI)
	model("roads", "road-driveway-double", result, Vector3(-7.8, -0.03, 2.5), Vector3(8.0, 1.0, 8.0))
	# Original coherent fuel hardware: canopy, supports, pump cabinet, display,
	# hose and nozzle. No named pump model exists in the reviewed supplied packs.
	box(result, Vector3(-1.6, 3.9, 1.2), Vector3(9.8, 0.35, 6.0), Color("de7545"))
	box(result, Vector3(-1.6, 3.67, 1.2), Vector3(9.5, 0.12, 5.7), Color("fff0cc"))
	for x: float in [-5.5, 2.2]:
		for z: float in [-0.8, 3.2]:
			cylinder(result, Vector3(x, 1.8, z), 0.10, 3.6, Color("e9e4d3"))
	for z: float in [0.0, 2.4]:
		box(result, Vector3(-1.6, 0.12, z), Vector3(3.2, 0.25, 1.0), Color("e1d4af"))
		for x: float in [-2.6, -0.6]:
			box(result, Vector3(x, 0.85, z), Vector3(0.62, 1.5, 0.5), Color("f0e7ce"))
			box(result, Vector3(x, 1.18, z + 0.26), Vector3(0.45, 0.32, 0.04), Color("214b49"))
			box(result, Vector3(x, 0.65, z + 0.27), Vector3(0.5, 0.48, 0.045), Color("de7545"))
			var hose := cylinder(result, Vector3(x + 0.39, 0.75, z), 0.035, 1.2, Color("283c3b"))
			hose.rotation.z = 0.16
			box(result, Vector3(x + 0.38, 1.3, z + 0.1), Vector3(0.08, 0.26, 0.1), Color("204d45"))
	label(result, "LITTLE PINE\nFUEL + COFFEE", Vector3(-1.4, 4.55, 1.2), Color("fff2d1"), 40)
	model("nature", "tree_oak", result, Vector3(7, 0, 7), Vector3.ONE * 1.2)
	model("nature", "plant_bush", result, Vector3(6.2, 0, -5), Vector3.ONE * 2.0)
	return result
