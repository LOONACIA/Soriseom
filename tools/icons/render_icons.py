# /// script
# requires-python = ">=3.12"
# dependencies = ["resvg-py==0.5.0", "pillow==13.0.0"]
# ///
"""Generate the app's PNG and ICO assets from the SVG sources.

Edit the SVG sources and rerun this script to update the generated PNG and ICO
files. Do not edit those generated assets directly.
"""

import argparse
import io
from pathlib import Path

import resvg_py
from PIL import Image

ICON_DIR = Path(__file__).resolve().parent
ASSET_DIR = ICON_DIR.parent.parent / "src" / "Soriseom.App" / "Assets"


def render_svg(svg: str, size: int) -> Image.Image:
    return Image.open(
        io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=size, height=size)))
    ).convert("RGBA")


def png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def centered_png(svg: str, width: int, height: int, ratio: float) -> bytes:
    size = round(height * ratio)
    canvas = Image.new("RGBA", (width, height))
    canvas.alpha_composite(render_svg(svg, size), ((width - size) // 2, (height - size) // 2))
    return png_bytes(canvas)


def ico_bytes(svg: str, sizes: list[int]) -> bytes:
    frames = [render_svg(svg, size) for size in sizes]
    buffer = io.BytesIO()
    frames[-1].save(
        buffer,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=frames[:-1],
        bitmap_format="bmp",
    )
    return buffer.getvalue()


def build_assets() -> dict[str, bytes]:
    app_svg = (ICON_DIR / "app-icon.svg").read_text(encoding="utf-8")
    tray_svg = (ICON_DIR / "tray-icon.svg").read_text(encoding="utf-8")
    assets = {}
    for scale, square44, square150, wide_width, splash_width, splash_height, store in (
        (100, 44, 150, 310, 620, 300, 50),
        (125, 55, 188, 388, 775, 375, 63),
        (150, 66, 225, 465, 930, 450, 75),
        (200, 88, 300, 620, 1240, 600, 100),
        (400, 176, 600, 1240, 2480, 1200, 200),
    ):
        assets[f"Square44x44Logo.scale-{scale}.png"] = png_bytes(render_svg(app_svg, square44))
        assets[f"Square150x150Logo.scale-{scale}.png"] = centered_png(
            app_svg, square150, square150, 0.66
        )
        assets[f"Wide310x150Logo.scale-{scale}.png"] = centered_png(
            app_svg, wide_width, square150, 0.6
        )
        assets[f"SplashScreen.scale-{scale}.png"] = centered_png(
            app_svg, splash_width, splash_height, 0.6
        )
        assets[f"StoreLogo.scale-{scale}.png"] = png_bytes(render_svg(app_svg, store))

    for size in (16, 24, 32, 48, 256):
        assets[f"Square44x44Logo.targetsize-{size}_altform-unplated.png"] = png_bytes(
            render_svg(app_svg, size)
        )

    assets["AppIcon.ico"] = ico_bytes(app_svg, [16, 20, 24, 32, 40, 48, 64, 256])
    assets["TrayIconForDarkTaskbar.ico"] = ico_bytes(tray_svg, [16, 20, 24, 32, 40, 48])
    assets["TrayIconForLightTaskbar.ico"] = ico_bytes(
        tray_svg.replace("#FFFFFF", "#1B1B1B"), [16, 20, 24, 32, 40, 48]
    )
    return assets


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check assets without writing files.")
    args = parser.parse_args()
    assets = build_assets()
    if args.check:
        differences = []
        for name, content in assets.items():
            path = ASSET_DIR / name
            if not path.is_file():
                differences.append(f"Missing: {name}")
            elif path.read_bytes() != content:
                differences.append(f"Different: {name}")
        existing = {path.name for pattern in ("*.png", "*.ico") for path in ASSET_DIR.glob(pattern)}
        differences.extend(f"Unexpected: {name}" for name in sorted(existing - assets.keys()))
        for difference in differences:
            print(difference)
        return 1 if differences else 0

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    for name, content in assets.items():
        (ASSET_DIR / name).write_bytes(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
