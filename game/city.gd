class_name TaxiCityView
extends Control

signal road_tapped(node: int)

const Model = preload("res://game/model.gd")
var vehicle := Vector2(660, 660)
var heading: float = 0.0
var taxi_color := Color("ffc857")
var objective_node: int = -1
var pickup_mode: bool = true
var route_nodes: Array[int] = []
var overview: bool = false
var camera := Vector2(660, 660)
var clock: float = 0.0
var fleet: Array[Dictionary] = []
var buildings: Dictionary = {}
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	font = ThemeDB.fallback_font
	for district_name: String in ["foundry", "central", "garden"]:
		var textures: Array[Texture2D] = []
		for index: int in range(6):
			var path: String = "res://assets/city/%s_%d.png" % [district_name, index]
			if ResourceLoader.exists(path): textures.append(load(path))
		buildings[district_name] = textures
	for index: int in range(12):
		fleet.append({"horizontal": index % 2 == 0, "lane": (index * 3 + 1) % 7, "offset": float(index * 173), "speed": 34 + index * 2,
			"color": [Color("e99c83"), Color("79a7be"), Color("9dcdb4"), Color("b5a9d9")][index % 4]})

func _process(delta: float) -> void:
	clock += delta
	var desired: Vector2 = Vector2(660, 660) if overview else vehicle
	camera = camera.lerp(desired, minf(1.0, delta * 7.0))
	queue_redraw()

func zoom_level() -> float:
	return minf(size.x / 1560.0, size.y / 1500.0) if overview else 0.8

func screen_point(world: Vector2) -> Vector2:
	return (world - camera) * zoom_level() + size * 0.5

func world_point(screen: Vector2) -> Vector2:
	return (screen - size * 0.5) / zoom_level() + camera

func closest_node(world: Vector2) -> int:
	var column: int = clampi(roundi(world.x / Model.STEP), 0, 6)
	var row: int = clampi(roundi(world.y / Model.STEP), 0, 6)
	return row * 7 + column

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		road_tapped.emit(closest_node(world_point(event.position)))
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		road_tapped.emit(closest_node(world_point(event.position)))
		accept_event()

func traffic_near(world: Vector2) -> bool:
	for car_data: Dictionary in fleet:
		var along: float = fposmod(float(car_data.offset) + clock * float(car_data.speed), 1580) - 130
		var pos: Vector2 = Vector2(along, float(car_data.lane) * Model.STEP - 16) if car_data.horizontal else Vector2(float(car_data.lane) * Model.STEP + 16, along)
		if pos.distance_squared_to(world) < 900: return true
	return false

func _draw() -> void:
	var z: float = zoom_level()
	draw_rect(Rect2(Vector2.ZERO, size), Color("c2d8c1"))
	# Different surface palettes make each neighborhood readable without a menu.
	for column: int in range(-1, 7):
		for row: int in range(-1, 7):
			var district_name: String = Model.district(clampi(column, 0, 6))
			var base: Color = Color("c9c7bc") if district_name == "Foundry" else (Color("d5cdbb") if district_name == "Central" else Color("b6d1a6"))
			var start: Vector2 = Vector2(column, row) * Model.STEP + Vector2(42, 42)
			var rect := Rect2(screen_point(start), Vector2.ONE * (Model.STEP - 84) * z)
			draw_rect(rect.grow(11 * z), base.darkened(0.08))
			draw_rect(rect, base)
	for index: int in range(7):
		var p: float = float(index) * Model.STEP
		var left: Vector2 = screen_point(Vector2(-120, p))
		var right: Vector2 = screen_point(Vector2(1440, p))
		var top: Vector2 = screen_point(Vector2(p, -120))
		var bottom: Vector2 = screen_point(Vector2(p, 1440))
		draw_line(left, right, Color("8fada9"), 86 * z)
		draw_line(top, bottom, Color("8fada9"), 86 * z)
		draw_line(left, right, Color("3c5260"), 67 * z)
		draw_line(top, bottom, Color("3c5260"), 67 * z)
		for segment: int in range(-3, 37):
			var a: float = float(segment) * 44.0
			draw_line(screen_point(Vector2(a, p)), screen_point(Vector2(a + 17, p)), Color("9fb7b6"), maxf(1, 2 * z))
			draw_line(screen_point(Vector2(p, a)), screen_point(Vector2(p, a + 17)), Color("9fb7b6"), maxf(1, 2 * z))
	# Kenney buildings are supplied transparent previews, composed over our original road grid.
	for row: int in range(6):
		for column: int in range(6):
			var region: String = "foundry" if column < 2 else ("central" if column < 4 else "garden")
			var textures: Array = buildings.get(region, [])
			var middle: Vector2 = Vector2(column + 0.5, row + 0.5) * Model.STEP
			if not textures.is_empty():
				var texture: Texture2D = textures[(row * 7 + column * 3) % textures.size()]
				draw_texture_rect(texture, Rect2(screen_point(middle - Vector2(80, 99)), Vector2(160, 160) * z), false)
			var tree_color := Color("559877") if region != "foundry" else Color("6b9591")
			for tree_index: int in range(3):
				var tree: Vector2 = middle + Vector2(-55 + tree_index * 52, 63)
				draw_circle(screen_point(tree + Vector2(4, 5)), 11 * z, Color(0.1, 0.2, 0.22, 0.13))
				draw_circle(screen_point(tree), (10 + tree_index % 2 * 3) * z, tree_color)
	if not route_nodes.is_empty():
		var previous: Vector2 = vehicle
		for node: int in route_nodes:
			draw_line(screen_point(previous), screen_point(Model.point(node)), Color("71d7d1"), 8 * z, true)
			previous = Model.point(node)
	for car_data: Dictionary in fleet:
		var along: float = fposmod(float(car_data.offset) + clock * float(car_data.speed), 1580) - 130
		var pos: Vector2 = Vector2(along, float(car_data.lane) * Model.STEP - 16) if car_data.horizontal else Vector2(float(car_data.lane) * Model.STEP + 16, along)
		_draw_car(pos, PI / 2 if car_data.horizontal else PI, car_data.color, z * 0.8, false)
	if objective_node >= 0:
		var marker: Vector2 = screen_point(Model.point(objective_node))
		var marker_color := Color("ffc857") if pickup_mode else Color("60d6bc")
		var pulse: float = 1.0 + sin(clock * 4) * 0.13
		draw_circle(marker, 39 * z * pulse, Color(marker_color, 0.18))
		draw_arc(marker, 27 * z, 0, TAU, 30, marker_color, 4 * z, true)
		var sign_pos: Vector2 = marker + Vector2(-22, -66) * z
		draw_style_box(_marker_box(marker_color), Rect2(sign_pos, Vector2(44, 30) * z))
		if z > 0.5: draw_string(font, sign_pos + Vector2(14, 22) * z, "P" if pickup_mode else "★", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(20 * z), Color("102638"))
	_draw_car(vehicle, heading, taxi_color, z, true)
	if overview:
		var labels := [["FOUNDRY", Vector2(180, -20), Color("607c87")], ["CENTRAL", Vector2(660, -20), Color("927b62")], ["GARDEN", Vector2(1170, -20), Color("598a6e")]]
		for entry: Array in labels:
			var at: Vector2 = screen_point(entry[1])
			draw_string(font, at - Vector2(30, 0), entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, entry[2])
	# Gentle vignette borders keep the map neatly inside its card.
	draw_line(Vector2(0, 0), Vector2(size.x, 0), Color("102638"), 4)
	draw_line(Vector2(0, size.y), size, Color("102638"), 4)

func _marker_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(7)
	return box

func _draw_car(world: Vector2, angle: float, color: Color, z: float, player: bool) -> void:
	var at: Vector2 = screen_point(world)
	if player:
		draw_circle(at, 37 * z, Color(1, 0.8, 0.32, 0.18))
		draw_arc(at, 34 * z, 0, TAU, 32, Color(1, 0.86, 0.48, 0.65), 2 * z, true)
	draw_set_transform(at, angle, Vector2.ONE * z)
	draw_rect(Rect2(-18, -13, 7, 12), Color("182632"))
	draw_rect(Rect2(11, -13, 7, 12), Color("182632"))
	draw_rect(Rect2(-18, 11, 7, 12), Color("182632"))
	draw_rect(Rect2(11, 11, 7, 12), Color("182632"))
	draw_polygon(PackedVector2Array([Vector2(-13, -28), Vector2(13, -28), Vector2(16, -12), Vector2(16, 24), Vector2(10, 29), Vector2(-10, 29), Vector2(-16, 24), Vector2(-16, -12)]), PackedColorArray([color]))
	draw_rect(Rect2(-10, -13, 20, 15), Color("386071"))
	draw_rect(Rect2(-10, 10, 20, 10), Color("386071"))
	draw_line(Vector2(-9, -21), Vector2(9, -21), color.lightened(0.45), 3)
	if player:
		draw_rect(Rect2(-6, 0, 12, 7), Color("fff0c0"))
	draw_set_transform(Vector2.ZERO)
