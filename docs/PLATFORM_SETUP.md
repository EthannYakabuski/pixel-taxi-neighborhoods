# Android integrations and build handoff

## Current Round 4 Android export

The preset currently uses minimum API **24** / target API **35**, Gradle **AAB**, and ARM64, x86 and x86_64. These settings are configurable choices, not a fixed Godot target-SDK limit. Follow the [Round 4 Android guide](ROUND_FOUR_ANDROID.md); create a new unused output directory, export a debug `.aab`, then run `tools/verify_android_bundle.py` on the actual bundle.

The debug AAB is test-signed; release signing stays with the owner outside Git. ABI validation alone does not establish native gameplay, production services or Google Play acceptance. Exact Round 4 source CI and affected native checks are pending in this dated 2026-10-24 snapshot unless later source-bound handoff records establish them. Preserve historical APK/native QA identities; no new-game work is authorized by this continuation.

This project targets Godot **4.5.1 Compatibility**, Android (API35 target, min24), and a single-threaded Web export. Windows desktop builds are outside its scope. Production Play publication remains a separate human step: verify the then-current target API policy before release; a successful API35 test build is not a claim of current store-submission eligibility.

## Runtime services

`Services` is the game-facing adapter. Its Android implementation calls the supplied Poing AdMob **5.1.0** and Godot Play Games Services **3.4.0** packages. The Web/editor implementation never simulates a successful rewarded ad. Gameplay, saves, achievements and best scores continue locally.

- Menu banner: native 320x50dp banner anchored at the screen bottom. Menu UI consumes `Services.menu_bottom_reserve(reference)` and listens to `menu_bottom_reserve_changed`; gameplay calls `set_menu_visible(false)`.
- Interstitials: every second completed round/outage/job, when an ad is loaded; no added fixed-time throttle. Failed/unavailable ads do not prevent play.
- Rewarded: opt-in, available only after a real native rewarded ad loads; benefits granted only on the earned-reward callback, once per request. Dismissal/failure grants nothing.
- Consent: refresh UMP consent at Android launch, show a required form, and initialize advertising only after `OBTAINED` or `NOT_REQUIRED`. A privacy-options action is exposed. Without configured/available consent information, requests pause and gameplay continues. Google's sample AdMob app does not prove the publisher's eventual privacy-message configuration; this requires human final configuration/testing.
- Play Games: disabled until real app configuration is provided. Local unlocks and best scores are retained in `user://platform_pending_v1.json` and resubmitted idempotently after sign-in. Only the configured symbolic keys map to remote IDs.

### Menu geometry

`menu_bottom_reserve(reference: CanvasItem = null) -> float` returns the Android menu's required bottom margin in the reference node's local units. It uses the greater of the measured banner pixel height or a conservative 50dp unloaded fallback, adds safe-bottom pixels and12dp padding, then converts through `reference.get_viewport().get_screen_transform() * reference.get_global_transform_with_canvas()`. This retains window stretch when subwindows are embedded; `CanvasItem.get_screen_transform()` alone can omit that stretch. Non-immersive Android keeps a conservative48dp navigation allowance because safe-area coordinates can already omit system bars. The result is0 outside Android or while the menu banner is hidden.

Connect the no-argument `menu_bottom_reserve_changed` signal once, then update existing geometry after setting banner visibility. Measurements refresh on banner creation/load, viewport resize, resume, and half-second menu polling. Anchored containers use the result as a bottom margin. Fixed-position menus must fit/reposition their children within the usable rectangle; merely reducing a root's size does not move its fixed children. Query a stable owner/root when fitting a child stage, rather than feeding the newly scaled child's units back into its own scale. Keep gameplay geometry unchanged when the banner is hidden. Position menu toasts and modal controls above the same reserved region.

`menu_layout_metrics(reference)` exposes raw measurements for QA, and Android logs changed measurements as `NATIVE_MENU_METRICS`. Unit calculations with the supplied phone geometry (131px banner,126px navigation allowance,420dpi,1.8screen pixels per local unit) require161logical units; this is calculation evidence, not proof that a rebuilt Android layout has passed device testing. Actual menu/banner separation still requires screenshots and touch checks on the rebuilt APK.

Coordinate references: https://docs.godotengine.org/en/4.5/classes/class_canvasitem.html#class-canvasitem-method-get-screen-transform and https://docs.godotengine.org/en/4.5/classes/class_displayserver.html#class-displayserver-method-get-display-safe-area . Godot4.5.1's Android safe-area handling is in https://github.com/godotengine/godot/blob/4.5.1-stable/platform/android/java/lib/src/org/godotengine/godot/GodotIO.java .

## Human configuration

Android debug builds log `NATIVE_AD_EVENT` only from actual SDK presentation, dismissal, failure, and accepted earned-reward callbacks. `rewarded_earned` is logged after the game's successful callback and only once, with its event context. Request attempts are not presentation proof. Editor/Web unit callback exercises never emit these native diagnostics; no analytics or network calls were added.

1. Keep test IDs in use during development. Google's Android sample app ID and banner/interstitial/rewarded units are recorded in `platform/config.json`. The native SDK's manifest app ID comes from the project setting `admob/general/android/app_id`, with the plugin's same Google sample ID as its default. An absent `[admob]` section in `project.godot` is normal when this default is unchanged; the editor can omit default-valued settings. For production, set the real app ID in Godot Project Settings (serialized under `[admob]` as `general/android/app_id`) and update the JSON reference value too. JSON `admob.app_id` alone does not change the Android manifest. Source: `addons/admob/internal/exporters/android/export_plugin.gd:112-125` and `internal/services/project_settings_service.gd:27,62-63,124-130`.
2. In `platform/config.json`, fill `play_games.game_id`, set `enabled` to true, and map every game/catalog achievement and leaderboard key to its console ID. Set the same numeric game ID in `export_presets.cfg` (`godot_play_game_services/game_id`). The export's value `0` is a deliberate inactive placeholder, not a working Google project.
3. Configure package name, OAuth clients/signing fingerprints, authorized testers, Play Games resources, AdMob app/privacy messages, audience and production ad IDs in the owner's consoles. Supply signing material outside source control. Confirm applicable consent/audience settings before production.
4. Test real sign-in cancellation/failure, score/achievement submission, consent/privacy options, all test-ad formats, save persistence, offline behavior, and suspend/resume on the intended devices. Human production-ID/backend testing is distinct from passing local/CI tests.
5. Google Play publication remains the owner's responsibility. No workflow submits to Google Play or uses production signing keys.

## Build

Install/reuse Godot4.5.1, its matching export templates, Java17 and Android SDK platform35/build tools35, NDK28.1.13356709. A new workstation must have these dependencies available; the hosted workflow provisions its own isolated runner dependencies.

```sh
godot --headless --editor --path . --import
godot --headless --path . --script platform/tests/services_smoke.gd
godot --headless --path . --install-android-build-template --export-debug Android build/android/game-debug.aab
godot --headless --path . --export-release Web build/web/index.html
```

Create output directories first. The debug AAB is test-signed bundle software; it is not a production-signed release or directly installable APK. The preset includes ARM64, x86 and x86_64; every selected 32-bit ABI has its 64-bit counterpart. Release/AAB signing is performed only when the owner supplies signing configuration. `android/build` is generated from matching Godot templates and must not be committed with machine-local SDK paths/caches/keys.

The Android preset intentionally uses `runnable=false`. CLI exports still work; this prevents Godot's editor shutdown path from stopping the shared ADB server during a Web export. No global editor setting is changed. The API30 emulator also needs `rendering/shader_compiler/shader_cache/enabled.android=false` for its observed GL program-binary failure; retain the existing project setting unless an affected-device regression justifies changing it.

Enable `rendering/textures/vram_compression/import_etc2_astc=true` in project settings before importing assets for Android. Keep desktop texture import enabled for Web. Tests, test-only platform scripts, captures, marketing packages, helper scripts, logs and documentation are excluded from shipping resource packs. Copy the app icon to `platform/app-icon-512.png` and point the project icon setting there so excluding `marketing/` does not remove its runtime resource. Game catalogs and runtime art/audio remain included.

Hosted Actions verifies pinned Godot download digests, builds and validates the native Android debug AAB, validates Web/editor service fallback behavior, discovers and runs `tests/test_*.gd`, `tests/*_test.gd`, and `tests/smoke.gd` (requiring at least one), exports Web, retains Android artifacts seven days, and uploads Web artifacts. Pages deployment is disabled; no live site is configured by this workflow. Test processes have bounded timeouts; logs containing script/parse/assertion errors fail even if Godot exits0. CI does not substitute for human playtesting or verify unpublished Google service IDs. Do not enable Pages as part of ordinary updates.

## Vendored dependencies and notices

- `addons/GodotPlayGameServices`: user's supplied3.4.0 copy, including required MIT license and native debug/release AARs.
- Its copied exporter checks Android build templates only for Android exports, avoiding irrelevant warnings during Web export.
- `addons/admob`: user's supplied5.1.0 source, MIT license retained. Native Android `ads`/core AARs came from the official `android-template-v4.5.1.zip` release asset: https://github.com/poingstudios/godot-admob-plugin/releases/download/v5.1.0/android-template-v4.5.1.zip . SHA256 `f7fdf644d50c0e231d8f02ae044057e489d0bcafcf50e908a4858477e7ee05ee` verified against GitHub's release digest.
- No mediation networks or iOS binaries are bundled. A documented one-line change removes the copied AdMob editor's automatic binary installer call because Android binaries are already vendored and iOS is outside this project. Runtime APIs and native exports remain intact. Original source asset folders are untouched.
- Original project code uses Apache2.0; third-party components retain their own licenses. Preserve notices in the repository and distributed game's credits/licenses screen.

Public upstream references: https://github.com/poingstudios/godot-admob-plugin and https://github.com/godot-sdk-integrations/godot-play-game-services .

## Continue service configuration

This game has **16 achievement** and **4 leaderboard** definitions in `game/catalog.json`. Use their symbolic keys in `platform/config.json` under `play_games.achievements` and `play_games.leaderboards`; the existing keys must remain unchanged when inserting console IDs. Play Games is currently disabled and its IDs are blank. Set `play_games.game_id`, and set the same numeric value in the Android export preset at `godot_play_game_services/game_id` in `export_presets.cfg`, before enabling the configured service. Configure the package, OAuth signing fingerprints and authorized testers in the owner consoles.

`platform/config.json` also supplies banner/interstitial/rewarded unit IDs. Its `admob.app_id` is a reference value, not the Android manifest input: set the manifest App ID through Godot Project Settings `admob/general/android/app_id`, serialized as `general/android/app_id` under `[admob]` in `project.godot`, and keep the JSON reference consistent. The missing override is normal while the plugin default is Google's sample App ID. `test_mode` in this adapter only changes the displayed status wording; it does not substitute sample unit IDs or register test devices. Keep Google sample IDs for development, or explicitly configure and verify SDK test devices before using production units.

Run tests with disposable, process-local user-data roots. On Windows, redirect `APPDATA` and `LOCALAPPDATA` for the test child process; do not change the owner's global environment. Include `user://platform_pending_v1.json` in that isolation. A mocked callback or successful build does not establish native/production behavior. Follow `HANDOFF.txt` for the accepted local QA APK and remaining verification.
