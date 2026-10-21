extends Node
## Android-only native integrations. Web and editor never simulate ad entitlement.

signal availability_changed
signal service_notice(message: String)
signal menu_bottom_reserve_changed

var settings: Dictionary = {}
var _native_ads := false
var _ads_ready := false
var _pgs_ready := false
var _signed_in := false
var _menu_visible := true
var _round_count := 0
var _banner: AdView
var _interstitial: InterstitialAd
var _rewarded: RewardedAd
var _reward_callback := Callable()
var _reward_granted := false
var _reward_showing := false
var _reward_context := ""
var _interstitial_showing := false
var _sign_in_client: PlayGamesSignInClient
var _achievements_client: PlayGamesAchievementsClient
var _leaderboards_client: PlayGamesLeaderboardsClient
var _pending_unlocks: Dictionary = {}
var _pending_scores: Dictionary = {}
var _notice := "Offline progress is available."
var _menu_metric_elapsed := 0.0
var _menu_metric_key := ""
var _menu_metric_signal_pending := false

const PENDING_PATH := "user://platform_pending_v1.json"

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://platform/config.json"))
	if parsed is Dictionary:
		settings = parsed
	_load_pending()
	if OS.get_name() != "Android":
		_notice = "Local play: Android ads and Play Games are unavailable on this platform."
		return
	get_viewport().size_changed.connect(_refresh_menu_metrics)
	_refresh_menu_metrics()
	_start_play_games()
	_native_ads = Engine.has_singleton("PoingGodotAdMob")
	if not _native_ads:
		_notice = "Native AdMob is unavailable; the game remains fully playable."
		return
	_refresh_consent()

func _process(delta: float) -> void:
	if OS.get_name() != "Android" or not _menu_visible:
		return
	_menu_metric_elapsed += delta
	if _menu_metric_elapsed >= 0.5:
		_menu_metric_elapsed = 0.0
		_refresh_menu_metrics()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and OS.get_name() == "Android":
		_refresh_menu_metrics.call_deferred()

## Bottom margin in reference-local units. Use the unscaled owner/root when
## fitting a child stage, to avoid feeding a stage's changed scale back into itself.
func menu_bottom_reserve(reference: CanvasItem = null) -> float:
	if OS.get_name() != "Android" or not _menu_visible:
		return 0.0
	var metrics := _read_menu_metrics()
	return _menu_reserve_from_pixels(metrics.native_banner_pixels, metrics.safe_bottom_pixels, metrics.density, _menu_pixels_per_unit(reference))

func menu_layout_metrics(reference: CanvasItem = null) -> Dictionary:
	if OS.get_name() != "Android":
		return {"active": false, "reserve": 0.0}
	var metrics := _read_menu_metrics()
	metrics["active"] = _menu_visible
	metrics["pixels_per_local_unit"] = _menu_pixels_per_unit(reference)
	metrics["reserve"] = menu_bottom_reserve(reference)
	return metrics

static func _menu_reserve_from_pixels(native_banner_pixels: float, safe_bottom_pixels: float, density: float, pixels_per_local_unit: float) -> float:
	if is_nan(density) or is_inf(density) or density <= 0.0:
		density = 1.0
	if is_nan(pixels_per_local_unit) or is_inf(pixels_per_local_unit) or pixels_per_local_unit <= 0.0:
		pixels_per_local_unit = 1.0
	if is_nan(native_banner_pixels) or is_inf(native_banner_pixels):
		native_banner_pixels = 0.0
	if is_nan(safe_bottom_pixels) or is_inf(safe_bottom_pixels):
		safe_bottom_pixels = 0.0
	var pixels := maxf(native_banner_pixels, 50.0 * density) + maxf(0.0, safe_bottom_pixels) + 12.0 * density
	return ceilf(pixels / pixels_per_local_unit)

func _menu_pixels_per_unit(reference: CanvasItem) -> float:
	if is_instance_valid(reference) and reference.is_inside_tree():
		# CanvasItem.get_screen_transform() uses the popup transform, which can
		# be identity when subwindows are embedded and omit canvas_items stretch.
		var local_to_pixels := reference.get_viewport().get_screen_transform() * reference.get_global_transform_with_canvas()
		var scale_y := local_to_pixels.y.length()
		if scale_y > 0.0 and not is_nan(scale_y) and not is_inf(scale_y):
			return scale_y
	var viewport_height := get_viewport().get_visible_rect().size.y
	var window_height := float(DisplayServer.window_get_size().y)
	return window_height / viewport_height if viewport_height > 0.0 and window_height > 0.0 else 1.0

func _read_menu_metrics() -> Dictionary:
	var window_size := DisplayServer.window_get_size()
	var screen_size := DisplayServer.screen_get_size()
	var safe_area := DisplayServer.get_display_safe_area()
	var dpi := DisplayServer.screen_get_dpi()
	var density := maxf(1.0, float(dpi) / 160.0)
	# Non-edge-to-edge Godot/Android safe-area coordinates may already omit the
	# top bar. Preserve a conservative standard 48dp navigation allowance rather
	# than assuming a zero/underreported deficit means no bottom obstruction.
	var immersive := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	var safe_bottom := _menu_safe_bottom_pixels(window_size.y, screen_size.y, safe_area.end.y, safe_area.size.y, density, immersive)
	var native_height := 0.0
	if is_instance_valid(_banner):
		native_height = maxf(0.0, float(_banner.get_height_in_pixels()))
	return {"window_pixels": window_size, "screen_pixels": screen_size, "safe_area_pixels": safe_area, "dpi": dpi, "density": density, "native_banner_pixels": native_height, "safe_bottom_pixels": safe_bottom, "viewport_units": get_viewport().get_visible_rect().size, "menu_visible": _menu_visible}

static func _menu_safe_bottom_pixels(window_height: float, screen_height: float, safe_end_y: float, safe_height: float, density: float, immersive: bool) -> float:
	# Insets can be unavailable during startup. An empty rectangle must not
	# reserve the entire screen and make every menu control inaccessible.
	if safe_height <= 0.0:
		return 48.0 * density
	var bottom := maxf(0.0, maxf(window_height, screen_height) - safe_end_y)
	return bottom if immersive else maxf(bottom, 48.0 * density)

func _refresh_menu_metrics() -> void:
	if OS.get_name() != "Android" or not is_inside_tree():
		return
	var metrics := _read_menu_metrics()
	metrics["reference"] = "root_viewport"
	metrics["pixels_per_local_unit"] = _menu_pixels_per_unit(null)
	metrics["reserve"] = _menu_reserve_from_pixels(metrics.native_banner_pixels, metrics.safe_bottom_pixels, metrics.density, metrics.pixels_per_local_unit) if _menu_visible else 0.0
	var key := JSON.stringify(metrics)
	if key == _menu_metric_key:
		return
	_menu_metric_key = key
	print("NATIVE_MENU_METRICS ", key)
	if not _menu_metric_signal_pending:
		_menu_metric_signal_pending = true
		_emit_menu_metric_change.call_deferred()

func _emit_menu_metric_change() -> void:
	_menu_metric_signal_pending = false
	menu_bottom_reserve_changed.emit()

func status() -> String:
	return _notice

func _set_notice(message: String) -> void:
	_notice = message
	service_notice.emit(message)
	availability_changed.emit()

func _refresh_consent() -> void:
	if not Engine.has_singleton("PoingGodotAdMobUserMessagingPlatform"):
		_set_notice("Consent service unavailable; ad requests are paused.")
		return
	var parameters := ConsentRequestParameters.new()
	parameters.tag_for_under_age_of_consent = bool(settings.get("admob", {}).get("tag_for_under_age_of_consent", false))
	UserMessagingPlatform.consent_information.update(parameters, _consent_updated, _consent_update_failed)

func _consent_updated() -> void:
	var information := UserMessagingPlatform.consent_information
	if information.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED and information.get_is_consent_form_available():
		UserMessagingPlatform.load_consent_form(_consent_form_loaded, _consent_update_failed)
	else:
		_finish_consent()

func _consent_form_loaded(form: ConsentForm) -> void:
	UserMessagingPlatform.active_consent_form = form
	form.show(func(_error: FormError) -> void: _finish_consent())

func _consent_update_failed(error: FormError) -> void:
	_set_notice("Consent update unavailable: " + error.message)
	_finish_consent()

func _finish_consent() -> void:
	var consent_status := UserMessagingPlatform.consent_information.get_consent_status()
	if consent_status not in [ConsentInformation.ConsentStatus.OBTAINED, ConsentInformation.ConsentStatus.NOT_REQUIRED]:
		_set_notice("Ads are paused until consent information is available. Local play is unaffected.")
		return
	if _ads_ready:
		return
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = _on_ads_initialized
	MobileAds.initialize(listener)

func privacy_options() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("PoingGodotAdMobUserMessagingPlatform"):
		UserMessagingPlatform.show_privacy_options_form(func(_error: FormError) -> void: _refresh_consent())
	else:
		_set_notice("Privacy options for advertising are available in the Android app.")

func _on_ads_initialized(_initialization: InitializationStatus) -> void:
	_ads_ready = true
	_load_banner()
	_load_interstitial()
	_load_rewarded()
	_set_notice("Android test ads are enabled." if bool(settings.get("admob", {}).get("test_mode", true)) else "Android ad services are ready.")

func _ad_id(kind: String) -> String:
	return str(settings.get("admob", {}).get(kind + "_unit_id", ""))

func set_menu_visible(visible: bool) -> void:
	_menu_visible = visible
	if is_instance_valid(_banner):
		if visible:
			_banner.show()
		else:
			_banner.hide()
	_refresh_menu_metrics()

func _load_banner() -> void:
	if not _ads_ready or _ad_id("banner").is_empty():
		return
	_banner = AdView.new(_ad_id("banner"), AdSize.BANNER, AdPosition.BOTTOM)
	var listener := AdListener.new()
	listener.on_ad_loaded = func() -> void:
		set_menu_visible(_menu_visible)
		_refresh_menu_metrics()
	listener.on_ad_failed_to_load = func(error: LoadAdError) -> void: _set_notice("Banner unavailable: " + error.message)
	_banner.ad_listener = listener
	_banner.load_ad(AdRequest.new())
	_refresh_menu_metrics()
	if not _menu_visible:
		_banner.hide()

func _load_interstitial() -> void:
	if not _ads_ready or _ad_id("interstitial").is_empty():
		return
	var callback := InterstitialAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_interstitial = ad
		var content := FullScreenContentCallback.new()
		content.on_ad_showed_full_screen_content = func() -> void: _ad_diagnostic("interstitial_presented")
		content.on_ad_dismissed_full_screen_content = func() -> void:
			_ad_diagnostic("interstitial_dismissed")
			_interstitial_closed()
		content.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
			_ad_diagnostic("interstitial_failed", error.message)
			_interstitial_closed()
		ad.full_screen_content_callback = content
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void: _set_notice("Interstitial unavailable: " + error.message)
	InterstitialAdLoader.new().load(_ad_id("interstitial"), AdRequest.new(), callback)

func round_finished() -> void:
	_round_count += 1
	if _round_count % 2 != 0 or _interstitial_showing or _reward_showing:
		return
	if is_instance_valid(_interstitial):
		_interstitial_showing = true
		_interstitial.show()
	elif _ads_ready:
		_load_interstitial()

func _interstitial_closed() -> void:
	_interstitial_showing = false
	if is_instance_valid(_interstitial):
		_interstitial.destroy()
	_interstitial = null
	_load_interstitial()

func _load_rewarded() -> void:
	if not _ads_ready or _ad_id("rewarded").is_empty():
		return
	var callback := RewardedAdLoadCallback.new()
	callback.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded = ad
		var content := FullScreenContentCallback.new()
		content.on_ad_showed_full_screen_content = func() -> void: _ad_diagnostic("rewarded_presented", _reward_context)
		content.on_ad_dismissed_full_screen_content = func() -> void:
			_ad_diagnostic("rewarded_dismissed", _reward_context)
			_rewarded_closed()
		content.on_ad_failed_to_show_full_screen_content = func(error: AdError) -> void:
			_ad_diagnostic("rewarded_failed", _reward_context + ": " + error.message)
			_rewarded_closed()
		ad.full_screen_content_callback = content
		availability_changed.emit()
	callback.on_ad_failed_to_load = func(error: LoadAdError) -> void:
		_set_notice("Rewarded ad unavailable: " + error.message)
		availability_changed.emit()
	RewardedAdLoader.new().load(_ad_id("rewarded"), AdRequest.new(), callback)

func can_reward() -> bool:
	return _native_ads and _ads_ready and is_instance_valid(_rewarded) and not _reward_showing and not _interstitial_showing

func reward_requested(context: String, callback: Callable) -> void:
	if not can_reward():
		if callback.is_valid():
			callback.call_deferred(false)
		_set_notice("No rewarded ad is available. You can keep playing normally.")
		return
	_reward_context = context
	_reward_callback = callback
	_reward_granted = false
	_reward_showing = true
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = _earned_reward
	_rewarded.show(listener)
	availability_changed.emit()

func _earned_reward(_item: RewardedItem) -> void:
	if _reward_granted or not _reward_callback.is_valid():
		return
	_reward_granted = true
	var native_event := _native_ads and _reward_showing and is_instance_valid(_rewarded)
	var earned_context := _reward_context
	var callback := _reward_callback
	_reward_callback = Callable()
	callback.call(true)
	if native_event:
		_ad_diagnostic("rewarded_earned", earned_context)
	_set_notice("Reward earned: " + _reward_context)

func _ad_diagnostic(event: String, context: String = "") -> void:
	if OS.get_name() == "Android" and OS.is_debug_build() and _native_ads:
		print("NATIVE_AD_EVENT ", JSON.stringify({"event": event, "context": context}))

func _rewarded_closed() -> void:
	_reward_showing = false
	if _reward_callback.is_valid():
		var callback := _reward_callback
		_reward_callback = Callable()
		callback.call(false)
	if is_instance_valid(_rewarded):
		_rewarded.destroy()
	_rewarded = null
	_reward_context = ""
	_load_rewarded()
	availability_changed.emit()

func _start_play_games() -> void:
	var pgs: Dictionary = settings.get("play_games", {})
	if not bool(pgs.get("enabled", false)) or str(pgs.get("game_id", "")).is_empty():
		_set_notice("Play Games configuration is pending; achievements and scores are saved locally.")
		return
	var plugin := get_node_or_null("/root/GodotPlayGameServices")
	if plugin == null or not Engine.has_singleton("GodotPlayGameServices"):
		return
	if plugin.initialize() != 0:
		return
	_sign_in_client = PlayGamesSignInClient.new()
	_achievements_client = PlayGamesAchievementsClient.new()
	_leaderboards_client = PlayGamesLeaderboardsClient.new()
	add_child(_sign_in_client)
	add_child(_achievements_client)
	add_child(_leaderboards_client)
	_pgs_ready = true
	_sign_in_client.user_authenticated.connect(_authentication_changed)
	_sign_in_client.is_authenticated()

func sign_in() -> void:
	if _pgs_ready:
		_sign_in_client.sign_in()
	else:
		_set_notice("Play Games requires your app ID, credentials and tester configuration. Local progress is saved.")

func _authentication_changed(authenticated: bool) -> void:
	_signed_in = authenticated
	if authenticated:
		_flush_pending()
		_set_notice("Signed in to Google Play Games.")
	else:
		_set_notice("Play Games sign-in was unavailable or cancelled; local progress is safe.")

func unlock(key: String) -> void:
	_pending_unlocks[key] = true
	_save_pending()
	_flush_pending()

func submit(key: String, value: int) -> void:
	_pending_scores[key] = maxi(value, int(_pending_scores.get(key, value)))
	_save_pending()
	_flush_pending()

func _flush_pending() -> void:
	if not _pgs_ready or not _signed_in:
		return
	var pgs: Dictionary = settings.get("play_games", {})
	var achievements: Dictionary = pgs.get("achievements", {})
	var leaderboards: Dictionary = pgs.get("leaderboards", {})
	for key in _pending_unlocks:
		var remote_id := str(achievements.get(key, ""))
		if not remote_id.is_empty():
			_achievements_client.unlock_achievement(remote_id)
	for key in _pending_scores:
		var remote_id := str(leaderboards.get(key, ""))
		if not remote_id.is_empty():
			_leaderboards_client.submit_score(remote_id, int(_pending_scores[key]))
	# Retain best scores and unlocks locally; resubmission is idempotent and survives failed uploads.

func open_achievements() -> void:
	if _pgs_ready and _signed_in:
		_achievements_client.show_achievements()
	else:
		_set_notice("Local achievements remain available; online achievements need Play Games sign-in.")

func open_leaderboards(key: String = "") -> void:
	if not _pgs_ready or not _signed_in:
		_set_notice("Local records remain available; online leaderboards need Play Games sign-in.")
		return
	var remote_id := str(settings.get("play_games", {}).get("leaderboards", {}).get(key, ""))
	if remote_id.is_empty():
		_leaderboards_client.show_all_leaderboards()
	else:
		_leaderboards_client.show_leaderboard(remote_id)

func _load_pending() -> void:
	if not FileAccess.file_exists(PENDING_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PENDING_PATH))
	if parsed is Dictionary:
		_pending_unlocks = parsed.get("unlocks", {})
		_pending_scores = parsed.get("scores", {})

func _save_pending() -> void:
	var file := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"unlocks": _pending_unlocks, "scores": _pending_scores}))

func _exit_tree() -> void:
	if is_instance_valid(_banner):
		_banner.destroy()
	if is_instance_valid(_interstitial):
		_interstitial.destroy()
	if is_instance_valid(_rewarded):
		_rewarded.destroy()

func is_gameplay_blocked() -> bool:
	return _reward_showing or _interstitial_showing
