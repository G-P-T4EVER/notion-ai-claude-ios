#!/usr/bin/env python3
"""Generates Resources/Assets.xcassets: app icon + accent and launch colors.

Standard library only (zlib/struct PNG writer), so CI needs no pip install and
cannot trip over PEP 668 externally-managed environments.

Draws the Claude-style starburst: tapered rays on Anthropic bone white.
Run before `xcodegen generate`.
"""
import binascii
import json
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Resources", "Assets.xcassets")

BONE = (240, 238, 230)
CLAY = (217, 119, 87)

SIZE = 1024
RAYS = 11
OUTER = SIZE * 0.36
HALF_INNER = SIZE * 0.055
HALF_OUTER = SIZE * 0.012
STEP = 2.0 * math.pi / RAYS
CENTER = SIZE / 2.0


def write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def chunk(tag, data):
    crc = binascii.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)


def write_png(path, rows):
    raw = b"".join(b"\x00" + row for row in rows)
    header = struct.pack(">2I5B", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)


def coverage(x, y):
    """2x2 supersampled coverage of the starburst at one pixel."""
    hits = 0
    for dx in (0.25, 0.75):
        px = x + dx - CENTER
        for dy in (0.25, 0.75):
            py = y + dy - CENTER
            r = math.hypot(px, py)
            if r > OUTER:
                continue
            if r < HALF_INNER * 0.5:
                hits += 1
                continue
            delta = math.atan2(py, px) % STEP
            delta = min(delta, STEP - delta)
            half = HALF_INNER + (HALF_OUTER - HALF_INNER) * (r / OUTER)
            if r * delta <= half:
                hits += 1
    return hits / 4.0


def icon_rows():
    bone_row = bytes(BONE) * SIZE
    rows = []
    for y in range(SIZE):
        dy = y + 0.5 - CENTER
        if abs(dy) > OUTER + 1.0:
            rows.append(bone_row)
            continue

        span = math.sqrt(max(0.0, (OUTER + 1.0) ** 2 - dy * dy))
        left = max(0, int(CENTER - span) - 1)
        right = min(SIZE - 1, int(CENTER + span) + 1)

        row = bytearray(bone_row)
        for x in range(left, right + 1):
            alpha = coverage(x, y)
            if alpha <= 0.0:
                continue
            if alpha >= 1.0:
                pixel = CLAY
            else:
                pixel = tuple(
                    int(BONE[i] + (CLAY[i] - BONE[i]) * alpha + 0.5) for i in range(3)
                )
            row[x * 3:x * 3 + 3] = bytes(pixel)
        rows.append(bytes(row))
    return rows


def colorset(red, green, blue):
    return {
        "colors": [
            {
                "color": {
                    "color-space": "srgb",
                    "components": {
                        "red": "0x%02X" % red,
                        "green": "0x%02X" % green,
                        "blue": "0x%02X" % blue,
                        "alpha": "1.000",
                    },
                },
                "idiom": "universal",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }


def main():
    write_json(os.path.join(ASSETS, "Contents.json"), {"info": {"author": "xcode", "version": 1}})

    write_json(
        os.path.join(ASSETS, "AppIcon.appiconset", "Contents.json"),
        {
            "images": [
                {
                    "filename": "AppIcon.png",
                    "idiom": "universal",
                    "platform": "ios",
                    "size": "1024x1024",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    write_json(os.path.join(ASSETS, "AccentColor.colorset", "Contents.json"), colorset(*CLAY))
    write_json(
        os.path.join(ASSETS, "LaunchBackground.colorset", "Contents.json"),
        colorset(0x1A, 0x1A, 0x19),
    )

    write_png(os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon.png"), icon_rows())
    print("Assets written to " + ASSETS)


if __name__ == "__main__":
    main()
