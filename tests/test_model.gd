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
	_test_dispatch_and_tips()
	_test_legacy_migration()
	_test_pose_and_fare_metrics()
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

func _test_dispatch_and_tips() -> void:
	var model=Model.new("2026-10-20")
	var offered: Dictionary=model.current_offer()
	var balance: int=model.coins
	model.player_node=int(offered.pickup)
	check(model.current_offer()==offered,"Offered dispatch changed while driving")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(model.to_data()))
	var restored=Model.new("2026-10-20")
	check(restored.from_data(saved,"2026-10-20") and restored.current_offer().id==offered.id,"Single dispatch offer changed on reload")
	model.decline_offer()
	check(model.current_offer().id!=offered.id and model.coins==balance,"Declining must rotate one offer without payment")
	var sequence: int=model.dispatch_sequence
	model.accept_job(model.current_offer())
	model.decline_offer()
	check(model.dispatch_sequence==sequence and model.current_offer().is_empty(),"Active fare must block another dispatch")
	model.cancel_job()
	var clean=Model.new("2026-10-20")
	var clean_receipt: Dictionary=drive_finish(clean,0,false)
	check(int(clean_receipt.tip)>0 and clean_receipt.clean and clean_receipt.timely,"Fast clean real-distance fare missed its tip")
	var tipped_balance: int=clean.coins
	check(clean.complete_job().is_empty() and clean.coins==tipped_balance,"Tip paid twice")
	var crashed=Model.new("2026-10-20")
	var crashed_receipt: Dictionary=drive_finish(crashed,1,false)
	check(int(crashed_receipt.tip)==0 and not crashed_receipt.clean and int(crashed_receipt.base_fare)>0,"Collision should forfeit tip but preserve base fare")
	var scenic=Model.new("2026-10-20")
	var scenic_receipt: Dictionary=drive_finish(scenic,0,true)
	check(int(scenic_receipt.tip)==0 and not scenic_receipt.timely and int(scenic_receipt.base_fare)>0,"Late route should preserve base fare without a fast-drive tip")
	var teleported=Model.new("2026-10-20")
	var teleport_receipt: Dictionary=finish(teleported)
	check(int(teleport_receipt.tip)==0,"A fixture teleport cannot establish qualifying driven distance/time")

func drive_finish(model,crashes: int,late: bool) -> Dictionary:
	var job: Dictionary=model.current_offer()
	model.accept_job(job)
	model.player_node=int(job.pickup)
	model.pickup()
	model.tick_fare(float(model.active_job.deadline)+1.0 if late else float(model.active_job.deadline)*0.6)
	model.travel(float(model.active_job.metres))
	for unused: int in range(crashes): model.note_collision()
	model.player_node=int(job.destination)
	return model.complete_job()

func _test_legacy_migration() -> void:
	var legacy: Dictionary={"version":1,"coins":8765,"xp":1877,"jobs":17,"distance":12345.5,"income":7331,
		"rare":3,"player_node":23,"car":2,"owned_cars":[0,1,2],"upgrades":{"engine":3,"comfort":2,"radio":1},
		"visits":{"Foundry":4,"Central":8,"Garden":5},"active_job":{"id":112,"pickup":5,"destination":32,"passenger":"Maya - baker","rare":false,"base_fare":89,"picked_up":true,"district":"Central","metres":198.0},
		"unlocked":["taxi_first_fare"],"journal":["Maya - baker","Luna - astronaut"],"day":"2026-10-20","daily_jobs":3,"daily_distance":2200.0,"daily_rare":1,"daily_claimed":["daily_jobs"],"login_day":"2026-10-20","login_streak":4,"fare_boost":true,"sound":false}
	var restored=Model.new("2026-10-20")
	check(restored.from_data(legacy,"2026-10-20"),"V1 profile was not migrated")
	var migrated: Dictionary=restored.to_data()
	for key: String in legacy:
		if key in ["version","active_job"]: continue
		check(migrated[key]==legacy[key],"Migration altered banked profile field "+key)
	for key: String in legacy.active_job:
		check(restored.active_job[key]==legacy.active_job[key],"Migration repriced/lost accepted fare field "+key)
	check(migrated.version==2 and restored.driving_position==Model.point(23),"Migration did not initialize stable-address pose")
	check(not bool(restored.active_job.tip_eligible),"Legacy unknown collision/time history cannot prove a clean tip")
	restored.player_node=32
	var receipt: Dictionary=restored.complete_job()
	# 89 * (1+.12*comfort2) =110, earned boost55; original198m gives62XP.
	check(int(receipt.base_fare)==165 and int(receipt.tip)==0 and not restored.fare_boost,"Legacy accepted payout or earned boost entitlement changed")
	check(restored.xp==1877+62,"Legacy fare XP was repriced using the new map")

func _test_pose_and_fare_metrics() -> void:
	var model=Model.new("2026-10-20")
	model.accept_job(model.current_offer())
	model.tick_fare(10)
	check(float(model.active_job.elapsed)==0.0,"Pickup leg consumed passenger ride timer")
	model.player_node=int(model.active_job.pickup)
	model.pickup()
	model.tick_fare(12.5)
	model.travel(88.25)
	model.note_collision()
	model.driving_position=Model.point(24)+Vector2(0,5)
	model.driving_heading=0.75
	var saved: Dictionary=JSON.parse_string(JSON.stringify(model.to_data()))
	var restored=Model.new("2026-10-20")
	check(restored.from_data(saved,"2026-10-20"),"V2 pose/fare metrics did not load")
	check(restored.driving_position.is_equal_approx(model.driving_position) and is_equal_approx(restored.driving_heading,0.75),"Actual continuous vehicle pose lost on reload")
	check(is_equal_approx(float(restored.active_job.elapsed),12.5) and int(restored.active_job.collisions)==1 and is_equal_approx(float(restored.active_job.driven_metres),88.25),"Fare time/collision/distance metrics lost on reload")
	restored.tick_fare(-100)
	check(is_equal_approx(float(restored.active_job.elapsed),12.5),"Negative time advanced/regressed fare clock")
	saved.driving_position={"x":INF,"y":-INF}
	saved.driving_heading=NAN
	check(restored.from_data(saved,"2026-10-20") and restored.driving_position.is_finite() and is_finite(restored.driving_heading),"Corrupt non-finite pose accepted")
