#!/usr/bin/env python3
"""Generates Assets.xcassets (app icon + colors) so no binary files live in git.

Draws a Claude-style starburst mark on the Anthropic bone-white background.
Run before `xcodegen generate`.
"""
import json
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Resources", "Assets.xcassets")

BONE = (240, 238, 230, 255)
CLAY = (217, 119, 87, 255)


def write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def starburst(size=1024, rays=11, supersample=4):
    """The Anthropic/Claude starburst: tapered rays radiating from a center."""
    s = size * supersample
    image = Image.new("RGBA", (s, s), BONE)
    draw = ImageDraw.Draw(image)

    cx = cy = s / 2.0
    outer = s * 0.36
    inner = s * 0.045
    half_outer = s * 0.020
    half_inner = s * 0.055

    for index in range(rays):
        angle = (2.0 * math.pi * index) / rays - math.pi / 2.0
        ca, sa = math.cos(angle), math.sin(angle)
        # Perpendicular direction used to give each ray its tapered waist.
        px, py = -sa, ca

        tip_x, tip_y = cx + ca * outer, cy + sa * outer
        base_x, base_y = cx + ca * inner, cy + sa * inner

        polygon = [
            (tip_x + px * half_outer, tip_y + py * half_outer),
            (tip_x - px * half_outer, tip_y - py * half_outer),
            (base_x - px * half_inner, base_y - py * half_inner),
            (base_x + px * half_inner, base_y + py * half_inner),
        ]
        draw.polygon(polygon, fill=CLAY)

    hub = s * 0.055
    draw.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=CLAY)

    return image.resize((size, size), Image.LANCZOS)


def color_set(name, red, green, blue):
    write_json(
        os.path.join(ASSETS, "%s.colorset" % name, "Contents.json"),
        {
            "colors": [
                {
                    "color": {
                        "color-space": "srgb",
                        "components": {
                            "alpha": "1.000",
                            "blue": "0x%02X" % blue,
                            "green": "0x%02X" % green,
                            "red": "0x%02X" % red,
                        },
                    },
                    "idiom": "universal",
                }
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )


def main():
    os.makedirs(ASSETS, exist_ok=True)
    write_json(
        os.path.join(ASSETS, "Contents.json"),
        {"info": {"author": "xcode", "version": 1}},
    )

    icon_dir = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(icon_dir, exist_ok=True)

    # iOS 14 installs need the classic size matrix, not just the 1024 single icon.
    specs = [
        ("20x20", "2x", 40), ("20x20", "3x", 60),
        ("29x29", "2x", 58), ("29x29", "3x", 87),
        ("40x40", "2x", 80), ("40x40", "3x", 120),
        ("60x60", "2x", 120), ("60x60", "3x", 180),
    ]
    ipad_specs = [
        ("20x20", "1x", 20), ("20x20", "2x", 40),
        ("29x29", "1x", 29), ("29x29", "2x", 58),
        ("40x40", "1x", 40), ("40x40", "2x", 80),
        ("76x76", "1x", 76), ("76x76", "2x", 152),
        ("83.5x83.5", "2x", 167),
    ]

    master = starburst(1024)
    images = []
    rendered = {}

    def emit(idiom, size, scale, pixels):
        filename = "icon-%d.png" % pixels
        if pixels not in rendered:
            master.resize((pixels, pixels), Image.LANCZOS).convert("RGB").save(
                os.path.join(icon_dir, filename)
            )
            rendered[pixels] = filename
        images.append(
            {"size": size, "idiom": idiom, "filename": filename, "scale": scale}
        )

    for size, scale, pixels in specs:
        emit("iphone", size, scale, pixels)
    for size, scale, pixels in ipad_specs:
        emit("ipad", size, scale, pixels)

    master.convert("RGB").save(os.path.join(icon_dir, "icon-1024.png"))
    images.append(
        {
            "size": "1024x1024",
            "idiom": "ios-marketing",
            "filename": "icon-1024.png",
            "scale": "1x",
        }
    )

    write_json(
        os.path.join(icon_dir, "Contents.json"),
        {"images": images, "info": {"author": "xcode", "version": 1}},
    )

    color_set("LaunchBackground", 0x1A, 0x1A, 0x19)
    color_set("AccentColor", 0xD9, 0x77, 0x57)

    print("Assets written to %s" % ASSETS)


if __name__ == "__main__":
    main()
