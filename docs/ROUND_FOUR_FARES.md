# Round Four: a continuous taxi shift

Dispatch, pickup, completion and the next fare now use the same 3D city scene.
The compact incoming-fare card has Accept, Decline and Free drive actions. The
Fare button opens current-job information and cancellation. Cards park the cab
and clear held controls; closing a card never restores an old throttle contact.
Pickup and Complete fare still require a stopped cab at the actual gold curb.
Navigation still provides guidance only and never drives the car.

Completion banks the ordinary fare and XP once, then shows a contained result
card over the city. Next fare replaces that card with the next offer without
recreating the 3D world or moving the taxi. Home and Android Back retain their
existing park-and-save behavior.

## Optional doubled payout

The result's optional rewarded ad adds exactly the completed fare again,
including its actual clean-ride tip, for **2x total fare coins**. It does not
double the separate level-up bonus, XP, job count or daily completion count.
Unavailable, cancelled and unearned ads grant nothing. Web never simulates an
earned result. The game grants the bonus only after the native service reports
an earned callback for that request; actual native behavior still needs device
verification on the rebuilt application.

Save schema 3 stores the latest completed receipt, its serial number, whether
the result is still open and whether its doubled payout was already claimed.
Repeated taps, duplicate/stale callbacks and cold loads cannot repeat the bonus.
A new completed fare replaces the preceding receipt. Existing schema 1/2 banked
progress, accepted fares, car pose and previously earned next-fare sponsor boosts
are preserved. No historical completed-fare receipt is invented during migration.

## Visible passengers

Four supplied Kenney Mini Characters GLBs and their original colormap supply
actual skinned 3D passengers. An accepted passenger waits at the pickup curb,
walks to the stopped cab when picked up, then leaves the cab and walks away on
dropoff. The departing character hides after leaving the camera view. These
presentation animations pause when the application is covered; they never
advance fare/payment state. Reloading an accepted onboard fare restores an
onboard passenger rather than replaying pickup or granting a new reward.

Exact source-pack paths and hashes are in `assets/3d/SOURCE_MANIFEST.json`;
the unchanged CC0 notice is in
`LICENSES/Assets/kenney_mini-characters/License.txt`.

## Verification and remaining acceptance

Run with process-local disposable APPDATA/LOCALAPPDATA directories, never the
owner's real profile:

```sh
godot --headless --path . --script tests/test_round_four_fares.gd
godot --headless --path . --script tests/test_model.gd
godot --headless --path . --script tests/test_taxi_3d.gd
godot --headless --path . --script tests/test_city_graph.gd
godot --headless --path . --script tests/test_camera_3d.gd
godot --headless --path . --script tests/test_camera_fallback_3d.gd
godot --headless --path . --script platform/tests/services_smoke.gd
```

The Round Four suite exercises model idempotence, schema migration, isolated
file cold load, contained result/dispatch cards preserving the same 3D world,
actual imported passenger meshes/walk clips, coverage pause, and mocked
earned/unearned/unavailable service outcomes. These are synthetic source/engine
fixtures, not Android fare completion or real earned-ad proof.

The existing reserved genuine Android fare remains untouched and unverified.
The rebuilt app still needs genuine pickup/delivery/payment/reload acceptance,
real test-ad earned and dismissal flows, and visual checks of the changed fare
cards and passengers on phone/tablet. Refresh changed visual captures with
truthful build provenance. Retain the historical APKs and their separate QA;
do not attribute old screenshots or native results to this runtime update.

Android architecture/AAB changes and their validation are documented separately
in `docs/ROUND_FOUR_ANDROID.md`. Physical-device controls, audible output,
interactive Web and production service/backends remain owner acceptance work.
