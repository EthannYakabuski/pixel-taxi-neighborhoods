class_name TaxiModel
extends RefCounted

const GRID := 7
const STEP := 220.0
const DAY_REWARDS := [80, 110, 150, 200, 260, 340, 500]
const CARS := [
	{"name": "City Classic", "color": "#ffc857", "price": 0},
	{"name": "Coral Comet", "color": "#ff8278", "price": 420},
	{"name": "Sage Estate", "color": "#82c8ad", "price": 1100},
	{"name": "Midnight Violet", "color": "#b49bff", "price": 2400}
]
const PASSENGERS := ["Maya · baker", "Theo · gardener", "Ari · architect", "Jules · musician", "Noor · nurse", "Kit · courier"]
const RARE_PASSENGERS := ["Luna · astronaut", "Rex · movie star", "Pip · penguin keeper", "Ada · inventor"]

var coins: int = 180
var xp: int = 0
var jobs: int = 0
var distance: float = 0.0
var income: int = 0
var rare_delivered: int = 0
var player_node: int = 24
var car: int = 0
var owned_cars: Array = [0]
var upgrades: Dictionary = {"engine": 0, "comfort": 0, "radio": 0}
var visits: Dictionary = {"Foundry": 0, "Central": 0, "Garden": 0}
var active_job: Dictionary = {}
var unlocked: Array = []
var passenger_journal: Array = []
var day: String = ""
var daily_jobs: int = 0
var daily_distance: float = 0.0
var daily_rare: int = 0
var daily_claimed: Array = []
var login_day: String = ""
var login_streak: int = 0
var fare_boost: bool = false
var sound: bool = true

func _init(today: String = "") -> void:
	if today == "":
		today = Time.get_date_string_from_system(true)
	roll_day(today)

static func point(node: int) -> Vector2:
	return Vector2(node % GRID, node / GRID) * STEP

static func district(node: int) -> String:
	var column: int = node % GRID
	if column < 2:
		return "Foundry"
	if column < 5:
		return "Central"
	return "Garden"

static func adjacent(node: int) -> Array[int]:
	var result: Array[int] = []
	var x: int = node % GRID
	var y: int = node / GRID
	if x > 0: result.append(node - 1)
	if x < GRID - 1: result.append(node + 1)
	if y > 0: result.append(node - GRID)
	if y < GRID - 1: result.append(node + GRID)
	return result

static func route(start: int, goal: int) -> Array[int]:
	if start < 0 or start >= GRID * GRID or goal < 0 or goal >= GRID * GRID:
		return []
	var frontier: Array[int] = [start]
	var previous: Dictionary = {start: -1}
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		if current == goal: break
		for neighbor: int in adjacent(current):
			if not previous.has(neighbor):
				previous[neighbor] = current
				frontier.append(neighbor)
	if not previous.has(goal): return []
	var result: Array[int] = []
	var cursor: int = goal
	while cursor != start:
		result.push_front(cursor)
		cursor = int(previous[cursor])
	return result

func level() -> int:
	return int(sqrt(float(xp) / 80.0)) + 1

func level_progress() -> float:
	var low: int = (level() - 1) * (level() - 1) * 80
	var high: int = level() * level() * 80
	return float(xp - low) / float(high - low)

func add_xp(amount: int) -> int:
	var previous_level: int = level()
	xp += maxi(0, amount)
	var bonus: int = 0
	for new_level: int in range(previous_level + 1, level() + 1):
		bonus += 35 * new_level
	coins += bonus
	return bonus

func speed() -> float:
	return 118.0 + float(upgrades.engine) * 17.0

func upgrade_cost(kind: String) -> int:
	if not upgrades.has(kind) or int(upgrades[kind]) >= 5: return -1
	return int(120.0 * pow(1.75, int(upgrades[kind])))

func buy_upgrade(kind: String) -> bool:
	var price: int = upgrade_cost(kind)
	if price < 0 or coins < price: return false
	coins -= price
	upgrades[kind] = int(upgrades[kind]) + 1
	return true

func choose_car(index: int) -> bool:
	if index < 0 or index >= CARS.size(): return false
	if index not in owned_cars:
		var price: int = int(CARS[index].price)
		if coins < price: return false
		coins -= price
		owned_cars.append(index)
	car = index
	return true

func make_job(slot: int) -> Dictionary:
	var sequence: int = jobs + slot
	var pickup: int = posmod(jobs * 11 + slot * 17 + 5, 49)
	if pickup == player_node: pickup = (pickup + 7) % 49
	var destination: int = posmod(jobs * 19 + slot * 13 + 32, 49)
	if destination == pickup: destination = (destination + 19) % 49
	var rare: bool = posmod(sequence + 1, 7) == 0
	var passenger: String = RARE_PASSENGERS[(sequence / 7) % RARE_PASSENGERS.size()] if rare else PASSENGERS[sequence % PASSENGERS.size()]
	var length: int = route(pickup, destination).size()
	return {"id": sequence * 10 + slot, "pickup": pickup, "destination": destination, "passenger": passenger,
		"rare": rare, "base_fare": 65 + length * 12 + (55 if rare else 0), "picked_up": false,
		"district": district(destination), "metres": length * STEP * 0.45}

func accept_job(job: Dictionary) -> bool:
	if not active_job.is_empty() or not job.has_all(["pickup", "destination", "passenger", "base_fare", "rare"]): return false
	var pickup: int = int(job.pickup)
	var destination: int = int(job.destination)
	if pickup < 0 or pickup >= 49 or destination < 0 or destination >= 49 or pickup == destination: return false
	var length: int = route(pickup, destination).size()
	var rare: bool = bool(job.rare)
	active_job = {"id": int(job.get("id", 0)), "pickup": pickup, "destination": destination,
		"passenger": str(job.passenger).substr(0, 80), "rare": rare, "picked_up": false,
		"base_fare": 65 + length * 12 + (55 if rare else 0), "district": district(destination), "metres": length * STEP * 0.45}
	return true

func objective() -> int:
	if active_job.is_empty(): return player_node
	return int(active_job.destination if active_job.picked_up else active_job.pickup)

func pickup() -> bool:
	if active_job.is_empty() or bool(active_job.picked_up) or player_node != int(active_job.pickup): return false
	active_job.picked_up = true
	return true

func complete_job() -> Dictionary:
	if active_job.is_empty() or not bool(active_job.picked_up) or player_node != int(active_job.destination): return {}
	var completed: Dictionary = active_job.duplicate(true)
	active_job.clear()
	var payout: int = int(float(completed.base_fare) * (1.0 + 0.12 * int(upgrades.comfort)))
	if bool(completed.rare): payout += int(upgrades.radio) * 15
	if fare_boost:
		payout += payout / 2
		fare_boost = false
	coins += payout
	income += payout
	jobs += 1
	daily_jobs += 1
	visits[district(player_node)] = int(visits[district(player_node)]) + 1
	if completed.passenger not in passenger_journal: passenger_journal.append(completed.passenger)
	if completed.rare:
		rare_delivered += 1
		daily_rare += 1
	var level_bonus: int = add_xp(55 + int(completed.metres) / 25)
	return {"fare": payout, "level_bonus": level_bonus, "passenger": completed.passenger, "rare": completed.rare}

func travel(metres: float) -> void:
	var valid: float = maxf(0.0, metres)
	distance += valid
	daily_distance += valid

func cancel_job() -> void:
	active_job.clear()

func roll_day(today: String) -> void:
	# ISO dates are ordered; moving the local clock backwards cannot reset claims.
	if day != "" and today <= day: return
	day = today
	daily_jobs = 0
	daily_distance = 0
	daily_rare = 0
	daily_claimed = []

func claim_login(today: String) -> int:
	if login_day != "" and today <= login_day: return 0
	var yesterday: String = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_datetime_string(today + "T00:00:00")) - 86400)
	login_streak = (login_streak % 7) + 1 if login_day == yesterday else 1
	login_day = today
	var amount: int = DAY_REWARDS[login_streak - 1]
	coins += amount
	return amount

func quests() -> Array:
	return [
		{"key": "daily_jobs", "title": "Neighborhood regular", "detail": "Complete 3 fares", "value": daily_jobs, "goal": 3, "reward": 120},
		{"key": "daily_distance", "title": "City explorer", "detail": "Drive 2 km", "value": daily_distance, "goal": 2000, "reward": 150},
		{"key": "daily_rare", "title": "A special passenger", "detail": "Deliver a rare passenger", "value": daily_rare, "goal": 1, "reward": 180}
	]

func claim_quest(key: String) -> int:
	if key in daily_claimed: return 0
	for quest: Dictionary in quests():
		if quest.key == key and float(quest.value) >= float(quest.goal):
			daily_claimed.append(key)
			coins += int(quest.reward)
			add_xp(25)
			return int(quest.reward)
	return 0

func stat(key: String) -> int:
	match key:
		"jobs": return jobs
		"distance": return int(distance)
		"income": return income
		"rare": return rare_delivered
		"level": return level()
		"upgrades": return int(upgrades.engine) + int(upgrades.comfort) + int(upgrades.radio)
		"cars": return owned_cars.size()
		"districts": return int(int(visits.Foundry) > 0) + int(int(visits.Central) > 0) + int(int(visits.Garden) > 0)
		"passengers": return passenger_journal.size()
	return 0

func to_data() -> Dictionary:
	return {"version": 1, "coins": coins, "xp": xp, "jobs": jobs, "distance": distance, "income": income,
		"rare": rare_delivered, "player_node": player_node, "car": car, "owned_cars": owned_cars,
		"upgrades": upgrades, "visits": visits, "active_job": active_job, "unlocked": unlocked,
		"journal": passenger_journal, "day": day, "daily_jobs": daily_jobs, "daily_distance": daily_distance,
		"daily_rare": daily_rare, "daily_claimed": daily_claimed, "login_day": login_day, "login_streak": login_streak,
		"fare_boost": fare_boost, "sound": sound}

func from_data(data: Dictionary, today: String = "") -> bool:
	if int(data.get("version", 0)) != 1: return false
	coins = clampi(int(data.get("coins", 180)), 0, 1000000000)
	xp = clampi(int(data.get("xp", 0)), 0, 10000000)
	jobs = clampi(int(data.get("jobs", 0)), 0, 10000000)
	distance = clampf(float(data.get("distance", 0)), 0.0, 1000000000.0)
	income = clampi(int(data.get("income", 0)), 0, 1000000000)
	rare_delivered = clampi(int(data.get("rare", 0)), 0, jobs)
	player_node = clampi(int(data.get("player_node", 24)), 0, 48)
	car = clampi(int(data.get("car", 0)), 0, CARS.size() - 1)
	owned_cars = [0]
	for owned: Variant in data.get("owned_cars", []):
		if int(owned) >= 0 and int(owned) < CARS.size() and int(owned) not in owned_cars: owned_cars.append(int(owned))
	if car not in owned_cars: car = 0
	var stored_upgrades: Dictionary = data.get("upgrades", {}) if data.get("upgrades", {}) is Dictionary else {}
	for key: String in upgrades.keys(): upgrades[key] = clampi(int(stored_upgrades.get(key, 0)), 0, 5)
	var stored_visits: Dictionary = data.get("visits", {}) if data.get("visits", {}) is Dictionary else {}
	for key: String in visits.keys(): visits[key] = clampi(int(stored_visits.get(key, 0)), 0, jobs)
	active_job = {}
	var stored_job: Variant = data.get("active_job", {})
	if stored_job is Dictionary and not stored_job.is_empty():
		if accept_job(stored_job): active_job.picked_up = bool(stored_job.get("picked_up", false))
	unlocked = data.get("unlocked", []).duplicate() if data.get("unlocked", []) is Array else []
	passenger_journal = data.get("journal", []).duplicate() if data.get("journal", []) is Array else []
	day = str(data.get("day", ""))
	daily_jobs = clampi(int(data.get("daily_jobs", 0)), 0, jobs)
	daily_distance = clampf(float(data.get("daily_distance", 0)), 0, distance)
	daily_rare = clampi(int(data.get("daily_rare", 0)), 0, rare_delivered)
	daily_claimed = data.get("daily_claimed", []).duplicate() if data.get("daily_claimed", []) is Array else []
	login_day = str(data.get("login_day", ""))
	login_streak = clampi(int(data.get("login_streak", 0)), 0, 7)
	fare_boost = bool(data.get("fare_boost", false))
	sound = bool(data.get("sound", true))
	if today == "": today = Time.get_date_string_from_system(true)
	roll_day(today)
	return true
