extends "res://game/drive_kit.gd"
## Actual manual-driving city. GPS geometry never controls the vehicle.
const Graph = preload("res://game/city_graph.gd")
const WORLD_SCALE := 0.22
const CAMERA_CLEARANCE := 0.3
signal travelled(metres: float)
signal impact(speed: float)
var player: CharacterBody3D
var camera3d: Camera3D
var current_speed := 0.0
var steering := 0.0
var throttle := 0.0
var brake := false
var enabled := false
var max_speed := 15.0
var yaw := 0.0
var hit_grace := 0.0
var camera_shake := 0.0
var overview := false
var objective_node := -1
var route_nodes: Array[int] = []
var _gps_signature := ""
var _batches: Dictionary = {}
var _bounds: Dictionary = {}
var gameplay_guard: Callable
var _gps_root: Node3D
var _curb: Node3D
var _traffic: Array[Dictionary] = []
var _elapsed := 0.0
var _building_count := 0
var _car_index := -1
var _camera_probe := SphereShape3D.new()

func _ready() -> void:
	_camera_probe.radius = CAMERA_CLEARANCE
	sky_and_sun()
	get_viewport().msaa_3d = Viewport.MSAA_2X
	box(self, Vector3(130,-0.3,130), Vector3(1200,0.5,1200), Color("5d8c74"))
	_build_streets()
	_build_neighborhoods()
	_flush_batches()
	_gps_root = Node3D.new()
	_gps_root.name = "GuidanceOnlyGPS"
	add_child(_gps_root)
	_curb = Node3D.new()
	_curb.name = "PassengerCurb"
	add_child(_curb)
	cylinder(_curb, Vector3(0,0.07,0), 2.4, 0.12, Color("ffc857"))
	var beacon := cylinder(_curb, Vector3(0,2.2,0), 0.18, 4.4, Color("ffc857"))
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label(_curb,"PASSENGER",Vector3(0,5.0,0),Color("fff1d0"),28)
	camera3d = Camera3D.new()
	camera3d.name = "FollowingCamera3D"
	camera3d.fov = 58.0
	camera3d.v_offset = -0.9
	camera3d.far = 520.0
	camera3d.near = 0.15
	add_child(camera3d)
	camera3d.current = true
	set_car(0)
	set_pose(Graph.point(24),0.0)
	_build_traffic()

func set_car(index: int) -> void:
	if index == _car_index: return
	_car_index = index
	var previous := Vector3.ZERO
	if is_instance_valid(player):
		previous = player.position
		player.free()
	var kinds := ["taxi","sedan-sports","suv","sedan"]
	player = car(kinds[clampi(index,0,3)],self,-1,true) as CharacterBody3D
	player.collision_mask = 6
	player.position = previous
	player.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	player.safe_margin = 0.03

func set_pose(at: Vector2, heading: float) -> void:
	if not is_instance_valid(player): return
	player.position = Vector3(at.x*WORLD_SCALE,0,at.y*WORLD_SCALE)
	yaw = heading
	player.rotation.y = yaw
	_follow(1.0)

func graph_position() -> Vector2:
	return Vector2(player.position.x,player.position.z)/WORLD_SCALE

func set_controls(turn: float, accelerator: float, braking: bool) -> void:
	steering = clampf(turn,-1,1)
	throttle = clampf(accelerator,-1,1)
	brake = braking

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player): return
	_elapsed += delta
	hit_grace = maxf(0,hit_grace-delta)
	camera_shake = maxf(0,camera_shake-delta*2.2)
	if enabled and (not gameplay_guard.is_valid() or gameplay_guard.call()):
		var wanted := throttle * max_speed
		if throttle < 0: wanted *= 0.34
		if brake: wanted = 0.0
		current_speed = move_toward(current_speed,wanted,delta*(19.0 if brake else 5.0))
		yaw -= steering * clampf(absf(current_speed)/5.0,0,1) * 1.32 * delta * (-1.0 if current_speed < 0 else 1.0)
		player.rotation.y = yaw
		var old := player.position
		player.velocity = Vector3(sin(yaw),0,cos(yaw))*current_speed
		player.move_and_slide()
		var moved := player.position.distance_to(old)
		spin_wheels(player,moved,-steering)
		if moved > 0.001: travelled.emit(moved/WORLD_SCALE*0.45)
		if player.get_slide_collision_count() > 0 and absf(current_speed) > 2.0 and hit_grace <= 0:
			var hit_speed := absf(current_speed)
			current_speed *= -0.16
			hit_grace = 1.8
			camera_shake = 0.6
			impact.emit(hit_speed)
		# Leaving the street slows grass travel; there is no route-following force.
		var road: Dictionary = Graph.nearest_road(graph_position())
		if float(road.distance)*WORLD_SCALE > 6.0: current_speed = move_toward(current_speed,clampf(current_speed,-3.0,4.0),delta*14.0)
		_tick_traffic(delta)
	else:
		current_speed = 0.0
	_follow(delta,true)
	_curb.visible = objective_node >= 0
	if objective_node >= 0:
		var at := Graph.point(objective_node)*WORLD_SCALE
		_curb.position = Vector3(at.x,0.06,at.y)
		_curb.rotation.y = sin(_elapsed)*0.025

func _follow(delta: float, constrain: bool = false) -> void:
	if not is_instance_valid(camera3d) or not is_instance_valid(player): return
	var forward := Vector3(sin(yaw),0,cos(yaw))
	var wanted := player.position-forward*11.8+Vector3(0,7.2,0)
	var target := player.position+forward*12.0+Vector3(0,0.5,0)
	if overview:
		wanted = player.position+Vector3(0,95,0.1)
		target = player.position
	if camera_shake > 0: wanted.x += sin(_elapsed*70.0)*camera_shake*0.4
	# set_pose/_ready can snap outside a physics step; query space only from
	# the physics callback. Map keeps its existing unoccluded overhead view.
	var query_safe := constrain and Engine.is_in_physics_frame() and not overview
	var target_global := to_global(target)
	var focus := player.global_position+Vector3(0,1.5,0)
	if query_safe:
		var wanted_global := _constrain_camera(focus,to_global(wanted),target_global)
		if not wanted_global.is_finite():
			# A failed boom correction needs a separately validated close view.
			# Shorten look-ahead only here so the taxi stays framed from above.
			target_global = to_global(player.position+forward*0.5+Vector3(0,0.5,0))
			wanted_global = _constrain_camera(focus,to_global(player.position+Vector3(0,7.2,0)),target_global)
		if not wanted_global.is_finite():
			push_error("No collision-safe chase camera for the current vehicle pose")
			return
		wanted = to_local(wanted_global)
	var candidate := camera3d.position.lerp(wanted,minf(1.0,delta*7.0))
	if query_safe:
		# A clear destination alone cannot stop the lerp cutting a corner.
		var corrected := _constrain_camera(focus,to_global(candidate),target_global)
		# The desired position was validated with this frame's focus/target.
		candidate = to_local(corrected) if corrected.is_finite() else wanted
	camera3d.position = candidate
	camera3d.look_at(target_global)

func _constrain_camera(focus: Vector3, candidate: Vector3, target: Vector3) -> Vector3:
	if not Engine.is_in_physics_frame(): return Vector3.INF
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _camera_probe
	query.collision_mask = 4
	query.exclude = [player.get_rid()]
	query.margin = 0.03
	query.transform = Transform3D(Basis.IDENTITY,focus)
	# cast_motion ignores initial overlaps. A physically valid car leaves this
	# small focus sphere clear; report a failed constraint for an invalid pose.
	if not space.intersect_shape(query,1).is_empty(): return Vector3.INF
	for _iteration in range(4):
		# Camera3D's offsets move the rendered eye along this look-at basis.
		# Recheck after shortening because the new position changes that basis.
		var basis := Basis.looking_at(target-candidate)
		var eye_offset := basis*Vector3(camera3d.h_offset,camera3d.v_offset,0)
		var motion := candidate+eye_offset-focus
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions.size() != 2: break
		if fractions[0] >= 1.0: return candidate
		var length := motion.length()
		if length < 0.001: break
		candidate = focus+motion*maxf(0.0,fractions[0]-0.05/length)-eye_offset
	return Vector3.INF

func _queue(group: String, key: String, at: Vector3, size: Vector3 = Vector3.ONE, angle: float = 0.0) -> void:
	var id := group+"/"+key
	if not _batches.has(id): _batches[id] = []
	var basis := Basis(Vector3.UP,angle)*Basis.from_scale(size)
	_batches[id].append(Transform3D(basis,at))

func _flush_batches() -> void:
	# Real supplied GLB meshes, hardware-instanced for the mobile Compatibility path.
	# Source scenes are instantiated once per type; their meshes/materials stay intact.
	for id: String in _batches:
		var source: Node3D = (load(MODEL_ROOT+id+".glb") as PackedScene).instantiate()
		add_child(source)
		for node in source.find_children("*","MeshInstance3D",true,false):
			var mesh_node := node as MeshInstance3D
			var local := source.global_transform.affine_inverse()*mesh_node.global_transform
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.mesh = mesh_node.mesh
			instances.instance_count = _batches[id].size()
			for i in range(instances.instance_count): instances.set_instance_transform(i,_batches[id][i]*local)
			var draw := MultiMeshInstance3D.new()
			draw.name = "KenneyBatch_"+id.replace("/","_")
			draw.multimesh = instances
			draw.material_override = mesh_node.material_override
			if id.begins_with("commercial/") or id.begins_with("suburban/") or id.begins_with("industrial/"):
				var source_material = mesh_node.get_active_material(0)
				if source_material is StandardMaterial3D:
					var tinted: StandardMaterial3D = source_material.duplicate()
					var palette := [Color("e5c8a5"),Color("bacacb"),Color("d4b6a1"),Color("c7d3b2"),Color("b7c2d1"),Color("e4d7bd")]
					tinted.albedo_color = palette[posmod(id.hash(),palette.size())]
					draw.material_override = tinted
			add_child(draw)
		source.free()
	_batches.clear()

func _build_streets() -> void:
	for edge: Dictionary in Graph.segments():
		var points: PackedVector2Array = edge.points
		for i in range(points.size()-1):
			var a: Vector2 = points[i]*WORLD_SCALE
			var b: Vector2 = points[i+1]*WORLD_SCALE
			var length := a.distance_to(b)
			var count := maxi(1,ceili(length/9.0))
			for step in range(count):
				var at := a.lerp(b,(step+0.5)/count)
				_queue("roads","road-straight",Vector3(at.x,0.0,at.y),Vector3(length/count+0.15,1,9.0),-a.angle_to_point(b))
	for node in Graph.all_nodes():
		var at: Vector2 = Graph.point(node)*WORLD_SCALE
		_queue("roads","road-crossroad",Vector3(at.x,0.015,at.y),Vector3(9,1,9))
		if node % 4 == 0: _queue("roads","light-curved",Vector3(at.x+5.5,0,at.y+4.0),Vector3.ONE*2.5)

func _building(group: String, key: String, at: Vector2, angle: float, factor: float) -> void:
	_queue(group,key,Vector3(at.x,0.04,at.y),Vector3.ONE*factor,angle)
	# Match the transformed actual model bounds, including broad warehouse footprints.
	var id := group+"/"+key
	if not _bounds.has(id):
		var template: Node3D = (load(MODEL_ROOT+id+".glb") as PackedScene).instantiate()
		add_child(template)
		var first := true
		var bounds := AABB()
		for part in template.find_children("*","MeshInstance3D",true,false):
			var local: Transform3D = template.global_transform.affine_inverse()*part.global_transform
			var region: AABB = local*part.get_aabb()
			bounds = region if first else bounds.merge(region)
			first = false
		_bounds[id] = bounds
		template.free()
	var bounds: AABB = _bounds[id]
	var body := StaticBody3D.new()
	_building_count += 1
	body.name = "BuildingCollision_"+group+"_"+key+"_"+str(_building_count)
	body.collision_layer = 4
	body.collision_mask = 1
	body.position = Vector3(at.x,0,at.y)
	body.rotation.y = angle
	add_child(body)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bounds.size*factor
	shape.size.y = maxf(shape.size.y,1.0)
	hit.position = bounds.get_center()*factor
	hit.shape = shape
	body.add_child(hit)

func _build_neighborhoods() -> void:
	var serial := 0
	for edge: Dictionary in Graph.segments():
		var points: PackedVector2Array = edge.points
		var district: String = Graph.district(int(edge.a))
		for i in range(points.size()-1):
			var a: Vector2 = points[i]*WORLD_SCALE
			var b: Vector2 = points[i+1]*WORLD_SCALE
			var tangent := (b-a).normalized()
			var right := Vector2(-tangent.y,tangent.x)
			var count := maxi(1,int(a.distance_to(b)/18.0))
			for n in range(count):
				var at := a.lerp(b,(n+0.5)/count)
				for side in [-1,1]:
					serial += 1
					var curb := at+right*float(side)*13.0
					# Avoid overlap where another curved connector runs nearby.
					if float(Graph.nearest_road(curb/WORLD_SCALE).distance)*WORLD_SCALE < 9.5: continue
					var direction := -tangent.angle()+PI*0.5 if side > 0 else -tangent.angle()-PI*0.5
					if serial % 5 == 0 or district == "Garden" and serial % 3 == 0:
						_queue("nature","tree_oak",Vector3(curb.x,0,curb.y),Vector3.ONE*(2.8+serial%3*0.3))
						_queue("nature","plant_bush",Vector3(curb.x+3,0,curb.y+3),Vector3.ONE*3)
					else:
						var letter: String = ["a","b","c","d","e","f"][serial%6]
						var group := "commercial" if district == "Central" else "industrial" if district == "Foundry" else "suburban"
						var key := "building-type-"+letter if group == "suburban" else "building-"+letter
						_building(group,key,curb,direction,7.5 if group == "commercial" else 6.8)
						if serial%3 == 0: _queue("nature","tree_pineRoundA",Vector3(curb.x+right.x*4.5,0,curb.y+right.y*4.5),Vector3.ONE*2.7)
	# District arrival signs use the real graph coordinates, never a decorative flat grid.
	for node in [3,24,45]:
		var at := Graph.point(node)*WORLD_SCALE
		label(self,Graph.district(node).to_upper(),Vector3(at.x+8,5.5,at.y),Color("fff1d0"),32)

func set_guidance(guide: Dictionary, goal: int) -> void:
	objective_node = goal
	var signature := str(guide.get("start",-1))+":"+str(guide.get("route",[]))+":"+str(guide.get("projection",{}).get("piece",-1))+":"+str(goal)
	if signature == _gps_signature: return
	_gps_signature = signature
	for child in _gps_root.get_children(): child.free()
	if goal < 0 or guide.is_empty(): return
	var points: PackedVector2Array = guide.points
	for i in range(points.size()-1):
		var a: Vector2 = points[i]*WORLD_SCALE
		var b: Vector2 = points[i+1]*WORLD_SCALE
		if a.distance_to(b) < 0.01: continue
		var middle := (a+b)*0.5
		var stripe := box(_gps_root,Vector3(middle.x,0.09,middle.y),Vector3(a.distance_to(b),0.035,0.38),Color("ffc857"))
		stripe.rotation.y = -a.angle_to_point(b)
		stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_traffic() -> void:
	var edges := Graph.segments()
	for i in range(mini(14,edges.size())):
		var edge: Dictionary = edges[(i*7+3)%edges.size()]
		var body := car(["sedan","van","truck","hatchback-sports"][i%4],self,i,false)
		_traffic.append({"body":body,"edge":edge,"t":float(i%7)/7.0,"speed":0.045+float(i%3)*0.012})

func _tick_traffic(delta: float) -> void:
	for item in _traffic:
		var points: PackedVector2Array = item.edge.points
		item.t = fposmod(float(item.t)+delta*float(item.speed),1.0)
		var scaled := float(item.t)*float(points.size()-1)
		var index := mini(int(scaled),points.size()-2)
		var a: Vector2 = points[index]*WORLD_SCALE
		var b: Vector2 = points[index+1]*WORLD_SCALE
		var forward := (b-a).normalized()
		var at := a.lerp(b,fposmod(scaled,1.0))+Vector2(-forward.y,forward.x)*2.0
		item.body.position = Vector3(at.x,0.03,at.y)
		item.body.rotation.y = atan2(forward.x,forward.y)
		spin_wheels(item.body,delta*7.0)

func separate_starting_traffic() -> void:
	# A new/restored drive begins with room to react. Later traffic is physical.
	_tick_traffic(0)
	for item in _traffic:
		if item.body.position.distance_to(player.position) >= 12.0: continue
		var best_t: float = item.t
		var best_distance := 0.0
		for candidate in [0.07,0.31,0.59,0.87]:
			item.t = candidate
			_tick_traffic(0)
			var distance: float = item.body.position.distance_to(player.position)
			if distance > best_distance: best_distance=distance;best_t=candidate
		item.t = best_t
	_tick_traffic(0)
