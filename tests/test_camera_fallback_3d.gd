extends SceneTree
## Synthetic controlled constraint failures in the actual city geometry.
## No player profile, native/device proof or production test hook is involved.
const World = preload("res://game/city_world_3d.gd")
const ROADSIDE_POSE := Vector2(1620.05139160156,619.209289550781)
const ROADSIDE_HEADING := -2.16611205729617
var checks := 0
var failures := 0
var stepper: PhysicsStep

class FailureWorld extends World:
	var fail_calls: Array[int] = []
	var calls := 0
	var validated_desired := Vector3.INF
	func _constrain_camera(focus: Vector3, candidate: Vector3, target: Vector3) -> Vector3:
		calls += 1
		if calls in fail_calls: return Vector3.INF
		var result := super._constrain_camera(focus,candidate,target)
		if calls == 1 and result.is_finite(): validated_desired = result
		return result

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

func eye_is_embedded(world: Node3D) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = world.camera3d.get_camera_transform().origin
	query.collision_mask = 4
	query.exclude = [world.player.get_rid()]
	return not world.get_world_3d().direct_space_state.intersect_point(query,1).is_empty()

func verify_view(world: Node3D, label: String) -> void:
	var eye: Vector3 = world.camera3d.get_camera_transform().origin
	var focus: Vector3 = world.player.global_position+Vector3(0,1.5,0)
	check(not eye_is_embedded(world),label+": actual eye cannot reuse the embedded prior view")
	var line := PhysicsRayQueryParameters3D.create(focus,eye,4,[world.player.get_rid()])
	check(world.get_world_3d().direct_space_state.intersect_ray(line).is_empty(),label+": focus-to-eye segment stays clear")
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,eye)
	query.collision_mask = 4
	query.exclude = [world.player.get_rid()]
	check(world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),label+": actual eye retains near-plane clearance")
	var taxi: Vector3 = world.player.global_position+Vector3(0,0.7,0)
	check(world.camera3d.is_position_in_frustum(taxi),label+": taxi remains visible")

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(540,788)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := FailureWorld.new()
	viewport.add_child(world)
	world.set_physics_process(false)
	world.enabled = false
	world.set_controls(-0.4,0.6,true)
	stepper = PhysicsStep.new()
	root.add_child(stepper)
	stepper.set_physics_process(false)
	await physics_frame
	await physics_frame
	world.set_pose(ROADSIDE_POSE,ROADSIDE_HEADING)
	world.calls = 0
	world.fail_calls = [2]
	await step(func():
		check(eye_is_embedded(world),"controlled final-correction case starts with the legacy embedded snap")
		var pose: Transform3D = world.player.transform
		world._physics_process(1.0/60.0)
		check(world.calls == 2,"synthetic failure is restricted to the final smoothed correction")
		check(world.camera3d.global_position.distance_to(world.validated_desired)<0.001,"failed final correction uses this frame's validated desired position")
		verify_view(world,"failed final correction")
		check(world.player.transform == pose and is_equal_approx(world.steering,-0.4) and is_equal_approx(world.throttle,0.6) and world.brake,"fallback does not change vehicle pose or controls")
	)
	world.set_pose(ROADSIDE_POSE,ROADSIDE_HEADING)
	world.calls = 0
	world.fail_calls = [1]
	await step(func():
		var pose: Transform3D = world.player.transform
		world._physics_process(1.0/60.0)
		check(world.calls >= 2,"failed desired correction invokes a separately validated close view")
		verify_view(world,"failed desired correction")
		check(world.player.transform == pose,"close-view fallback cannot move the vehicle")
	)
	world.fail_calls.clear()
	await step(func():
		var building: Node = world.find_children("BuildingCollision_*","StaticBody3D",true,false)[0]
		var shape: CollisionShape3D = building.get_child(0)
		var blocked_focus := shape.global_position
		check(not world._constrain_camera(blocked_focus,world.camera3d.global_position,blocked_focus+Vector3.FORWARD*12).is_finite(),"initial probe overlap reports failure instead of trusting a clear sweep fraction")
	)
	viewport.queue_free()
	stepper.queue_free()
	await process_frame
	await process_frame
	print("TAXI_CAMERA_FALLBACK checks=%d failures=%d (synthetic controlled failures, actual world)" % [checks,failures])
	quit(1 if failures else 0)
