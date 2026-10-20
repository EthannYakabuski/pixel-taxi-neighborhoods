extends SceneTree

const Model = preload("res://game/model.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_routes()
	_test_job_integrity()
	_test_economy_and_upgrades()
	_test_daily_claims()
	_test_save_roundtrip()
	_test_job_variety()
	_test_file_roundtrip()
	print("PIXEL_TAXI_MODEL_TESTS: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _test_routes() -> void:
	for start: int in range(49):
		for destination: int in range(49):
			var path: Array[int] = Model.route(start, destination)
			check(path.size() > 0 or start == destination, "City road graph disconnected")
			var previous: int = start
			for node: int in path:
				check(node in Model.adjacent(previous), "Route leaves a connected street")
				previous = node
			check(previous == destination, "Route missed destination")
	check(Model.route(-1, 5).is_empty(), "Invalid start accepted")
	check(Model.route(5, 49).is_empty(), "Invalid destination accepted")

func _test_job_integrity() -> void:
	var model = Model.new("2026-10-20")
	var job: Dictionary = model.make_job(0)
	check(model.accept_job(job), "Valid contract rejected")
	check(not model.accept_job(model.make_job(1)), "Second active contract accepted")
	check(not model.pickup(), "Remote pickup accepted")
	check(model.complete_job().is_empty(), "Uncollected passenger delivered")
	model.player_node = int(job.pickup)
	check(model.pickup(), "Curb pickup rejected")
	check(not model.pickup(), "Duplicate pickup accepted")
	check(model.complete_job().is_empty(), "Remote delivery accepted")
	model.player_node = int(job.destination)
	var receipt: Dictionary = model.complete_job()
	check(not receipt.is_empty() and int(receipt.fare) > 0, "Valid delivery failed")
	var balance: int = model.coins
	check(model.complete_job().is_empty() and model.coins == balance, "Duplicate fare paid")
	check(model.jobs == 1 and model.daily_jobs == 1, "Job totals did not advance once")
	check(model.passenger_journal.size() == 1, "Passenger journal missing")

func _test_economy_and_upgrades() -> void:
	var model = Model.new("2026-10-20")
	check(not model.buy_upgrade("invalid"), "Unknown upgrade accepted")
	check(model.buy_upgrade("engine"), "Affordable engine refused")
	check(model.speed() > 118, "Engine does not affect speed")
	check(not model.buy_upgrade("comfort") and model.coins >= 0, "Unaffordable upgrade overspent")
	check(not model.choose_car(3), "Unaffordable car acquired")
	model.coins = 100000
	for unused: int in range(8): model.buy_upgrade("engine")
	check(int(model.upgrades.engine) == 5 and model.upgrade_cost("engine") == -1, "Upgrade cap broken")
	check(model.choose_car(2) and model.car == 2, "Car purchase failed")
	var balance: int = model.coins
	check(model.choose_car(2) and model.coins == balance, "Owned car charged twice")
	var bonus: int = model.add_xp(800)
	check(model.level() == 4 and bonus == 315, "Multi-level reward accounting incorrect")
	var second_bonus: int = model.add_xp(0)
	check(second_bonus == 0, "Level rewards paid twice")
	var normal = Model.new("2026-10-20")
	var boosted = Model.new("2026-10-20")
	boosted.fare_boost = true
	var normal_receipt: Dictionary = finish(normal)
	var boosted_receipt: Dictionary = finish(boosted)
	check(int(boosted_receipt.fare) > int(normal_receipt.fare) and not boosted.fare_boost, "Earned fare boost not consumed once")

func _test_daily_claims() -> void:
	var model = Model.new("2026-10-20")
	check(model.claim_login("2026-10-20") == 80, "First login reward wrong")
	check(model.claim_login("2026-10-20") == 0, "Login claimed twice")
	check(model.claim_login("2026-10-19") == 0, "Backward clock permits login reward")
	check(model.claim_login("2026-10-21") == 110, "Consecutive streak not advanced")
	check(model.claim_login("2026-10-23") == 80, "Broken streak not reset")
	model.daily_jobs = 3
	check(model.claim_quest("daily_jobs") == 120, "Complete daily quest refused")
	check(model.claim_quest("daily_jobs") == 0, "Daily quest paid twice")
	model.roll_day("2026-10-19")
	check(model.daily_jobs == 3, "Backward clock reset quests")
	model.roll_day("2026-10-21")
	check(model.daily_jobs == 0 and model.daily_claimed.is_empty(), "New day did not reset quests")
	model.travel(-100)
	check(model.distance == 0, "Negative distance accepted")

func _test_save_roundtrip() -> void:
	var model = Model.new("2026-10-20")
	model.coins = 2000
	model.buy_upgrade("comfort")
	model.choose_car(1)
	model.travel(2500)
	model.accept_job(model.make_job(2))
	model.player_node = int(model.active_job.pickup)
	model.pickup()
	var restored = Model.new("2026-10-20")
	check(restored.from_data(JSON.parse_string(JSON.stringify(model.to_data())), "2026-10-20"), "Save could not deserialize")
	check(restored.coins == model.coins and restored.car == 1 and restored.distance == 2500, "Progress roundtrip differed")
	check(bool(restored.active_job.picked_up), "Active passenger lost on restart")
	var bad: Dictionary = model.to_data()
	bad.coins = -999
	bad.player_node = 800
	bad.car = 99
	bad.upgrades.engine = 900
	bad.active_job = {}
	check(restored.from_data(bad, "2026-10-20"), "Corrupt numeric save rejected instead of repaired")
	check(restored.coins == 0 and restored.player_node == 48 and restored.car == 0 and int(restored.upgrades.engine) == 5, "Corrupt numeric values not bounded")
	check(not restored.from_data({"version": 99}), "Unsupported save version accepted")
	var repaired_job: Dictionary = {"pickup": 5, "destination": 32, "passenger": "Test passenger", "base_fare": -900, "rare": false}
	restored.cancel_job()
	check(restored.accept_job(repaired_job), "Repairable job rejected")
	check(float(restored.active_job.metres) > 0 and int(restored.active_job.base_fare) > 0, "Contract geometry/fare not reconstructed")

func _test_job_variety() -> void:
	var model = Model.new("2026-10-20")
	var found: Dictionary = {}
	var rare_count: int = 0
	for index: int in range(70):
		model.jobs = index
		var job: Dictionary = model.make_job(0)
		check(job.pickup != job.destination and job.metres > 0, "Degenerate contract generated")
		found[Model.district(int(job.destination))] = true
		if job.rare: rare_count += 1
	check(found.size() == 3, "Contracts do not visit every district")
	check(rare_count == 10, "Rare passenger cadence differs")

func _test_file_roundtrip() -> void:
	var path: String = "user://taxi_model_test_save.json"
	var model = Model.new("2026-10-20")
	finish(model)
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Test save could not open")
	if file == null: return
	file.store_string(JSON.stringify(model.to_data()))
	file.close()
	var restored = Model.new("2026-10-20")
	check(restored.from_data(JSON.parse_string(FileAccess.get_file_as_string(path)), "2026-10-20"), "Written save could not be read")
	check(restored.jobs == 1 and restored.coins == model.coins, "Written progress did not persist")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish(model) -> Dictionary:
	var job: Dictionary = model.make_job(0)
	model.accept_job(job)
	model.player_node = int(job.pickup)
	model.pickup()
	model.player_node = int(job.destination)
	return model.complete_job()
