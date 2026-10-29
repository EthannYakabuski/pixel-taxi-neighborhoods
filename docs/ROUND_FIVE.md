# Round Five: dispatch and passenger fairness

After a confirmed dropoff, the cab stays in the same city and returns automatically to free driving for 5–20 active-play seconds. A new fare then opens an acceptance prompt; dispatch never accepts it automatically. The saved timer does not advance behind a fare card, full-screen ad, background pause or unresolved save/reward transaction. A storage failure keeps the existing retry card and blocks new work until that exact fare is safely banked.

The optional once-only completed-fare bonus remains available under **Fare** during the break. Waiting, save retries and reopening the receipt never repeat coins, XP or completed-fare notifications. Save format 4 adds the remaining dispatch time; versions 1–3 and existing accepted fares remain supported.

Only collisions while the passenger is physically inside the taxi reduce the clean-ride tip and display its bump warning. Approaching the pickup, the walk-to-cab animation, free driving and the departed passenger cannot incur tip penalties. Base fares and the existing time/distance qualification are unchanged.

Home retains a bottom banner. Driving uses a top banner in place of the large title, with the Manual Drive/level and coin labels below its reserved strip. The driving HUD shows passenger name, speed and distance. Fare cards park the cab, replace its controls and fit between the HUD and safe bottom feedback row. Android banner metrics and system insets are still device-dependent and need real-device inspection.

Interstitial opportunities occur only at each tenth durably saved completed fare, using its absolute saved total. Duplicate completion notifications cannot reopen the same opportunity. If no ad is available, play continues; a later load does not unexpectedly open an ad during driving. No forced ad, paid service or synthetic native callback is used.

## Validation and remaining acceptance

`tests/test_round_five.gd` covers saved wait intervals, explicit acceptance, paused dispatch, legacy accepted-fare retention, physical passenger collision phases, scene-driven completion banking, ten-fare boundaries and banner/card geometry at three viewport sizes. Its callbacks, transactions and profiles are isolated fixtures, not evidence of a genuine fare or SDK ad. Existing route, camera, input and reward-storage fault suites remain strict.

Run fixtures with process-local `APPDATA`/`LOCALAPPDATA` on Windows or `XDG_DATA_HOME`/`XDG_CONFIG_HOME` on Linux. Set `DOTS_TEST_ROOT` to their disposable parent; the new fixture refuses an ordinary or Android profile. CI supplies a new isolated directory for each discovered test.

Fresh interactive Web inspection, Android rendering/banner/ad lifecycle, genuine end-to-end driving, physical-device audio and signed-in production services must be recorded separately. Historical native APKs and screenshots retain their original build provenance; a source pass or CI export does not replace those runtime checks. Preserve the owner's reserved Taxi test state.
