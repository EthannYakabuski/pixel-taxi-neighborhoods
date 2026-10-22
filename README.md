# Pixel Taxi Neighborhoods

A little city. A thousand small stories.

Manually drive a real 3D Kenney taxi through connected industrial, downtown and suburban neighborhoods. Accept or decline a single dispatch offer, deliver passengers, earn clean/timely tips, meet rare riders, upgrade your cab and grow your driver level.

## Play

Accept or decline the current dispatch. Hold and drag the drive pad with one thumb to accelerate and steer; drag down deliberately to reverse while steering. Separate steering, brake and reverse controls support two-thumb play. Releasing the pad coasts; use Brake to stop. Keyboard W/S or arrows accelerate/reverse, A/D or arrows steer, and Space brakes. Stop at the gold curb to pick up or drop off. GPS highlights the weighted shortest road route and recalculates after a wrong turn; it never drives the car. Collisions slow the cab and affect tip eligibility, while banked coins remain safe. Spend fares on upgrades and check daily jobs and your passenger journal.

Touch/mouse portrait play and offline local saves are supported. Android is the primary target; Web retains gameplay and saves when Android services are unavailable. Browser play never grants pretend ad rewards.

## Development

Original code: Apache-2.0. Developer: [EthannYakabuski](https://github.com/EthannYakabuski). Included assets/plugins retain their own licenses and notices.

Use Godot **4.5.1**, **Compatibility**, matching export templates, Java 17 and the Android SDK. The test preset uses minimum API 24 and target API 35. This is a test-configured build; final release signing, current Play requirements and production backend verification remain with the owner. See [native setup](docs/PLATFORM_SETUP.md).

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/test_model.gd
godot --headless --path . --script tests/test_city_graph.gd
godot --headless --path . --script tests/test_taxi_3d.gd
godot --headless --path . --script platform/tests/services_smoke.gd
godot --headless --path . --export-release Web build/web/index.html
godot --headless --path . --install-android-build-template --export-debug Android build/android/game-debug.apk
```

Create build/web and build/android first. Android package: `com.ethannyakabuski.pixeltaxi`. Tests and capture helpers are documented under game/ and tests/. No Windows build is supplied.

**Round Two native core/fare status: NOT READY.** The current `1f7e068f` runtime has passing source CI and local Android/Web exports, but its genuine Android pickup, delivery, once-only payout and reload check remain incomplete. A bounded native attempt did not complete the fare; it does not establish human handling acceptance. See the [manual Android fare checklist](docs/MANUAL_ANDROID_FARE_QA.md), [current checkpoint](CHECKPOINT.md) and [3D update notes](docs/ROUND_TWO_3D.md). The original Round One QA APK/archive and its historical proof remain separate and unchanged.

## Integration and handoff

AdMob uses Google's official test IDs. Menus support a banner, every two completed rounds create an interstitial opportunity, and rewarded benefits require the earned-reward callback. Unavailable ads or consent leave normal play usable. Google Play Games uses symbolic achievement/leaderboard maps with empty production IDs and is disabled until the owner configures them. See platform/config.json and docs/PLATFORM_SETUP.md.

Marketing text, icons, feature art and screenshot provenance are in marketing/. The current evidence, limitations and exact next owner actions are in HANDOFF.txt. Production backend testing, human playtesting and Google Play publication are human-owned.

## CI and Web

GitHub Actions imports resources, runs game/service tests with strict error checks, exports Web and an Android debug APK, and uploads artifacts with the accompanying license notices. **Pages deployment is disabled**; this workflow does not publish a live site or submit to Google Play. Current build/test status is recorded below and in `HANDOFF.txt`. A passing run does not verify production services, physical devices or browser interaction.

## Continue development

Open this repository root as the game's Codex project and start a focused task for the requested change. Read `AGENTS.md`, this README, `HANDOFF.txt` and `docs/PLATFORM_SETUP.md` first; a new task must obtain its context from these files and the current Git diff, rather than assume it inherits an earlier chat. This is the active development copy; older publication/export staging copies are archival.

Verified runtime CI (2026-10-22): `1f7e068f7ebfb3594f078d4fe0fc0a424e0a30de`; [passing build/test run](https://github.com/EthannYakabuski/pixel-taxi-neighborhoods/actions/runs/39752004038). This proves source/build checks, not native fare completion. Earlier CI and Round One native results are retained in the [historical handoff](docs/history/HANDOFF-before-round-two-native-status-20261022.txt).

This game has **16 achievement** and **4 leaderboard** definitions in `game/catalog.json`. Use their symbolic keys in `platform/config.json` under `play_games.achievements` and `play_games.leaderboards`; the existing keys must remain unchanged when inserting console IDs. Play Games is currently disabled and its IDs are blank. Set `play_games.game_id`, and set the same numeric value in the Android export preset at `godot_play_game_services/game_id` in `export_presets.cfg`, before enabling the configured service. Configure the package, OAuth signing fingerprints and authorized testers in the owner consoles.

`platform/config.json` also supplies banner/interstitial/rewarded unit IDs. Its `admob.app_id` is a reference value, not the Android manifest input: set the manifest App ID through Godot Project Settings `admob/general/android/app_id`, serialized as `general/android/app_id` under `[admob]` in `project.godot`, and keep the JSON reference consistent. The missing override is normal while the plugin default is Google's sample App ID. `test_mode` in this adapter only changes the displayed status wording; it does not substitute sample unit IDs or register test devices. Keep Google sample IDs for development, or explicitly configure and verify SDK test devices before using production units. See [platform setup](docs/PLATFORM_SETUP.md).

Preserve original local packages and QA evidence. Current candidate and historical native-tested APK identities are distinguished in `HANDOFF.txt`; hosted CI archives contain separately built binaries that have not received the local native QA. Documentation-only changes do not require rebuilding or replacing the original QA APK. Run tests with isolated process-local user-data directories, including the platform pending-service store, so the owner's real saves cannot be changed. Preserve notices and inspect explicit file diffs before staging.

## Future extension

Night Shift: evening fares, neon weather and a new rare-passenger set.

## Licenses

See [the complete accompanying notices](LICENSES/INDEX.txt) for the engine,
fonts, plugins and assets. Keep the `LICENSES` directory with every redistributed
Android or Web build; original-code Apache licensing does not replace third-party
terms. CI copies these notices beside both exports and includes them with the
Android artifact.

## Public source and local artifacts

Public repository: [Pixel Taxi Neighborhoods](https://github.com/EthannYakabuski/pixel-taxi-neighborhoods). Current source and this continuation documentation are tracked here. Prebuilt exports, real saves, private QA records, credentials and signing material stay outside the published source history. Local artifact availability is described in `HANDOFF.txt`; a fresh clone does not contain the original debug APK.

Original work is Apache-2.0; assets, fonts, engine and plugins retain their own terms in `LICENSES/`, `NOTICE` and source notices. Creature Mixer assets, where used, have custom non-NFT/non-blockchain terms and are not CC0.
