extends SceneTree
## Isolated synthetic source/engine fixtures, never native fare or ad evidence.
const Model = preload("res://game/model.gd")
const Graph = preload("res://game/city_graph.gd")
var checks := 0
var failures := 0
class EarnedFixture extends Node:
	var callbacks: Array[Callable] = []
	var contexts: Array[String] = []
	var available := true
	var covered := false
	func set_menu_visible(_visible: bool) -> void: pass
	func unlock(_key: String) -> void: pass
	func submit(_key: String,_value: int) -> void: pass
	func round_finished() -> void: pass
	func is_gameplay_blocked() -> bool: return covered
	func can_reward() -> bool: return available
	func reward_requested(context: String,callback: Callable) -> void:
		contexts.append(context)
		callbacks.append(callback)

func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)

func finish(model) -> Dictionary:
	var offer: Dictionary = model.current_offer()
	model.accept_job(offer)
	model.player_node = int(offer.pickup)
	model.pickup()
	model.tick_fare(8.0)
	model.travel(float(model.active_job.metres))
	model.player_node = int(offer.destination)
	return model.complete_job()

func check_card_containment(game) -> void:
	var bounds := Rect2(Vector2.ZERO,game.fare_card.size)
	for child: Node in game.fare_card.get_children():
		if child is Control:
			check(bounds.encloses(child.get_rect()),"fare-card child stays within its actual panel: "+child.name)
	check(game.fare_card.position.y >= 220 and game.fare_card.position.y+game.fare_card.size.y<game.action_button.position.y,"fare card stays below HUD and above drive controls")

func run() -> void:
	var m = Model.new("2026-10-24")
	check(not m.can_double_last_fare() and m.double_last_fare(0)==0,"no bonus exists before a completed fare")
	var receipt := finish(m)
	var serial: int = receipt.id
	var balance: int = m.coins
	var income: int = m.income
	var xp: int = m.xp
	var jobs: int = m.jobs
	check(m.receipt_open and m.can_double_last_fare(),"completed receipt is saved and eligible")
	check(m.double_last_fare(serial+1)==0 and m.coins==balance,"stale/wrong receipt ID grants nothing")
	check(m.double_last_fare(serial)==int(receipt.fare),"earned bonus equals full original fare including actual tip")
	check(m.coins==balance+int(receipt.fare) and m.income==income+int(receipt.fare),"original fare plus bonus totals exactly 2x")
	check(m.jobs==jobs and m.xp==xp,"bonus never counts an extra fare or XP/level reward")
	check(m.double_last_fare(serial)==0,"duplicate reward cannot pay twice")
	var reloaded = Model.new("2026-10-24")
	check(reloaded.from_data(JSON.parse_string(JSON.stringify(m.to_data())),"2026-10-24"),"version3 receipt roundtrip loads")
	check(reloaded.double_last_fare(serial)==0 and reloaded.coins==m.coins,"cold load preserves paid receipt idempotence")
	reloaded.acknowledge_receipt()
	check(not reloaded.receipt_open,"Next acknowledges result without changing bank")
	var second := finish(reloaded)
	check(int(second.id)!=serial and reloaded.double_last_fare(serial)==0,"next genuine completion expires old receipt callback")
	var legacy := m.to_data()
	legacy.version=2
	legacy.erase("last_receipt")
	legacy.erase("receipt_open")
	legacy.fare_boost=true
	var migrated = Model.new("2026-10-24")
	check(migrated.from_data(legacy,"2026-10-24") and migrated.fare_boost,"legacy earned sponsor is preserved")
	check(migrated.last_receipt.is_empty() and not migrated.receipt_open,"migration never invents old paid fare entitlements")
	# Replace service lookup only within this fixture process, preserving the real
	# fallback autoload node and never presenting/requesting native ads.
	var previous := root.get_node_or_null("Services")
	if is_instance_valid(previous): previous.name="ServicesUnchangedFixtureBackup"
	var service := EarnedFixture.new()
	service.name="Services"
	root.add_child(service)
	var game = load("res://main.tscn").instantiate()
	game.demo=true
	root.add_child(game)
	game._show("drive")
	await process_frame
	var city_id: int = game.city.get_instance_id()
	var world = game.city.world
	check(game.screen=="drive" and game.fare_card_mode=="offer","shift starts with compact offer in live city")
	check(game.fare_card.size.y < game.stage.size.y*0.5,"fare UI is contained card, not full-screen menu")
	check_card_containment(game)
	check(game._drive_input_blocked(),"offer parks and blocks driving while choosing")
	game.fare_card.get_node("DeclineFare").pressed.emit()
	check(game.city.get_instance_id()==city_id and game.model.active_job.is_empty(),"declining keeps same city and advances only offer")
	game.fare_card.get_node("AcceptFare").pressed.emit()
	check(game.fare_card_mode=="" and not game.model.active_job.is_empty(),"accept closes card and starts fare in same city")
	game._process(0.0)
	await physics_frame
	check(world.passenger_phase=="waiting" and world.passenger.visible,"actual supplied Kenney passenger waits at pickup")
	check(world.passenger.find_children("*","MeshInstance3D",true,false).size()>0,"passenger contains real imported meshes")
	check(is_instance_valid(world._passenger_animation),"actual supplied character has animation player")
	var job: Dictionary=game.model.active_job.duplicate(true)
	world.set_pose(Graph.point(int(job.pickup)),0.0)
	world.current_speed=0
	game._curb_action()
	game._process(0.0)
	check(bool(game.model.active_job.picked_up) and world.passenger_phase=="boarding","curb pickup starts walk-to-cab animation")
	check(str(world._passenger_animation.current_animation).ends_with("walk"),"boarding uses the supplied actual walk clip")
	world._tick_passenger(3.0)
	check(world.passenger_phase=="onboard" and not world.passenger.visible,"boarded passenger is hidden inside cab")
	world.set_pose(Graph.point(int(job.destination)),0.0)
	world.current_speed=0
	game._curb_action()
	game._process(0.0)
	check(game.screen=="drive" and game.city.get_instance_id()==city_id,"completed fare preserves exact 3D scene")
	check(game.fare_card_mode=="receipt" and game.model.active_job.is_empty(),"result controls appear on in-scene card")
	check_card_containment(game)
	check(world.passenger_phase=="departing" and world.passenger.visible,"dropoff starts visible walk-away")
	var passenger_before: Vector3=world.passenger.position
	world._tick_passenger(0.5)
	check(world.passenger.position.distance_to(passenger_before)>0.1,"departing character actually walks away")
	world.presentation_paused=true
	passenger_before=world.passenger.position
	world._tick_passenger(10.0)
	check(world.passenger.position==passenger_before,"covered app freezes passenger presentation")
	world.presentation_paused=false
	world._tick_passenger(30.0)
	check(not world.passenger.visible and world.passenger_phase=="","walking passenger is removed after leaving camera view")
	var bank: int=game.model.coins
	var fare: int=game.model.last_receipt.fare
	service.available=false
	game._request_completed_bonus()
	check(service.callbacks.is_empty() and game.model.coins==bank,"unavailable ad grants nothing")
	service.available=true
	game._request_completed_bonus()
	check(service.callbacks.size()==1 and game.reward_pending,"one requested callback is pending")
	game._request_completed_bonus()
	check(service.callbacks.size()==1,"repeat tap cannot create parallel request")
	service.callbacks[0].call(false)
	check(game.model.coins==bank and game.model.can_double_last_fare(),"unearned dismissal preserves eligibility and bank")
	game._request_completed_bonus()
	service.callbacks[0].call(true)
	check(game.reward_pending and game.model.coins==bank,"stale old callback cannot consume new pending request")
	service.callbacks[1].call(true)
	check(game.model.coins==bank+fare and not game.model.can_double_last_fare(),"only accepted earned callback doubles completed fare")
	service.callbacks[1].call(true)
	check(game.model.coins==bank+fare,"duplicate earned callback grants no extra coins")
	game.demo=false
	game._save() # Process-local APPDATA/LOCALAPPDATA; never an owner's profile.
	game._stop_audio()
	root.remove_child(game)
	game.queue_free()
	await process_frame
	await process_frame
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.demo=true
	check(game.model.coins==bank+fare and not game.model.can_double_last_fare(),"actual isolated file cold load preserves once-only doubled payment")
	game._show("drive")
	city_id=game.city.get_instance_id()
	check(game.fare_card_mode=="receipt","cold return restores pending result within city")
	check_card_containment(game)
	var request_count: int=service.callbacks.size()
	game._request_completed_bonus()
	check(service.callbacks.size()==request_count,"cold return cannot request already-paid result again")
	game.fare_card.get_node("NextFare").pressed.emit()
	check(game.city.get_instance_id()==city_id and game.fare_card_mode=="offer","Next fare remains in same city")
	game._stop_audio()
	root.remove_child(game)
	game.queue_free()
	service.queue_free()
	if is_instance_valid(previous): previous.name="Services"
	await process_frame
	await process_frame
	print("TAXI_ROUND_FOUR checks=%d failures=%d (isolated synthetic engine/source fixtures; no native fare/ad proof)" % [checks,failures])
	quit(1 if failures else 0)
