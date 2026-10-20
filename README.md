# Pixel Taxi Neighborhoods

A little city. A thousand small stories.

Drive a connected city across industrial, downtown and suburban districts. Pick up fares, deliver passengers, meet rare riders, upgrade your cab and grow your driver level.

## Play

Choose a job, steer manually or tap a connected road destination, collect the passenger and follow the delivery route. Spend fares on upgrades and check daily jobs and your passenger journal.

Touch/mouse portrait play and offline local saves are supported. Android is the primary target; Web retains gameplay and saves when Android services are unavailable. Browser play never grants pretend ad rewards.

## Development

Original code: Apache-2.0. Developer: [EthannYakabuski](https://github.com/EthannYakabuski). Included assets/plugins retain their own licenses and notices.

Use Godot **4.5.1**, **Compatibility**, matching export templates, Java 17 and the Android SDK. The test preset uses minimum API 24 and target API 35. This is a test-configured build; final release signing, current Play requirements and production backend verification remain with the owner. See [native setup](docs/PLATFORM_SETUP.md).

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/test_model.gd
godot --headless --path . --script platform/tests/services_smoke.gd
godot --headless --path . --export-release Web build/web/index.html
godot --headless --path . --install-android-build-template --export-debug Android build/android/game-debug.apk
```

Create build/web and build/android first. Android package: `com.ethannyakabuski.pixeltaxi`. Tests and capture helpers are documented under game/ and tests/. No Windows build is supplied.

## Integration and handoff

AdMob uses Google's official test IDs. Menus support a banner, every two completed rounds create an interstitial opportunity, and rewarded benefits require the earned-reward callback. Unavailable ads or consent leave normal play usable. Google Play Games uses symbolic achievement/leaderboard maps with empty production IDs and is disabled until the owner configures them. See platform/config.json and docs/PLATFORM_SETUP.md.

Marketing text, icons, feature art and screenshot provenance are in marketing/. The current evidence, limitations and exact next owner actions are in HANDOFF.txt. Production backend testing, human playtesting and Google Play publication are human-owned.

## CI and Web

Hosted GitHub Actions imports resources, runs game/service tests, exports Web and an Android debug APK, and deploys Web through Pages. Build outputs, caches and signing keys are excluded from source. Confirm actual run results in HANDOFF.txt; workflow presence alone is not a passing CI claim.

## Future extension

Night Shift: evening fares, neon weather and a new rare-passenger set.

## Licenses

See [the complete accompanying notices](LICENSES/INDEX.txt) for the engine,
fonts, plugins and assets. Keep the `LICENSES` directory with every redistributed
Android or Web build; original-code Apache licensing does not replace third-party
terms. CI copies these notices beside both exports and includes them with the
Android artifact.

## Public source and deployment status

This repository publishes the existing local-test source package. The recorded HANDOFF and docs describe their dated local verification; they do not establish production service, physical-device, audio, browser or human acceptance.

GitHub-hosted build/test/artifact CI is configured. The Pages deployment job is explicitly skipped pending separate authorization; no live Pages site is claimed. No real saves, private coordinator evidence, credentials, signing identities or prebuilt APK/Web exports are committed. Build outputs remain CI artifacts.

Apache-2.0 covers original project work. Third-party assets, fonts, engine and plugins retain their own terms in LICENSES and source notices; where present, Creature Mixer custom terms exclude NFT/blockchain projects and are not CC0.
