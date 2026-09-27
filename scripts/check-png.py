#!/usr/bin/env python3
"""Reads a PNG back out with somebody else's code, and says whether it is a picture of anything.

## Why this is not written in Swift

The engine writes PNGs with nothing but arithmetic — no compression library, because the engine is not allowed one.
That is the whole point of it, and it is also why the engine cannot be trusted to check its own output: a test written
against the same understanding of the format would pass just as happily if that understanding were wrong. Every reader
in the world would then refuse the file and every test would say it was fine.

So the check is made by something that knows the format independently: Python's zlib, which is the real one, and which
verifies the stream's checksum as a side effect of decompressing it. If the bytes are malformed this fails; if the
checksum is wrong this fails; and neither failure can be talked round by the code under test.

## And whether it is a picture of anything

Separately, and just as important: a correct PNG of a blank rectangle is a correct PNG. That happened twice while this
was being built — once the heat view came out flat green because empty air was painted, once the field came out black
because each body was drawn a single pixel wide. Both produced perfectly valid files. So this also counts how many
different colours are in the picture and how much of it is not the commonest one, which is the cheapest question that
would have caught either.

    python3 scripts/check-png.py pictures/*.png
    python3 scripts/check-png.py --min-colours 8 --min-busy 0.5 pictures/powder.png
"""

import argparse
import struct
import sys
import zlib
from collections import Counter


def read(path):
    """A PNG's size and its rows of pixels, or a complaint about why it is not a PNG."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("does not start with the eight bytes every PNG starts with")

    at = 8
    width = height = depth = colour_type = None
    stream = b""
    names = []
    while at + 8 <= len(data):
        length = struct.unpack(">I", data[at : at + 4])[0]
        name = data[at + 4 : at + 8]
        body = data[at + 8 : at + 8 + length]
        if at + 12 + length > len(data):
            raise ValueError("a block runs off the end of the file")
        recorded = struct.unpack(">I", data[at + 8 + length : at + 12 + length])[0]
        if zlib.crc32(name + body) & 0xFFFFFFFF != recorded:
            raise ValueError(f"the checksum on the {name.decode('latin1')} block is wrong")
        names.append(name.decode("latin1"))
        if name == b"IHDR":
            width, height, depth, colour_type = struct.unpack(">IIBB", body[:10])
        elif name == b"IDAT":
            stream += body
        at += 12 + length

    if names[:1] != ["IHDR"] or names[-1:] != ["IEND"]:
        raise ValueError(f"the blocks are in the wrong order: {', '.join(names)}")
    if width is None:
        raise ValueError("there is no header block")
    if depth != 8 or colour_type != 2:
        raise ValueError(f"expected eight bits a channel and plain red-green-blue, got {depth} and type {colour_type}")

    # zlib's own decompressor, which checks the stream's trailing checksum as it goes.
    raw = zlib.decompress(stream)
    stride = width * 3 + 1
    if len(raw) != stride * height:
        raise ValueError(f"the pixels come to {len(raw)} bytes, not the {stride * height} the header implies")
    rows = []
    for y in range(height):
        row = raw[y * stride : (y + 1) * stride]
        if row[0] != 0:
            raise ValueError(f"row {y} says its pixels were altered, which this writer never does")
        rows.append(row[1:])
    return width, height, rows


def main():
    parser = argparse.ArgumentParser(description="Checks a PNG is a PNG, and a picture of something.")
    parser.add_argument("files", nargs="+")
    parser.add_argument(
        "--min-colours",
        type=int,
        default=8,
        help="how many different colours a picture must contain (default 8)",
    )
    parser.add_argument(
        "--min-busy",
        type=float,
        default=0.2,
        help="what percentage of the picture must differ from its commonest colour (default 0.2)",
    )
    settings = parser.parse_args()

    trouble = False
    for path in settings.files:
        try:
            width, height, rows = read(path)
        except Exception as why:  # noqa: BLE001 — every failure is reported the same way.
            print(f"{path}: NOT A PICTURE — {why}")
            trouble = True
            continue

        counts = Counter()
        for row in rows:
            for i in range(0, len(row), 3):
                counts[row[i : i + 3]] += 1
        total = width * height
        commonest, most = counts.most_common(1)[0]
        busy = 100.0 * (total - most) / total
        note = f"{path}: {width}x{height}, {len(counts)} colours, {busy:.2f}% not the background"
        if len(counts) < settings.min_colours:
            print(f"{note} — TOO FEW COLOURS, wanted {settings.min_colours}")
            trouble = True
        elif busy < settings.min_busy:
            print(f"{note} — VERY NEARLY BLANK, wanted {settings.min_busy}% of it used")
            trouble = True
        else:
            print(f"{note} — fine")

    return 1 if trouble else 0


if __name__ == "__main__":
    sys.exit(main())
