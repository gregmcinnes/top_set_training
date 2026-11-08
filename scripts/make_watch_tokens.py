#!/usr/bin/env python3
"""Generate SBSWatch/WatchTokens.xcassets from Shared/Tokens.xcassets.

actool drops dark ("luminosity") appearances when it compiles a catalogue for
watchOS, so the shared colour sets resolve to their Chalk values on the Watch,
which is always dark. This writes each colour set with its Iron value as the only
value. Run it after changing a token; SBSTests/WatchTokensTests fails if the two
catalogues drift apart.

    python3 scripts/make_watch_tokens.py
"""
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Shared/Tokens.xcassets/Colors"
DST = ROOT / "SBSWatch/WatchTokens.xcassets"

INFO = {"info": {"author": "xcode", "version": 1}}


def iron_value(colorset: dict) -> dict:
    colors = colorset["colors"]
    for entry in colors:
        for appearance in entry.get("appearances", []):
            if appearance == {"appearance": "luminosity", "value": "dark"}:
                return entry["color"]
    # Same value in both themes (plates): the one universal entry
    return colors[0]["color"]


def main() -> None:
    if DST.exists():
        shutil.rmtree(DST)
    (DST / "Colors").mkdir(parents=True)
    (DST / "Contents.json").write_text(json.dumps(INFO, indent=2) + "\n")
    (DST / "Colors/Contents.json").write_text(json.dumps(INFO, indent=2) + "\n")
    for src in sorted(SRC.glob("*.colorset")):
        colorset = json.loads((src / "Contents.json").read_text())
        out = {"colors": [{"color": iron_value(colorset), "idiom": "universal"}], **INFO}
        (DST / "Colors" / src.name).mkdir()
        (DST / "Colors" / src.name / "Contents.json").write_text(json.dumps(out, indent=2) + "\n")
    print(f"Wrote {len(list(SRC.glob('*.colorset')))} colour sets to {DST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
