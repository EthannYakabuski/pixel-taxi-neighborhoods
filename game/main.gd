extends Control

const Model = preload("res://game/model.gd")
const City = preload("res://game/city.gd")
const INK := Color("102638")
const MIST := Color("b9d1da")
const GOLD := Color("ffc857")
const MINT := Color("79d5bd")
const SAVE_PATH := "user://neighborhoods_v1.json"

var model = Model.new()
var stage: Control
var page_content: Control
var menu_scroll: ScrollContainer
var city: Control
var screen: String = "home"
var vehicle_position := Vector2(660, 660)
var vehicle_heading: float = 0.0
var travel_path: Array[int] = []
var held_direction := Vector2i.ZERO
var automatic: bool = false
var pulse_timer: float = 0.0
var autosave_timer: float = 0.0
var toast_timer: float = 0.0
var toast_label: Label
var coins_label: Label
var info_label: Label
var action_button: Button
var progress_label: Label
var catalog: Dictionary = {}
var last_receipt: Dictionary = {}
var sfx: AudioStreamPlayer
var music: AudioStreamPlayer
var capture_path: String = ""
var demo: bool = false
var runtime_smoke: bool = false
var reward_pending: bool = false
var boot_view: String = "home"

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--view="): boot_view = argument.trim_prefix("--view=")
		if argument == "--demo": demo = true
		if argument == "--runtime-smoke": runtime_smoke = true
	if not demo: _load_save()
	if demo: _demo_state()
	vehicle_position = Model.point(model.player_node)
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://game/catalog.json"))
	sfx = AudioStreamPlayer.new()
	add_child(sfx)
	music = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/city_evening.wav"):
		music.stream = load("res://assets/audio/city_evening.wav")
		if music.stream is AudioStreamWAV:
			music.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			music.stream.loop_end = int(music.stream.get_length() * music.stream.mix_rate)
		music.volume_db = -14
	add_child(music)
	if model.sound and DisplayServer.get_name() != "headless": music.play()
	get_viewport().size_changed.connect(_fit_stage)
	var native_services := _services()
	if is_instance_valid(native_services) and native_services.has_signal("menu_bottom_reserve_changed"):
		native_services.connect("menu_bottom_reserve_changed", _apply_banner_layout)
	_sync_achievements()
	_show(boot_view)
	if not capture_path.is_empty(): _capture_after_frame()
	if runtime_smoke: _runtime_smoke()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen != "home": _show("home")

func _exit_tree() -> void:
	_stop_audio()

func _stop_audio() -> void:
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	if is_instance_valid(sfx):
		sfx.stop()
		sfx.stream = null

func _process(delta: float) -> void:
	if toast_timer > 0:
		toast_timer -= delta
		if is_instance_valid(toast_label): toast_label.visible = toast_timer > 0
	if screen == "drive":
		var keyboard := Vector2i.ZERO
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A): keyboard = Vector2i.LEFT
		elif Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D): keyboard = Vector2i.RIGHT
		elif Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W): keyboard = Vector2i.UP
		elif Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S): keyboard = Vector2i.DOWN
		var direction: Vector2i = keyboard if keyboard != Vector2i.ZERO else held_direction
		if direction != Vector2i.ZERO:
			automatic = false
			if travel_path.is_empty(): _manual_step(direction)
		if not travel_path.is_empty():
			var destination: Vector2 = Model.point(travel_path[0])
			var old_position: Vector2 = vehicle_position
			var effective_speed: float = model.speed()
			if is_instance_valid(city) and city.traffic_near(vehicle_position): effective_speed *= 0.72
			vehicle_position = vehicle_position.move_toward(destination, effective_speed * delta)
			var movement: Vector2 = vehicle_position - old_position
			model.travel(movement.length() * 0.45)
			if movement.length_squared() > 0.001: vehicle_heading = lerp_angle(vehicle_heading, movement.angle() + PI / 2, minf(1, delta * 12))
			if vehicle_position.distance_to(destination) < 0.1:
				model.player_node = travel_path.pop_front()
				if not automatic: travel_path.clear()
				if travel_path.is_empty() and model.objective() == model.player_node and not model.active_job.is_empty():
					_toast("At the curb. Your passenger is ready.")
					_play("res://assets/audio/arrival.ogg")
		if is_instance_valid(city):
			city.vehicle = vehicle_position
			city.heading = vehicle_heading
			city.route_nodes = travel_path
			city.taxi_color = Color(Model.CARS[model.car].color)
			city.objective_node = model.objective() if not model.active_job.is_empty() else -1
			city.pickup_mode = not bool(model.active_job.get("picked_up", false))
	pulse_timer += delta
	autosave_timer += delta
	if pulse_timer > 0.35:
		pulse_timer = 0
		if screen == "drive": _refresh_drive()
	if autosave_timer > 12:
		autosave_timer = 0
		model.roll_day(Time.get_date_string_from_system(true))
		_save()

func _fit_stage() -> void:
	if not is_instance_valid(stage): return
	var available: Vector2 = get_viewport_rect().size
	var scale_factor: float = minf(available.x / 540.0, available.y / 960.0)
	stage.scale = Vector2.ONE * scale_factor
	stage.position = (available - Vector2(540, 960) * scale_factor) * 0.5
	_apply_banner_layout()

func _apply_banner_layout(reserve_override: float = -1.0) -> void:
	if not is_instance_valid(menu_scroll): return
	var reserve := reserve_override
	var services := _services()
	if reserve < 0.0:
		reserve = float(services.call("menu_bottom_reserve", stage)) if is_instance_valid(services) and services.has_method("menu_bottom_reserve") else 0.0
	if screen != "home": reserve = 0.0
	reserve = clampf(reserve, 0.0, 400.0)
	menu_scroll.size = Vector2(540, 960.0 - reserve)
	menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if reserve > 0.0 else ScrollContainer.SCROLL_MODE_SHOW_NEVER
	menu_scroll.mouse_filter = Control.MOUSE_FILTER_PASS if reserve > 0.0 else Control.MOUSE_FILTER_IGNORE
	if reserve <= 0.0: menu_scroll.scroll_vertical = 0
	if is_instance_valid(toast_label): toast_label.position.y = minf(875.0, menu_scroll.size.y - 60.0)


func _show(view: String) -> void:
	screen = view
	held_direction = Vector2i.ZERO
	if is_instance_valid(stage):
		stage.hide()
		stage.queue_free()
	stage = Control.new()
	stage.size = Vector2(540, 960)
	add_child(stage)
	menu_scroll = ScrollContainer.new()
	menu_scroll.size = Vector2(540, 960)
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.follow_focus = true
	stage.add_child(menu_scroll)
	page_content = Control.new()
	page_content.custom_minimum_size = Vector2(540, 960)
	page_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_scroll.add_child(page_content)
	city = null
	toast_label = null
	coins_label = null
	_panel(Rect2(0, 0, 540, 960), INK, 0)
	match view:
		"drive": _drive()
		"dispatch": _dispatch()
		"garage": _garage()
		"daily": _daily()
		"journal": _journal()
		"settings": _settings()
		"receipt": _receipt()
		_: screen = "home"; _home()
	toast_label = _label("", Rect2(28, 875, 484, 45), 16, Color("102638"), HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.add_theme_stylebox_override("normal", _box(GOLD, 12))
	toast_label.visible = false
	_fit_stage()
	var services: Node = _services()
	if services != null: services.call("set_menu_visible", screen == "home")
	_apply_banner_layout()
	_save()

func _header(title: String, subtitle: String = "") -> void:
	_label(title, Rect2(24, 25, 360, 38), 29, Color("fff5dc"))
	_label(subtitle, Rect2(25, 69, 380, 28), 14, MIST)
	coins_label = _label("%d coins" % model.coins, Rect2(365, 30, 150, 28), 19, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_panel(Rect2(24, 108, 492, 4), Color("315064"), 2)
	if screen != "home": _button("‹ Home", Rect2(24, 907, 120, 36), func(): _show("home"), true)

func _home() -> void:
	_header("PIXEL TAXI", "NEIGHBORHOODS  ·  TAKE THE SCENIC FARE")
	_panel(Rect2(22, 129, 496, 362), Color("b8cfc2"), 22)
	_add_city(Rect2(30, 154, 480, 305), true)
	_label("A little city. A lot of stories.", Rect2(24, 506, 492, 38), 25, Color("fff5dc"), HORIZONTAL_ALIGNMENT_CENTER)
	_label("Driver level %d  ·  %d fares  ·  %.1f km" % [model.level(), model.jobs, model.distance / 1000], Rect2(24, 547, 492, 28), 16, MIST, HORIZONTAL_ALIGNMENT_CENTER)
	_progress(Rect2(42, 587, 456, 7), model.level_progress(), MINT)
	_button("CONTINUE FARE" if not model.active_job.is_empty() else "START YOUR SHIFT", Rect2(24, 621, 492, 62), func(): _show("drive" if not model.active_job.is_empty() else "dispatch"))
	_button("Garage & upgrades", Rect2(24, 704, 238, 59), func(): _show("garage"), true)
	_button("Daily rewards", Rect2(278, 704, 238, 59), func(): _show("daily"), true)
	_button("Driver journal", Rect2(24, 779, 238, 56), func(): _show("journal"), true)
	_button("Sound & services", Rect2(278, 779, 238, 56), func(): _show("settings"), true)
	_label("Kind passengers. Open streets. Your own pace.", Rect2(24, 849, 492, 26), 14, MIST, HORIZONTAL_ALIGNMENT_CENTER)
	# Bottom 56 px intentionally reserved for the native menu banner.
	_panel(Rect2(0, 904, 540, 56), Color("0c1e2c"), 0)

func _dispatch() -> void:
	_header("THE DISPATCH", "Choose a story. Every neighborhood is connected.")
	if not model.active_job.is_empty():
		_panel(Rect2(24, 145, 492, 180), Color("1e3b50"), 17)
		_label("A passenger is waiting", Rect2(44, 166, 450, 34), 25, GOLD)
		_label(model.active_job.passenger, Rect2(44, 211, 450, 34), 20, Color.WHITE)
		_button("Resume fare", Rect2(44, 263, 275, 45), func(): _show("drive"))
		_button("Cancel", Rect2(333, 263, 158, 45), func(): model.cancel_job(); travel_path.clear(); _show("dispatch"), true)
		return
	for slot: int in range(3):
		var job: Dictionary = model.make_job(slot)
		var y: float = 147 + slot * 213
		_panel(Rect2(24, y, 492, 193), Color("284756") if job.rare else Color("1d394b"), 18)
		var person: Texture2D = load("res://assets/people/passenger_%d.png" % ((model.jobs + slot) % 6))
		_texture(person, Rect2(41, y + 15, 72, 72))
		_label("SPECIAL GUEST" if job.rare else "NEIGHBORHOOD FARE", Rect2(126, y + 17, 360, 21), 12, GOLD if job.rare else MINT)
		_label(job.passenger, Rect2(126, y + 45, 360, 32), 22, Color("fff5dc"))
		_label("%s → %s" % [Model.district(int(job.pickup)), Model.district(int(job.destination))], Rect2(44, y + 94, 440, 27), 18, MIST)
		_label("%.1f km  ·  %d+ coins" % [float(job.metres) / 1000, job.base_fare], Rect2(44, y + 128, 280, 25), 16, Color.WHITE)
		_button("Accept →", Rect2(345, y + 133, 145, 43), func():
			if model.accept_job(job):
				travel_path.clear()
				_show("drive")
				_route_to(model.objective())
		)
	_label("Tap streets to guide your cab, or use the thumb buttons.", Rect2(28, 807, 484, 50), 15, MIST, HORIZONTAL_ALIGNMENT_CENTER)

func _drive() -> void:
	_header("ON THE CLOCK", "%s  ·  DRIVER LEVEL %d" % [Model.district(model.player_node).to_upper(), model.level()])
	_panel(Rect2(18, 129, 504, 99), Color("1e3b50"), 17)
	info_label = _label("", Rect2(36, 145, 468, 65), 20, Color("fff5dc"))
	_panel(Rect2(18, 242, 504, 394), Color("bed2bd"), 16)
	_add_city(Rect2(20, 244, 500, 390), false)
	city.road_tapped.connect(_route_to)
	action_button = _button("", Rect2(18, 653, 504, 54), _curb_action)
	var labels: Array[String] = ["← LEFT", "↓ DOWN", "↑ UP", "RIGHT →"]
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT]
	for index: int in range(4):
		var button: Button = _button(labels[index], Rect2(18 + index * 128, 725, 120, 60), func(): pass, true)
		var direction: Vector2i = directions[index]
		button.button_down.connect(func(): held_direction = direction; automatic = false)
		button.button_up.connect(func(): if held_direction == direction: held_direction = Vector2i.ZERO)
	_button("Follow route", Rect2(18, 804, 244, 51), func():
		if model.active_job.is_empty(): _show("dispatch")
		else: _route_to(model.objective())
	, true)
	_button("Dispatch", Rect2(278, 804, 244, 51), func(): _show("dispatch"), true)
	_button("City map", Rect2(169, 907, 147, 36), func(): city.overview = not city.overview, true)
	_button("Pull over", Rect2(334, 907, 184, 36), func(): travel_path.clear(); held_direction = Vector2i.ZERO; _toast("Parked. Enjoy the neighborhood."), true)
	_refresh_drive()

func _refresh_drive() -> void:
	if not is_instance_valid(info_label): return
	if model.active_job.is_empty():
		info_label.text = "Free drive · %s\nFind a fare whenever you feel like it." % Model.district(model.player_node)
		action_button.text = "Find a passenger"
		action_button.disabled = false
	else:
		var is_pickup: bool = not bool(model.active_job.picked_up)
		info_label.text = "%s %s\n%s · %.1f km driven" % ["Pick up" if is_pickup else "Drop off", model.active_job.passenger, Model.district(model.objective()), model.distance / 1000]
		var at_curb: bool = model.player_node == model.objective() and travel_path.is_empty() and vehicle_position.distance_to(Model.point(model.player_node)) < 1
		action_button.text = ("Pick up passenger" if is_pickup else "Complete fare & get paid") if at_curb else "Follow the highlighted route to the curb"
		action_button.disabled = not at_curb
	if is_instance_valid(coins_label): coins_label.text = "%d coins" % model.coins

func _route_to(goal: int) -> void:
	if screen != "drive": return
	automatic = true
	var start: int = model.player_node
	var new_path: Array[int] = []
	if not travel_path.is_empty() and vehicle_position.distance_to(Model.point(model.player_node)) > 1:
		start = travel_path[0]
		new_path.append(start)
	new_path.append_array(Model.route(start, goal))
	travel_path = new_path
	_toast("Route set. Thumb buttons take over at any time.")

func _manual_step(direction: Vector2i) -> void:
	var column: int = model.player_node % 7 + direction.x
	var row: int = model.player_node / 7 + direction.y
	if column < 0 or column >= 7 or row < 0 or row >= 7: return
	travel_path = [row * 7 + column]

func _curb_action() -> void:
	if model.active_job.is_empty():
		_show("dispatch")
		return
	if not bool(model.active_job.picked_up):
		if model.pickup():
			_play("res://assets/audio/arrival.ogg")
			_route_to(model.objective())
			_toast("Welcome aboard. Let's take the scenic route.")
	else:
		last_receipt = model.complete_job()
		if not last_receipt.is_empty():
			_play("res://assets/audio/reward.ogg")
			_sync_achievements()
			var services: Node = _services()
			if services != null: services.call("round_finished")
			_show("receipt")
	_save()
	_refresh_drive()

func _receipt() -> void:
	_header("FARE COMPLETE", "One more story, safely delivered.")
	_panel(Rect2(24, 153, 492, 386), Color("1e3b50"), 22)
	_texture(load("res://assets/taxi.png"), Rect2(185, 171, 170, 170))
	_label("+%d coins" % int(last_receipt.get("fare", 0)), Rect2(44, 344, 452, 58), 45, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_label(str(last_receipt.get("passenger", "Thanks for the ride!")), Rect2(44, 410, 452, 40), 23, Color("fff5dc"), HORIZONTAL_ALIGNMENT_CENTER)
	_label("%d total fares · Driver level %d" % [model.jobs, model.level()], Rect2(44, 461, 452, 30), 18, MIST, HORIZONTAL_ALIGNMENT_CENTER)
	if int(last_receipt.get("level_bonus", 0)) > 0: _label("Level-up bonus: +%d coins" % last_receipt.level_bonus, Rect2(44, 504, 452, 28), 18, MINT, HORIZONTAL_ALIGNMENT_CENTER)
	_button("NEXT FARE →", Rect2(24, 579, 492, 62), func(): _show("dispatch"))
	_button("Sponsor next fare · +50% coins", Rect2(24, 662, 492, 58), func(): _request_boost(), true)
	_label("Optional rewarded ad. Your next fare stays available.", Rect2(30, 734, 480, 42), 15, MIST, HORIZONTAL_ALIGNMENT_CENTER)
	_button("Visit the garage", Rect2(24, 800, 492, 54), func(): _show("garage"), true)

func _garage() -> void:
	_header("THE GARAGE", "A cab with character. A little better every shift.")
	_texture(load("res://assets/taxi.png"), Rect2(219, 124, 104, 104))
	var upgrade_rows := [["engine", "Engine", "A quicker, smoother city cruise"], ["comfort", "Comfort", "+12% fare income per level"], ["radio", "Good company", "Extra rare-passenger tips"]]
	for index: int in range(upgrade_rows.size()):
		var entry: Array = upgrade_rows[index]
		var kind: String = entry[0]
		var y: float = 238 + index * 103
		_panel(Rect2(24, y, 492, 88), Color("1e3b50"), 14)
		_label("%s · %d / 5" % [entry[1], int(model.upgrades[kind])], Rect2(41, y + 10, 317, 28), 20, Color("fff5dc"))
		_label(entry[2], Rect2(41, y + 46, 322, 25), 13, MIST)
		var cost: int = model.upgrade_cost(kind)
		var upgrade_button: Button = _button("MAX" if cost < 0 else str(cost), Rect2(378, y + 18, 119, 52), func():
			if model.buy_upgrade(kind): _play("res://assets/audio/reward.ogg"); _sync_achievements(); _show("garage")
			else: _toast("A few more fares will cover that upgrade.")
		)
		upgrade_button.disabled = cost < 0 or model.coins < cost
	_label("YOUR NEXT COLOR", Rect2(26, 566, 490, 28), 14, MINT)
	for index: int in range(Model.CARS.size()):
		var car_data: Dictionary = Model.CARS[index]
		var x: float = 24 + index * 126
		_panel(Rect2(x, 610, 114, 165), Color(car_data.color).darkened(0.65), 14)
		_label("●", Rect2(x + 25, 612, 68, 48), 44, Color(car_data.color), HORIZONTAL_ALIGNMENT_CENTER)
		_label(car_data.name.replace(" ", "\n"), Rect2(x + 8, 664, 98, 47), 14, Color("fff5dc"), HORIZONTAL_ALIGNMENT_CENTER)
		var choice: int = index
		var label: String = "DRIVING" if model.car == index else ("SELECT" if index in model.owned_cars else str(car_data.price))
		var car_button: Button = _button(label, Rect2(x + 7, 724, 100, 35), func():
			if model.choose_car(choice): _sync_achievements(); _show("garage")
			else: _toast("Keep making the neighborhood smile.")
		, true)
		car_button.disabled = model.car == index
	_button("Back to the streets", Rect2(24, 809, 492, 53), func(): _show("drive"))

func _daily() -> void:
	model.roll_day(Time.get_date_string_from_system(true))
	_header("DAILY GOOD THINGS", "A few little goals. Plenty of room to ramble.")
	_panel(Rect2(24, 143, 492, 205), Color("264858"), 18)
	_label("A week around the block", Rect2(42, 162, 450, 32), 24, Color("fff5dc"))
	for index: int in range(7):
		var x: float = 42 + index * 65
		_panel(Rect2(x, 212, 56, 63), GOLD if index == model.login_streak - 1 else Color("355669"), 9)
		_label(str(index + 1), Rect2(x, 218, 56, 25), 20, INK if index == model.login_streak - 1 else Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		_label(str(Model.DAY_REWARDS[index]), Rect2(x, 246, 56, 21), 12, INK if index == model.login_streak - 1 else MIST, HORIZONTAL_ALIGNMENT_CENTER)
	var today: String = Time.get_date_string_from_system(true)
	var login_button: Button = _button("Collected today" if model.login_day >= today else "Collect today's welcome", Rect2(42, 291, 456, 41), func():
		var amount: int = model.claim_login(today)
		_show("daily")
		if amount > 0: _toast("Welcome back! +%d coins" % amount); _play("res://assets/audio/reward.ogg")
	)
	login_button.disabled = model.login_day >= today
	var quests: Array = model.quests()
	for index: int in range(quests.size()):
		var quest: Dictionary = quests[index]
		var y: float = 373 + index * 145
		_panel(Rect2(24, y, 492, 127), Color("1e3b50"), 14)
		_label(quest.title, Rect2(42, y + 14, 350, 30), 21, Color("fff5dc"))
		_label("%s · %d / %d" % [quest.detail, mini(int(quest.value), int(quest.goal)), quest.goal], Rect2(42, y + 49, 340, 27), 15, MIST)
		_progress(Rect2(42, y + 90, 300, 7), float(quest.value) / float(quest.goal), MINT)
		var claim: Button = _button("✓" if quest.key in model.daily_claimed else "+%d" % quest.reward, Rect2(371, y + 48, 124, 54), func():
			var amount: int = model.claim_quest(quest.key)
			_sync_achievements()
			_show("daily")
			if amount > 0: _toast("Quest complete! +%d coins" % amount); _play("res://assets/audio/reward.ogg")
		)
		claim.disabled = quest.key in model.daily_claimed or float(quest.value) < float(quest.goal)
	_label("Daily goals reset at 00:00 UTC. Progress saves locally.", Rect2(28, 823, 484, 36), 14, MIST, HORIZONTAL_ALIGNMENT_CENTER)

func _journal() -> void:
	_header("DRIVER JOURNAL", "%d passengers met  ·  %d special guests" % [model.passenger_journal.size(), model.rare_delivered])
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 142)
	scroll.size = Vector2(492, 703)
	page_content.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 478
	list.add_theme_constant_override("separation", 13)
	scroll.add_child(list)
	for entry: Dictionary in catalog.get("achievements", []):
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		card.custom_minimum_size = Vector2(478, 105)
		card.add_theme_stylebox_override("panel", _box(Color("264a54") if entry.key in model.unlocked else Color("1d394b"), 14))
		list.add_child(card)
		var text := Label.new()
		text.text = "%s  %s\n%s\n%d / %d" % ["★" if entry.key in model.unlocked else "○", entry.title, entry.description, mini(model.stat(entry.stat), int(entry.threshold)), int(entry.threshold)]
		text.add_theme_font_size_override("font_size", 16)
		text.add_theme_color_override("font_color", Color("fff5dc"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var margin := MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 15)
		margin.add_child(text)
		card.add_child(margin)
	_button("Play Games achievements", Rect2(190, 907, 327, 36), func(): _service_call("open_achievements"), true)

func _settings() -> void:
	_header("A COMFORTABLE RIDE", "Your cab, your company, your pace.")
	_panel(Rect2(24, 146, 492, 240), Color("1e3b50"), 18)
	_label("Around the neighborhood", Rect2(44, 168, 448, 38), 25, Color("fff5dc"))
	_label("Tap a street intersection to set a route.\nUse the four thumb buttons or arrow keys\nto take over. Pick up and drop off at the\nmarked curb. No fuel, damage or rush.", Rect2(44, 220, 448, 137), 19, MIST)
	_button("Sound: ON" if model.sound else "Sound: OFF", Rect2(24, 414, 492, 55), func():
		model.sound = not model.sound
		if model.sound: music.play()
		else: music.stop()
		_show("settings")
	, true)
	_button("Connect Play Games", Rect2(24, 493, 492, 55), func(): _service_call("sign_in"), true)
	_button("City miles leaderboard", Rect2(24, 572, 492, 55), func(): _service_call("open_leaderboards", ["taxi_distance"]), true)
	_button("Privacy options", Rect2(24, 651, 492, 55), func(): _service_call("privacy_options"), true)
	_label("Progress is saved on this device. Optional Google\nservices handle Android ads and online rankings.\nYou can keep driving offline.", Rect2(32, 742, 476, 94), 17, MIST, HORIZONTAL_ALIGNMENT_CENTER)

func _request_boost() -> void:
	if reward_pending: return
	var services: Node = _services()
	if services == null or not bool(services.call("can_reward")):
		_toast("No sponsor available. Your next fare is ready.")
		return
	reward_pending = true
	services.call("reward_requested", "next_fare_bonus", func(granted: bool):
		if not reward_pending: return
		reward_pending = false
		if granted:
			model.fare_boost = true
			_save()
			_toast("Your next fare earns 50% extra coins.")
		else: _toast("No reward earned. You can keep driving.")
	)

func _service_call(method: String, arguments: Array = []) -> void:
	var services: Node = _services()
	if services == null:
		_toast("This service is unavailable. Offline play is ready.")
		return
	services.callv(method, arguments)

func _services() -> Node:
	return get_node_or_null("/root/Services")

func _sync_achievements() -> void:
	var services: Node = _services()
	for entry: Dictionary in catalog.get("achievements", []):
		if model.stat(entry.stat) >= int(entry.threshold):
			if entry.key not in model.unlocked: model.unlocked.append(entry.key)
			if services != null: services.call("unlock", entry.key)
	if services != null:
		for board: Dictionary in catalog.get("leaderboards", []): services.call("submit", board.key, model.stat(board.stat))
	_save()

func _save() -> void:
	if demo: return
	var file := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(model.to_data()))
	file.close()
	var absolute: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH): DirAccess.copy_absolute(absolute, absolute + ".bak")
	DirAccess.rename_absolute(absolute + ".tmp", absolute)

func _load_save() -> void:
	for path: String in [SAVE_PATH, SAVE_PATH + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and model.from_data(parsed): return

func _demo_state() -> void:
	model.coins = 935
	model.xp = 1490
	model.jobs = 18
	model.income = 3260
	model.distance = 12620
	model.rare_delivered = 3
	model.daily_jobs = 2
	model.daily_distance = 1420
	model.login_streak = 3
	model.visits = {"Foundry": 5, "Central": 8, "Garden": 5}
	model.passenger_journal = ["Maya · baker", "Theo · gardener", "Luna · astronaut"]
	model.upgrades = {"engine": 2, "comfort": 1, "radio": 1}
	if boot_view == "drive":
		var job: Dictionary = model.make_job(2)
		job.pickup = 24
		job.destination = 40
		model.accept_job(job)
		model.pickup()
		travel_path = Model.route(24, 40)
		automatic = true
	if boot_view == "receipt": last_receipt = {"fare": 215, "passenger": "Luna · astronaut", "rare": true, "level_bonus": 140}

func _runtime_smoke() -> void:
	await get_tree().create_timer(0.25).timeout
	if screen != "drive": _show("drive")
	model.cancel_job()
	var job: Dictionary = model.make_job(0)
	job.pickup = model.player_node
	job.destination = (model.player_node + 1) % 49
	model.accept_job(job)
	_curb_action()
	await get_tree().create_timer(3.0).timeout
	if model.player_node != int(model.active_job.destination):
		push_error("Runtime smoke failed to follow a route")
		get_tree().quit(1)
		return
	_curb_action()
	if last_receipt.is_empty(): get_tree().quit(1); return
	print("PIXEL_TAXI_RUNTIME_OK: route, pickup, delivery and receipt completed")
	_stop_audio()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)

func _capture_after_frame() -> void:
	for index: int in range(12): await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		push_error("Screenshot capture requires an actual rendering display")
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(capture_path)
	print("PIXEL_TAXI_CAPTURE: ", capture_path, " result=", error)
	_stop_audio()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0 if error == OK else 1)

func _add_city(rect: Rect2, overview: bool) -> void:
	city = City.new()
	city.position = rect.position
	city.size = rect.size
	city.overview = overview
	city.vehicle = vehicle_position
	city.camera = Vector2(660, 660) if overview else vehicle_position
	city.taxi_color = Color(Model.CARS[model.car].color)
	page_content.add_child(city)
	if overview: city.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _play(path: String) -> void:
	if not model.sound or DisplayServer.get_name() == "headless" or not is_instance_valid(sfx) or not ResourceLoader.exists(path): return
	sfx.stream = load(path)
	sfx.volume_db = -10
	sfx.play()

func _toast(message: String) -> void:
	if not is_instance_valid(toast_label): return
	toast_label.text = message
	toast_label.visible = true
	toast_timer = 3.0

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style

func _panel(rect: Rect2, color: Color, radius: int) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box(color, radius))
	page_content.add_child(panel)
	return panel

func _label(text: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_content.add_child(label)
	return label

func _texture(texture: Texture2D, rect: Rect2) -> void:
	var display := TextureRect.new()
	display.position = rect.position
	display.size = rect.size
	display.texture = texture
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_content.add_child(display)

func _button(text: String, rect: Rect2, action: Callable, secondary: bool = false) -> Button:
	var button := Button.new()
	button.mouse_filter = Control.MOUSE_FILTER_PASS if screen != "drive" else Control.MOUSE_FILTER_STOP
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.add_theme_font_size_override("font_size", 17 if rect.size.y < 60 else 19)
	button.add_theme_color_override("font_color", Color("e8f2ed") if secondary else INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("718c9a"))
	button.add_theme_stylebox_override("normal", _box(Color("294a5e") if secondary else GOLD, 12))
	button.add_theme_stylebox_override("hover", _box(MINT, 12))
	button.add_theme_stylebox_override("pressed", _box(GOLD.darkened(0.15), 12))
	button.add_theme_stylebox_override("disabled", _box(Color("20394b"), 12))
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func(): _play("res://assets/audio/click.ogg"); action.call())
	page_content.add_child(button)
	return button

func _progress(rect: Rect2, value: float, color: Color) -> void:
	_panel(rect, Color("315064"), 4)
	var filled: Rect2 = rect
	filled.size.x *= clampf(value, 0, 1)
	if filled.size.x > 0: _panel(filled, color, 4)
