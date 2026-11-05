"""Decode the death strip drawn by the addon (WallOfShameForever/DeathStrip.lua).

Keep the constants in sync with the Lua side.
"""

BLOCK = 4  # block size in physical pixels
COLS = 48  # blocks per row
MAX_PAYLOAD = 240
HEADER_BLOCKS = 8
MAGIC = [(3, 0, 3), (0, 3, 0), (3, 3, 0), (0, 0, 3)]
MIN_STEP = 20  # minimal gap between two calibration levels

# Biggest possible strip: header + (2 + payload + 2) bytes * 4 digits / 3 per block
MAX_BLOCKS = HEADER_BLOCKS + -(-(MAX_PAYLOAD + 4) * 4 // 3)
WIDTH = COLS * BLOCK
MAX_HEIGHT = -(-MAX_BLOCKS // COLS) * BLOCK

# Where the addon can draw the strip (option in game, DeathStrip.lua ns.STRIP_POSITIONS), anchored
# to that point of the game screen in a frame of WIDTH x MAX_HEIGHT, blocks from its top-left
# corner: (column, row), 0 = left / top, 1 = center / middle, 2 = right / bottom. Never the middle
# of the screen.
POSITIONS = {"TOPLEFT": (0, 0), "TOP": (1, 0), "TOPRIGHT": (2, 0), "LEFT": (0, 1), "RIGHT": (2, 1),
             "BOTTOMLEFT": (0, 2), "BOTTOM": (1, 2), "BOTTOMRIGHT": (2, 2)}
SLACK = 2  # rounding of the game's layout (centered strip on an odd size...), in area units


def fletcher16(data):
    a = b = 0
    for byte in data:
        a = (a + byte) % 255
        b = (b + a) % 255
    return a, b


def decode(img, ox=0, oy=0, block_size=BLOCK):
    """Return (payload, strip_bottom) from an RGB PIL image where the strip starts at (ox, oy),
    or None when there is no valid strip. block_size: size of a block in the image's pixels
    (BLOCK, or another size when the capture is not in physical pixels, e.g. macOS Retina).
    strip_bottom: first row under the strip."""
    width, height = img.size
    if width < ox + COLS * block_size or height < oy + block_size:
        return None
    px = img.load()
    half = block_size / 2

    def sample(i):
        col, row = i % COLS, i // COLS
        y = int(oy + row * block_size + half)
        if y >= height:
            raise IndexError(i)
        return px[int(ox + col * block_size + half), y][:3]

    calib = [sample(i) for i in range(4)]
    for c in range(3):
        values = [calib[level][c] for level in range(4)]
        if any(values[i + 1] - values[i] < MIN_STEP for i in range(3)):
            return None

    def block(i):
        rgb = sample(i)
        return tuple(min(range(4), key=lambda lv: abs(calib[lv][c] - rgb[c])) for c in range(3))

    try:
        if [block(HEADER_BLOCKS - 4 + i) for i in range(4)] != MAGIC:
            return None

        digits = []

        def read_bytes(count):
            # digits are packed 3 per block, 4 per byte
            while len(digits) < count * 4:
                digits.extend(block(HEADER_BLOCKS + len(digits) // 3))
            return [
                digits[i] * 64 + digits[i + 1] * 16 + digits[i + 2] * 4 + digits[i + 3]
                for i in range(0, count * 4, 4)
            ]

        hi, lo = read_bytes(2)
        length = hi * 256 + lo
        if length == 0 or length > MAX_PAYLOAD:
            return None
        data = read_bytes(2 + length + 2)
        payload = bytes(data[2:2 + length])
        if tuple(data[2 + length:]) != fletcher16(payload):
            return None
    except IndexError:
        return None

    blocks = HEADER_BLOCKS + -(-len(digits) // 3)
    return payload.decode("utf-8", errors="replace"), int(oy + -(-blocks // COLS) * block_size + 0.999)


# macOS shows the game's sRGB colours in the screen's colour profile (Display P3 on Macs since
# 2016): greys stay, pure colours bleed into each other (sRGB red 255,0,0 is 234,51,35 in P3), so
# the levels of the strip no longer match the calibration greys. from_display_p3 turns a capture
# back into sRGB: sRGB curve to linear, P3 -> sRGB matrix (D65), back to the sRGB curve.
P3_TO_SRGB = (1.2249, -0.2247, 0.0, 0.0,
              -0.0420, 1.0419, 0.0, 0.0,
              -0.0197, -0.0786, 1.0979, 0.0)


def _to_linear(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def _to_srgb(v):
    v = min(1.0, max(0.0, v))
    return v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


_LINEAR = [round(_to_linear(i) * 255) for i in range(256)] * 3
_GAMMA = [round(_to_srgb(i / 255) * 255) for i in range(256)] * 3


def from_display_p3(img):
    """RGB PIL image captured on a Display P3 screen -> the game's sRGB colours (approximate:
    8-bit linear steps, plenty for the 4 levels of the strip)."""
    return img.point(_LINEAR).convert("RGB", P3_TO_SRGB).point(_GAMMA)


def find(img, block_size, xs, ys):
    """Look for the strip with its top-left corner anywhere in xs x ys (ranges of img pixels).
    Returns (payload, (left, top, right, bottom)): the strip's box in img pixels, a little wide,
    or None."""
    half = int(block_size / 2 + 0.999)
    for oy in ys:
        for ox in xs:
            found = decode(img, ox, oy, block_size)
            if found:
                # the first hit can be half a block early (the sample point enters the first block)
                payload, bottom = found
                return payload, (ox, oy, int(ox + COLS * block_size + 0.999) + half, bottom + half)
    return None


def locate(img, block_size, max_dx, max_dy):
    """Look for the strip near the top-left corner of img: on macOS the capture starts at the window
    frame (title bar included), not at the game's first pixel. Returns (payload, strip bottom)."""
    found = find(img, block_size, range(max_dx + 1), range(max_dy + 1))
    return found and (found[0], found[1][3])


def search_area(position, width, height, scale=1.0, margin_x=0, margin_y=0):
    """Where the top-left corner of the strip can be when the addon anchors it at position, in a
    window of width x height area units (Windows: real pixels of the game; macOS: points of the
    window, title bar included). scale: physical pixels per area unit (the strip is drawn in
    physical pixels). margin_x, margin_y: macOS, the frame and title bar on the left and top of
    the game. Returns (x_lo, x_hi, y_lo, y_hi) in area units, or None if the window is too small."""
    sw, sh = WIDTH / scale, MAX_HEIGHT / scale
    if width < sw or height < sh:
        return None
    col, row = POSITIONS[position]

    def span(size, strip_size, margin, where):
        free = size - strip_size
        if where == 0:
            return 0, min(free, margin)
        if where == 1:
            return max(0, free / 2 - SLACK), min(free, (free + margin) / 2 + SLACK)
        return max(0, free - margin - SLACK), free

    return (*span(width, sw, margin_x, col), *span(height, sh, margin_y, row))


def read(capture, area, position, margin_x=0, margin_y=0, display_p3=False):
    """Look for the strip at one position of the game window. capture(region) returns the image of
    a region of the screen ({left, top, width, height} in area units, like area). Returns
    (payload, strip box in the capture pixels of the whole area, capture pixels per area unit).
    display_p3: macOS, also try the capture converted back from the screen's colour profile."""
    scale = area.get("scale") or 1.0
    found_area = search_area(position, area["width"], area["height"], scale, margin_x, margin_y)
    if not found_area:
        return None
    x_lo, x_hi, y_lo, y_hi = found_area
    left, top = int(x_lo), int(y_lo)
    right = min(area["width"], int(x_hi + WIDTH / scale) + 2)
    bottom = min(area["height"], int(y_hi + MAX_HEIGHT / scale) + 2)
    img = capture({"left": area["left"] + left, "top": area["top"] + top,
                   "width": right - left, "height": bottom - top})
    per_unit = img.width / (right - left)  # capture pixels per area unit (Retina: 1 or 2)
    block = BLOCK * per_unit / scale
    xs = range(int((x_lo - left) * per_unit), int((x_hi - left) * per_unit) + 1)
    ys = range(int((y_lo - top) * per_unit), int((y_hi - top) * per_unit) + 1)
    # as captured, else back from the screen's colour profile (Display P3) to the game's colours
    found = find(img, block, xs, ys) or (display_p3 and find(from_display_p3(img), block, xs, ys))
    if not found:
        return None
    payload, (l, t, r, b) = found
    dx, dy = left * per_unit, top * per_unit
    return payload, (int(l + dx), int(t + dy), int(r + dx + 0.999), int(b + dy + 0.999)), per_unit


def hide(screen, box, position):
    """The game screen without the strip: cut off with the rows above it at the top edge (on macOS
    the title bar goes with them) or below it at the bottom edge; in the middle of the left or
    right edge, covered with the line of the game just above it."""
    left, top, right, bottom = box
    row = POSITIONS[position][1]
    if row == 0:
        return screen.crop((0, min(bottom, screen.height - 1), screen.width, screen.height))
    if row == 2:
        return screen.crop((0, 0, screen.width, max(1, top)))
    left, right = max(0, left - 1), min(screen.width, right + 1)
    top, bottom = max(1, top - 1), min(screen.height, bottom + 1)
    line = screen.crop((left, top - 1, right, top))
    screen = screen.copy()
    screen.paste(line.resize((right - left, bottom - top)), (left, top))
    return screen
