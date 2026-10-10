#!/usr/bin/env python3
"""Builds the game's art and map files from the reference images in art_src/.

  art_src/map_mockup.png  -> assets/tiles.png + assets/tiles.json   (36 unique 32x32 tiles cut from the mockup)
  maps/*.txt (ASCII)      -> maps/*.json                            (wall pieces picked automatically)
  (generated in code)     -> assets/chars.png                       (placeholder crew, 4 directions)
  art_src/hud.dmi         -> assets/hud_monitor.png                 (heartbeat monitor animation)

Run from the project folder:  python3 tools/make_assets.py
Needs Pillow. The game itself never runs this; it only reads the outputs.
"""
import json
import os
import struct
import sys
import zlib

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_src")
OUT = os.path.join(ROOT, "assets")
MAPS = os.path.join(ROOT, "maps")
T = 32

# ----------------------------------------------------------------- tiles

# The mockup is a 2x screenshot whose tile grid starts 5 px in from the corner.
MOCK_SCALE, MOCK_OX, MOCK_OY = 2, 5, 5

# name -> (column, row) in the mockup grid, plus what the tile is for the game.
#   kind: "wall" blocks movement, "floor"/"door" can be walked on.
TILES = [
    ("wall_h", (1, 0), "wall"),
    ("wall_tl", (0, 0), "wall"),
    ("wall_tr", (10, 0), "wall"),
    ("wall_bl", (0, 3), "wall"),
    ("wall_br", (10, 3), "wall"),
    ("wall_tdown", (2, 0), "wall"),
    ("wall_cross", (2, 3), "wall"),
    ("wall_v", (2, 1), "wall"),
    ("wall_v_end", (2, 2), "wall"),
    ("wall_v_end_l", (0, 2), "wall"),
    ("wall_v_end_r", (10, 2), "wall"),
    ("wall_v_end_a", (2, 5), "wall"),
    ("airlock", (2, 4), "door"),
    ("door", (6, 3), "wall"),
    ("door_open", None, "door"),
    ("window", (7, 3), "wall"),
    ("window_l", (4, 3), "wall"),
    ("window_r", (5, 3), "wall"),
    ("console_1", (3, 0), "wall"),
    ("console_2", (4, 0), "wall"),
    ("console_3", (5, 0), "wall"),
    ("console_4", (6, 0), "wall"),
    ("console_5", (7, 0), "wall"),
    ("floor_l_t", (3, 1), "floor"),
    ("floor_m_t", (4, 1), "floor"),
    ("floor_r_t", (7, 1), "floor"),
    ("floor_l_b", (3, 2), "floor"),
    ("floor_m_b", (4, 2), "floor"),
    ("floor_r_b", (7, 2), "floor"),
    ("floor_n", (1, 1), "floor"),
]
ATLAS_COLS = 8


def load_mockup():
    im = Image.open(os.path.join(SRC, "map_mockup.png")).convert("RGBA")
    return im.resize((im.width // MOCK_SCALE, im.height // MOCK_SCALE), Image.NEAREST)


def cut(mock, col, row):
    x, y = MOCK_OX + col * T, MOCK_OY + row * T
    return mock.crop((x, y, x + T, y + T))


def make_door_open(mock):
    """An open doorway drawn from the closed door: the leaves are slid into the
    frame and the opening shows the dark floor of the airlock tile."""
    door = cut(mock, 6, 3)
    airlock = cut(mock, 2, 4)
    px = door.load()
    floor_col = airlock.getpixel((16, 14))
    edge_col = airlock.getpixel((16, 9))
    out = door.copy()
    o = out.load()
    # opening: between the teal strip / left post and the right post, below the lintel
    x0, x1, y0, y1 = 8, 27, 7, 31
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            o[x, y] = floor_col
    # a thin sliver of each leaf stays visible at the sides
    for y in range(y0, y1 + 1):
        o[x0, y] = px[x0, y]
        o[x0 + 1, y] = px[x0 + 1, y]
        o[x1, y] = px[x1, y]
        o[x1 - 1, y] = px[x1 - 1, y]
    # floor seam across the threshold
    for x in range(x0 + 2, x1 - 1):
        o[x, 19] = edge_col
    return out


def build_tiles():
    mock = load_mockup()
    rows = (len(TILES) + ATLAS_COLS - 1) // ATLAS_COLS
    atlas = Image.new("RGBA", (ATLAS_COLS * T, rows * T), (0, 0, 0, 0))
    meta = {"tile_size": T, "columns": ATLAS_COLS, "tiles": []}
    images = {}
    for i, (name, src, kind) in enumerate(TILES):
        im = make_door_open(mock) if name == "door_open" else cut(mock, *src)
        images[name] = im
        atlas.paste(im, ((i % ATLAS_COLS) * T, (i // ATLAS_COLS) * T))
        meta["tiles"].append({"id": i, "name": name, "kind": kind})
    atlas.save(os.path.join(OUT, "tiles.png"))
    with open(os.path.join(OUT, "tiles.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    return images, {name: i for i, (name, _, _) in enumerate(TILES)}


# ------------------------------------------------------------------ maps
#
# ASCII map legend:
#   ' '  space outside the ship        '.'  floor            's'  floor + spawn point
#   '#'  wall (piece chosen from its neighbours)
#   'D'  door in a horizontal wall      'A'  airlock in a vertical wall
#   'W'  window    '<' '>'  wide window (left, right half)
#   '1'..'5'  wall with a console on it
#
# The tile art is made for decks two tiles tall separated by horizontal wall
# bands, so maps follow that pattern and the script refuses anything else.

BAND_CHARS = set("#DW<>12345")
FLOOR_CHARS = set(".s")


class MapError(Exception):
    pass


def resolve_map(name, lines, ids):
    h = len(lines)
    w = max(len(l) for l in lines)
    g = [l.ljust(w) for l in lines]

    def at(x, y):
        return g[y][x] if 0 <= x < w and 0 <= y < h else " "

    def solid(x, y):  # anything that is part of the wall structure
        return at(x, y) in BAND_CHARS or at(x, y) == "A"

    cells = [-1] * (w * h)
    spawns = []
    for y in range(h):
        for x in range(w):
            c = at(x, y)
            n, s, e, wst = solid(x, y - 1), solid(x, y + 1), solid(x + 1, y), solid(x - 1, y)
            piece = None
            if c == " ":
                continue
            if c in FLOOR_CHARS:
                if c == "s":
                    spawns.append([x, y])
                left = at(x - 1, y) in FLOOR_CHARS
                right = at(x + 1, y) in FLOOR_CHARS
                top = at(x, y - 1) not in FLOOR_CHARS
                bottom = at(x, y + 1) not in FLOOR_CHARS
                if top == bottom:
                    raise MapError(f"{name}: floor at {x},{y} is not in a deck exactly two tiles tall")
                row = "t" if top else "b"
                if not left and not right:
                    piece = "floor_n"
                else:
                    piece = "floor_%s_%s" % ("l" if not left else ("r" if not right else "m"), row)
            elif c == "A":
                if not (n and s) or e or wst:
                    raise MapError(f"{name}: airlock at {x},{y} must sit inside a vertical wall")
                if at(x, y - 1) == "A" or at(x, y + 1) == "A":
                    raise MapError(f"{name}: airlock at {x},{y} touches another airlock")
                piece = "airlock"
            elif c in BAND_CHARS:
                horizontal = e or wst
                if not horizontal:
                    # part of a vertical wall
                    if c != "#":
                        raise MapError(f"{name}: '{c}' at {x},{y} must be inside a horizontal wall")
                    if not n or not s:
                        raise MapError(f"{name}: loose wall end at {x},{y}")
                    below_is_band = solid(x - 1, y + 1) or solid(x + 1, y + 1)
                    if not below_is_band:
                        piece = "wall_v"
                    elif at(x, y - 1) == "A":
                        piece = "wall_v_end_a"
                    elif not solid(x - 1, y + 1):
                        piece = "wall_v_end_l"   # the band below turns right only (bottom-left corner)
                    elif not solid(x + 1, y + 1):
                        piece = "wall_v_end_r"
                    else:
                        piece = "wall_v_end"
                else:
                    special = {"D": "door_open", "W": "window", "<": "window_l", ">": "window_r",
                               "1": "console_1", "2": "console_2", "3": "console_3",
                               "4": "console_4", "5": "console_5"}
                    if c in special:
                        if not (e and wst) or n or s:
                            raise MapError(f"{name}: '{c}' at {x},{y} needs plain wall on both sides and none above/below")
                        if c == "D" and not (at(x, y - 1) in FLOOR_CHARS and at(x, y + 1) in FLOOR_CHARS):
                            raise MapError(f"{name}: door at {x},{y} needs floor above and below")
                        if c == "<" and at(x + 1, y) != ">" or c == ">" and at(x - 1, y) != "<":
                            raise MapError(f"{name}: wide window at {x},{y} needs both halves '<>'")
                        piece = special[c]
                    elif e and wst:
                        piece = "wall_cross" if (n and s) else ("wall_tdown" if s else "wall_h")
                    elif e and not wst:
                        if n == s:
                            raise MapError(f"{name}: wall end at {x},{y} has no matching corner piece")
                        piece = "wall_tl" if s else "wall_bl"
                    else:
                        if n == s:
                            raise MapError(f"{name}: wall end at {x},{y} has no matching corner piece")
                        piece = "wall_tr" if s else "wall_br"
            else:
                raise MapError(f"{name}: unknown character '{c}' at {x},{y}")
            cells[y * w + x] = ids[piece]
    if not spawns:
        raise MapError(f"{name}: no spawn points ('s')")
    return {"name": name, "width": w, "height": h, "cells": cells, "spawns": spawns}


def build_maps(images, ids):
    names = {i: n for n, i in ids.items()}
    for fn in sorted(os.listdir(MAPS)):
        if not fn.endswith(".txt"):
            continue
        name = fn[:-4]
        with open(os.path.join(MAPS, fn), encoding="utf-8") as f:
            lines = [l.rstrip("\n") for l in f if not l.startswith(";")]
        while lines and not lines[-1].strip():
            lines.pop()
        m = resolve_map(name, lines, ids)
        with open(os.path.join(MAPS, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(m, f, separators=(",", ":"))
        # preview picture for a quick look
        prev = Image.new("RGBA", (m["width"] * T, m["height"] * T), (12, 12, 20, 255))
        for i, t in enumerate(m["cells"]):
            if t >= 0:
                prev.alpha_composite(images[names[t]], ((i % m["width"]) * T, (i // m["width"]) * T))
        os.makedirs(os.path.join(ROOT, "tools", "preview"), exist_ok=True)
        prev.resize((prev.width * 2, prev.height * 2), Image.NEAREST).save(
            os.path.join(ROOT, "tools", "preview", name + ".png"))
        walk = sum(1 for t in m["cells"] if t >= 0 and TILES[t][2] != "wall")
        print(f"map {name}: {m['width']}x{m['height']}, walkable tiles {walk}, spawns {len(m['spawns'])}")


# ------------------------------------------------------------ characters
#
# Placeholder crew drawn in code: a suited figure with a gas mask and an
# orange visor, loosely after the reference sheet (which has one pose and
# cropped feet, so it cannot be used directly). One 32x48 frame per
# (direction, pose); one row of 12 frames per suit colour.
#   directions in order: down, up, left, right;  poses: stand, step A, step B

CHAR_W, CHAR_H = 32, 48
SUIT_COLOURS = [
    ("red", (200, 55, 45)), ("blue", (47, 111, 208)), ("green", (58, 154, 74)),
    ("yellow", (217, 165, 32)), ("purple", (138, 79, 200)), ("orange", (217, 112, 42)),
    ("cyan", (42, 169, 184)), ("white", (201, 204, 212)),
]
OUTLINE = (20, 20, 28, 255)
HELM = (86, 88, 100, 255)
HELM_D = (58, 60, 72, 255)
HELM_L = (120, 123, 138, 255)
VISOR = (240, 122, 40, 255)
VISOR_L = (255, 190, 90, 255)
GLOVE = (112, 116, 128, 255)
BOOT = (52, 54, 64, 255)
TANK = (128, 132, 146, 255)
TANK_D = (92, 96, 110, 255)
STRIPE = (232, 236, 244, 255)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c) + (255,)


def draw_char(colour, direction, pose):
    im = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    px = im.load()
    base = colour + (255,)
    dark = shade(colour, 0.72)
    lite = shade(colour, 1.22)

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < CHAR_W and 0 <= y < CHAR_H:
                    px[x, y] = c

    bob = 1 if pose != 0 else 0          # body dips a pixel while stepping
    top = 7 + bob
    if direction in (0, 1):               # facing the camera / away from it
        # legs
        l_up = 2 if pose == 1 else 0
        r_up = 2 if pose == 2 else 0
        rect(11, 33, 15, 42 - l_up, base); rect(11, 33, 12, 42 - l_up, dark)
        rect(17, 33, 21, 42 - r_up, base); rect(20, 33, 21, 42 - r_up, dark)
        rect(11, 39 - l_up, 15, 39 - l_up, STRIPE); rect(17, 39 - r_up, 21, 39 - r_up, STRIPE)
        rect(10, 43 - l_up, 15, 45 - l_up, BOOT); rect(17, 43 - r_up, 22, 45 - r_up, BOOT)
        # torso
        rect(10, top + 12, 22, top + 25, base)
        rect(10, top + 12, 11, top + 25, dark); rect(21, top + 12, 22, top + 25, dark)
        rect(10, top + 25, 22, top + 25, shade(colour, 0.55))
        # arms swing opposite to the legs
        la = 1 if pose == 2 else 0
        ra = 1 if pose == 1 else 0
        rect(7, top + 13, 9, top + 22 - la, base); rect(7, top + 13, 7, top + 22 - la, dark)
        rect(23, top + 13, 25, top + 22 - ra, base); rect(25, top + 13, 25, top + 22 - ra, dark)
        rect(7, top + 16, 9, top + 16, STRIPE); rect(23, top + 16, 25, top + 16, STRIPE)
        rect(7, top + 23 - la, 9, top + 24 - la, GLOVE); rect(23, top + 23 - ra, 25, top + 24 - ra, GLOVE)
        # head
        rect(11, top, 21, top + 10, HELM)
        rect(11, top, 21, top + 1, HELM_L)
        rect(11, top + 9, 21, top + 10, HELM_D)
        if direction == 0:
            rect(13, top + 13, 19, top + 13, lite)                    # collar
            rect(12, top + 3, 20, top + 5, VISOR); rect(12, top + 3, 20, top + 3, VISOR_L)
            rect(14, top + 7, 18, top + 10, HELM_D)                    # mask
            rect(11, top + 7, 12, top + 9, HELM_D); rect(20, top + 7, 21, top + 9, HELM_D)  # filters
            rect(15, top + 15, 17, top + 16, lite)                    # chest badge
        else:
            rect(13, top + 4, 19, top + 4, HELM_D)                    # strap
            rect(12, top + 14, 20, top + 22, TANK)                    # air tank
            rect(12, top + 14, 13, top + 22, TANK_D); rect(12, top + 22, 20, top + 22, TANK_D)
            rect(15, top + 12, 17, top + 13, TANK_D)
    else:                                  # profile, drawn facing left
        # legs: scissor while stepping
        if pose == 0:
            rect(13, 33, 18, 42, base); rect(17, 33, 18, 42, dark)
            rect(13, 39, 18, 39, STRIPE)
            rect(12, 43, 18, 45, BOOT)
        else:
            f = -3 if pose == 1 else 3     # front leg offset
            rect(13 + f, 33, 17 + f, 41, base); rect(13 + f, 38, 17 + f, 38, STRIPE)
            rect(12 + f, 42, 17 + f, 44, BOOT)
            rect(14 - f, 33, 18 - f, 42, dark)
            rect(13 - f, 43, 18 - f, 45, BOOT)
            rect(13, 33, 18, 35, base)
        # torso
        rect(12, top + 12, 19, top + 25, base)
        rect(18, top + 12, 19, top + 25, dark)
        rect(12, top + 25, 19, top + 25, shade(colour, 0.55))
        rect(20, top + 14, 22, top + 22, TANK); rect(22, top + 14, 22, top + 22, TANK_D)   # tank on the back
        # near arm
        sw = 0 if pose == 0 else (-2 if pose == 1 else 2)
        rect(14 - sw, top + 13, 16 - sw, top + 22, base); rect(16 - sw, top + 13, 16 - sw, top + 22, dark)
        rect(14 - sw, top + 16, 16 - sw, top + 16, STRIPE)
        rect(14 - sw, top + 23, 16 - sw, top + 24, GLOVE)
        # head
        rect(11, top, 20, top + 10, HELM)
        rect(11, top, 20, top + 1, HELM_L)
        rect(11, top + 9, 20, top + 10, HELM_D)
        rect(10, top + 3, 15, top + 5, VISOR); rect(10, top + 3, 15, top + 3, VISOR_L)
        rect(9, top + 7, 13, top + 10, HELM_D)                         # mask snout
        rect(16, top + 6, 18, top + 8, HELM_D)                         # side filter
    # outline around the silhouette
    solid = [[px[x, y][3] > 0 for x in range(CHAR_W)] for y in range(CHAR_H)]
    for y in range(CHAR_H):
        for x in range(CHAR_W):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < CHAR_W and 0 <= ny < CHAR_H and solid[ny][nx]:
                    px[x, y] = OUTLINE
                    break
    if direction == 3:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    # soft shadow under the feet, so the figure sits on the floor
    out = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    sp = out.load()
    for y in range(43, 48):
        half = (9, 11, 11, 10, 7)[y - 43]
        for x in range(16 - half, 16 + half):
            sp[x, y] = (0, 0, 0, 70)
    out.alpha_composite(im)
    return out


def build_chars():
    sheet = Image.new("RGBA", (CHAR_W * 12, CHAR_H * len(SUIT_COLOURS)), (0, 0, 0, 0))
    for row, (_, colour) in enumerate(SUIT_COLOURS):
        for d in range(4):
            for pose in range(3):
                sheet.paste(draw_char(colour, d, pose), ((d * 3 + pose) * CHAR_W, row * CHAR_H))
    sheet.save(os.path.join(OUT, "chars.png"))
    prev = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    bg = Image.new("RGBA", prev.size, (74, 78, 88, 255))
    bg.alpha_composite(prev)
    bg.save(os.path.join(ROOT, "tools", "preview", "chars.png"))
    print(f"chars: {len(SUIT_COLOURS)} colours x 12 frames -> assets/chars.png")


# -------------------------------------------------------------------- HUD
#
# A BYOND .dmi is a PNG with a text block listing its icon states. The first
# state of hud.dmi is the heartbeat monitor (22 frames, 0.8 ds each).

def read_dmi_states(path):
    data = open(path, "rb").read()
    pos, desc = 8, ""
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + ln]
        if typ == b"zTXt" and body.startswith(b"Description\x00"):
            desc = zlib.decompress(body[len(b"Description\x00") + 1:]).decode("utf-8", "replace")
        pos += 12 + ln
    states, cur, size = [], None, {}
    for line in desc.splitlines():
        t = line.strip()
        if t.startswith("state ="):
            cur = {"name": t.split("=", 1)[1].strip().strip('"'), "dirs": 1, "frames": 1, "delay": []}
            states.append(cur)
        elif "=" in t:
            k, v = [q.strip() for q in t.split("=", 1)]
            if cur is None:
                size[k] = v
            elif k in ("dirs", "frames"):
                cur[k] = int(v)
            elif k == "delay":
                cur["delay"] = [float(q) for q in v.split(",")]
    return int(size.get("width", 32)), int(size.get("height", 32)), states


def build_hud():
    path = os.path.join(SRC, "hud.dmi")
    fw, fh, states = read_dmi_states(path)
    sheet = Image.open(path).convert("RGBA")
    cols = sheet.width // fw
    first = states[0]
    n = first["frames"] * first["dirs"]
    strip = Image.new("RGBA", (fw * n, fh), (0, 0, 0, 0))
    for i in range(n):
        strip.paste(sheet.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh)), (i * fw, 0))
    strip.save(os.path.join(OUT, "hud_monitor.png"))
    delay = first["delay"][0] if first["delay"] else 1.0
    with open(os.path.join(OUT, "hud_monitor.json"), "w", encoding="utf-8") as f:
        json.dump({"frame_width": fw, "frame_height": fh, "frames": n, "frame_seconds": delay / 10.0}, f)
    print(f"hud: monitor {n} frames of {fw}x{fh}, {delay / 10.0:.2f} s per frame ({len(states)} states in the .dmi)")


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(ROOT, "tools", "preview"), exist_ok=True)
    images, ids = build_tiles()
    print(f"tiles: {len(ids)} -> assets/tiles.png")
    build_maps(images, ids)
    build_chars()
    build_hud()


if __name__ == "__main__":
    try:
        main()
    except MapError as e:
        print("MAP ERROR:", e)
        sys.exit(1)
