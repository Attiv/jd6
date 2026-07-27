# /// script
# dependencies = ["pillow"]
# ///
"""生成聊天背景图：5 套主题 × 亮/暗，1170x2532（iPhone 分辨率）。
背景与对方气泡色刻意拉开对比，并叠加轻噪点与径向渐变。"""
import math, random
from PIL import Image, ImageDraw, ImageFilter
import os

W, H = 1170, 2532
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wallpapers")
os.makedirs(OUT, exist_ok=True)

def hx(s):
    s = s.lstrip('#')
    return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def vgrad(top, bottom):
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        c = lerp(top, bottom, y / (H - 1))
        for x in range(W):
            px[x, y] = c
    return img

def add_glow(img, center, color, radius, alpha):
    """径向柔光"""
    glow = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(glow)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=alpha)
    glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.55))
    layer = Image.new("RGB", (W, H), color)
    img.paste(layer, (0, 0), glow)
    return img

def add_noise(img, amount=5):
    rnd = random.Random(42)
    px = img.load()
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            n = rnd.randint(-amount, amount)
            r, g, b = px[x, y]
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)))
    return img

def add_dots(img, color, alpha=18, step=110, r=3):
    """细微圆点网格纹理"""
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    c = color + (alpha,)
    for j, y in enumerate(range(0, H + step, step)):
        off = step // 2 if j % 2 else 0
        for x in range(-step, W + step, step):
            d.ellipse([x + off - r, y - r, x + off + r, y + r], fill=c)
    img = img.convert("RGBA")
    img.alpha_composite(ov)
    return img.convert("RGB")

def add_waves(img, color, alpha=14, count=9):
    """疏朗的水墨波纹线"""
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    c = color + (alpha,)
    for i in range(count):
        base_y = H * (i + 0.5) / count
        pts = []
        for x in range(0, W + 20, 20):
            y = base_y + math.sin(x / 260 + i * 1.7) * 46 + math.sin(x / 90 + i) * 12
            pts.append((x, y))
        d.line(pts, fill=c, width=5)
    ov = ov.filter(ImageFilter.GaussianBlur(1.2))
    img = img.convert("RGBA")
    img.alpha_composite(ov)
    return img.convert("RGB")

def save(img, name):
    img = add_noise(img)
    path = os.path.join(OUT, name)
    img.save(path, quality=92)
    print("saved", name)

# ---------- iMessage ----------
# 亮色：对方气泡 #E9E9EB(浅灰) → 背景用带蓝调的冷白渐变拉开距离
img = vgrad(hx("F4F8FD"), hx("DCE7F5"))
img = add_glow(img, (W * 0.8, H * 0.12), hx("CFE0F7"), 620, 120)
img = add_glow(img, (W * 0.15, H * 0.85), hx("E8F1FC"), 700, 110)
save(img, "imessage_light.png")
# 暗色：对方气泡 #26262A → 背景更深的蓝黑
img = vgrad(hx("0A0C12"), hx("10131C"))
img = add_glow(img, (W * 0.75, H * 0.1), hx("14213A"), 640, 130)
save(img, "imessage_dark.png")

# ---------- Telegram ----------
# 亮色：经典天蓝 + 圆点纹理（对方气泡纯白，蓝底对比强）
img = vgrad(hx("B7DCF2"), hx("9CC8E8"))
img = add_glow(img, (W * 0.5, H * 0.06), hx("CDE9F8"), 700, 100)
img = add_dots(img, hx("6FA8CE"), alpha=46)
save(img, "telegram_light.png")
# 暗色：午夜蓝 + 更暗圆点（对方气泡 #182533，背景压得更深）
img = vgrad(hx("081019"), hx("0B1622"))
img = add_dots(img, hx("233A52"), alpha=52)
save(img, "telegram_dark.png")

# ---------- 墨玉 ----------
# 亮色：宣纸米色 + 水墨波纹（对方气泡 #F7F4EE 更白，背景略深托起气泡）
img = vgrad(hx("EAE4D6"), hx("DFD8C6"))
img = add_glow(img, (W * 0.2, H * 0.1), hx("F2EDE0"), 620, 110)
img = add_waves(img, hx("A89F88"), alpha=22)
save(img, "moyu_light.png")
# 暗色：墨色 + 黛绿微光（对方气泡 #26282B，背景更黑更绿）
img = vgrad(hx("121513"), hx("171B18"))
img = add_glow(img, (W * 0.8, H * 0.12), hx("22302A"), 640, 120)
img = add_waves(img, hx("3A463E"), alpha=20)
save(img, "moyu_dark.png")

# ---------- 落日橙 ----------
# 亮色：奶油橙晖（对方气泡 #FFF3E6 偏白，背景加深一档带粉橙渐变）
img = vgrad(hx("FBE8D4"), hx("F3D5BC"))
img = add_glow(img, (W * 0.5, H * 0.1), hx("FFDFC2"), 720, 140)
img = add_glow(img, (W * 0.1, H * 0.9), hx("F7CBAF"), 640, 100)
save(img, "sunset_light.png")
# 暗色：炉火余温（对方气泡 #2E2620，背景更深的焦糖黑）
img = vgrad(hx("15100C"), hx("1C1510"))
img = add_glow(img, (W * 0.75, H * 0.1), hx("40281A"), 640, 130)
save(img, "sunset_dark.png")

# ---------- 极夜紫 ----------
# 亮色：淡紫雾（对方气泡 #F2F3F5 灰白，背景带紫调冷灰拉开）
img = vgrad(hx("EFEBFA"), hx("DDD6F0"))
img = add_glow(img, (W * 0.8, H * 0.08), hx("D4C8F5"), 640, 130)
img = add_glow(img, (W * 0.15, H * 0.9), hx("E6DEF8"), 640, 100)
save(img, "nightviolet_light.png")
# 暗色：石墨紫夜（对方气泡 #2B2D31，背景更深带紫光）
img = vgrad(hx("141318"), hx("18161F"))
img = add_glow(img, (W * 0.75, H * 0.1), hx("2A2247"), 660, 130)
save(img, "nightviolet_dark.png")

print("done ->", OUT)
