# Pixel Taxi Neighborhoods: continuation

## Round 4 continuation

Work only on the requested Round 4 changes; do not start new games. The current Android default is Gradle **AAB**, min API **24** / target API **35**, with ARM64, x86 and x86_64. Follow the [Round 4 Android guide](docs/ROUND_FOUR_ANDROID.md) for current export instructions instead of older APK examples in historical guides.

The 2026-10-24 continuation snapshot does not claim passing exact-current-source CI or native acceptance for rebuilt Round 4 binaries. Record later source-bound checks in `HANDOFF.txt`; keep all dated original APK evidence intact. Debug AABs are test-signed bundles, distinct from owner-signed releases. Preserve user configuration and untracked files.

Open this repository root as the single active game project. Start each focused task by reading `README.md`, `HANDOFF.txt` and `docs/PLATFORM_SETUP.md`, then inspect Git status/diff. Do not assume an earlier conversation or use an archival staging copy as a parallel source of truth.

## Targets and verification

- Godot 4.5.1, Compatibility renderer; Android primary, single-threaded Web secondary. Current test export is min API 24/target API 35; owner verifies current release eligibility. No Windows export.
- The recorded passing public CI baseline and native-tested local APK SHA256 are in `HANDOFF.txt`. CI archives are separate binaries without that native QA. Keep original local artifacts unchanged; documentation-only edits need no rebuild.
- Run tests in isolated process-local user-data directories, including the platform pending-service store. Preserve real saves and never manufacture gameplay or native-ad evidence.
- For runtime changes, import scripts, run relevant game tests and the service smoke test, and retain strict error checks. Test rebuilt affected behavior before changing QA claims.

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/test_model.gd
godot --headless --path . --script tests/test_city_graph.gd
godot --headless --path . --script tests/test_taxi_3d.gd
godot --headless --path . --script platform/tests/services_smoke.gd
```

## Service IDs

- `game/catalog.json`: 16 achievements/4 leaderboards. Preserve symbolic keys; put console IDs in the matching `platform/config.json` maps. PGS starts disabled; set its numeric game ID both there and in `export_presets.cfg` at `godot_play_game_services/game_id`, with owner console/OAuth/signing/tester setup.
- AdMob unit IDs come from `platform/config.json`. Manifest App ID comes from `admob/general/android/app_id` in Godot Project Settings (`project.godot`), not JSON `admob.app_id`. Keep both reference values consistent.
- `test_mode` changes status wording only; it neither replaces production unit IDs nor registers SDK test devices. Keep Google sample IDs for ordinary development.

## Publication and scope

- Stage only reviewed project files. Private QA originals, raw logs, saves, backups, signing material, credentials, generated SDK builds and prebuilt exports stay out of published history. Ignore rules do not protect already tracked paths; inspect each diff.
- Preserve `LICENSE`, `NOTICE`, `LICENSES/` and asset/plugin terms. Retain notices with distributed binaries.
- Pages deployment remains disabled; no Library change or Google Play publication is part of ordinary updates. Production configuration, real-service/physical-device testing and human acceptance remain owner work.
- Work on the requested game/update. This continuation covers Round 4 only and does not authorize new games.

## Current 3D update

Read `docs/ROUND_TWO_3D.md`. Preserve all legacy banked progress, accepted fares and earned fare boosts during version-1 migration. Navigation must never write throttle, steering or car pose. The original APK QA describes the prior build; rebuild and test affected native behavior before refreshing that claim.
