# Manual 3D city update

The current source uses real supplied Kenney car, road, commercial/suburban/industrial building and nature models. A perspective camera follows the player's car. The city contains49 stable addresses,68 curved connected road segments and450 physical building footprints across Foundry, Central and Garden. The street layout has neighborhood loops, inner courtyards, a central boulevard and separate inter-district arterials. Hardware-instanced actual model meshes reduce repeated draw submissions for the Compatibility renderer. Exact supplied model/atlas bytes and unchanged CC0 notices are recorded in `assets/3d/SOURCE_MANIFEST.json` and `LICENSES/Assets/`.

## Player control and GPS

Hold and drag the drive pad to accelerate and steer with one thumb. Separate left/right steering buttons, brake and hold-to-reverse allow two-thumb play and recovery from obstacles. Keyboard arrows or W/S/A/D and Space are also available. Release the drive control to coast; use the brake to stop at the gold passenger curb. Home stops driving and preserves the current fare/pose. Map changes the camera only.

Dispatch offers one persisted contract with accept/decline. Guidance projects the actual vehicle position onto the occupied curved street and compares both endpoint costs before choosing the shortest weighted route. Wrong turns recalculate the visible gold route and turn cue. GPS never changes throttle, steering, heading or car position. There is no auto-drive mode.

Physical traffic/building contact slows and bumps the car, shakes the following camera and counts against fare quality. One overlap cannot repeatedly score hits during its grace period. A new/restored drive places nearby traffic far enough away to react; later traffic remains physical. Collisions do not remove banked coins. Clean, timely passenger driving can earn a20% tip within the configured bounds; a damaged or late trip keeps its normal fare. The fare timer counts foreground driving time, including idling, after pickup. Fullscreen coverage freezes physics/time and requires explicit Resume on return.

## Save compatibility and services

The existing save filename is unchanged. Version2 adds actual car pose, persisted dispatch sequence/offer and collision/time/distance metrics. Migration keeps all24 original banked profile groups, purchases, claims, passenger journal and earned fare boosts. An already accepted legacy fare retains its original fare and distance/XP entitlement; because its prior driving quality was not recorded, tips begin with the next new dispatch. No prior progress is manufactured or removed.

Official AdMob sample IDs and disabled PGS placeholders remain. Symbolic achievement/leaderboard definitions are unchanged. Production ID setup remains in `docs/PLATFORM_SETUP.md`, including the AdMob manifest Project Setting versus JSON reference value. Reward benefits still require the earned native SDK callback; offline fallback grants no pretend ad reward.

## Verification and remaining acceptance

The graph suite checks all-pairs weighted shortest routes independently, connected legal street crossings and exact projection/guidance. Model tests cover legacy entitlement migration, persisted single offers, economy/daily/reward accounting and qualifying tips. The integrated scene test exercises actual Physics3D movement/collision, touch steering, GPS non-driving/wrong-turn recalculation, fullscreen freeze/Resume and a file/scene cold load of pose and picked-up fare. These are synthetic isolated source tests, not real SDK gameplay or player-save evidence.

Actual Godot Compatibility GPU views were inspected for all three districts, following-car framing, street continuity, GPS cues, readable controls and distinct model types. Illustrative marketing artwork and these source diagnostics must never replace final-build native screenshots. The APK/native QA in `HANDOFF.txt` identifies the retained earlier build. New Android/Web exports, native collision/manual delivery/reward/ad-return/Back/save/offline checks and final-build captures remain required. Human handling/balance/long-session review, audible output, physical devices, interactive Web and production services remain unverified.

Use Godot4.5.1 Compatibility, Android primary and Web secondary. The observed test preset remains minAPI24/target35, not a current Play release-eligibility claim. No Pages activation, Library change, Windows export or Google Play publication is included.
