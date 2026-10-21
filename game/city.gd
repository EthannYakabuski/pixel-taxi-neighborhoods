extends SubViewportContainer
## A real 3D viewport; road guidance is informational and never an input driver.
const World = preload("res://game/city_world_3d.gd")
var world: Node3D
var viewport3d: SubViewport
var overview := false
var vehicle := Vector2.ZERO
var heading := 0.0
var route_nodes: Array[int] = []
var guidance: Dictionary = {}
var objective_node := -1
var pickup_mode := true
var taxi_color := Color("ffc857")
var driving := false
var selected_car := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	viewport3d = SubViewport.new()
	viewport3d.name = "Actual3DCityViewport"
	viewport3d.size = Vector2i(maxi(1,int(size.x)),maxi(1,int(size.y)))
	viewport3d.own_world_3d = true
	viewport3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport3d)
	world = World.new()
	viewport3d.add_child(world)
	world.set_car(selected_car)
	world.set_pose(vehicle,heading)
	world.separate_starting_traffic()
	world.enabled = driving
	resized.connect(func(): viewport3d.size = Vector2i(maxi(1,int(size.x)),maxi(1,int(size.y))))

func _process(_delta: float) -> void:
	if not is_instance_valid(world): return
	world.overview = overview
	world.set_guidance(guidance,objective_node)

func traffic_near(_point: Vector2) -> bool:
	return false # Physical CharacterBody3D collisions replace the old proximity slow-down.
