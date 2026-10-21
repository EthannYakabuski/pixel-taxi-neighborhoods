class_name CityGraph
extends RefCounted
## Stable addresses in three authored neighborhoods. Routing weights are the
## lengths of the same curved street polylines used by the rendered world.
const FOUNDRY_IDS := [0,1,7,8,14,15,21,22,28,29,35,36,42,43]
const CENTRAL_RING := [2,3,4,9,10,11,16,18,30,32,37,38,39,44,45,46]
const GARDEN_IDS := [5,6,12,13,19,20,26,27,33,34,40,41,47,48]
static var _points: Dictionary = {}
static var _neighbors: Dictionary = {}
static var _segments: Array[Dictionary] = []
static var _lookup: Dictionary = {}

static func _ensure() -> void:
	if not _points.is_empty(): return
	var foundry := [Vector2(-320,-360),Vector2(-80,-500),Vector2(230,-400),Vector2(380,-100),Vector2(350,180),Vector2(180,400),Vector2(-140,450),Vector2(-350,250),Vector2(-410,-30),Vector2(-380,-200),Vector2(-160,-150),Vector2(100,-150),Vector2(100,150),Vector2(-160,150)]
	var garden := [Vector2(0,-530),Vector2(310,-440),Vector2(510,-140),Vector2(460,180),Vector2(270,430),Vector2(-50,560),Vector2(-340,420),Vector2(-470,140),Vector2(-430,-180),Vector2(-230,-420),Vector2(-150,-170),Vector2(150,-130),Vector2(160,170),Vector2(-140,180)]
	for i: int in range(14):
		_points[FOUNDRY_IDS[i]] = foundry[i] + Vector2(300,650)
		_points[GARDEN_IDS[i]] = garden[i] + Vector2(2240,700)
	for i: int in range(16):
		var angle: float = -PI/2.0 + float(i)*TAU/16.0
		var variation: float = 1.0 + 0.045*sin(angle*3.0+0.4)
		_points[CENTRAL_RING[i]] = Vector2(1250,600) + Vector2(cos(angle)*380.0,sin(angle)*500.0)*variation
	_points[24] = Vector2(1250,600)
	_points[23] = Vector2(1050,600)
	_points[25] = Vector2(1450,600)
	_points[17] = Vector2(1250,350)
	_points[31] = Vector2(1250,850)
	for id: int in range(49): _neighbors[id] = []
	_neighborhood(FOUNDRY_IDS)
	_neighborhood(GARDEN_IDS)
	for i: int in range(16): _connect(CENTRAL_RING[i],CENTRAL_RING[(i+1)%16])
	for pair in [[24,23],[24,25],[24,17],[24,31],[23,17],[17,25],[25,31],[31,23],[17,CENTRAL_RING[0]],[25,CENTRAL_RING[4]],[31,CENTRAL_RING[8]],[23,CENTRAL_RING[12]]]:
		_connect(pair[0],pair[1])
	# Separate northern/southern arterials make useful inter-district loops.
	_connect(FOUNDRY_IDS[3],CENTRAL_RING[12])
	_connect(FOUNDRY_IDS[4],CENTRAL_RING[10])
	_connect(CENTRAL_RING[4],GARDEN_IDS[8])
	_connect(CENTRAL_RING[6],GARDEN_IDS[7])

static func _neighborhood(ids: Array) -> void:
	for i: int in range(10): _connect(ids[i],ids[(i+1)%10])
	for i: int in range(4): _connect(ids[10+i],ids[10+(i+1)%4])
	for pair in [[0,10],[2,11],[5,12],[7,13]]: _connect(ids[pair[0]],ids[pair[1]])

static func _connect(a: int,b: int) -> void:
	var start: Vector2 = _points[a]
	var end: Vector2 = _points[b]
	var delta := end-start
	var bend := minf(delta.length()*0.035,14.0) * (1.0 if (a+b)%2==0 else -1.0)
	var control := (start+end)*0.5 + delta.normalized().orthogonal()*bend
	var points := PackedVector2Array()
	for i: int in range(7):
		var t: float = float(i)/6.0
		points.append((1.0-t)*(1.0-t)*start + 2.0*(1.0-t)*t*control+t*t*end)
	var length := 0.0
	for i: int in range(1,points.size()): length += points[i-1].distance_to(points[i])
	var entry: Dictionary = {"a":a,"b":b,"points":points,"length":length}
	_segments.append(entry)
	_lookup[Vector2i(mini(a,b),maxi(a,b))] = entry
	_neighbors[a].append(b)
	_neighbors[b].append(a)

static func all_nodes() -> Array[int]:
	_ensure()
	var result: Array[int] = []
	for i: int in range(49): result.append(i)
	return result

static func point(id: int) -> Vector2:
	_ensure()
	return _points.get(id,Vector2(1250,600))

static func district(id: int) -> String:
	if id<0 or id>=49: return "Central"
	if id in FOUNDRY_IDS: return "Foundry"
	if id in GARDEN_IDS: return "Garden"
	return "Central"

static func adjacent(id: int) -> Array[int]:
	_ensure()
	var result: Array[int] = []
	for neighbor: int in _neighbors.get(id,[]): result.append(neighbor)
	return result

static func segments() -> Array[Dictionary]:
	_ensure()
	return _segments.duplicate(true)

static func edge_points(a: int,b: int) -> PackedVector2Array:
	_ensure()
	var entry: Dictionary = _lookup.get(Vector2i(mini(a,b),maxi(a,b)),{})
	if entry.is_empty(): return PackedVector2Array()
	var result: PackedVector2Array = entry.points.duplicate()
	if a!=int(entry.a): result.reverse()
	return result

static func edge_length(a: int,b: int) -> float:
	_ensure()
	var entry: Dictionary = _lookup.get(Vector2i(mini(a,b),maxi(a,b)),{})
	return float(entry.get("length",INF))

static func route(start: int,goal: int) -> Array[int]:
	_ensure()
	if not _points.has(start) or not _points.has(goal) or start==goal: return []
	var costs: Dictionary = {start:0.0}
	var previous: Dictionary = {}
	var frontier: Array[int] = [start]
	while not frontier.is_empty():
		var best: int = frontier[0]
		for candidate: int in frontier:
			if float(costs[candidate])<float(costs[best]): best=candidate
		frontier.erase(best)
		if best==goal: break
		for neighbor: int in _neighbors[best]:
			var next_cost: float = float(costs[best])+edge_length(best,neighbor)
			if next_cost+0.00001<float(costs.get(neighbor,INF)):
				costs[neighbor]=next_cost
				previous[neighbor]=best
				if neighbor not in frontier: frontier.append(neighbor)
	if not previous.has(goal): return []
	var result: Array[int] = []
	var cursor := goal
	while cursor!=start:
		result.push_front(cursor)
		cursor=int(previous[cursor])
	return result

static func route_length(start: int,path: Array[int]) -> float:
	var result := 0.0
	var current := start
	for next: int in path:
		var length := edge_length(current,next)
		if not is_finite(length): return INF
		result+=length
		current=next
	return result

static func nearest_node(at: Vector2) -> int:
	_ensure()
	var best := 24
	var distance := INF
	for id: int in _points:
		var test: float = at.distance_squared_to(_points[id])
		if test<distance: best=id; distance=test
	return best

static func nearest_road(at: Vector2) -> Dictionary:
	_ensure()
	var best: Dictionary = {"point":point(24),"a":24,"b":17,"t":0.0,"piece":0,"distance":INF}
	for entry: Dictionary in _segments:
		var points: PackedVector2Array = entry.points
		var travelled := 0.0
		for i: int in range(1,points.size()):
			var projected := Geometry2D.get_closest_point_to_segment(at,points[i-1],points[i])
			var distance := at.distance_to(projected)
			if distance<float(best.distance):
				best={"point":projected,"a":entry.a,"b":entry.b,"t":(travelled+points[i-1].distance_to(projected))/float(entry.length),"piece":i-1,"distance":distance}
			travelled+=points[i-1].distance_to(points[i])
	return best


static func guidance(at: Vector2,goal: int) -> Dictionary:
	# GPS chooses between BOTH endpoints of the actual occupied street. Merely
	# choosing the nearest junction can send the driver along a longer route.
	_ensure()
	if not _points.has(goal): return {}
	var projection: Dictionary=nearest_road(at)
	var a: int=projection.a
	var b: int=projection.b
	var path_a: Array[int]=route(a,goal)
	var path_b: Array[int]=route(b,goal)
	var street_length: float=edge_length(a,b)
	var cost_a: float=float(projection.t)*street_length+route_length(a,path_a)
	var cost_b: float=(1.0-float(projection.t))*street_length+route_length(b,path_b)
	var start: int=a if cost_a<=cost_b else b
	var path: Array[int]=path_a if start==a else path_b
	var points := PackedVector2Array([Vector2(projection.point)])
	var occupied: PackedVector2Array=edge_points(a,b)
	var piece: int=projection.piece
	if start==a:
		for i: int in range(piece,-1,-1):
			if points[-1].distance_to(occupied[i])>0.001: points.append(occupied[i])
	else:
		for i: int in range(piece+1,occupied.size()):
			if points[-1].distance_to(occupied[i])>0.001: points.append(occupied[i])
	var current:=start
	for node: int in path:
		var edge: PackedVector2Array=edge_points(current,node)
		for i: int in range(1,edge.size()):
			if points[-1].distance_to(edge[i])>0.001: points.append(edge[i])
		current=node
	var nodes: Array[int]=[start]
	nodes.append_array(path)
	var next_point: Vector2=points[1] if points.size()>1 else point(goal)
	var next_direction: Vector2=next_point-Vector2(projection.point)
	var next_node: int=start if Vector2(projection.point).distance_to(point(start))>0.01 else path[0] if not path.is_empty() else goal
	return {"start":start,"route":path,"nodes":nodes,"points":points,"projection":projection,
		"street_length":minf(cost_a,cost_b),"length":minf(cost_a,cost_b)+float(projection.distance),
		"distance_to_road":float(projection.distance),"next_point":next_point,"next_node":next_node,
		"bearing":atan2(next_direction.x,next_direction.y),"goal":goal}
