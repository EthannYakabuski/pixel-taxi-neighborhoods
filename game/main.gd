extends Control

const Model = preload("res://game/model.gd")
const AtomicSave = preload("res://game/atomic_save.gd")
const City = preload("res://game/city.gd")
const Graph = preload("res://game/city_graph.gd")
const INK := Color("102638")
const MIST := Color("b9d1da")
const GOLD := Color("ffc857")
const MINT := Color("79d5bd")
const SAVE_PATH := "user://neighborhoods_v1.json"

var model = Model.new()
var save_store = AtomicSave.new(SAVE_PATH)
var stage: Control
var page_content: Control
var menu_scroll: ScrollContainer
var city: Control
var screen: String = "home"
var vehicle_position := Vector2(660, 660)
var vehicle_heading: float = 0.0
var travel_path: Array[int] = []
var held_direction := Vector2i.ZERO
var automatic: bool = false # Compatibility field; navigation never drives the car.
var turn_input := 0.0
var gas_held := false
var brake_held := false
var reverse_held := false
const PAD_REVERSE_START := 32.0
const PAD_REVERSE_RELEASE := 16.0
# Touch indices and the physical mouse (-1) own their holds independently.
var _drive_pointers: Dictionary = {}
var nav_node := -1
var nav_goal := -1
var nav_timer := 0.0
var navigation: Dictionary = {}
var application_suspended := false
var service_was_covering := false
var resume_required := false
var discard_frame := false
var _audio_shutting_down := false
var pulse_timer: float = 0.0
var autosave_timer: float = 0.0
var toast_timer: float = 0.0
var toast_label: Label
var coins_label: Label
var info_label: Label
var action_button: Button
var fare_card: Panel
var fare_card_mode := ""
var progress_label: Label
var catalog: Dictionary = {}
var last_receipt: Dictionary = {}
var sfx: AudioStreamPlayer
var music: AudioStreamPlayer
var capture_path: String = ""
var demo: bool = false
var runtime_smoke: bool = false
var reward_pending: bool = false
var reward_request_serial: int = 0
var boot_view: String = "home"

func _ready() -> void:
	get_tree().auto_accept_quit = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--view="): boot_view = argument.trim_prefix("--view=")
		if argument == "--demo": demo = true
		if argument == "--runtime-smoke": runtime_smoke = true
	if not demo: _load_save()
	if demo: _demo_state()
	vehicle_position = model.driving_position
	vehicle_heading = model.driving_heading
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
	if what == NOTIFICATION_APPLICATION_PAUSED:
		application_suspended = true
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		resume_required = screen == "drive"
		_set_parked()
	if what == NOTIFICATION_APPLICATION_RESUMED:
		application_suspended = false
		discard_frame = true
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _quit_cleanly()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen != "home": _show("home")

func _exit_tree() -> void:
	reward_pending = false
	reward_request_serial += 1
	_clear_drive_inputs()
	_stop_audio()

func _stop_audio() -> void:
	_audio_shutting_down = true
	if is_instance_valid(music):
		music.stop()
		music.stream = null
	if is_instance_valid(sfx):
		sfx.stop()
		sfx.stream = null

func _process(delta: float) -> void:
	var services := _services()
	var covered := application_suspended or (is_instance_valid(services) and services.has_method("is_gameplay_blocked") and bool(services.call("is_gameplay_blocked")))
	if covered:
		service_was_covering = true
		resume_required = screen == "drive"
		_set_parked()
	if service_was_covering and not covered:
		service_was_covering = false
		discard_frame = true
	if discard_frame:
		delta = 0
		discard_frame = false
	delta = clampf(delta,0.0,0.08)
	if toast_timer > 0:
		toast_timer -= delta
		if is_instance_valid(toast_label): toast_label.visible = toast_timer > 0
	if screen == "drive" and is_instance_valid(city) and is_instance_valid(city.world):
		var world = city.world
		world.enabled = not _drive_input_blocked()
		world.presentation_paused = covered or resume_required
		world.set_passenger(model.active_job)
		var turn := turn_input
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A): turn -= 1.0
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D): turn += 1.0
		var accelerator := 1.0 if gas_held or Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W) else 0.0
		if reverse_held or Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S): accelerator = -1.0
		world.max_speed = 14.0 + float(model.upgrades.engine)*1.8
		world.set_controls(turn,accelerator,brake_held or Input.is_physical_key_pressed(KEY_SPACE))
		_remember_pose()
		if world.enabled: model.tick_fare(delta)
		var nearest := Graph.nearest_node(vehicle_position)
		model.player_node = nearest
		var goal := model.objective() if not model.active_job.is_empty() else -1
		nav_timer -= delta
		if nearest != nav_node or goal != nav_goal or nav_timer <= 0:
			nav_timer = 0.4
			nav_node = nearest
			nav_goal = goal
			navigation = Graph.guidance(vehicle_position,goal) if goal >= 0 else {}
			travel_path.assign(navigation.get("route",[]))
			city.guidance = navigation
			city.route_nodes = travel_path
		city.objective_node = goal
		city.pickup_mode = not bool(model.active_job.get("picked_up",false))
	pulse_timer += delta
	autosave_timer += delta
	if pulse_timer > 0.25:
		pulse_timer = 0
		if screen == "drive": _refresh_drive()
	if autosave_timer > 8:
		autosave_timer = 0
		model.roll_day(Time.get_date_string_from_system(true))
		_save()

func _remember_pose() -> void:
	if is_instance_valid(city) and is_instance_valid(city.world) and screen == "drive":
		vehicle_position = city.world.graph_position()
		vehicle_heading = city.world.yaw
		model.driving_position = vehicle_position
		model.driving_heading = vehicle_heading

func _clear_drive_inputs() -> void:
	_drive_pointers.clear()
	gas_held = false
	turn_input = 0
	brake_held = false
	reverse_held = false

func _set_parked() -> void:
	_clear_drive_inputs()
	if is_instance_valid(city) and is_instance_valid(city.world):
		city.world.set_controls(0,0,true)
		city.world.current_speed = 0
		city.world.enabled = false

func _resume_driving() -> void:
	resume_required = false
	discard_frame = true
	_refresh_drive()

func _drive_distance(metres: float) -> void:
	if screen != "drive" or resume_required or application_suspended: return
	model.travel(metres)

func _drive_impact(_speed: float) -> void:
	model.note_collision()
	_play("res://assets/audio/click.ogg")
	_toast("Bump! Slow down — a clean ride earns a better tip.")
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
	if is_instance_valid(toast_label): toast_label.position.y = 221.0 if screen == "drive" else minf(875.0, menu_scroll.size.y - 60.0)


func _show(view: String) -> void:
	# Fare dispatch and receipts share the persistent city, never a full-screen page.
	if view in ["dispatch","receipt"]: view = "drive"
	_remember_pose()
	_set_parked()
	screen = view
	nav_node = -1
	nav_goal = -1
	resume_required = false
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
	fare_card = null
	fare_card_mode = ""
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
	toast_label = _label("", Rect2(28, 221 if screen == "drive" else 875, 484, 45), 16, Color("102638"), HORIZONTAL_ALIGNMENT_CENTER)
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
	coins_label = _label("Save pending" if model.has_unsaved_fare() else "%d coins" % model.coins, Rect2(365, 30, 150, 28), 19, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	_panel(Rect2(24, 108, 492, 4), Color("315064"), 2)
	if screen != "home" and screen != "drive": _button("‹ Home", Rect2(24, 907, 120, 36), func(): _show("home"), true)

func _home() -> void:
	_header("PIXEL TAXI", "NEIGHBORHOODS  ·  TAKE THE SCENIC FARE")
	_panel(Rect2(22, 129, 496, 362), Color("b8cfc2"), 22)
	_add_city(Rect2(30, 154, 480, 305), true)
	_label("A little city. A lot of stories.", Rect2(24, 506, 492, 38), 25, Color("fff5dc"), HORIZONTAL_ALIGNMENT_CENTER)
	_label("Driver level %d  ·  %d fares  ·  %.1f km" % [model.level(), model.jobs, model.distance / 1000], Rect2(24, 547, 492, 28), 16, MIST, HORIZONTAL_ALIGNMENT_CENTER)
	_progress(Rect2(42, 587, 456, 7), model.level_progress(), MINT)
	_button("SAVE COMPLETED FARE" if model.has_unsaved_fare() else "CONTINUE FARE" if not model.active_job.is_empty() else "START YOUR SHIFT", Rect2(24, 621, 492, 62), func(): _show("drive"))
	_button("Garage & upgrades", Rect2(24, 704, 238, 59), func(): _show("garage"), true)
	_button("Daily rewards", Rect2(278, 704, 238, 59), func(): _show("daily"), true)
	_button("Driver journal", Rect2(24, 779, 238, 56), func(): _show("journal"), true)
	_button("Sound & services", Rect2(278, 779, 238, 56), func(): _show("settings"), true)
	_label("Kind passengers. Open streets. Your own pace.", Rect2(24, 849, 492, 26), 14, MIST, HORIZONTAL_ALIGNMENT_CENTER)
	# Bottom 56 px intentionally reserved for the native menu banner.
	_panel(Rect2(0, 904, 540, 56), Color("0c1e2c"), 0)

func _dispatch() -> void:
	# Compatibility for older callers; this is an in-scene card.
	_open_fare_card("active" if not model.active_job.is_empty() else "offer")

func _open_fare_card(mode: String) -> void:
	if screen != "drive" or reward_pending: return
	if model.has_pending_double_reward() or model.has_unsaved_fare(): mode = "receipt"
	_set_parked()
	fare_card_mode = mode
	if is_instance_valid(fare_card):
		fare_card.hide()
		fare_card.queue_free()
	fare_card = _panel(Rect2(18,270,504,400),Color("152f41"),20)
	fare_card.name = "InSceneFareCard"
	# Build in page coordinates, then reparent into the contained card.
	var before := page_content.get_children()
	if mode == "receipt":
		var receipt: Dictionary = model.last_receipt
		_label("FARE AWAITING SAVE" if model.has_unsaved_fare() else "FARE COMPLETE  +%d coins" % int(receipt.get("fare",0)),Rect2(36,286,468,38),25,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
		_label(str(receipt.get("passenger","Thanks for the ride!")),Rect2(36,329,468,30),18,Color.WHITE,HORIZONTAL_ALIGNMENT_CENTER)
		_label("Tip +%d  |  %s" % [int(receipt.get("tip",0)),str(receipt.get("tip_reason",""))],Rect2(36,365,468,48),14,MIST,HORIZONTAL_ALIGNMENT_CENTER)
		var reward_text := "Retry saving completed fare" if model.has_unsaved_fare() else "Retry saving earned reward" if model.has_pending_double_reward() else "2x received" if not model.can_double_last_fare() else "Watch ad: 2x fare (+%d)" % int(receipt.get("fare",0))
		var reward := _button(reward_text,Rect2(36,423,468,58),_request_completed_bonus,true)
		reward.name = "DoubleCompletedFare"
		reward.disabled = reward_pending or not model.can_double_last_fare()
		var next := _button("NEXT FARE",Rect2(36,496,468,58),_next_fare)
		next.name = "NextFare"
		next.disabled = model.has_pending_double_reward() or model.has_unsaved_fare()
		_label("Coins/XP not saved. Keep app open and retry." if model.has_unsaved_fare() else "Earned reward not saved. Keep this app open; retry." if model.has_pending_double_reward() else "Optional ad. Your fare is already safely banked.",Rect2(36,570,468,36),14,MIST,HORIZONTAL_ALIGNMENT_CENTER)
	elif mode == "active":
		_label("CURRENT FARE",Rect2(36,298,468,38),26,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
		_label(str(model.active_job.get("passenger","")),Rect2(36,351,468,38),21,Color.WHITE,HORIZONTAL_ALIGNMENT_CENTER)
		_label("Follow the gold route and brake at the curb.",Rect2(36,401,468,42),16,MIST,HORIZONTAL_ALIGNMENT_CENTER)
		_button("BACK TO DRIVING",Rect2(36,468,468,58),_close_fare_card).name = "CloseFareCard"
		_button("Cancel fare",Rect2(36,548,468,50),func(): model.cancel_job();travel_path.clear();_save();_open_fare_card("offer"),true)
	else:
		var job: Dictionary = model.current_offer()
		_label("INCOMING FARE" if not bool(job.rare) else "SPECIAL GUEST",Rect2(36,286,468,34),24,GOLD,HORIZONTAL_ALIGNMENT_CENTER)
		_label(str(job.passenger),Rect2(36,332,468,38),22,Color.WHITE,HORIZONTAL_ALIGNMENT_CENTER)
		_label("%s to %s\n%.1f km  |  %d+ coins + clean-ride tip" % [Model.district(int(job.pickup)),Model.district(int(job.destination)),float(job.metres)/1000,int(job.base_fare)],Rect2(36,380,468,66),17,MIST,HORIZONTAL_ALIGNMENT_CENTER)
		_button("ACCEPT FARE",Rect2(36,465,468,58),func():
			if model.accept_job(job):
				travel_path.clear()
				_close_fare_card()
				_save()
		).name = "AcceptFare"
		_button("Decline - next offer",Rect2(36,541,468,54),func(): model.decline_offer();_save();_open_fare_card("offer"),true).name = "DeclineFare"
		_button("Free drive",Rect2(160,602,220,50),_close_fare_card,true)
	for node: Node in page_content.get_children():
		if node not in before:
			node.reparent(fare_card,false)
			if node is Control: node.position -= fare_card.position
	_refresh_drive()

func _close_fare_card() -> void:
	if reward_pending or model.has_pending_double_reward() or model.has_unsaved_fare(): return
	if is_instance_valid(fare_card):
		fare_card.hide()
		fare_card.queue_free()
	fare_card = null
	fare_card_mode = ""
	_clear_drive_inputs()
	discard_frame = true
	_refresh_drive()

func _next_fare() -> void:
	if reward_pending or model.has_pending_double_reward() or model.has_unsaved_fare(): return
	var was_open: bool = model.receipt_open
	model.acknowledge_receipt()
	if not _save():
		model.receipt_open = was_open
		_open_fare_card("receipt")
		_toast("Cannot save next fare. Keep this receipt and retry.")
		return
	if model.active_job.is_empty(): _open_fare_card("offer")
	else: _close_fare_card()

func _drive() -> void:
	_add_city(Rect2(0,112,540,788),false)
	_header("YOUR CITY, YOUR WHEEL", "MANUAL DRIVE · LEVEL %d" % model.level())
	_panel(Rect2(18,128,504,84),Color("1e3b50"),17)
	info_label = _label("",Rect2(32,137,476,66),17,Color("fff5dc"))
	action_button = _button("",Rect2(18,689,504,58),_curb_action)
	var left := _button("◀",Rect2(18,772,86,80),func(): pass,true)
	_bind_drive_control(left,"left")
	var right := _button("▶",Rect2(112,772,86,80),func(): pass,true)
	_bind_drive_control(right,"right")
	var pedal := _button("HOLD / DRAG\nDOWN: REVERSE",Rect2(208,772,202,80),func(): pass)
	_bind_drive_control(pedal,"pad")
	var stop := _button("BRAKE",Rect2(420,772,102,80),func(): pass,true)
	_bind_drive_control(stop,"brake")
	_panel(Rect2(8,854,524,38),INK,8)
	_label("Drag left/right to steer; drag down to reverse.",Rect2(18,858,504,30),14,MIST,HORIZONTAL_ALIGNMENT_CENTER)
	_button("Fare",Rect2(24,907,123,36),func(): _open_fare_card("active" if not model.active_job.is_empty() else "receipt" if model.receipt_open else "offer"),true)
	_button("Map",Rect2(162,907,102,36),func(): city.overview=not city.overview,true)
	var reverse := _button("Reverse",Rect2(279,907,113,36),func(): pass,true)
	_bind_drive_control(reverse,"reverse")
	_button("Home",Rect2(407,907,110,36),func(): _show("home"),true)
	_refresh_drive()
	if model.receipt_open or model.has_pending_double_reward() or model.has_unsaved_fare(): _open_fare_card("receipt")
	elif model.active_job.is_empty(): _open_fare_card("offer")

func _bind_drive_control(button: Button, action: String) -> void:
	button.name = "Drive_"+action
	# BaseButton's mouse-only down/up signals cannot identify separate fingers.
	button.gui_input.connect(_drive_control_event.bind(action,button))

func _drive_input_blocked() -> bool:
	if screen != "drive" or application_suspended or resume_required or reward_pending or model.has_pending_double_reward() or model.has_unsaved_fare() or (is_instance_valid(fare_card) and fare_card.visible): return true
	var services := _services()
	return is_instance_valid(services) and services.has_method("is_gameplay_blocked") and bool(services.call("is_gameplay_blocked"))

func _drive_control_event(event: InputEvent, action: String, button: Control) -> void:
	# Late events from a hidden/queued previous page cannot own the new controls.
	if button.get_parent() != page_content or not button.is_visible_in_tree(): return
	# Android sends both native touch and emulated mouse events. Only native touch
	# owns that finger; duplicate mouse releases must not clear another hold.
	if event.device == InputEvent.DEVICE_ID_EMULATION: return
	var pointer := -1
	var position := Vector2.ZERO
	var pressed := false
	var released := false
	if event is InputEventScreenTouch:
		pointer = event.index
		position = event.position
		pressed = event.pressed and not event.canceled
		released = not pressed
	elif event is InputEventScreenDrag:
		pointer = event.index
		position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		position = event.position
		pressed = event.pressed and not event.canceled
		released = not pressed
	elif event is InputEventMouseMotion:
		position = event.position
		released = (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0
	else:
		return
	if pressed:
		if _drive_input_blocked() or not Rect2(Vector2.ZERO,button.size).has_point(position): return
		if _drive_pointers.has(pointer): return
		if action == "pad":
			for held: Dictionary in _drive_pointers.values():
				if held.action == "pad": return
		_drive_pointers[pointer] = {"action":action,"anchor":position,"position":position,"reverse":false}
	else:
		if not _drive_pointers.has(pointer) or _drive_pointers[pointer].action != action: return
		if released or _drive_input_blocked():
			_drive_pointers.erase(pointer)
		elif action == "pad":
			var held: Dictionary = _drive_pointers[pointer]
			held.position = position
			var down: float = position.y-held.anchor.y
			# Deliberate pull-down selects reverse; hysteresis prevents jitter at
			# its boundary. Returning near the press height selects forward again.
			if down >= PAD_REVERSE_START: held.reverse = true
			elif down <= PAD_REVERSE_RELEASE: held.reverse = false
	_update_drive_inputs()

func _update_drive_inputs() -> void:
	gas_held = false
	reverse_held = false
	brake_held = false
	turn_input = 0.0
	for held: Dictionary in _drive_pointers.values():
		match held.action:
			"left": turn_input -= 1.0
			"right": turn_input += 1.0
			"brake": brake_held = true
			"reverse": reverse_held = true
			"pad":
				gas_held = gas_held or not held.reverse
				reverse_held = reverse_held or held.reverse
				turn_input += clampf((held.position.x-held.anchor.x)/72.0,-1.0,1.0)
	turn_input = clampf(turn_input,-1.0,1.0)

func _refresh_drive() -> void:
	if not is_instance_valid(info_label): return
	var speed := absf(city.world.current_speed) if is_instance_valid(city) and is_instance_valid(city.world) else 0.0
	if resume_required:
		info_label.text = "Drive paused while the app was covered.\nYour position and fare are safe."
		action_button.text = "Resume driving"
		action_button.disabled = false
		return
	if is_instance_valid(fare_card) and fare_card.visible:
		info_label.text = "Cab parked safely.\nYour next journey starts right here."
		action_button.text = "Choose an action on the fare card"
		action_button.disabled = true
		if is_instance_valid(coins_label): coins_label.text = "Save pending" if model.has_unsaved_fare() else "%d coins" % model.coins
		return
	if model.active_job.is_empty():
		info_label.text = "%s · %d km/h\nFree drive — choose a dispatch when ready." % [Model.district(model.player_node),int(speed*3.6)]
		action_button.text = "Find a passenger"
		action_button.disabled = false
	else:
		var pickup := not bool(model.active_job.picked_up)
		var gap := vehicle_position.distance_to(Model.point(model.objective()))*0.45
		var cue := "ARRIVE AT THE GOLD CURB" if gap < 18 else _navigation_cue()
		info_label.text = "%s %s · %d km/h\n%s · Curb: %dm direct" % ["Pick up" if pickup else "Deliver",str(model.active_job.passenger).split(" ")[0],int(speed*3.6),cue,int(gap)]
		var at_curb := gap < 10.0 and speed < 1.6
		action_button.text = ("Pick up passenger" if pickup else "Complete fare") if at_curb else "Brake at the gold passenger curb"
		action_button.disabled = not at_curb
	if is_instance_valid(coins_label): coins_label.text = "Save pending" if model.has_unsaved_fare() else "%d coins" % model.coins

func _navigation_cue() -> String:
	# This describes alignment with the occupied road, not a future junction.
	# Match the actual world's existing off-street grass slow-down boundary.
	if float(navigation.get("distance_to_road",0.0))*City.World.WORLD_SCALE > 6.0:
		return "Return to gold route"
	if travel_path.is_empty(): return "Follow gold line"
	var next := Model.point(travel_path[0])
	var direction := (next-vehicle_position).normalized()
	var desired: float = float(navigation.get("bearing",atan2(direction.x,direction.y)))
	var angle := wrapf(desired-vehicle_heading,-PI,PI)
	if angle < -0.35: return "Align RIGHT with gold line"
	if angle > 0.35: return "Align LEFT with gold line"
	return "Follow gold line"

func _route_to(goal: int) -> void:
	if screen != "drive": return
	# Informational only: no route waypoint ever changes throttle or steering.
	navigation = Graph.guidance(vehicle_position,goal)
	travel_path.assign(navigation.get("route",[]))
	if is_instance_valid(city): city.guidance=navigation;city.route_nodes=travel_path
	_toast("GPS recalculated. You stay at the wheel.")

func _manual_step(direction: Vector2i) -> void:
	turn_input = float(direction.x)

func _curb_action() -> void:
	if resume_required: _resume_driving();return
	if _drive_input_blocked(): return
	if model.active_job.is_empty(): _open_fare_card("offer");return
	_remember_pose()
	if vehicle_position.distance_to(Model.point(model.objective()))*0.45 >= 10.0: return
	if is_instance_valid(city) and absf(city.world.current_speed) >= 1.6: return
	model.player_node = model.objective()
	if not bool(model.active_job.picked_up):
		if model.pickup():
			_play("res://assets/audio/arrival.ogg")
			_route_to(model.objective())
			_toast("Welcome aboard. A prompt, clean ride earns a tip.")
	else:
		var completed_passenger: Dictionary = model.active_job.duplicate(true)
		last_receipt = model.complete_job()
		if not last_receipt.is_empty():
			city.world.passenger_departed(completed_passenger)
			_retry_completed_fare_save()
			_open_fare_card("receipt")
			_refresh_drive()
			return
	_save()
	_refresh_drive()

func _receipt() -> void:
	_open_fare_card("receipt")

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
	_label("Hold & drag: left/right steers; down reverses.\nGPS guides; it never drives the cab.\nBrake at gold curbs, or hold Reverse + steering.\nCollisions slow you and remove clean tips.\nPrompt, collision-free fares can earn a tip.", Rect2(44, 220, 448, 137), 19, MIST)
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

func _retry_completed_fare_save() -> bool:
	if reward_pending or not model.has_unsaved_fare(): return false
	_set_parked()
	var notify := not bool(model.last_receipt.get("round_notified",false))
	model.last_receipt.bank_saved = true
	model.last_receipt.round_notified = true
	if not _save():
		model.last_receipt.bank_saved = false
		model.last_receipt.round_notified = not notify
		if screen == "drive": _open_fare_card("receipt")
		_toast("Fare not saved. Keep app open and tap Retry save.")
		return false
	# The exact completion/XP calculation happened once at the curb. Retry
	# only confirms the held state; cadence is notified once after that save.
	if notify:
		_play("res://assets/audio/reward.ogg")
		_sync_achievements()
		var services := _services()
		if services != null: services.call("round_finished")
	if screen == "drive": _open_fare_card("receipt")
	return true

func _request_completed_bonus() -> void:
	if reward_pending: return
	if model.has_unsaved_fare():
		_retry_completed_fare_save()
		return
	if model.has_pending_double_reward():
		_retry_earned_reward_save()
		return
	if not model.can_double_last_fare(): return
	var services: Node = _services()
	if services == null or not bool(services.call("can_reward")):
		_toast("No ad available. Your completed fare stays banked.")
		return
	var receipt_id: int = int(model.last_receipt.id)
	if not model.begin_double_request(receipt_id): return
	# Save the original paid fare and request-only marker before opening an ad.
	if not _save():
		model.cancel_double_request(receipt_id)
		_toast("Cannot save progress. No ad opened; free space and retry.")
		return
	reward_request_serial += 1
	var request_serial := reward_request_serial
	reward_pending = true
	_set_parked()
	services.call("reward_requested", "completed_fare_%d" % receipt_id, func(granted: bool):
		if not reward_pending or request_serial != reward_request_serial: return
		reward_pending = false
		if granted and model.mark_double_earned(receipt_id):
			_retry_earned_reward_save()
		else:
			model.cancel_double_request(receipt_id)
			var saved := _save()
			if screen == "drive": _open_fare_card("receipt")
			_toast("No extra reward. Your fare is safe." if saved else "No extra reward. Progress could not be saved.")
	)

func _retry_earned_reward_save() -> bool:
	if reward_pending or not model.has_pending_double_reward(): return false
	_set_parked()
	# First journal the actual-earned entitlement. If the later credit write
	# fails, a cold load can still retry without asking for another ad.
	if not _save():
		_reward_save_failed()
		return false
	var receipt_id: int = int(model.last_receipt.id)
	var coins_before: int = model.coins
	var income_before: int = model.income
	var extra: int = model.double_last_fare(receipt_id)
	if extra <= 0: return false
	if not _save():
		model.coins = coins_before
		model.income = income_before
		model.last_receipt.double_claimed = false
		model.last_receipt.reward_state = "earned"
		_reward_save_failed()
		return false
	_sync_achievements()
	if screen == "drive": _open_fare_card("receipt")
	_toast("Fare doubled and saved: +%d coins." % extra)
	return true

func _reward_save_failed() -> void:
	if screen == "drive": _open_fare_card("receipt")
	_toast("Earned reward not saved. Keep app open and tap Retry save.")

func _service_call(method: String, arguments: Array = []) -> void:
	var services: Node = _services()
	if services == null:
		_toast("This service is unavailable. Offline play is ready.")
		return
	services.callv(method, arguments)

func _services() -> Node:
	return get_node_or_null("/root/Services")

func _sync_achievements() -> void:
	if model.has_unsaved_fare(): return # Never publish tentative fare/XP/income after a failed write.
	var services: Node = _services()
	for entry: Dictionary in catalog.get("achievements", []):
		if model.stat(entry.stat) >= int(entry.threshold):
			if entry.key not in model.unlocked: model.unlocked.append(entry.key)
			if services != null: services.call("unlock", entry.key)
	if services != null:
		for board: Dictionary in catalog.get("leaderboards", []): services.call("submit", board.key, model.stat(board.stat))
	_save()

func _save() -> bool:
	_remember_pose()
	if demo: return true # Isolated presentation/test fixtures never write profiles.
	return save_store.write(model.to_data())

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
		automatic = false
	if boot_view == "receipt": last_receipt = {"fare": 215, "passenger": "Luna · astronaut", "rare": true, "level_bonus": 140}

func _runtime_smoke() -> void:
	# Synthetic keyboard-equivalent throttle: GPS alone must never move the car.
	await get_tree().create_timer(0.25).timeout
	if screen != "drive": _show("drive")
	_close_fare_card() # This isolated smoke fixture explicitly chooses free drive.
	var before := vehicle_position
	_route_to(32)
	await get_tree().create_timer(0.25).timeout
	assert(vehicle_position.distance_to(before)<0.5,"GPS must not auto-drive")
	gas_held = true
	await get_tree().create_timer(1.0).timeout
	gas_held = false
	assert(vehicle_position.distance_to(before)>1.0,"Manual throttle must move actual car")
	print("PIXEL_TAXI_RUNTIME_OK: actual3D manual throttle, GPS never auto-drives")
	_quit_cleanly()

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
	city.overview = false # Home is a close 3D car portrait; Map is explicit during driving.
	city.vehicle = vehicle_position
	city.heading = vehicle_heading
	city.selected_car = model.car
	city.driving = not overview
	page_content.add_child(city)
	if not overview:
		city.world.gameplay_guard = func():
			return not _drive_input_blocked()
		city.world.travelled.connect(_drive_distance)
		city.world.impact.connect(_drive_impact)
	else:
		city.world.camera3d.position = city.world.player.position+Vector3(-4.2,2.5,4.8)
		city.world.camera3d.v_offset = 0.0
		city.world.camera3d.look_at(city.world.player.position+Vector3(0,0.65,0))
		city.world.set_physics_process(false)

func _play(path: String) -> void:
	if _audio_shutting_down or not model.sound or DisplayServer.get_name() == "headless" or not is_instance_valid(sfx) or not ResourceLoader.exists(path): return
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

func _quit_cleanly() -> void:
	set_process(false)
	_set_parked()
	_save()
	_audio_shutting_down = true
	await get_tree().create_timer(0.15,true,false,true).timeout
	_stop_audio()
	await get_tree().create_timer(0.25,true,false,true).timeout
	get_tree().quit()
