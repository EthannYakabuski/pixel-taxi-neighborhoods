# Pixel Taxi continuation checkpoint

Updated2026-10-22. **Round Two native core/fare: NOT READY.**

- Runtime: `1f7e068f7ebfb3594f078d4fe0fc0a424e0a30de`.
- Local Android candidate: `3E42A66EF772EAE02B047E3CF75DCABF5E21F49275E527EADFD0708488D7D0CB`; full local paths/export identities and qualifications are in `HANDOFF.txt`.
- [Runtime CI passed](https://github.com/EthannYakabuski/pixel-taxi-neighborhoods/actions/runs/39752004038). Documentation CI is separate. No local rebuild is required for this status update.
- Current native evidence: update retained genuine profile; Home and stopped Map navigation rendered/responded. A bounded driving attempt stopped before pickup. Current fare completion, once-only payout and payment retention after reload remain incomplete.
- Preserve the genuine accepted fare, boost, progression and collision history. Do not reset or manufacture state, replay rewards or treat an earlier APK's successful fare as current proof.
- Next permitted validation is the [manual Android fare checklist](docs/MANUAL_ANDROID_FARE_QA.md), followed by affected native checks and six distinct actual screenshots per phone/logical7-inch/logical10-inch profile. This checkpoint does not itself authorize another automated driving recovery.
- The previous sanitized handoff is retained in `docs/history/HANDOFF-before-round-two-native-status-20261022.txt`. Its original APK/archive and recorded Round One proof remain historical.
- Do not alter physics, routing, economy, service values or camera merely to obtain a successful test. The latest incomplete attempt established no new source defect.
- Read `AGENTS.md`, `README.md`, `HANDOFF.txt` and `docs/PLATFORM_SETUP.md` before a fresh task. Keep private records, profiles and logs out of published files; inspect the current Git diff and preserve user edits.
