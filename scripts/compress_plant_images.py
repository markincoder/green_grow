# -*- coding: utf-8 -*-
"""Compress plant PNGs in assets/plants to phone/tablet JPEG sizes."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps" / "microgreens" / "assets" / "plants"

# Square sources (1024) → keep square for avatar + 4:3 carousel contain.
# 900px covers phone ~3x (~300dp) and tablet ~2x (~450dp) without huge APK weight.
MAX_SIDE = 900
JPEG_QUALITY = 82


def compress_one(src: Path) -> Path:
    dest = src.with_suffix(".jpg")
    im = Image.open(src).convert("RGB")
    im.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
    im.save(dest, "JPEG", quality=JPEG_QUALITY, optimize=True)
    return dest


def ensure_default() -> None:
    dest = ASSETS / "default1.jpg"
    if dest.exists():
        return
    im = Image.new("RGB", (512, 512), (216, 243, 220))
    draw = ImageDraw.Draw(im)
    draw.ellipse((140, 140, 372, 372), fill=(45, 106, 79))
    im.save(dest, "JPEG", quality=JPEG_QUALITY, optimize=True)


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    ensure_default()
    pngs = sorted(ASSETS.glob("*.png"))
    if not pngs:
        print("No PNG files in", ASSETS)
        return

    before = sum(p.stat().st_size for p in pngs)
    after = 0
    for src in pngs:
        dest = compress_one(src)
        after += dest.stat().st_size
        src.unlink()
        print(f"{src.name} → {dest.name} ({dest.stat().st_size // 1024} KB)")

    print(
        f"Done: {len(pngs)} files, {before / 1e6:.1f} MB → {after / 1e6:.1f} MB"
    )


if __name__ == "__main__":
    main()
