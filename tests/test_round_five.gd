extends SceneTree
## Isolated source/scene fixtures; not native driving, ad or real payout evidence.
const Model = preload("res://game/model.gd")
var checks := 0
var failures := 0

class ServicesFixture extends Node:
	var home_visible := false
	var drive_visible := false
	var covered := false
	var completed: Array[int] = []
	func set_menu_visible(value: bool) -> void: home_visible = value
	func set_driving_visible(value: bool) -> void: drive_visible = value
	func menu_bottom_reserve(_reference) -> float: return 100.0 if home_visible else 0.0
	func driving_top_reserve(_reference) -> float: return 126.0 if drive_visible else 0.0
	func driving_bottom_reserve(_reference) -> float: return 87.0 if drive_visible else 0.0
	func unlock(_key: String) -> void: pass
	func submit(_key: String, _value: int) -> void: pass
	func fare_finished(total: int) -> void: completed.append(total)
	func is_gameplay_blocked() -> bool: return covered
	func can_reward() -> bool: return false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func complete_fixture(model) -> Dictionary:
	var offer: Dictionary = model.current_offer()
	check(model.accept_job(offer), "available offer can be explicitly accepted")
	model.player_node = int(offer.pickup)
	check(model.pickup(), "source fixture pickup succeeds")
	model.tick_fare(8.0)
	model.travel(float(model.active_job.metres))
	model.player_node = int(offer.destination)
	return model.complete_job()

func run() -> void:
	var expected := OS.get_environment("DOTS_TEST_ROOT").replace("\\", "/").trim_suffix("/")
	var actual := OS.get_user_data_dir().replace("\\", "/")
	if expected.is_empty() or not actual.begins_with(expected + "/") or OS.get_name() == "Android":
		push_error("Round Five fixtures require a disposable DOTS_TEST_ROOT containing the actual user data directory")
		quit(2)
		return
	var model = Model.new("2026-10-29")
	for index: int in range(1,33):
		var receipt := complete_fixture(model)
		var bank: int = model.coins
		var wait: float = model.dispatch_wait_remaining
		check(wait >= 5.0 and wait <= 20.0, "every completion waits five to twenty active seconds")
		check(model.current_offer().is_empty() and not model.accept_job(model.make_job(0)), "no offer or auto-accept during free drive")
		check(not model.tick_dispatch(50.0) and model.dispatch_wait_remaining == wait, "unconfirmed fare cannot advance dispatch")
		model.last_receipt.bank_saved = true # Only this isolated fixture confirms its simulated transaction.
		model.last_receipt.round_notified = true
		check(not model.tick_dispatch(-1.0) and not model.tick_dispatch(INF), "invalid time never advances dispatch")
		check(not model.tick_dispatch(wait - 0.25), "offer is not available early")
		var cold = Model.new("2026-10-29")
		check(cold.from_data(JSON.parse_string(JSON.stringify(model.to_data())), "2026-10-29"), "version four cooldown saves and loads")
		check(is_equal_approx(cold.dispatch_wait_remaining, 0.25) and cold.jobs == index and cold.coins == bank, "cold load preserves exact bank and remaining free drive")
		check(cold.tick_dispatch(0.25) and not cold.tick_dispatch(1.0), "expiry produces exactly one availability edge")
		check(cold.active_job.is_empty() and not cold.current_offer().is_empty(), "expiry supplies an offer without accepting it")
		check(cold.coins == bank and int(cold.last_receipt.id) == int(receipt.id), "waiting never repeats fare or reward")
		model = cold
	var collision = Model.new("2026-10-29")
	check(collision.accept_job(collision.current_offer()), "tip fixture accepts only available offer")
	check(not collision.note_collision() and int(collision.active_job.collisions) == 0, "approach bump cannot reduce tip")
	collision.player_node = int(collision.active_job.pickup)
	collision.pickup()
	check(not collision.note_collision(false) and int(collision.active_job.collisions) == 0, "boarding bump cannot reduce tip")
	check(collision.note_collision(true) and int(collision.active_job.collisions) == 1, "only physically onboard bump reduces tip")
	var old := collision.to_data()
	old.version = 3
	old.erase("dispatch_wait_remaining")
	var migrated = Model.new("2026-10-29")
	check(migrated.from_data(old, "2026-10-29") and migrated.active_job == collision.active_job, "existing version-three accepted fare and metrics stay exact")
	check(migrated.dispatch_wait_remaining == 0.0 and migrated.coins == collision.coins, "legacy migration adds no reward or synthetic wait")
	var service = load("res://platform/services.gd").new()
	service.set_menu_visible(true)
	check(service._menu_visible and not service._driving_visible and service.banner_position() == AdPosition.BOTTOM, "Home chooses bottom banner")
	service.set_driving_visible(true)
	check(not service._menu_visible and service._driving_visible and service.banner_position() == AdPosition.TOP, "driving chooses one top banner")
	service.set_driving_visible(false)
	check(not service._driving_visible and not service._menu_visible, "other menus hide banner")
	for total: int in range(1,31):
		check(service.is_interstitial_boundary(total) == (total % 10 == 0), "interstitial boundary is each tenth durable fare")
	service.fare_finished(10)
	check(service._last_interstitial_completion == 10, "completion boundary recorded")
	service.fare_finished(10)
	check(service._last_interstitial_completion == 10, "duplicate completion cannot retry same boundary")
	service.free()
	var original := root.get_node_or_null("Services")
	if is_instance_valid(original): original.name = "OriginalServicesForIsolatedRoundFive"
	var fake := ServicesFixture.new()
	fake.name = "Services"
	root.add_child(fake)
	var game = load("res://main.tscn").instantiate()
	game.demo = true
	root.add_child(game)
	game.set_process(false)
	game.model = Model.new("2026-10-29")
	game._show("home")
	check(fake.home_visible and not fake.drive_visible, "Home requests bottom banner")
	game._show("drive")
	await process_frame
	check(fake.drive_visible and not fake.home_visible, "drive requests top banner")
	check(game.fare_card_mode == "offer" and game.model.active_job.is_empty(), "fresh prompt awaits explicit acceptance")
	for profile: Vector2i in [Vector2i(540,960),Vector2i(600,960),Vector2i(800,1280)]:
		root.size = profile
		await process_frame
		game._apply_banner_layout(0.0,126.0,87.0)
		check(game.header_subtitle.position.y >= 126.0 and game.coins_label.position.y >= 126.0, "manual-drive level and coins below native strip")
		check(game.header_subtitle.get_rect().end.x < game.coins_label.position.x, "level and coin labels remain separate")
		check(game.drive_hud_panel.position.y >= game.header_rule.position.y + 12.0, "HUD below the header rule")
		var card_rect := Rect2(game.fare_card.position, game.fare_card.size * game.fare_card.scale)
		check(card_rect.position.y >= game.drive_hud_panel.get_rect().end.y and card_rect.end.y <= 960.0 - 87.0 - 64.0, "whole offer fits below HUD and above safe bottom feedback")
		check(not game.action_button.visible, "offer replaces disabled driving controls")
		check(not game.info_label.text.contains("gold") and not game.info_label.text.contains("line"), "driving HUD contains no alignment/gold-line text")
	game.fare_card.get_node("AcceptFare").pressed.emit()
	var world = game.city.world
	game._process(0.0)
	game._drive_impact(1.0)
	check(int(game.model.active_job.collisions) == 0 and not game.toast_label.text.begins_with("Bump"), "approach impact has no tip warning")
	game.model.player_node = int(game.model.active_job.pickup)
	game.model.pickup()
	world.passenger_phase = "boarding" # Isolated scene state, never a real saved profile.
	game._drive_impact(1.0)
	check(int(game.model.active_job.collisions) == 0, "scene boarding impact does not reduce tip")
	world.passenger_phase = "onboard"
	game._drive_impact(1.0)
	check(int(game.model.active_job.collisions) == 1 and game.toast_label.text.begins_with("Bump"), "scene onboard impact alone warns and reduces tip")
	game.model.player_node = int(game.model.active_job.destination)
	game.model.complete_job()
	var earned_bank: int = game.model.coins
	check(game._retry_completed_fare_save(), "source scene confirms simulated completion once")
	check(game.fare_card_mode == "" and game.model.active_job.is_empty(), "successful bank automatically returns free driving")
	check(fake.completed == [1] and game.model.coins == earned_bank, "durable fare notifies cadence once without recalculating reward")
	game._retry_completed_fare_save()
	check(fake.completed == [1], "repeat bank retry cannot duplicate cadence")
	var before: float = game.model.dispatch_wait_remaining
	fake.covered = true
	game._process(0.08)
	check(game.model.dispatch_wait_remaining == before, "fullscreen cover freezes dispatch")
	fake.covered = false
	game.resume_required = false
	game.discard_frame = false
	for index: int in range(260): game._process(0.08)
	check(game.fare_card_mode == "offer" and game.model.active_job.is_empty(), "actual scene clock opens next acceptance prompt, never auto-accepts")
	check(game.model.coins == earned_bank and game.model.jobs == 1, "scene wait cannot invent payment")
	game._stop_audio()
	root.remove_child(game)
	game.queue_free()
	fake.queue_free()
	if is_instance_valid(original): original.name = "Services"
	await process_frame
	await process_frame
	print("TAXI_ROUND_FIVE checks=%d failures=%d (isolated source/scene fixtures; no native driving/ad/backend proof)" % [checks, failures])
	quit(1 if failures else 0)
