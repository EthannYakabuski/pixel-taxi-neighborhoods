# Pixel Taxi Neighborhoods: Google Play Games achievement import

Prepared 2026-11-12. Upload only **pixel-taxi-neighborhoods-achievements-google-play.zip** from this directory.
The ZIP contains two headerless CSVs and 16 original 512 x 512 PNGs at
its root. Companion files are intentionally outside the ZIP.

## Choices to review before import

- All 16 achievements are Standard (Incremental Value False; steps blank).
  game/main.gd reports completed local achievements to platform/services.gd, whose
  PGS adapter calls unlock_achievement, not increment or set-steps. Local progress
  thresholds do not make them PGS incremental achievements.
- All start Revealed. Point values range from 10 to
  100, totaling 640; 1360 points remain below
  Google's 2000-point game allowance. Higher milestones generally receive more.
  Points and initial states are proposed package choices, not catalog values.
  Review them before publishing, when type and initial state become immutable.
- Names, catalog order and original icon bytes are preserved. Google prohibits
  commas in names/descriptions, even if quoted, so only these descriptions were
  normalized in the import (the game catalog itself is unchanged):
- taxi_earned: "Earn 10,000 coins from fares." -> "Earn 10000 coins from fares."

## Import and ID mapping

1. Select this game in Play Console > Play Games Services > Setup and management >
   Achievements > Import achievements, then upload only the ZIP.
2. Review the rows, points, initial states and icons, and save as draft.
3. Copy generated IDs into achievement-id-mapping-and-points.csv and map each
   CatalogKey to its corresponding platform/config.json entry. This package does
   not bind generated IDs, change configuration, enable services or publish.
4. Configure/test the PGS integration before publishing. If achievements already
   exist, reconcile Console definitions first to avoid duplicate imports. Console
   contents were not inspected and no Console upload or native test was performed.

Metadata supplies the catalog's English text for the game's default locale.
Confirm the intended English default locale before import. The optional
AchievementsLocalizations.csv is omitted; no translations were invented.

## Reproduce and validate

From the project root, run:
    python tools/build_play_games_achievements.py
To verify tracked outputs without modifying them:
    python tools/build_play_games_achievements.py --check

Python 3 standard library only. The generator reads game/catalog.json, original
marketing/achievements PNGs, platform/services.gd and the explicit proposed point
map in tools/play_games_achievement_points.json. Validation checks CSV fields,
names, mappings, PNG dimensions/chunk CRC/decompression, archive CRC and exact
source icon bytes, total points, and Google's file/layout/size constraints.
validation-report.json records LF-normalized source text hashes and exact icon/ZIP
hashes. The text output check tolerates Git checkout line endings. ZIP output is
deterministic; a same-input rerun must match byte-for-byte.

This is an import-package validation, not Google Play acceptance, gameplay QA or
a release build. No runtime, signing configuration, saves or existing artifacts
were changed. Source and asset notices remain in LICENSE, NOTICE and LICENSES.

Official references checked 2026-11-12:
- https://developer.android.com/games/pgs/integrate-achievements#zip-file-guidelines
- https://developer.android.com/games/pgs/achievements#points_and_experience_points
