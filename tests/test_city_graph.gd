extends SceneTree
## Synthetic independent graph regression, not native driving evidence.
const Graph = preload("res://game/city_graph.gd")
var checks := 0
var failures := 0
func check(ok: bool,why: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(why)
func _initialize() -> void:
	_geometry()
	_shortest_paths()
	_projection_and_recalculation()
	_guidance_from_actual_position()
	print("TAXI_CITY_GRAPH_TESTS: %d checks; %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
func _geometry() -> void:
	var nodes: Array[int] = Graph.all_nodes()
	check(nodes.size()==49 and nodes[0]==0 and nodes[-1]==48,"Legacy addresses must remain stable")
	var edges: Array[Dictionary] = Graph.segments()
	var keys: Dictionary = {}
	var directions: Dictionary = {}
	for edge: Dictionary in edges:
		var a: int=edge.a
		var b: int=edge.b
		var key := Vector2i(mini(a,b),maxi(a,b))
		check(not keys.has(key),"Duplicate road")
		keys[key]=true
		var points: PackedVector2Array = edge.points
		check(points.size()>=3 and points[0].is_equal_approx(Graph.point(a)) and points[-1].is_equal_approx(Graph.point(b)),"Rendered polyline must meet its junctions")
		check(b in Graph.adjacent(a) and a in Graph.adjacent(b),"Road adjacency is not bidirectional")
		var direction: Vector2 = points[-1]-points[0]
		directions[int(rad_to_deg(direction.angle())/10.0)]=true
	check(edges.size()>nodes.size() and directions.size()>12,"City must have loops and varied road angles, not a flat grid")
	# Every geometric crossing must be a shared graph junction. This independently
	# checks the actual sampled rendered polylines, not just their endpoints.
	for i: int in range(edges.size()):
		var one: Dictionary=edges[i]
		for j: int in range(i+1,edges.size()):
			var two: Dictionary=edges[j]
			var shared: Array[int]=[]
			for id: int in [int(one.a),int(one.b)]:
				if id==int(two.a) or id==int(two.b): shared.append(id)
			var p: PackedVector2Array=one.points
			var q: PackedVector2Array=two.points
			for x: int in range(1,p.size()):
				for y: int in range(1,q.size()):
					var cross: Variant=Geometry2D.segment_intersects_segment(p[x-1],p[x],q[y-1],q[y])
					if cross==null: continue
					var junction := false
					for id: int in shared:
						if Vector2(cross).distance_to(Graph.point(id))<0.01: junction=true
					check(junction,"Road crossing lacks a connected junction: %s / %s" % [str(one.a)+"-"+str(one.b),str(two.a)+"-"+str(two.b)])
	var first: Vector2=edges[0].points[0]
	edges[0].points[0]=Vector2(99999,99999)
	check(Graph.segments()[0].points[0]==first,"Presentation caller mutated routing geometry")
func _shortest_paths() -> void:
	var nodes: Array[int]=Graph.all_nodes()
	var lengths: Dictionary={}
	var best: Dictionary={}
	for a: int in nodes:
		for b: int in nodes: best[Vector2i(a,b)]=0.0 if a==b else INF
	for edge: Dictionary in Graph.segments():
		var points: PackedVector2Array=edge.points
		var length:=0.0
		for i: int in range(1,points.size()): length+=points[i-1].distance_to(points[i])
		lengths[Vector2i(edge.a,edge.b)]=length
		lengths[Vector2i(edge.b,edge.a)]=length
		best[Vector2i(edge.a,edge.b)]=length
		best[Vector2i(edge.b,edge.a)]=length
	# Floyd-Warshall is independent of the runtime Dijkstra frontier algorithm.
	for via: int in nodes:
		for a: int in nodes:
			for b: int in nodes:
				best[Vector2i(a,b)]=minf(best[Vector2i(a,b)],best[Vector2i(a,via)]+best[Vector2i(via,b)])
	for a: int in nodes:
		for b: int in nodes:
			var path: Array[int]=Graph.route(a,b)
			check(a==b or not path.is_empty(),"Disconnected address")
			var current:=a
			var length:=0.0
			for node: int in path:
				check(lengths.has(Vector2i(current,node)),"GPS left a real connected street")
				length+=float(lengths.get(Vector2i(current,node),INF))
				current=node
			check(current==b and absf(length-float(best[Vector2i(a,b)]))<0.1,"GPS route is not shortest by actual street length")
	check(Graph.route(-1,24).is_empty() and Graph.route(24,49).is_empty(),"Invalid address accepted")
func _projection_and_recalculation() -> void:
	for node: int in Graph.all_nodes():
		check(Graph.nearest_node(Graph.point(node))==node,"Nearest address missed exact junction")
		var projection: Dictionary=Graph.nearest_road(Graph.point(node))
		check(float(projection.distance)<0.01 and Vector2(projection.point).distance_to(Graph.point(node))<0.01,"Road projection missed exact junction")
	for edge: Dictionary in Graph.segments():
		var middle: Vector2=edge.points[3]
		var projection: Dictionary=Graph.nearest_road(middle)
		check(float(projection.distance)<0.01 and float(projection.t)>=0.0 and float(projection.t)<=1.0,"Street projection is not on the rendered geometry")
	var original: Array[int]=Graph.route(24,5)
	var wrong:=23 if original[0]!=23 else 25
	var revised: Array[int]=Graph.route(wrong,5)
	check(not revised.is_empty() and revised!=original,"Wrong-turn position did not produce a new GPS route")
	check(Graph.point(24)==Vector2(1250,600),"Legacy central address changed unexpectedly")


func _guidance_from_actual_position() -> void:
	for edge: Dictionary in Graph.segments():
		var samples: PackedVector2Array=edge.points
		var at: Vector2=samples[2]+(samples[3]-samples[2]).normalized().orthogonal()*3.0
		for goal: int in [0,5,24,32,48]:
			var result: Dictionary=Graph.guidance(at,goal)
			var projection: Dictionary=result.projection
			var a: int=projection.a
			var b: int=projection.b
			var cost_a: float=float(projection.t)*Graph.edge_length(a,b)+Graph.route_length(a,Graph.route(a,goal))
			var cost_b: float=(1.0-float(projection.t))*Graph.edge_length(a,b)+Graph.route_length(b,Graph.route(b,goal))
			check(absf(float(result.street_length)-minf(cost_a,cost_b))<0.05,"GPS did not choose the shortest occupied-edge endpoint")
			var points: PackedVector2Array=result.points
			var measured:=0.0
			for i: int in range(1,points.size()): measured+=points[i-1].distance_to(points[i])
			check(points[0].distance_to(Vector2(projection.point))<0.001 and points[-1].distance_to(Graph.point(goal))<0.001,"Trimmed GPS polyline missed projection/goal")
			check(absf(measured-float(result.street_length))<0.1 and absf(float(result.length)-measured-float(projection.distance))<0.1,"GPS distance does not match the rendered trimmed route")
			check(result.start in [a,b] and result.next_point is Vector2 and is_finite(float(result.bearing)),"GPS turn target is invalid")
	var original: Dictionary=Graph.guidance(Graph.point(24),5)
	var wrong: Dictionary=Graph.guidance(Graph.point(23),5)
	check(original.points!=wrong.points,"Actual wrong turn did not recalculate the full GPS polyline")
	check(Graph.guidance(Graph.point(24),999).is_empty(),"Invalid GPS destination accepted")
