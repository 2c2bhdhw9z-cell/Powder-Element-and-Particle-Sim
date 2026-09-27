#!/usr/bin/env python3
"""Draws Crucible's app icon.

## Why the icon is generated rather than committed as a picture somebody drew

Because this app draws particles, and an icon of particles should be drawn by the same kind of arithmetic that
draws the app — a spiral placed by the golden angle, exactly as the sunflower scene places its seeds. That means
the icon can be explained, adjusted by changing a number, and regenerated at any size, instead of being a binary
nobody can open or account for.

The result is still committed, because the build runs on a machine with no Python for this step and an icon is not
worth adding a dependency for. Run this when the icon should change:

    python3 scripts/make-icon.py

Writes native/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
"""

from __future__ import annotations

import math
import pathlib
import struct
import zlib

SIZE = 1024
OUT = (
    pathlib.Path(__file__).resolve().parent.parent
    / "native/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
)

# The lab's own near-black, so the icon sits in the same room as the app.
BACKGROUND = (10, 10, 12)
# How many bodies are in the spiral. Enough to read as a crowd, few enough that each one is a dot.
BODIES = 3400
# Pi times three minus the square root of five: the golden angle, about 137.5 degrees. The one turn that fills a
# disc evenly instead of producing arms — the same constant the sunflower scene uses, and for the same reason.
GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))


def warm_to_cool(along: float) -> tuple[int, int, int]:
    """The app's own sweep: hot at the middle, cool at the rim."""
    along = max(0.0, min(1.0, along))
    hot = (255, 176, 92)
    mid = (244, 63, 94)
    cool = (56, 189, 248)
    if along < 0.5:
        share = along * 2
        first, second = hot, mid
    else:
        share = (along - 0.5) * 2
        first, second = mid, cool
    return tuple(round(a + (b - a) * share) for a, b in zip(first, second))


def draw() -> list[list[tuple[int, int, int]]]:
    pixels = [[BACKGROUND] * SIZE for _ in range(SIZE)]
    centre = SIZE / 2
    # Most of the square, but not the corners: iOS rounds an icon off, so anything out there is cut away. Filling
    # about nine tenths of the width puts the rim just inside where the rounding starts.
    outer = SIZE * 0.45

    for index in range(BODIES):
        through = (index + 0.5) / BODIES
        # The radius grows as the square root of how far through we are, which is what keeps the bodies the same
        # distance apart all the way out — area grows as the square of radius.
        radius = math.sqrt(through) * outer
        angle = index * GOLDEN_ANGLE
        x = centre + math.cos(angle) * radius
        y = centre + math.sin(angle) * radius
        # Larger and brighter toward the middle, as a real disc's bulge is.
        size = 2.0 + 6.0 * (1 - through) ** 1.5
        red, green, blue = warm_to_cool(through)
        # The rim keeps enough light to read as part of the same thing rather than as dust round it.
        brightness = 0.55 + 0.45 * (1 - through)

        reach = int(size) + 2
        for dy in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                px, py = int(x) + dx, int(y) + dy
                if not (0 <= px < SIZE and 0 <= py < SIZE):
                    continue
                away = math.hypot(x - px, y - py)
                if away > size:
                    continue
                # A soft edge, so a dot is a point of light rather than a tile.
                coverage = min(1.0, (1 - away / size) * 1.6) * brightness
                if coverage <= 0:
                    continue
                had = pixels[py][px]
                # Added rather than laid over, so where the spiral crowds it genuinely brightens.
                pixels[py][px] = (
                    min(255, round(had[0] + red * coverage)),
                    min(255, round(had[1] + green * coverage)),
                    min(255, round(had[2] + blue * coverage)),
                )
    return pixels


def write_png(pixels: list[list[tuple[int, int, int]]], path: pathlib.Path) -> None:
    """Writes a plain, opaque PNG. Written out by hand because it needs nothing installed."""
    raw = bytearray()
    for row in pixels:
        # Every row is preceded by its filter type; nought means "stored as it is".
        raw.append(0)
        for red, green, blue in row:
            raw += bytes((red, green, blue))

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    write_png(draw(), OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
