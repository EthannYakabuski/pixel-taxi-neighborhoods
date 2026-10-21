extends SceneTree
## Synthetic integrated source test. This is never native/player-save evidence.
const Model = preload("res://game/model.gd")
const Graph = preload("res://game/city_graph.gd")
var checks := 0
var failures := 0
var hit_count := 0
class CoveredService extends Node:
	var covering := false
	func is_gameplay_blocked() -> bool: return covering
	func set_menu_visible(_visible: bool) -> void: pass
	func unlock(_key: String) -> void: pass
	func submit(_key: String,_value: int) -> void: pass
	func round_finished() -> void: pass
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.demo = true
	root.add_child(game)
	game._show("drive")
	var world = game.city.world
	check(world.player is CharacterBody3D,"actual player is a physical 3D car")
	check(world.player.get_node("KenneyCar").find_children("*","MeshInstance3D",true,false).size()>0,"actual supplied car meshes are present")
	check(world.camera3d is Camera3D and world.camera3d.current,"following perspective camera is current")
	check(world.find_children("KenneyBatch_*","MultiMeshInstance3D",true,false).size()>12,"actual city meshes use mobile hardware instancing")
	check(world.find_children("BuildingCollision_*","StaticBody3D",true,false).size()>70,"sprawling actual building footprints collide physically")
	var job: Dictionary = game.model.current_offer()
	check(game.model.accept_job(job),"single dispatch offer can be accepted")
	game._route_to(game.model.objective())
	var before: Vector2 = world.graph_position()
	await create_timer(0.3).timeout
	check(world.graph_position().distance_to(before)<0.05,"GPS guidance never drives the car")
	check(not game.automatic,"no automatic movement mode remains")
	var press := InputEventScreenTouch.new()
	press.position = Vector2(100,40)
	press.pressed = true
	game._steering_pad_event(press)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(140,40)
	game._steering_pad_event(drag)
	var before_distance: float = game.model.distance
	await create_timer(0.6).timeout
	check(world.graph_position().distance_to(before)>1.0,"one-thumb hold drives actual CharacterBody3D")
	check(world.yaw < -0.01,"rightward thumb drag steers right in the actual following camera")
	check(game.model.distance>before_distance,"only actual physical movement advances distance")
	press.pressed=false
	game._steering_pad_event(press)
	game.brake_held=true
	await create_timer(0.4).timeout
	check(absf(world.current_speed)<0.1,"brake brings car to a stop")
	game.brake_held=false
	# A real Physics3D obstacle exercises collision response; no model-only shortcut.
	world.set_pose(Graph.point(24),0)
	var wall := StaticBody3D.new()
	wall.collision_layer=4
	wall.collision_mask=1
	world.add_child(wall)
	wall.position=world.player.position+Vector3(0,0,2.1)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(10,3,1)
	hit.position.y=1.5
	hit.shape=shape
	wall.add_child(hit)
	world.hit_grace=0
	world.impact.connect(func(_speed: float): hit_count+=1)
	var bank: int = game.model.coins
	var collisions: int = game.model.active_job.collisions
	game.gas_held=true
	await create_timer(0.7).timeout
	check(hit_count==1,"physical collision has one impact during hit grace")
	check(game.model.active_job.collisions==collisions+1,"actual impact affects current fare quality")
	check(game.model.coins==bank,"collision preserves banked progression")
	game._set_parked()
	wall.queue_free()
	await physics_frame
	world.set_pose(Graph.point(int(job.pickup)),0)
	world.current_speed=0
	game._curb_action()
	check(bool(game.model.active_job.picked_up),"stopped actual curb allows pickup")
	var service: Node = root.get_node_or_null("Services")
	var owns_service := service==null
	if owns_service:
		service = CoveredService.new()
		service.name="Services"
		root.add_child(service)
	_set_covered(service,true)
	game._process(20)
	before=world.graph_position()
	var elapsed: float = game.model.active_job.elapsed
	await create_timer(0.25).timeout
	check(world.graph_position().distance_to(before)<0.01,"fullscreen coverage freezes actual physics")
	check(game.model.active_job.elapsed==elapsed,"fullscreen coverage does not consume fare time")
	_set_covered(service,false)
	game._process(20)
	check(game.resume_required and not world.enabled,"ad return requires explicit Resume")
	game._resume_driving()
	game._process(20)
	check(world.graph_position().distance_to(before)<0.01,"covered return delta never moves vehicle")
	# Wrong-turn guidance uses actual road projection and cannot modify pose/input.
	world.set_pose(Graph.point(6),1.2)
	game._remember_pose()
	game.nav_timer=0
	game._process(0.01)
	var expected: Dictionary=Graph.guidance(world.graph_position(),game.model.objective())
	check(game.travel_path==expected.route,"GPS recalculates weighted route after wrong turn")
	check(is_equal_approx(world.yaw,1.2) and not game.gas_held,"recalculation cannot steer or accelerate")
	game._set_parked()
	# Isolated local file round trip, with the existing public save filename.
	game.demo=false
	game._save()
	var saved_pose: Vector2=world.graph_position()
	var saved_balance: int=game.model.coins
	var saved_job: Dictionary=game.model.active_job.duplicate(true)
	game._stop_audio()
	game.queue_free()
	await process_frame
	await process_frame
	var restored=load("res://main.tscn").instantiate()
	root.add_child(restored)
	check(restored.model.coins==saved_balance,"scene cold load preserves banked coins")
	check(restored.vehicle_position.distance_to(saved_pose)<0.01,"scene cold load restores actual driving pose")
	var fare_retained: bool = restored.model.active_job.size()==saved_job.size()
	for key in saved_job:
		var actual: Variant = restored.model.active_job.get(key)
		var expected_value: Variant = saved_job[key]
		if expected_value is float:
			fare_retained = fare_retained and (actual is float or actual is int) and is_equal_approx(float(actual),float(expected_value))
		else: fare_retained = fare_retained and actual==expected_value
	check(fare_retained,"scene cold load retains picked-up fare quality/time/entitlement")
	restored.demo=true
	restored._stop_audio()
	restored.queue_free()
	if owns_service: service.queue_free()
	await process_frame
	await process_frame
	print("TAXI_3D_INTEGRATION checks=%d failures=%d (synthetic source, actual engine physics/input)" % [checks,failures])
	quit(1 if failures else 0)

func _set_covered(service: Node, value: bool) -> void:
	if service is CoveredService: service.covering=value
	else: service.set("_interstitial_showing",value)
