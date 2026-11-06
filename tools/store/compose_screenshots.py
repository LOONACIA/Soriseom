# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow==13.0.0"]
# ///
"""Compose three Store screenshots per language from captured PNG materials."""

import argparse
import os
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = (1920, 1080)
WHITE = (255, 255, 255)
BODY = (255, 255, 255, 205)
COPY = {
    "ko-KR": {
        "font": "noto",
        "title_weight": "Bold",
        "popup_title": ["곡이 바뀌면", "잠깐 알려 줍니다"],
        "popup_body": "제목, 아티스트, 앨범아트를 몇 초 동안 보여 주고 사라집니다. 작업 중인 창의 포커스는 그대로입니다.",
        "settings_title": ["보이는 방식은", "직접 정합니다"],
        "settings_body": "표시 시간, 위치, 크기, 테마를 바꾸고 앱마다 팝업을 켜거나 끌 수 있습니다.",
    },
    "en-US": {
        "font": "segoe",
        "title_weight": "Bold Display",
        "popup_title": ["A quick note when", "the track changes"],
        "popup_body": "Title, artist, and album art for a few seconds, then it's gone. Your current window keeps focus.",
        "settings_title": ["You choose", "how it shows"],
        "settings_body": "Change the display time, position, size, and theme, and turn popups on or off for each app.",
    },
}


def background() -> Image.Image:
    # Near #155488, the color the popup materials are captured on, so their acrylic tint fits.
    top, bottom = (24, 92, 146), (18, 74, 122)
    column = Image.new("RGB", (1, SIZE[1]))
    for y in range(SIZE[1]):
        t = y / SIZE[1]
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize(SIZE).convert("RGBA")


def load_font(path: Path, size: int, weight: str) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(path), size)
    font.set_variation_by_name(weight)
    return font


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines = [""]
    for word in text.split(" "):
        candidate = f"{lines[-1]} {word}".strip()
        if lines[-1] and draw.textlength(candidate, font=font) > width:
            lines.append(word)
        else:
            lines[-1] = candidate
    return lines


def draw_text(
    canvas: Image.Image, culture: str, key: str, font_path: Path, top: int | None, width: int
) -> None:
    """Draw the title and body at the left, from top or centered vertically when top is None."""
    copy = COPY[culture]
    # A separate layer, so the body's alpha blends with the background instead of replacing it.
    layer = Image.new("RGBA", SIZE)
    draw = ImageDraw.Draw(layer)
    title_font = load_font(font_path, 76, copy["title_weight"])
    body_font = load_font(font_path, 32, "Regular")
    title = copy[f"{key}_title"]
    body = wrap(draw, copy[f"{key}_body"], body_font, width)
    y = (SIZE[1] - (len(title) * 100 + 36 + len(body) * 50)) // 2 if top is None else top
    for line in title:
        draw.text((140, y), line, font=title_font, fill=WHITE)
        y += 100
    y += 36
    for line in body:
        draw.text((142, y), line, font=body_font, fill=BODY)
        y += 50
    canvas.alpha_composite(layer)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    image = image.convert("RGBA")
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1), radius=radius, fill=255
    )
    image.putalpha(mask)
    return image


def place(canvas: Image.Image, item: Image.Image, x: int, y: int, radius: int) -> None:
    shadow = Image.new("RGBA", SIZE)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, y + 10, x + item.width - 1, y + item.height - 1 + 10),
        radius=radius,
        fill=(0, 0, 0, 80),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))
    canvas.alpha_composite(item, (x, y))


def compose_popups(culture: str, paths: list[Path], font_path: Path) -> Image.Image:
    canvas = background()
    popups = []
    for path in paths:
        with Image.open(path) as source:
            popup = rounded(source, source.height // 2)
        popups.append(
            popup.resize((620, round(popup.height * 620 / popup.width)), Image.Resampling.LANCZOS)
        )
    # Each popup covers only the empty right side of the one before it, so every title stays readable.
    step_x, step_y = 380, 116
    x = 1800 - 620 - step_x * (len(popups) - 1)
    y = 500
    for popup in popups:
        place(canvas, popup, x, y, popup.height // 2)
        x += step_x
        y += step_y
    draw_text(canvas, culture, "popup", font_path, 110, 900)
    return canvas


def compose_desktop(path: Path) -> Image.Image:
    with Image.open(path) as source:
        desktop = source.convert("RGB")
    if desktop.width != SIZE[0]:
        desktop = desktop.resize(
            (SIZE[0], round(desktop.height * SIZE[0] / desktop.width)), Image.Resampling.LANCZOS
        )
    return desktop


def compose_settings(culture: str, path: Path, font_path: Path) -> Image.Image:
    canvas = background()
    with Image.open(path) as source:
        radius = round(source.width * 8 / 720)
        settings = rounded(source, radius)
    scale = min(1, 800 / settings.width, 960 / settings.height)
    if scale < 1:
        settings = settings.resize(
            (round(settings.width * scale), round(settings.height * scale)),
            Image.Resampling.LANCZOS,
        )
    place(
        canvas, settings,
        1040 + (800 - settings.width) // 2,
        (SIZE[1] - settings.height) // 2,
        round(radius * scale),
    )
    draw_text(canvas, culture, "settings", font_path, None, 720)
    return canvas


def find_fonts() -> dict[str, Path] | None:
    noto = [Path(r"C:\Windows\Fonts\NotoSansKR-VF.ttf")]
    if local_app_data := os.environ.get("LOCALAPPDATA"):
        noto.append(Path(local_app_data) / "Microsoft/Windows/Fonts/NotoSansKR-VF.ttf")
    candidates = {"noto": noto, "segoe": [Path(r"C:\Windows\Fonts\SegUIVar.ttf")]}
    fonts = {}
    for name, paths in candidates.items():
        found = next((path for path in paths if path.is_file()), None)
        if found is None:
            print(f"Font not found: {' or '.join(str(path) for path in paths)}", file=sys.stderr)
            return None
        fonts[name] = found
    return fonts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="Folder containing materials and receiving screenshots.")
    args = parser.parse_args()

    fonts = find_fonts()
    if fonts is None:
        return 1

    skipped = False
    for culture in COPY:
        paths = [
            args.folder / f"store-material-{culture}-{name}.png"
            for name in ("popup-1", "popup-2", "popup-3", "desktop", "settings")
        ]
        missing = [path for path in paths if not path.is_file()]
        if missing:
            for path in missing:
                print(f"Missing: {path}", file=sys.stderr)
            skipped = True
            continue
        font_path = fonts[COPY[culture]["font"]]
        for number, screenshot in enumerate((
            compose_popups(culture, paths[:3], font_path),
            compose_desktop(paths[3]),
            compose_settings(culture, paths[4], font_path),
        ), start=1):
            path = args.folder / f"store-{culture}-{number}.png"
            screenshot.convert("RGB").save(path, format="PNG")
            print(path)
    return 1 if skipped else 0


if __name__ == "__main__":
    raise SystemExit(main())
