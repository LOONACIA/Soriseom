# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow==13.0.0"]
# ///
"""Compose two 1920x1080 Store screenshots per language from captured PNG materials."""

import argparse
import os
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = (1920, 1080)
AMBER = (251, 191, 36)
WHITE = (255, 255, 255)
COPY = {
    "ko-KR": {
        "popup_title": "곡이 바뀌는 순간",
        "popup_lines": [
            [("창을 바꾸지 않아도", WHITE)],
            [("제목·아티스트·앨범아트", AMBER), ("를 바로 확인하세요", WHITE)],
        ],
        "settings_title": ["원하는 대로", "맞추세요"],
        "features": [
            "표시 시간 2~10초",
            "위치 6곳, 크기 70~100%",
            "밝게·어둡게 테마",
            "앱별로 켜고 끄기",
        ],
    },
    "en-US": {
        "popup_title": "When the track changes",
        "popup_lines": [
            [("See the ", WHITE), ("title, artist, and album art", AMBER)],
            [("without switching windows", WHITE)],
        ],
        "settings_title": ["Make it", "yours"],
        "features": [
            "Show for 2 to 10 seconds",
            "6 positions, 70% to 100% size",
            "Light or dark theme",
            "Turn popups on or off per app",
        ],
    },
}

type Line = list[tuple[str, tuple[int, int, int]]]


def background() -> Image.Image:
    small = Image.new("RGB", (192, 108))
    start, end = (13, 110, 104), (30, 58, 168)
    for y in range(108):
        for x in range(192):
            t = x / 192 * 0.55 + y / 108 * 0.45
            small.putpixel((x, y), tuple(round(a + (b - a) * t) for a, b in zip(start, end)))
    canvas = small.resize(SIZE, Image.Resampling.BICUBIC).convert("RGBA")
    waves = Image.new("RGBA", SIZE)
    draw = ImageDraw.Draw(waves)
    for cx, cy, count in ((1640, 250, 7), (260, 880, 6)):
        for i in range(count):
            radius = 90 + i * 85
            draw.ellipse(
                (cx - radius, cy - radius, cx + radius, cy + radius),
                outline=(*WHITE, max(10, 46 - i * 6)),
                width=6,
            )
    canvas.alpha_composite(waves.filter(ImageFilter.GaussianBlur(1.5)))
    return canvas


def line_width(draw: ImageDraw.ImageDraw, line: Line, font: ImageFont.FreeTypeFont) -> float:
    return sum(draw.textlength(text, font=font) for text, _ in line)


def fit_font(path: Path, weight: str, lines: list[Line], size: int, width: int) -> ImageFont.FreeTypeFont:
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    while True:
        font = ImageFont.truetype(str(path), size)
        font.set_variation_by_name(weight)
        if max(line_width(draw, line, font) for line in lines) <= width:
            return font
        size -= 2


def draw_line(
    canvas: Image.Image, line: Line, font: ImageFont.FreeTypeFont, x: float | None, y: int
) -> None:
    draw = ImageDraw.Draw(canvas)
    if x is None:
        x = (SIZE[0] - line_width(draw, line, font)) / 2
    text_y = y - font.getbbox("".join(text for text, _ in line))[1]
    shadow = Image.new("RGBA", SIZE)
    shadow_draw = ImageDraw.Draw(shadow)
    next_x = x
    for text, _ in line:
        shadow_draw.text((next_x, text_y + 6), text, font=font, fill=(0, 0, 0, 120))
        next_x += shadow_draw.textlength(text, font=font)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))
    for text, color in line:
        draw.text((x, text_y), text, font=font, fill=color)
        x += draw.textlength(text, font=font)


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
        (x, y + 18, x + item.width - 1, y + item.height - 1 + 18),
        radius=radius,
        fill=(0, 0, 0, 120),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
    canvas.alpha_composite(item, (x, y))


def compose_popups(culture: str, paths: list[Path], font_path: Path) -> Image.Image:
    copy = COPY[culture]
    canvas = background()
    title = [(copy["popup_title"], AMBER)]
    font = fit_font(font_path, "Black", [title], 112, 1700)
    draw_line(canvas, title, font, None, 70)

    x0, y0 = (1920 - (430 + 620)) // 2, 320
    for path, (dx, dy) in zip(paths, ((0, 0), (430, 140), (170, 280))):
        with Image.open(path) as source:
            popup = rounded(source, source.height // 2)
        popup = popup.resize(
            (620, round(popup.height * 620 / popup.width)), Image.Resampling.LANCZOS
        )
        place(canvas, popup, x0 + dx, y0 + dy, popup.height // 2)

    lines = copy["popup_lines"]
    font = fit_font(font_path, "Bold", lines, 64, 1760)
    for line, y in zip(lines, (820, 912)):
        draw_line(canvas, line, font, None, y)
    return canvas


def compose_settings(culture: str, path: Path, font_path: Path) -> Image.Image:
    copy = COPY[culture]
    canvas = background()
    titles = [[(text, AMBER)] for text in copy["settings_title"]]
    font = fit_font(font_path, "Black", titles, 100, 860)
    for line, y in zip(titles, (210, 340)):
        draw_line(canvas, line, font, 130, y)
    features = [[("· " + text, WHITE)] for text in copy["features"]]
    font = fit_font(font_path, "Bold", features, 46, 860)
    for i, line in enumerate(features):
        draw_line(canvas, line, font, 136, 540 + i * 82)

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
        60 + (960 - settings.height) // 2,
        round(radius * scale),
    )
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="Folder containing materials and receiving screenshots.")
    args = parser.parse_args()

    font_paths = [Path(r"C:\Windows\Fonts\NotoSansKR-VF.ttf")]
    if local_app_data := os.environ.get("LOCALAPPDATA"):
        font_paths.append(Path(local_app_data) / "Microsoft/Windows/Fonts/NotoSansKR-VF.ttf")
    font_path = next((path for path in font_paths if path.is_file()), None)
    if font_path is None:
        print("NotoSansKR-VF.ttf was not found in C:\\Windows\\Fonts or "
              "%LOCALAPPDATA%\\Microsoft\\Windows\\Fonts.", file=sys.stderr)
        return 1

    skipped = False
    for culture in COPY:
        paths = [
            args.folder / f"store-material-{culture}-{name}.png"
            for name in ("popup-1", "popup-2", "popup-3", "settings")
        ]
        missing = [path for path in paths if not path.is_file()]
        if missing:
            for path in missing:
                print(f"Missing: {path}", file=sys.stderr)
            skipped = True
            continue
        for number, screenshot in enumerate((
            compose_popups(culture, paths[:3], font_path),
            compose_settings(culture, paths[3], font_path),
        ), start=1):
            path = args.folder / f"store-{culture}-{number}.png"
            screenshot.convert("RGB").save(path, format="PNG")
            print(path)
    return 1 if skipped else 0


if __name__ == "__main__":
    raise SystemExit(main())
