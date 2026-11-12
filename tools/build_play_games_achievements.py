#!/usr/bin/env python3
"""Build and validate this project's Google Play Games import using Python 3 stdlib."""
import argparse
import csv
import hashlib
import io
import json
import re
import struct
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "marketing" / "play-games-achievements"
SPEC = Path(__file__).with_name("play_games_achievement_points.json")
SCHEMA = "https://developer.android.com/games/pgs/integrate-achievements#zip-file-guidelines"
POINTS_GUIDE = "https://developer.android.com/games/pgs/achievements#points_and_experience_points"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def csv_bytes(rows):
    stream = io.StringIO(newline="")
    csv.writer(stream, lineterminator="\r\n").writerows(rows)
    return stream.getvalue().encode("utf-8")


def clean_text(text):
    # Google prohibits commas even inside quoted Name/Description fields.
    return re.sub(r"(?<=\d),(?=\d)", "", text).replace(",", ";")


def validate_png(data):
    require(data[:8] == b"\x89PNG\r\n\x1a\n", "Not a PNG")
    offset, chunks, packed, header = 8, [], bytearray(), None
    while offset < len(data):
        require(offset + 12 <= len(data), "Truncated PNG chunk")
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + length]
        require(len(body) == length and offset + 12 + length <= len(data), "Truncated PNG")
        crc = struct.unpack(">I", data[offset + 8 + length:offset + 12 + length])[0]
        require((zlib.crc32(kind + body) & 0xffffffff) == crc, "PNG CRC mismatch")
        chunks.append(kind)
        if kind == b"IHDR":
            require(header is None and len(chunks) == 1 and length == 13, "Invalid IHDR")
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            packed.extend(body)
        offset += length + 12
        if kind == b"IEND":
            require(length == 0 and offset == len(data), "Invalid IEND")
            break
    require(header is not None and chunks[-1] == b"IEND" and packed, "Incomplete PNG")
    width, height, depth, color, compression, filtering, interlace = header
    require((width, height) == (512, 512), "Icon must be 512 x 512")
    require(compression == 0 and filtering == 0 and interlace == 0, "Unexpected PNG encoding")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color)
    require(channels is not None and depth in (1, 2, 4, 8, 16), "Invalid PNG format")
    inflated = zlib.decompress(bytes(packed))
    stride = (width * channels * depth + 7) // 8 + 1
    require(len(inflated) == stride * height, "Invalid decompressed PNG size")
    require(all(inflated[y * stride] in range(5) for y in range(height)), "Invalid PNG filter")
    return {"width": width, "height": height, "bit_depth": depth, "color_type": color}


def make_inputs():
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    catalog_bytes = (ROOT / "game/catalog.json").read_bytes()
    entries = json.loads(catalog_bytes)["achievements"]
    services = (ROOT / "platform/services.gd").read_bytes()
    service_text = services.decode("utf-8-sig")
    require("_achievements_client.unlock_achievement(remote_id)" in service_text, "Review current PGS unlock API")
    require(not re.search(r"_achievements_client\.(increment|set_steps)", service_text), "Incremental API requires review")
    keys = [entry["key"] for entry in entries]
    require(len(keys) == len(set(keys)) and set(keys) == set(spec["points"]), "Point keys do not match catalog")
    require(10 <= len(entries) <= 400, "Unexpected achievement count")
    metadata, mappings, worksheet, icons, edits = [], [], [], {}, []
    for index, entry in enumerate(entries, 1):
        key = entry["key"]
        name = clean_text(entry["name"])
        description = clean_text(entry["description"])
        require(0 < len(name) <= 100 and len(description) <= 500, "Text limits exceeded")
        require(not any(c in name + description for c in "\r\n,"), "Unsupported text")
        points = spec["points"][key]
        require(type(points) is int and 5 <= points <= 200 and points % 5 == 0, "Invalid points")
        icon_relative = entry.get("icon", f"marketing/achievements/{key}.png")
        icon_path = (ROOT / icon_relative).resolve()
        require(icon_path.parent == (ROOT / "marketing/achievements").resolve(), "Unexpected icon source")
        require(icon_path.name == f"{key}.png", "Icon must match the catalog key")
        icon = icon_path.read_bytes()
        validate_png(icon)
        require(len(icon) < 1000000, "Icon exceeds conservative 1 MB limit")
        icons[icon_path.name] = icon
        metadata.append([name, description, "False", "", "Revealed", str(points), str(index)])
        mappings.append([name, icon_path.name])
        worksheet.append([key, name, description, "Standard", points, "Revealed", icon_relative, "", entry["description"]])
        if (name, description) != (entry["name"], entry["description"]):
            edits.append({"key": key, "source_name": entry["name"], "import_name": name,
                          "source_description": entry["description"], "import_description": description})
    require(len(set(row[0] for row in metadata)) == len(metadata), "Duplicate achievement names")
    require(sum(int(row[5]) for row in metadata) <= 2000, "Game points exceed 2000")
    members = {"AchievementsMetadata.csv": csv_bytes(metadata),
               "AchievementsIconsMappings.csv": csv_bytes(mappings), **icons}
    return spec, entries, metadata, worksheet, edits, members, catalog_bytes, services


def validate_archive(archive_bytes, expected):
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        require(len(names) == len(set(names)) <= 403, "ZIP duplicate names or too many files")
        require(set(names) == set(expected), "ZIP member set mismatch")
        require(all("/" not in n and "\\" not in n and Path(n).suffix.lower() in (".csv", ".png", ".jpg", ".jpeg") for n in names),
                "ZIP must contain only flat CSV/image files")
        require(len(archive_bytes) < 800000000, "ZIP exceeds size limit")
        require(archive.testzip() is None, "ZIP CRC failed")
        for info in infos:
            require(info.file_size < 1000000, "ZIP member exceeds conservative 1 MB")
            require(archive.read(info.filename) == expected[info.filename], "ZIP bytes differ from sources")
        meta_bytes = archive.read("AchievementsMetadata.csv")
        map_bytes = archive.read("AchievementsIconsMappings.csv")
        require(not meta_bytes.startswith(b"\xef\xbb\xbf") and not map_bytes.startswith(b"\xef\xbb\xbf"), "CSV has BOM")
        meta = list(csv.reader(io.StringIO(meta_bytes.decode("utf-8"))))
        mappings = list(csv.reader(io.StringIO(map_bytes.decode("utf-8"))))
        require(all(len(row) == 7 and row[2:5] == ["False", "", "Revealed"] for row in meta), "Metadata schema mismatch")
        require([int(row[6]) for row in meta] == list(range(1, len(meta) + 1)), "Invalid list order")
        require(all(len(row) == 2 for row in mappings), "Mapping schema mismatch")
        require([row[0] for row in meta] == [row[0] for row in mappings], "Mapping names/order mismatch")
        require(set(row[1] for row in mappings) == set(names) - {"AchievementsMetadata.csv", "AchievementsIconsMappings.csv"}, "Icon mapping incomplete")
    return len(infos)


def run(check=False):
    spec, entries, meta, worksheet, edits, members, catalog_bytes, services = make_inputs()
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        for filename, content in members.items():
            info = zipfile.ZipInfo(filename, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, content, compresslevel=9)
    archive_bytes = stream.getvalue()
    count = validate_archive(archive_bytes, members)
    filename = spec["slug"] + "-achievements-google-play.zip"
    total = sum(int(row[5]) for row in meta)
    report = {"schema_checked": "2026-11-12", "game": spec["title"], "achievement_count": len(entries),
              "standard_count": len(entries), "incremental_count": 0, "initial_state": "Revealed",
              "points_total": total, "points_remaining": 2000 - total,
              "zip_filename": filename, "zip_bytes": len(archive_bytes), "zip_sha256": sha(archive_bytes),
              "zip_member_count": count, "catalog_sha256": sha(catalog_bytes.replace(b"\r\n", b"\n")),
              "services_sha256": sha(services.replace(b"\r\n", b"\n")), "source_text_hash_line_endings": "LF", "comma_normalizations": edits,
              "validated": ["CSV headerless UTF-8; seven/two fields", "flat allowlisted archive",
                            "complete unique key/name/icon mapping", "catalog order and text (documented comma normalization)",
                            "points limits and total", "standard type matches unlock-only code",
                            "ZIP CRC and every archived byte", "PNG dimensions/chunk CRC/decompression/filter",
                            "original icon SHA256 matches archive", "member and archive size limits"],
              "icons": [{"filename": n, "bytes": len(b), "sha256": sha(b), **validate_png(b)}
                        for n, b in members.items() if n.endswith(".png")],
              "play_console_uploaded": False, "play_console_acceptance_tested": False,
              "sources": [SCHEMA, POINTS_GUIDE]}
    text_edits = "\n".join(f'- {e["key"]}: "{e["source_description"]}" -> "{e["import_description"]}"' for e in edits) or "- None."
    readme = f"""# {spec["title"]}: Google Play Games achievement import

Prepared 2026-11-12. Upload only **{filename}** from this directory.
The ZIP contains two headerless CSVs and {len(entries)} original 512 x 512 PNGs at
its root. Companion files are intentionally outside the ZIP. The .gdignore marker
keeps these console CSVs out of Godot translation imports and game resources.

## Choices to review before import

- All {len(entries)} achievements are Standard (Incremental Value False; steps blank).
  game/main.gd reports completed local achievements to platform/services.gd, whose
  PGS adapter calls unlock_achievement, not increment or set-steps. Local progress
  thresholds do not make them PGS incremental achievements.
- All start Revealed. Point values range from {min(int(r[5]) for r in meta)} to
  {max(int(r[5]) for r in meta)}, totaling {total}; {2000-total} points remain below
  Google's 2000-point game allowance. Higher milestones generally receive more.
  Points and initial states are proposed package choices, not catalog values.
  Review them before publishing, when type and initial state become immutable.
- Names, catalog order and original icon bytes are preserved. Google prohibits
  commas in names/descriptions, even if quoted, so only these descriptions were
  normalized in the import (the game catalog itself is unchanged):
{text_edits}

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
validation-report.json records LF-normalized source text hashes and exact icon/ZIP\nhashes. The text output check tolerates Git checkout line endings. ZIP output is
deterministic; a same-input rerun must match byte-for-byte.

This is an import-package validation, not Google Play acceptance, gameplay QA or
a release build. No runtime, signing configuration, saves or existing artifacts
were changed. Source and asset notices remain in LICENSE, NOTICE and LICENSES.

Official references checked 2026-11-12:
- {SCHEMA}
- {POINTS_GUIDE}
"""
    outputs = {".gdignore": b"", filename: archive_bytes,
               "AchievementsMetadata.csv": members["AchievementsMetadata.csv"],
               "AchievementsIconsMappings.csv": members["AchievementsIconsMappings.csv"],
               "achievement-id-mapping-and-points.csv": csv_bytes([["CatalogKey", "Name", "ImportDescription", "Type", "Points", "InitialState", "SourceIcon", "PlayGamesAchievementId", "OriginalDescription"], *worksheet]),
               "validation-report.json": (json.dumps(report, indent=2, ensure_ascii=False) + "\n").encode("utf-8"),
               "README.md": readme.encode("utf-8")}
    if check:
        for name, data in outputs.items():
            actual = (OUT / name).read_bytes()
            if not name.endswith(".zip"):
                actual, data = actual.replace(b"\r\n", b"\n"), data.replace(b"\r\n", b"\n")
            require(actual == data, f"Stale or changed output: {name}")
    else:
        OUT.mkdir(parents=True, exist_ok=True)
        for name, data in outputs.items():
            (OUT / name).write_bytes(data)
    print(json.dumps({"game": spec["title"], "achievements": len(entries), "points": total,
                      "zip": str(OUT / filename), "bytes": len(archive_bytes),
                      "sha256": sha(archive_bytes), "check_only": check}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Compare every generated output without writing")
    run(parser.parse_args().check)
