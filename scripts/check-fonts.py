#!/usr/bin/env python3
"""Checks that the app asks for typefaces that are actually in the bundle.

A font name that does not match anything is the worst kind of wrong here, because nothing
reports it. `Font.custom` does not fail, it does not warn, and it does not crash — it quietly
hands back the system face. The app still runs and still looks perfectly tidy; it just does not
look like Crucible, with no clue as to why. That was the original complaint about this port, and
a single mistyped letter anywhere would bring it straight back.

So this compares three things and fails if they disagree:

  1. the PostScript names the Swift code asks for, in App/Design/Palette.swift;
  2. the PostScript names actually recorded inside the font files;
  3. the file names listed in Info.plist, which is what makes iOS register them at all.

Uses nothing but the standard library, so it runs anywhere the rest of the checks do. The
TrueType name table is simple enough to read directly and that is cheaper than a dependency.

    python3 scripts/check-fonts.py
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / "native/App/Resources/Fonts"
PALETTE = ROOT / "native/App/Design/Palette.swift"
INFO_PLIST = ROOT / "native/App/Info.plist"

# Name table entry 6 is the PostScript name, which is what `Font.custom` matches against.
POSTSCRIPT_NAME_ID = 6


def postscript_name(path: Path) -> str | None:
    """Reads a TrueType file's PostScript name out of its name table."""
    data = path.read_bytes()
    if len(data) < 12:
        return None

    # Offset table: a tag, then the number of tables, then the table records.
    table_count = struct.unpack_from(">H", data, 4)[0]
    name_offset = None
    for i in range(table_count):
        record = 12 + i * 16
        if record + 16 > len(data):
            return None
        tag = data[record : record + 4]
        if tag == b"name":
            name_offset = struct.unpack_from(">I", data, record + 8)[0]
            break
    if name_offset is None:
        return None

    count, string_offset = struct.unpack_from(">HH", data, name_offset + 2)
    best = None
    for i in range(count):
        record = name_offset + 6 + i * 12
        platform, encoding, _language, name_id, length, offset = struct.unpack_from(
            ">HHHHHH", data, record
        )
        if name_id != POSTSCRIPT_NAME_ID:
            continue
        start = name_offset + string_offset + offset
        raw = data[start : start + length]
        # Windows entries are two bytes per character; Macintosh ones are one.
        try:
            text = raw.decode("utf-16-be") if platform == 3 else raw.decode("mac-roman")
        except UnicodeDecodeError:
            continue
        # Either platform will do, but prefer the Windows entry where both exist, since that is
        # the one tools agree on.
        if best is None or platform == 3:
            best = text
    return best


def names_requested_in_code() -> list[str]:
    """The PostScript names the Swift enums list, in the order they appear."""
    source = PALETTE.read_text()
    # Each case looks like:  case semiBold = "Syne-SemiBold"
    return re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', source)


def files_listed_in_plist() -> list[str]:
    """The font file names Info.plist registers."""
    text = INFO_PLIST.read_text()
    match = re.search(r"<key>UIAppFonts</key>\s*<array>(.*?)</array>", text, re.S)
    if not match:
        return []
    return re.findall(r"<string>([^<]+)</string>", match.group(1))


def main() -> int:
    problems: list[str] = []

    if not FONT_DIR.is_dir():
        print(f"No font directory at {FONT_DIR}", file=sys.stderr)
        return 1

    files = sorted(FONT_DIR.glob("*.ttf"))
    if not files:
        print(f"No font files in {FONT_DIR}", file=sys.stderr)
        return 1

    installed: dict[str, Path] = {}
    for path in files:
        name = postscript_name(path)
        if name is None:
            problems.append(f"{path.name}: could not read a PostScript name out of it")
            continue
        installed[name] = path

    requested = names_requested_in_code()
    if not requested:
        problems.append(f"{PALETTE.name}: found no typeface names at all — has it been renamed?")

    for name in requested:
        if name not in installed:
            close = ", ".join(sorted(installed)) or "none"
            problems.append(
                f'the app asks for "{name}" and no bundled file declares it '
                f"(available: {close})"
            )

    # Every file also has to be listed in Info.plist, or iOS never registers it and the name
    # match above is beside the point.
    listed = set(files_listed_in_plist())
    for path in files:
        if path.name not in listed:
            problems.append(f"{path.name} is in the bundle but missing from UIAppFonts")
    for entry in listed:
        if not (FONT_DIR / entry).exists():
            problems.append(f"UIAppFonts lists {entry}, which is not in the bundle")

    print(f"Checked {len(files)} font files against {len(requested)} names asked for in code.")
    for name in requested:
        mark = "ok" if name in installed else "MISSING"
        source = installed[name].name if name in installed else "-"
        print(f"  {mark:8} {name:24} {source}")

    if problems:
        print("", file=sys.stderr)
        for problem in problems:
            print(f"  problem: {problem}", file=sys.stderr)
        print(
            "\nA name that matches nothing does not fail at build time and does not crash — "
            "the app silently draws in the system face instead.",
            file=sys.stderr,
        )
        return 1

    print("Every typeface the app asks for is present and registered.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
