extends SceneTree
## Filesystem faults and mocked callbacks in disposable process-local data only.
const Model = preload("res://game/model.gd")
const AtomicSave = preload("res://game/atomic_save.gd")
const Graph = preload("res://game/city_graph.gd")
var checks := 0
var failures := 0

class FaultStore extends "res://game/atomic_save.gd":
	var writes := 0
	var fail_on_write := 0
	var fail_stage := ""
	func write(data: Dictionary) -> bool:
		writes += 1
		return super.write(data)
	func failing(stage: String) -> bool:
		return (writes == fail_on_write or fail_on_write < 0) and fail_stage == stage
	func _open(temporary: String) -> FileAccess:
		return null if failing("open") else super._open(temporary)
	func _write_payload(file: FileAccess,payload: String) -> Error:
		return ERR_FILE_CANT_WRITE if failing("write") else super._write_payload(file,payload)
	func _copy(source: String,destination: String) -> Error:
		return ERR_CANT_CREATE if failing("copy") else super._copy(source,destination)
	func _rename(source: String,destination: String) -> Error:
		return ERR_CANT_CREATE if failing("rename") else super._rename(source,destination)
	func _read(source: String) -> String:
		return "injected unverifiable readback" if source==path and failing("readback") else super._read(source)

class RewardFixture extends Node:
	var callbacks: Array[Callable] = []
	var rounds := 0
	var submissions := 0
	func set_menu_visible(_visible: bool) -> void: pass
	func unlock(_key: String) -> void: pass
	func submit(_key: String,_value: int) -> void: submissions += 1
	func round_finished() -> void: rounds += 1
	func is_gameplay_blocked() -> bool: return false
	func can_reward() -> bool: return true
	func reward_requested(_context: String,callback: Callable) -> void: callbacks.append(callback)

func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)

func finish(model) -> void:
	var offer: Dictionary=model.current_offer()
	model.accept_job(offer)
	model.player_node=int(offer.pickup)
	model.pickup()
	model.player_node=int(offer.destination)
	model.complete_job()

func baseline(game,service: RewardFixture) -> FaultStore:
	service.callbacks.clear()
	service.rounds=0
	service.submissions=0
	game.model=Model.new("2026-10-24")
	finish(game.model)
	game.model.last_receipt.bank_saved=true # This fixture starts after a confirmed base fare.
	game.model.last_receipt.round_notified=true
	game.reward_pending=false
	game.reward_request_serial+=1
	var store:=FaultStore.new()
	game.save_store=store
	game.demo=false
	check(game._save(),"baseline local receipt writes successfully")
	store.writes=0
	game._open_fare_card("receipt")
	return store

func load_profile() -> Variant:
	var restored=Model.new("2026-10-24")
	check(restored.from_data(JSON.parse_string(FileAccess.get_file_as_string("user://neighborhoods_v1.json")),"2026-10-24"),"actual saved profile parses after fault/retry")
	return restored

func run() -> void:
	# Actual writer boundaries: no failed temp/backup/replace step may be reported
	# as success, and the existing primary remains byte-exact in these failures.
	for stage: String in ["open","write","copy","rename"]:
		var store:=FaultStore.new()
		store.path="user://atomic-fault-"+stage+".json"
		check(store.write({"coins":900,"marker":"baseline"}),stage+" initial atomic save succeeds")
		var before:=FileAccess.get_file_as_string(store.path)
		store.fail_stage=stage
		store.fail_on_write=2
		check(not store.write({"coins":1800,"marker":"candidate"}),stage+" fault is reported as failed save")
		check(FileAccess.get_file_as_string(store.path)==before,stage+" fault preserves existing primary exactly")
		store.fail_on_write=0
		check(store.write({"coins":1800,"marker":"candidate"}),stage+" cleared fault allows ordinary write retry")
	var previous:=root.get_node_or_null("Services")
	if is_instance_valid(previous): previous.name="ServicesPreservedPersistenceFixture"
	var service:=RewardFixture.new()
	service.name="Services"
	root.add_child(service)
	var game=load("res://main.tscn").instantiate()
	game.demo=true
	root.add_child(game)
	game._show("drive")
	await process_frame
	for stage: String in ["open","write","copy","rename"]:
		var store:=baseline(game,service)
		var balance: int=game.model.coins
		store.fail_stage=stage
		store.fail_on_write=1
		game._request_completed_bonus()
		check(service.callbacks.is_empty() and not game.reward_pending,stage+" request-save fault prevents SDK request entirely")
		check(game.model.coins==balance and not game.model.has_pending_double_reward(),stage+" pre-ad failure creates no earned entitlement")
		check(game.toast_label.text.begins_with("Cannot save progress"),stage+" pre-ad failure gives honest visible feedback")
		store.fail_on_write=0
		game._request_completed_bonus()
		check(service.callbacks.size()==1,"storage recovery can launch the first actual request")
		service.callbacks[0].call(false)
		check(game.model.coins==balance,"unearned callback still grants nothing after storage recovery")
	for write_number: int in [2,3]:
		for stage: String in ["open","write","copy","rename"]:
			var store:=baseline(game,service)
			var balance: int=game.model.coins
			var income: int=game.model.income
			var fare: int=game.model.last_receipt.fare
			store.fail_stage=stage
			store.fail_on_write=write_number
			game._request_completed_bonus()
			check(service.callbacks.size()==1,"successful pre-ad checkpoint makes exactly one request")
			service.callbacks[0].call(true)
			check(game.model.coins==balance and game.model.income==income and not bool(game.model.last_receipt.double_claimed),stage+" earned/credit save fault rolls back unconfirmed money and claimed flag")
			check(game.model.has_pending_double_reward(),stage+" actually-earned reward stays pending for retry")
			check(game.toast_label.text.begins_with("Earned reward not saved"),stage+" failed save never displays confirmed doubled payout")
			check(game.fare_card.get_node("DoubleCompletedFare").text=="Retry saving earned reward",stage+" pending card offers save retry rather than another ad")
			check(game.fare_card.get_node("NextFare").disabled,"next fare cannot discard an unsettled earned reward")
			game._next_fare()
			check(game.fare_card_mode=="receipt" and game.model.active_job.is_empty(),"direct Next cannot bypass pending earned reward")
			var saved=load_profile()
			check(saved.coins==balance and not bool(saved.last_receipt.double_claimed),"disk never contains falsely confirmed money on injected failures")
			check(saved.has_pending_double_reward()==(write_number==3),"cold state distinguishes actual earned journal from request-only marker")
			var duplicate: Callable=service.callbacks[0]
			duplicate.call(true)
			check(game.model.coins==balance,"duplicate callback cannot grant while storage retry is pending")
			store.fail_on_write=0
			game._request_completed_bonus() # Retry is not an ad request.
			check(service.callbacks.size()==1,"save retry never invokes SDK or requires another ad")
			check(game.model.coins==balance+fare and game.model.income==income+fare and bool(game.model.last_receipt.double_claimed),"ordinary save recovery credits the earned fare once")
			check(game.toast_label.text.begins_with("Fare doubled and saved"),"confirmed message appears only after successful checked save")
			duplicate.call(true)
			game._request_completed_bonus()
			check(game.model.coins==balance+fare and service.callbacks.size()==1,"duplicate/stale callbacks and extra retry taps cannot duplicate credit")
			saved=load_profile()
			check(saved.coins==balance+fare and not saved.has_pending_double_reward() and not saved.can_double_last_fare(),"cold successful retry retains exactly-once claimed payout")
			await process_frame
	# Rename may succeed while final verification cannot read back. The UI must
	# stay conservative; either cold-read or same-session retry still pays once.
	var uncertain:=baseline(game,service)
	var uncertain_bank: int=game.model.coins
	var uncertain_fare: int=game.model.last_receipt.fare
	uncertain.fail_stage="readback"
	uncertain.fail_on_write=3
	game._request_completed_bonus()
	service.callbacks[0].call(true)
	check(game.model.has_pending_double_reward() and game.model.coins==uncertain_bank,"unverified final readback is never announced as confirmed credit")
	var actual_disk=load_profile()
	check(actual_disk.coins==uncertain_bank+uncertain_fare and not actual_disk.can_double_last_fare(),"cold verified primary sees already-written claimed transaction exactly once")
	uncertain.fail_on_write=0
	game._request_completed_bonus()
	check(game.model.coins==uncertain_bank+uncertain_fare and service.callbacks.size()==1,"uncertain same-session retry converges to once-only credit without another ad")
	# The newly introduced completion card/cadence has the same durability gate.
	game.model=Model.new("2026-10-24")
	var job: Dictionary=game.model.current_offer()
	game.model.accept_job(job)
	game._show("drive")
	var world=game.city.world
	world.set_pose(Graph.point(int(job.pickup)),0)
	world.current_speed=0
	game._curb_action()
	check(bool(game.model.active_job.picked_up),"completion fixture reaches source curb pickup")
	var completion:=FaultStore.new()
	game.save_store=completion
	check(game._save(),"picked-up fare baseline is saved before completion fault")
	completion.writes=0
	completion.fail_stage="rename"
	completion.fail_on_write=-1
	service.callbacks.clear()
	service.rounds=0
	service.submissions=0
	world.set_pose(Graph.point(int(job.destination)),0)
	world.current_speed=0
	game._curb_action()
	var completed_bank: int=game.model.coins
	var completed_xp: int=game.model.xp
	var completed_jobs: int=game.model.jobs
	check(game.model.has_unsaved_fare() and game.model.active_job.is_empty(),"failed completion save holds its exact completed receipt in memory")
	check(service.rounds==0 and service.callbacks.is_empty(),"failed completion cannot notify cadence or request ads")
	game._sync_achievements()
	check(service.submissions==0,"unsaved fare progress cannot submit scores remotely, including explicit sync")
	check(game.fare_card.get_node("NextFare").disabled and game.fare_card.get_node("DoubleCompletedFare").text=="Retry saving completed fare","unconfirmed completion exposes retry and disables Next")
	check(game.coins_label.text=="Save pending" and game.toast_label.text.begins_with("Fare not saved"),"unconfirmed payout is visibly unsaved rather than safely banked")
	game._next_fare()
	game._request_completed_bonus()
	check(service.callbacks.is_empty() and service.rounds==0 and game.fare_card_mode=="receipt","Next and reward actions cannot bypass failed base-save gate")
	actual_disk=load_profile()
	check(actual_disk.jobs==0 and not actual_disk.active_job.is_empty(),"failure before any completion write retains only the prior durable fare, not fabricated cold recovery")
	completion.fail_on_write=0
	game._request_completed_bonus() # Saves held completion, does not launch an ad.
	check(not game.model.has_unsaved_fare() and game.model.jobs==completed_jobs and game.model.xp==completed_xp and game.model.coins==completed_bank,"base retry persists held payout/XP once without recalculation")
	check(service.rounds==1 and service.callbacks.is_empty(),"cadence occurs once after base save, and retry opens no ad request")
	check(service.submissions>0,"confirmed base fare can submit its saved score progress")
	game._retry_completed_fare_save()
	check(service.rounds==1 and game.model.jobs==completed_jobs,"repeated completion retry cannot replay cadence or completion")
	actual_disk=load_profile()
	check(actual_disk.jobs==completed_jobs and actual_disk.xp==completed_xp and actual_disk.coins==completed_bank and not actual_disk.has_unsaved_fare(),"cold reload retains once-only saved base completion")
	completion.fail_stage="open"
	completion.fail_on_write=-1
	game._next_fare()
	check(game.model.receipt_open and game.fare_card_mode=="receipt" and game.model.active_job.is_empty(),"failed Next acknowledgement save retains receipt rather than advancing")
	completion.fail_on_write=0
	# A real persisted earned journal survives cold reconstruction before credit.
	var store:=baseline(game,service)
	var balance: int=game.model.coins
	var fare: int=game.model.last_receipt.fare
	store.fail_stage="rename"
	store.fail_on_write=3
	game._request_completed_bonus()
	service.callbacks[0].call(true)
	game._stop_audio()
	root.remove_child(game)
	game.queue_free()
	await process_frame
	await process_frame
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game._show("drive")
	check(game.model.has_pending_double_reward() and game.fare_card_mode=="receipt","cold scene exposes persisted actual-earned retry")
	var request_count:=service.callbacks.size()
	game._request_completed_bonus()
	check(game.model.coins==balance+fare and service.callbacks.size()==request_count,"cold actual-earned retry needs no new ad and credits exactly once")
	game.demo=true
	game._stop_audio()
	root.remove_child(game)
	game.queue_free()
	service.queue_free()
	if is_instance_valid(previous): previous.name="Services"
	await process_frame
	await process_frame
	print("TAXI_REWARD_PERSISTENCE checks=%d failures=%d (isolated filesystem faults and mocked callback fixtures; not native ad evidence)" % [checks,failures])
	quit(1 if failures else 0)
