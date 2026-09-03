from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
FONT_CN = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_CN_LIGHT = "/System/Library/Fonts/STHeiti Light.ttc"
FONT_EN = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
WHITE = (248, 251, 255, 255)
MUTED = (174, 190, 210, 255)
CYAN = (41, 207, 255, 255)
BLUE = (36, 116, 255, 255)
RED = (255, 76, 45, 255)


def font(size: int, light: bool = False, english: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_EN if english else (FONT_CN_LIGHT if light else FONT_CN)
    return ImageFont.truetype(path, size=size)


def rounded(draw: ImageDraw.ImageDraw, xy, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def place_icon(canvas: Image.Image, x: int, y: int, size: int = 96):
    icon = Image.open(ROOT / "UU远程真实图标.png").convert("RGBA")
    icon = icon.resize((size, size), Image.Resampling.LANCZOS)
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.rounded_rectangle((x + 8, y + 8, x + size - 8, y + size - 8), 24, fill=(0, 153, 255, 135))
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    canvas.alpha_composite(glow)
    canvas.alpha_composite(icon, (x, y))


def label(draw, x, y, text, color, fill):
    f = font(25)
    box = draw.textbbox((0, 0), text, font=f)
    w = box[2] - box[0] + 42
    rounded(draw, (x, y, x + w, y + 48), 24, fill=fill, outline=color, width=2)
    draw.text((x + 21, y + 8), text, font=f, fill=color)


def cover():
    image = Image.open("/tmp/uu-scroll-cover-base.png").convert("RGBA")
    draw = ImageDraw.Draw(image, "RGBA")
    w, h = image.size

    # A gentle top veil guarantees headline contrast while retaining the generated atmosphere.
    veil = Image.new("RGBA", image.size, (0, 0, 0, 0))
    vd = ImageDraw.Draw(veil)
    vd.rectangle((0, 0, w, 410), fill=(3, 7, 13, 170))
    veil = veil.filter(ImageFilter.GaussianBlur(20))
    image.alpha_composite(veil)
    draw = ImageDraw.Draw(image, "RGBA")

    place_icon(image, 72, 58, 94)
    draw = ImageDraw.Draw(image, "RGBA")
    draw.text((185, 73), "UU 远程 · macOS", font=font(28), fill=WHITE)
    rounded(draw, (185, 113, 368, 149), 18, fill=(18, 119, 255, 50), outline=(51, 190, 255, 165), width=1)
    draw.text((207, 118), "免费开源工具", font=font(19), fill=CYAN)

    draw.text((70, 184), "UU 远程滚动", font=font(75), fill=WHITE, stroke_width=1, stroke_fill=(0, 0, 0, 120))
    draw.text((70, 268), "终于顺了", font=font(114), fill=CYAN, stroke_width=2, stroke_fill=(0, 63, 100, 150))
    draw.text((76, 394), "鼠标 + 触控板  ·  一键修复", font=font(35, light=True), fill=(220, 232, 245, 255))

    label(draw, 194, 514, "之前：反向 · 乱飘", RED, (52, 11, 7, 205))
    label(draw, 596, 514, "现在：精准 · 丝滑", CYAN, (5, 36, 54, 205))

    rounded(draw, (62, h - 188, w - 62, h - 55), 30, fill=(4, 12, 23, 218), outline=(55, 177, 255, 100), width=2)
    draw.text((98, h - 160), "方向不反  ｜  速度不飘  ｜  滚动丝滑", font=font(31), fill=WHITE)
    draw.text((99, h - 107), "让远程操作，重新拥有 Mac 的手感", font=font(25, light=True), fill=CYAN)
    draw.text((w - 312, h - 39), "GitHub · FlynnAIwang", font=font(17, english=True), fill=(127, 150, 176, 255))

    out = ROOT / "01-UU远程滚动修复-封面-3x4.png"
    image.convert("RGB").save(out, quality=96)
    return out


def effects():
    image = Image.open("/tmp/uu-scroll-effects-base.png").convert("RGBA")
    draw = ImageDraw.Draw(image, "RGBA")
    w, h = image.size

    top = Image.new("RGBA", image.size, (0, 0, 0, 0))
    td = ImageDraw.Draw(top)
    td.rectangle((0, 0, w, 430), fill=(3, 8, 16, 158))
    top = top.filter(ImageFilter.GaussianBlur(22))
    image.alpha_composite(top)
    place_icon(image, 66, 55, 88)
    draw = ImageDraw.Draw(image, "RGBA")
    draw.text((171, 67), "UU Remote Mac Scroll Fix", font=font(24, english=True), fill=WHITE)
    draw.text((171, 108), "鼠标 + 触控板双优化", font=font(20), fill=CYAN)

    draw.text((66, 178), "一个工具", font=font(68), fill=WHITE)
    draw.text((66, 252), "把滚动体验拉回 Mac", font=font(61), fill=CYAN)
    draw.text((71, 334), "滚多少，走多少。终于不飘了。", font=font(31, light=True), fill=(214, 228, 243, 255))

    cards = [
        ("方向一致", "远程不再反着滚"),
        ("鼠标丝滑", "保留 Mos 手感"),
        ("触控更稳", "灵敏度单独降低"),
        ("本地不变", "其他软件照常用"),
    ]
    x0, gap, card_w, y0 = 48, 16, 228, 1147
    for i, (title, subtitle) in enumerate(cards):
        x = x0 + i * (card_w + gap)
        rounded(draw, (x, y0, x + card_w, y0 + 208), 24, fill=(5, 17, 31, 218), outline=(51, 168, 255, 140), width=2)
        rounded(draw, (x + 22, y0 + 21, x + 67, y0 + 66), 13, fill=(25, 167, 255, 55), outline=(65, 209, 255, 190), width=2)
        draw.line(
            (x + 32, y0 + 44, x + 41, y0 + 53, x + 58, y0 + 34),
            fill=CYAN,
            width=4,
            joint="curve",
        )
        draw.text((x + 20, y0 + 88), title, font=font(29), fill=WHITE)
        draw.text((x + 20, y0 + 140), subtitle, font=font(19, light=True), fill=MUTED)

    draw.text((63, h - 47), "一次配置 · 开机自启 · 免费开源", font=font(21), fill=(171, 196, 219, 255))
    draw.text((w - 380, h - 47), "github.com/FlynnAIwang", font=font(18, english=True), fill=CYAN)

    out = ROOT / "02-UU远程滚动修复-效果介绍-3x4.png"
    image.convert("RGB").save(out, quality=96)
    return out


if __name__ == "__main__":
    for path in (cover(), effects()):
        with Image.open(path) as result:
            print(f"saved={path} pixels={result.width}x{result.height} ratio={result.width / result.height:.4f}")
