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
	await process_frame # Present/lay out actual controls before synthetic GUI input.
	await _check_drive_touch_routing(game)
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
	var pad := _drive_point(game,"pad")
	_touch(0,pad,true)
	_drag(0,pad+_drive_offset(game,Vector2(40,0)))
	var before_distance: float = game.model.distance
	await create_timer(0.6).timeout
	check(world.graph_position().distance_to(before)>1.0,"one-thumb hold drives actual CharacterBody3D")
	check(world.yaw < -0.01,"rightward thumb drag steers right in the actual following camera")
	check(game.model.distance>before_distance,"only actual physical movement advances distance")
	_touch(0,pad+_drive_offset(game,Vector2(40,0)),false)
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
	_touch(90,_drive_point(game,"pad"),true)
	_touch(91,_drive_point(game,"right"),true)
	_touch(92,_drive_point(game,"reverse"),true)
	_touch(93,_drive_point(game,"brake"),true)
	_set_covered(service,true)
	game._process(20)
	check(_controls_clear(game),"ad coverage clears all pointer holds as well as control values")
	before=world.graph_position()
	var elapsed: float = game.model.active_job.elapsed
	await create_timer(0.25).timeout
	check(world.graph_position().distance_to(before)<0.01,"fullscreen coverage freezes actual physics")
	check(game.model.active_job.elapsed==elapsed,"fullscreen coverage does not consume fare time")
	_set_covered(service,false)
	game._process(20)
	check(game.resume_required and not world.enabled,"ad return requires explicit Resume")
	_drag(90,_drive_point(game,"pad")+_drive_offset(game,Vector2(40,40)))
	_touch(94,_drive_point(game,"pad"),true)
	check(_controls_clear(game),"covered-return drags/new touches cannot rearm before Resume")
	_mouse_click(game.action_button)
	_drag(90,_drive_point(game,"pad")+_drive_offset(game,Vector2(50,50)))
	check(_controls_clear(game),"Resume cannot resurrect discarded touch owners")
	for index in range(90,95): _touch(index,_drive_point(game,"pad"),false)
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
	_touch(95,_drive_point(game,"reverse"),true)
	_touch(96,_drive_point(game,"left"),true)
	game._stop_audio()
	root.remove_child(game)
	check(_controls_clear(game),"tree exit clears owned drive inputs synchronously")
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

# Route synthetic contacts through Viewport hit-testing/capture and real gui_input
# signals. These fixtures never call the private drive event handler directly.
func _drive_point(game, action: String) -> Vector2:
	var control: Control = game.page_content.get_node("Drive_"+action)
	return control.get_global_transform_with_canvas()*(control.size*0.5)

func _drive_offset(game, value: Vector2) -> Vector2:
	return game.stage.get_global_transform_with_canvas().basis_xform(value)

func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index=index;event.position=position;event.pressed=pressed;event.canceled=canceled
	root.push_input(event,true)

func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index=index;event.position=position
	root.push_input(event,true)

func _mouse_button(position: Vector2, pressed: bool, device: int = 0) -> void:
	if pressed: _mouse_motion(position,0,device)
	var event := InputEventMouseButton.new()
	event.position=position;event.global_position=position;event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.device=device
	root.push_input(event,true)

func _mouse_motion(position: Vector2, mask: int = MOUSE_BUTTON_MASK_LEFT, device: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position=position;event.global_position=position;event.button_mask=mask;event.device=device
	root.push_input(event,true)

func _mouse_click(control: Control) -> void:
	var at := control.get_global_transform_with_canvas()*(control.size*0.5)
	_mouse_button(at,true)
	_mouse_button(at,false)

func _controls_clear(game) -> bool:
	return game._drive_pointers.is_empty() and not game.gas_held and not game.reverse_held and not game.brake_held and is_zero_approx(game.turn_input)

func _check_drive_touch_routing(game) -> void:
	# Independent arrow/reverse holds must work in either touch order.
	for order in [["reverse","right"],["right","reverse"],["reverse","left"],["left","reverse"]]:
		var a := _drive_point(game,order[0]);var b := _drive_point(game,order[1])
		_touch(10,a,true);_touch(11,b,true)
		check(game.reverse_held and absf(game.turn_input)>0.99,"reverse plus arrow works in touch order "+str(order))
		_mouse_button(a,true,InputEvent.DEVICE_ID_EMULATION)
		_mouse_button(a,false,InputEvent.DEVICE_ID_EMULATION)
		check(game.reverse_held and absf(game.turn_input)>0.99,"duplicate emulated mouse cannot release either real finger")
		_touch(10,a,false)
		check(game.reverse_held if order[1]=="reverse" else absf(game.turn_input)>0.99,"releasing first finger preserves second hold")
		_touch(11,b,false)
		check(_controls_clear(game),"both released contacts leave no drive input")
	# Pedal/arrow and pedal/brake need the same order-independent ownership.
	for other in ["left","brake"]:
		for order in [["pad",other],[other,"pad"]]:
			var a := _drive_point(game,order[0]);var b := _drive_point(game,order[1])
			_touch(20,a,true);_touch(21,b,true)
			check(game.gas_held and (game.brake_held if other=="brake" else game.turn_input<0),"pad plus "+other+" works in both orders")
			_touch(20,a,false)
			check(game.gas_held if order[1]=="pad" else (game.brake_held if other=="brake" else game.turn_input<0),"releasing one pad/control finger leaves the other active")
			_touch(21,b,false)
			check(_controls_clear(game),"pad/control pair fully releases")
	for order in [["pad","reverse"],["reverse","pad"]]:
		var a := _drive_point(game,order[0]);var b := _drive_point(game,order[1])
		_touch(22,a,true);_touch(23,b,true)
		game._process(0)
		check(game.gas_held and game.reverse_held and game.city.world.throttle<0,"manual Reverse overrides independently held gas in either order")
		_touch(22,a,false)
		check(game.gas_held if order[1]=="pad" else game.reverse_held,"pad/manual Reverse first release preserves the other finger")
		_touch(23,b,false)
		check(_controls_clear(game),"pad/manual Reverse pair fully releases")
	var pad := _drive_point(game,"pad")
	_touch(30,pad,true)
	_drag(30,pad+_drive_offset(game,Vector2(36,20)))
	check(game.gas_held and not game.reverse_held and game.turn_input>0,"ordinary horizontal drag/vertical jitter remains forward steering")
	_drag(30,pad+_drive_offset(game,Vector2(36,40)))
	check(game.reverse_held and not game.gas_held and game.turn_input>0,"one deliberate down/right drag reverses and steers together")
	_drag(30,pad+_drive_offset(game,Vector2(36,24)))
	check(game.reverse_held,"reverse hysteresis avoids boundary jitter")
	_touch(31,pad,true);_drag(31,pad+_drive_offset(game,Vector2(-50,-20)));_touch(31,pad,false)
	check(game.reverse_held and game.turn_input>0,"second pad finger cannot replace the first anchor or release its hold")
	_touch(32,_drive_point(game,"reverse"),true)
	_touch(32,_drive_point(game,"reverse"),false)
	check(game.reverse_held and game.turn_input>0,"manual Reverse release preserves independent pad reverse")
	_drag(30,pad+_drive_offset(game,Vector2(36,8)))
	check(game.gas_held and not game.reverse_held,"returning near press height selects forward without losing steering")
	_touch(30,pad,false,true)
	check(_controls_clear(game),"canceled pad contact clears its owned inputs")
	# An outside press cannot acquire a control merely by dragging over it.
	var outside: Vector2 = game.stage.get_global_transform_with_canvas()*Vector2(5,700)
	_touch(40,outside,true);_drag(40,pad);_drag(40,pad+_drive_offset(game,Vector2(40,40)))
	check(_controls_clear(game),"outside press and reentry cannot acquire an unowned pad")
	_touch(40,pad,false)
	_touch(40,pad,true);_drag(40,pad+_drive_offset(game,Vector2(40,80)));_drag(40,pad+_drive_offset(game,Vector2(40,40)))
	check(game.reverse_held and game.turn_input>0,"owned pad capture survives drag-out and reentry")
	_touch(40,outside,false)
	check(_controls_clear(game),"release outside clears the captured owner")
	_touch(41,_drive_point(game,"left"),true);_touch(42,_drive_point(game,"right"),true)
	check(is_zero_approx(game.turn_input),"opposing held arrows cancel")
	_touch(41,_drive_point(game,"left"),false,true)
	check(game.turn_input>0.99,"canceling left preserves the independently held right")
	_touch(42,_drive_point(game,"right"),false)
	# Physical mouse remains separate from raw touch and supports the same pad.
	_touch(43,_drive_point(game,"reverse"),true)
	_mouse_button(_drive_point(game,"right"),true)
	check(game.reverse_held and game.turn_input>0.99,"physical mouse does not replace an active native touch")
	_mouse_button(_drive_point(game,"right"),false)
	check(game.reverse_held and is_zero_approx(game.turn_input),"physical mouse release preserves native Reverse")
	_touch(43,_drive_point(game,"reverse"),false)
	_mouse_button(pad,true);_mouse_motion(pad+_drive_offset(game,Vector2(40,40)))
	check(game.reverse_held and game.turn_input>0,"physical mouse pad can deliberately reverse and steer")
	_mouse_motion(pad,0)
	check(_controls_clear(game),"missing mouse hold mask safely clears only physical mouse owner")
	_mouse_button(pad,false)
	# Keep actual engine movement evidence: one touch can execute a reverse arc.
	var world = game.city.world
	game._set_parked();world.set_pose(Graph.point(24),0)
	var start: Vector2=world.graph_position()
	_touch(44,pad,true);_drag(44,pad+_drive_offset(game,Vector2(40,40)))
	await create_timer(0.35).timeout
	check(world.current_speed<0 and world.throttle<0,"routed one-thumb reverse drives actual physics backward")
	check(world.graph_position().y<start.y and world.yaw>0.001,"reverse horizontal steering follows unchanged actual car physics")
	_touch(44,pad,false);game._set_parked();world.set_pose(Graph.point(24),0)
	# Notifications and Back clear ownership; stale captured events cannot rearm.
	for notice in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT,Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT,Node.NOTIFICATION_APPLICATION_PAUSED]:
		_touch(50,pad,true);_touch(51,_drive_point(game,"right"),true)
		_touch(52,_drive_point(game,"reverse"),true);_touch(53,_drive_point(game,"brake"),true)
		game.notification(notice)
		check(_controls_clear(game) and game.resume_required,"focus/pause notification clears all held contacts")
		_drag(50,pad+_drive_offset(game,Vector2(40,40)));_touch(54,pad,true)
		check(_controls_clear(game),"paused/focus-lost contacts cannot rearm")
		game.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		_mouse_click(game.action_button)
		check(not game.resume_required,"actual Resume button remains usable after clearing touch input")
		_drag(50,pad+_drive_offset(game,Vector2(40,40)))
		check(_controls_clear(game),"resuming does not resurrect a discarded finger")
		for index in range(50,55): _touch(index,pad,false)
	_touch(60,pad,true)
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(game.screen=="home" and _controls_clear(game),"Android Back preserves existing Home policy and clears input")
	game._show("drive")
	_drag(60,pad+_drive_offset(game,Vector2(40,40)))
	check(_controls_clear(game),"late old-page drag cannot populate new-page controls")
	_touch(60,pad,false)
	await process_frame
