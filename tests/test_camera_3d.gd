extends SceneTree
## Isolated actual-world geometry regression. Synthetic numeric poses only;
## never native gameplay, SDK, player-save or rendered-image evidence.
const World = preload("res://game/city_world_3d.gd")
const Graph = preload("res://game/city_graph.gd")
const Main = preload("res://game/main.gd")
const ROADSIDE_POSE := Vector2(1620.05139160156,619.209289550781)
const ROADSIDE_HEADING := -2.16611205729617
var checks := 0
var failures := 0
var camera_failures := 0
var stepper: PhysicsStep

class PhysicsStep extends Node:
	signal finished
	var action: Callable
	func _physics_process(_delta: float) -> void:
		set_physics_process(false)
		action.call()
		finished.emit()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void: call_deferred("run")

func step(action: Callable) -> void:
	stepper.action = action
	stepper.set_physics_process(true)
	await stepper.finished

func camera_checks(world: Node3D, label: String) -> void:
	var before_failures := failures
	var space := world.get_world_3d().direct_space_state
	var camera: Camera3D = world.camera3d
	var eye := camera.get_camera_transform().origin
	var focus: Vector3 = world.player.global_position + Vector3(0,1.5,0)
	var point := PhysicsPointQueryParameters3D.new()
	point.collision_mask = 4
	point.exclude = [world.player.get_rid()]
	point.position = eye
	check(space.intersect_point(point,1).is_empty(), label + ": actual camera eye is outside buildings")
	var line := PhysicsRayQueryParameters3D.create(focus,eye,4,[world.player.get_rid()])
	line.hit_from_inside = true
	check(space.intersect_ray(line).is_empty(), label + ": vehicle-to-eye segment is unobstructed")
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 4
	query.exclude = [world.player.get_rid()]
	sphere.radius = 0.3
	query.margin = 0.03
	query.transform = Transform3D(Basis.IDENTITY,focus)
	check(space.intersect_shape(query,1).is_empty(), label + ": vehicle focus starts clear of building geometry")
	sphere.radius = 0.25
	query.margin = 0.0
	query.transform = Transform3D(Basis.IDENTITY,eye)
	check(space.intersect_shape(query,1).is_empty(), label + ": actual eye has near-plane corner clearance")
	for corner in [Vector2.ZERO,Vector2(540,0),Vector2(0,788),Vector2(540,788)]:
		point.position = camera.project_position(corner,camera.near)
		check(space.intersect_point(point,1).is_empty(), label + ": projected near-plane corner is outside buildings")
	var car_focus: Vector3 = world.player.global_position + Vector3(0,0.7,0)
	check(not camera.is_position_behind(car_focus) and camera.is_position_in_frustum(car_focus), label + ": taxi remains in the visible camera frustum")
	camera_failures += failures-before_failures

func check_step(world: Node3D, label: String) -> void:
	var pose: Transform3D = world.player.transform
	var controls := Vector3(world.steering,world.throttle,float(world.brake))
	var heading: float = world.yaw
	world._physics_process(1.0/60.0)
	camera_checks(world,label)
	check(world.player.transform == pose and world.yaw == heading, label + ": camera cannot change vehicle pose")
	check(Vector3(world.steering,world.throttle,float(world.brake)) == controls, label + ": camera cannot change vehicle controls")

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(540,788)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world = World.new()
	viewport.add_child(world)
	world.set_physics_process(false)
	world.enabled = false
	world.set_controls(0.35,0.6,true)
	stepper = PhysicsStep.new()
	root.add_child(stepper)
	stepper.set_physics_process(false)
	await physics_frame
	await physics_frame
	# Start with the legacy snap at a roadside pose that obstructed the chase
	# view. The first physics step must recover even while interpolation runs.
	world.set_pose(ROADSIDE_POSE,ROADSIDE_HEADING)
	await step(func(): check_step(world,"roadside first smoothing frame"))
	for index in range(36):
		# Small consecutive heading changes exercise the real lerp around walls.
		world.yaw = ROADSIDE_HEADING + float(index+1)*0.018
		world.player.rotation.y = world.yaw
		await step(func(): check_step(world,"roadside turn frame %d" % index))
	world.set_pose(Graph.point(24),0.0)
	await step(func():
		world._physics_process(1.0)
		var wanted: Vector3 = world.player.position + Vector3(0,7.2,-11.8)
		check(world.camera3d.position.distance_to(wanted)<0.001,"clear street keeps the original follow distance and height")
		camera_checks(world,"clear street")
		check(is_equal_approx(world.camera3d.fov,58.0) and is_equal_approx(world.camera3d.v_offset,-0.9),"FOV and original camera offset remain unchanged")
	)
	world.overview = true
	await step(func():
		var before: Vector3 = world.camera3d.position
		var pose: Transform3D = world.player.transform
		var expected := before.lerp(world.player.position+Vector3(0,95,0.1),7.0/60.0)
		world._physics_process(1.0/60.0)
		check(world.camera3d.position.distance_to(expected)<0.001,"Map retains its original camera interpolation")
		check(world.player.transform == pose,"Map cannot move the vehicle")
	)
	world.overview = false
	await step(func(): check_step(world,"return from Map"))
	var game = Main.new()
	game.vehicle_position = Graph.point(0)
	game.navigation = Graph.guidance(game.vehicle_position,48)
	game.travel_path = game.navigation.route
	var before_route: Dictionary = game.navigation.duplicate(true)
	game.vehicle_heading = float(game.navigation.bearing)-0.8
	check(game._navigation_cue().begins_with("Align LEFT"),"current-road left alignment is labelled as alignment, not a junction instruction")
	game.vehicle_heading = float(game.navigation.bearing)+0.8
	check(game._navigation_cue().begins_with("Align RIGHT"),"current-road right alignment is labelled as alignment, not a junction instruction")
	game.vehicle_heading = float(game.navigation.bearing)
	check(game._navigation_cue() == "Follow gold line","aligned road guidance follows the visible line")
	check(game.navigation == before_route,"cue presentation cannot change the weighted route")
	# Exercise the real HUD formatter and its actual themed font on the longest
	# diagonal city trip. This fixture never enters Main._ready or loads a save.
	game.page_content = Control.new()
	game.add_child(game.page_content)
	game.info_label = game._label("",Rect2(32,137,476,66),17,Color.WHITE)
	game.action_button = Button.new()
	game.page_content.add_child(game.action_button)
	game.city = Main.City.new()
	game.add_child(game.city)
	game.city.world = world
	game.model.accept_job(game.model.current_offer())
	game.model.active_job.picked_up = true
	game.model.active_job.destination = 48
	for offset in [-0.8,0.0,0.8]:
		game.vehicle_heading = float(game.navigation.bearing)+offset
		game._refresh_drive()
		var font: Font = game.info_label.get_theme_font("font")
		for line: String in game.info_label.text.split("\n"):
			check(font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x<=476.0,"actual alignment/direct-curb HUD text fits its unchanged width")
	game.vehicle_position = Vector2(-1000,-1000)
	game.navigation = Graph.guidance(game.vehicle_position,29)
	game.travel_path = game.navigation.route
	check(game._navigation_cue() == "Return to gold route","meaningfully off-road guidance directs the player back to the route")
	game.free()
	viewport.queue_free()
	stepper.queue_free()
	await process_frame
	await process_frame
	print("TAXI_CAMERA checks=%d failures=%d camera_failures=%d (synthetic actual-world geometry and cue semantics)" % [checks,failures,camera_failures])
	quit(1 if failures else 0)
