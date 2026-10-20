extends SceneTree

var responses: Array[bool] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var services := root.get_node("Services")
	await _test_embedded_window_scale(services)
	assert(services.menu_bottom_reserve() == 0.0, "Web/editor must retain their existing menu geometry")
	assert(services.menu_bottom_reserve(null) == 0.0, "Null reference is safe on non-Android")
	# Geometry-only calculations, not simulated native ads or a native-device pass.
	assert(services._menu_reserve_from_pixels(131, 126, 2.625, 1.8) == 161.0, "Actual phone pixel geometry requires 161 logical units")
	assert(services._menu_reserve_from_pixels(0, 126, 2.625, 1.8) == 161.0, "Unloaded banner must reserve its 50dp fallback")
	assert(services._menu_reserve_from_pixels(180, 126, 2.625, 1.8) == 188.0, "Larger measured native banner must increase reserve")
	assert(services._menu_reserve_from_pixels(-1, -1, 1, 2) == 31.0, "Invalid negative native sizes must stay conservative")
	assert(services._menu_reserve_from_pixels(50, 0, 1, 0) == 62.0, "Uninitialized scale must avoid division by zero")
	assert(services._menu_safe_bottom_pixels(1731, 1731, 1668, 1668, 2.625, false) == 126.0, "Underreported Android safe inset retains the navigation floor")
	assert(services._menu_safe_bottom_pixels(1920, 1920, 0, 0, 2.625, false) == 126.0, "Unknown safe area must not reserve the whole window")
	assert(services._menu_safe_bottom_pixels(1920, 1920, 1920, 1920, 2.625, true) == 0.0, "Known immersive safe area requires no navigation floor")
	assert(not services.can_reward(), "Editor/headless must not grant simulated ad rewards")
	services.reward_requested("smoke", func(granted: bool) -> void: responses.append(granted))
	await process_frame
	await process_frame
	assert(responses == [false], "Unavailable ad must deliver exactly one unsuccessful callback")
	services.set_menu_visible(false)
	services.round_finished()
	services.round_finished()
	assert(not services.can_reward(), "Round completion must not fabricate a rewarded entitlement")
	services.set_menu_visible(true)
	_test_reward_callback_contract(services)
	print("SERVICES_SMOKE_PASS: menu pixel/safe-area geometry and local fallbacks safe; reward callbacks settle once")
	quit(0)

func _test_embedded_window_scale(services: Node) -> void:
	# Real headless Window/Control transforms reproduce the native scale bug;
	# no ad callbacks or Android device behavior are simulated by this test.
	var old_size := root.size
	var old_mode := root.content_scale_mode
	var old_aspect := root.content_scale_aspect
	var old_content_size := root.content_scale_size
	var old_embed := root.gui_embed_subwindows
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(540, 960)
	root.gui_embed_subwindows = true
	root.size = Vector2i(1080, 1731)
	var reference := Control.new()
	root.add_child(reference)
	await process_frame
	await process_frame
	var pixels_per_unit: float = services._menu_pixels_per_unit(reference)
	var popup_scale := reference.get_screen_transform().y.length()
	assert(is_equal_approx(pixels_per_unit, 1.803125), "Viewport stretch must contribute to physical pixel scale")
	assert(is_equal_approx(popup_scale, 1.0), "Embedded-window popup scale reproduces the prior missing-stretch bug")
	assert(services._menu_reserve_from_pixels(0, 126, 2.625, pixels_per_unit) == 161.0, "Native geometry must reserve 161 local units")
	assert(services._menu_reserve_from_pixels(0, 126, 2.625, popup_scale) == 289.0, "Prior popup scale incorrectly reserved 289 local units")
	reference.scale = Vector2(1.0, 0.8)
	await process_frame
	assert(is_equal_approx(float(services._menu_pixels_per_unit(reference)), 1.4425), "A stable child-stage scale must be included once")
	root.remove_child(reference)
	reference.queue_free()
	root.content_scale_mode = old_mode
	root.content_scale_aspect = old_aspect
	root.content_scale_size = old_content_size
	root.gui_embed_subwindows = old_embed
	root.size = old_size
	print("EMBEDDED_WINDOW_SCALE_PASS: 1080x1731/540x960 scale1.803125 reserve161; prior popup scale1 reserve289")

func _test_reward_callback_contract(services: Node) -> void:
	# Invoke callback handlers directly; no test object can load or show a native ad.
	responses.clear()
	services.set("_reward_callback", func(granted: bool) -> void: responses.append(granted))
	services.set("_reward_granted", false)
	services.set("_reward_showing", true)
	services.call("_earned_reward", null)
	services.call("_earned_reward", null)
	services.call("_rewarded_closed")
	assert(responses == [true], "An earned reward must settle once, including duplicate callback and dismissal")
	assert(not services.can_reward(), "Dismissal must not leave a rewarded ad reusable")
	responses.clear()
	services.set("_reward_callback", func(granted: bool) -> void: responses.append(granted))
	services.set("_reward_granted", false)
	services.set("_reward_showing", true)
	services.call("_rewarded_closed")
	services.call("_rewarded_closed")
	services.call("_earned_reward", null)
	assert(responses == [false], "Dismissal/show failure must settle false once and ignore a late earned callback")
