"""Decode the death strip drawn by the addon (ShameWallForever/DeathStrip.lua).

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


def fletcher16(data):
    a = b = 0
    for byte in data:
        a = (a + byte) % 255
        b = (b + a) % 255
    return a, b


def decode(img):
    """Return (payload, strip_height) from an RGB PIL image whose top-left corner is the
    top-left corner of the WoW client area, or None when there is no valid strip."""
    width, height = img.size
    if width < WIDTH or height < BLOCK:
        return None
    px = img.load()

    def sample(i):
        col, row = i % COLS, i // COLS
        y = row * BLOCK + BLOCK // 2
        if y >= height:
            raise IndexError(i)
        return px[col * BLOCK + BLOCK // 2, y][:3]

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
    return payload.decode("utf-8", errors="replace"), -(-blocks // COLS) * BLOCK
