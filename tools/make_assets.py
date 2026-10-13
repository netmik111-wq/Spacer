#!/usr/bin/env python3
"""Builds the game's art and map files from the reference images in art_src/.

  art_src/map_mockup.png  -> assets/tiles.png + assets/tiles.json   (32x32 tiles cut from the mockup, plus
                                                                     see-through floors drawn in code)
  maps/*.txt (ASCII)      -> maps/*.json                            (wall pieces picked automatically;
                                                                     one drawing per deck)
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
#   kind: "wall" blocks movement, everything else can be walked on:
#     "floor", "door";
#     "glass"   a glass floor: the deck below shows through, air does not pass;
#     "grate"   a catwalk: the deck below shows through and shares its air;
#     "hatch"   a hole in the floor with a ladder down: shows and shares air like a grate;
#     "ladder"  the foot of that ladder on the deck below.
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
    # door states drawn in code (new tiles go at the end: maps store tile numbers)
    ("door_half", None, "door"),
    ("airlock_closed", None, "door"),
    ("airlock_half", None, "door"),
]
# See-through floors and ladders are made from every floor piece, so the edge
# of a room looks the same whatever its floor is made of.
FLOOR_PIECES = ["floor_l_t", "floor_m_t", "floor_r_t", "floor_l_b", "floor_m_b", "floor_r_b", "floor_n"]
COVERS = ["glass", "grate", "hatch", "ladder"]
for _cover in COVERS:
    for _piece in FLOOR_PIECES:
        TILES.append((_cover + _piece[5:], None, _cover))
# machines on a wall, drawn in code
TILES.append(("engine", None, "wall"))
TILES.append(("air_plant", None, "wall"))
TILES.append(("locker", None, "wall"))
TILES.append(("lock_pump", None, "wall"))
ATLAS_COLS = 8


def load_mockup():
    im = Image.open(os.path.join(SRC, "map_mockup.png")).convert("RGBA")
    return im.resize((im.width // MOCK_SCALE, im.height // MOCK_SCALE), Image.NEAREST)


def cut(mock, col, row):
    x, y = MOCK_OX + col * T, MOCK_OY + row * T
    return mock.crop((x, y, x + T, y + T))


def make_door_open(mock, gap=1.0):
    """An open doorway drawn from the closed door: the leaves are slid into the
    frame and the opening shows the dark floor of the airlock tile.
    gap=0.5 gives the half-open frame shown while the door moves."""
    door = cut(mock, 6, 3)
    airlock = cut(mock, 2, 4)
    px = door.load()
    floor_col = airlock.getpixel((16, 14))
    edge_col = airlock.getpixel((16, 9))
    out = door.copy()
    o = out.load()
    # opening: between the teal strip / left post and the right post, below the lintel
    x0, x1, y0, y1 = 8, 27, 7, 31
    if gap < 1.0:
        mid = (x0 + x1) // 2
        half = int((x1 - x0) * gap / 2)
        x0, x1 = mid - half, mid + half + 1
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            o[x, y] = floor_col
    if gap >= 1.0:
        # a thin sliver of each leaf stays visible at the sides
        for y in range(y0, y1 + 1):
            o[x0, y] = px[x0, y]
            o[x0 + 1, y] = px[x0 + 1, y]
            o[x1, y] = px[x1, y]
            o[x1 - 1, y] = px[x1 - 1, y]
    else:
        for y in range(y0, y1 + 1):       # dark edges of the two leaves
            o[x0, y] = (36, 38, 50, 255)
            o[x1, y] = (36, 38, 50, 255)
    # floor seam across the threshold
    for x in range(x0 + 2, x1 - 1):
        o[x, 19] = edge_col
    return out


def make_airlock_closed(mock, gap=0.0):
    """The airlock tile from the mockup shows an open passage through a vertical
    wall. Closed, a bulkhead in the door's colours fills the passage; it parts
    in the middle (gap=0.5 is the half-open frame)."""
    out = cut(mock, 2, 4).copy()
    o = out.load()
    plate, plate_d, teal, teal_l, dark = (154, 158, 170, 255), (112, 116, 130, 255), (10, 158, 143, 255), (38, 196, 178, 255), (36, 38, 50, 255)
    x0, x1, y0, y1 = 12, 19, 1, 25                 # the passage between the frame posts
    mid = (y0 + y1) // 2
    open_half = int((y1 - y0) * gap / 2)
    for y in range(y0, y1 + 1):
        if abs(y - mid) < open_half:
            continue                                # the gap between the two leaves
        for x in range(x0, x1 + 1):
            c = plate
            if x in (x0, x1) or y in (y0, y1):
                c = dark
            elif abs(y - mid) == open_half or (gap == 0.0 and y == mid):
                c = dark                            # the seam where the leaves meet
            elif y in (y0 + 2, y0 + 3, y1 - 2, y1 - 3):
                c = teal_l if y in (y0 + 2, y1 - 3) else teal
            elif x == x1 - 1:
                c = plate_d
            o[x, y] = c
    return out


FRAME_D = (36, 38, 50, 255)
FRAME_L = (150, 156, 168, 255)
RAIL = (176, 182, 194, 255)
RAIL_D = (96, 100, 114, 255)
HAZARD = (226, 176, 44, 255)


def make_cover(floor, cover):
    """A floor piece with its middle replaced: glass, a grating, an open hatch
    with a ladder going down, or the foot of that ladder. The first three are
    see-through: what is not drawn here shows the deck below."""
    out = floor.copy()
    o = out.load()
    x0, x1, y0, y1 = 4, 27, 4, 27                  # the panel inside the piece's rim

    def ladder(top, bottom):
        for y in range(top, bottom + 1):
            o[11, y] = RAIL; o[12, y] = RAIL_D
            o[19, y] = RAIL; o[20, y] = RAIL_D
        for y in range(top + 2, bottom, 4):
            for x in range(13, 19):
                o[x, y] = RAIL
                o[x, y + 1] = RAIL_D

    if cover == "ladder":
        for x in range(x0 + 2, x1 - 1):            # a painted outline on the floor around the ladder
            if (x // 3) % 2 == 0:
                o[x, y0 + 1] = HAZARD
                o[x, y1 - 1] = HAZARD
        for y in range(y0 + 2, y1 - 1):
            if (y // 3) % 2 == 0:
                o[x0 + 1, y] = HAZARD
                o[x1 - 1, y] = HAZARD
        ladder(y0 + 3, y1 - 3)
        return out
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            edge = min(x - x0, x1 - x, y - y0, y1 - y)
            if edge == 0:
                o[x, y] = FRAME_D
            elif cover == "hatch":
                if edge <= 2:
                    o[x, y] = HAZARD if ((x + y) // 3) % 2 == 0 else FRAME_D
                else:
                    o[x, y] = (6, 7, 12, 110)      # the shaft: a dark opening
            elif edge == 1:
                o[x, y] = FRAME_L
            elif cover == "glass":
                o[x, y] = (120, 190, 235, 44)
                if (x + y) in (26, 27, 34):        # reflections across the pane
                    o[x, y] = (215, 240, 255, 120)
            else:                                  # grate: bars every fourth pixel
                bar_x, bar_y = (x - x0) % 4 == 1, (y - y0) % 4 == 1
                if bar_x or bar_y:
                    o[x, y] = RAIL_D if (bar_x and bar_y) else (118, 123, 138, 255)
                else:
                    o[x, y] = (8, 9, 14, 60)
    if cover == "hatch":
        ladder(y0 + 3, y1 - 5)
    return out


def make_machine(wall, what):
    """A machine set into a horizontal wall, in the manner of the consoles:
    the engine (a housing with a glowing core), the air plant (a vent) or the
    supply locker (a cabinet with two doors)."""
    out = wall.copy()
    o = out.load()
    cap, body, mid, dark = (191, 193, 193, 255), (147, 156, 165, 255), (106, 107, 122, 255), (43, 43, 59, 255)

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                o[x, y] = c

    if what == "engine":
        rect(4, 3, 27, 24, body); rect(4, 3, 27, 4, cap); rect(4, 24, 27, 24, mid)
        rect(6, 6, 25, 22, dark)
        # the core behind a round window
        for y in range(7, 21):
            for x in range(9, 23):
                d = ((x - 15.5) ** 2 + (y - 13.5) ** 2) ** 0.5
                if d < 3.2:
                    o[x, y] = (190, 250, 255, 255)
                elif d < 5.2:
                    o[x, y] = (60, 215, 230, 255)
                elif d < 6.4:
                    o[x, y] = (20, 120, 140, 255)
                elif d < 7.4:
                    o[x, y] = mid
        for x in range(6, 26):                         # warning stripes under it
            o[x, 22] = HAZARD if (x // 2) % 2 == 0 else dark
        for px in (8, 9, 22, 23):                      # feed pipes down to the deck
            rect(px, 25, px, 29, mid if px in (8, 22) else body)
    elif what == "lock_pump":
        # the airlock pump: a panel with a gauge and two lamps (pump out, pump in)
        rect(6, 4, 25, 24, body); rect(6, 4, 25, 5, cap); rect(6, 24, 25, 24, mid)
        rect(8, 7, 23, 15, dark)
        for y in range(8, 15):
            for x in range(9, 23):
                d = ((x - 15.5) ** 2 + (y - 15.0) ** 2) ** 0.5
                if 5.5 < d < 7.0:
                    o[x, y] = (200, 205, 210, 255)
        for i in range(5):
            o[15 + i // 2, 14 - i] = HAZARD
        rect(9, 18, 13, 21, (200, 70, 50, 255)); rect(18, 18, 22, 21, (70, 170, 220, 255))
        for x in range(6, 26):
            o[x, 23] = HAZARD if (x // 2) % 2 == 0 else dark
    elif what == "locker":
        rect(5, 3, 26, 25, body); rect(5, 3, 26, 4, cap); rect(5, 25, 26, 25, mid)
        rect(7, 6, 15, 23, (176, 138, 62, 255)); rect(16, 6, 24, 23, (176, 138, 62, 255))   # two doors
        rect(7, 6, 15, 7, (214, 176, 92, 255)); rect(16, 6, 24, 7, (214, 176, 92, 255))
        rect(7, 22, 24, 23, (128, 98, 44, 255))
        rect(15, 6, 16, 23, dark)                                                           # the gap between them
        rect(13, 13, 14, 16, cap); rect(17, 13, 18, 16, cap)                                # handles
        for x in range(7, 25):                                                              # a marked band
            if x not in (15, 16):
                o[x, 10] = dark if (x // 2) % 2 == 0 else HAZARD
        rect(9, 18, 12, 20, dark); rect(10, 19, 11, 19, (90, 220, 110, 255))                # a small label
    else:
        rect(5, 5, 26, 23, body); rect(5, 5, 26, 6, cap); rect(5, 23, 26, 23, mid)
        rect(7, 8, 24, 18, dark)
        for y in range(9, 18, 2):                      # the slats of the vent
            rect(8, y, 23, y, mid)
        rect(7, 20, 24, 21, (111, 190, 240, 255))      # the outlet
        rect(7, 21, 24, 21, (70, 130, 200, 255))
        rect(22, 6, 23, 6, (90, 220, 110, 255))        # a lamp
    return out


def build_tiles():
    mock = load_mockup()
    rows = (len(TILES) + ATLAS_COLS - 1) // ATLAS_COLS
    atlas = Image.new("RGBA", (ATLAS_COLS * T, rows * T), (0, 0, 0, 0))
    meta = {"tile_size": T, "columns": ATLAS_COLS, "tiles": []}
    images = {}
    drawn = {
        "door_open": lambda: make_door_open(mock),
        "door_half": lambda: make_door_open(mock, 0.5),
        "airlock_closed": lambda: make_airlock_closed(mock),
        "airlock_half": lambda: make_airlock_closed(mock, 0.5),
        "engine": lambda: make_machine(images["wall_h"], "engine"),
        "air_plant": lambda: make_machine(images["wall_h"], "air_plant"),
        "locker": lambda: make_machine(images["wall_h"], "locker"),
        "lock_pump": lambda: make_machine(images["wall_h"], "lock_pump"),
    }
    for i, (name, src, kind) in enumerate(TILES):
        if kind in COVERS:
            im = make_cover(images["floor" + name[len(kind):]], kind)
        else:
            im = drawn[name]() if name in drawn else cut(mock, *src)
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
#   'g'  glass floor (the deck below shows through; air does not pass)
#   'c'  catwalk: a grating (the deck below shows through and shares its air)
#   'H'  ladder between decks: the same cell on two decks, one above the other
#   '#'  wall (piece chosen from its neighbours)
#   'D'  door in a horizontal wall      'A'  airlock in a vertical wall
#   'W'  window    '<' '>'  wide window (left, right half)
#   '1'..'5'  wall with a console on it
#   '6'  wall with the engine in it          '7'  wall with the air plant in it
#   '8'  wall with the supply locker in it
#   '9'  wall with an airlock pump in it: the floor in front is the chamber; its outer 'D' opens into space
#
#
# A ship with several decks is drawn deck by deck, the top one first. Each
# deck starts with a line "= its name"; all are laid over one another from
# the same corner. In the .json the decks sit in one grid, one below the
# other, `deck_stride` rows apart (a multiple of 16, with at least one empty
# row between decks), so a cell is still just x and y everywhere in the game.
#
# The tile art is made for rooms two tiles tall separated by horizontal wall
# bands, so maps follow that pattern and the script refuses anything else.

BAND_CHARS = set("#DW<>123456789")
FLOOR_CHARS = set(".sgcH")
COVER_OF = {"g": "glass", "c": "grate"}


class MapError(Exception):
    pass


def resolve_map(name, lines, ids, w, h, above, below):
    """One deck. `above` and `below` are the drawings of the decks next to it (or None)."""
    g = [l.ljust(w) for l in lines] + [" " * w] * (h - len(lines))

    def other(deck, x, y):
        if deck is None or y >= len(deck) or x >= len(deck[y]):
            return " "
        return deck[y][x]

    def at(x, y):
        return g[y][x] if 0 <= x < w and 0 <= y < h else " "

    def solid(x, y):  # anything that is part of the wall structure
        return at(x, y) in BAND_CHARS or at(x, y) == "A"

    cells = [-1] * (w * h)
    spawns = []
    doors = []                                   # [x, y, "D" or "A"]
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
                cover = COVER_OF.get(c)
                if c == "c" and other(below, x, y) not in FLOOR_CHARS:
                    raise MapError(f"{name}: catwalk at {x},{y} has no floor on the deck below (its air would have nowhere to go)")
                if c == "H":
                    down, up = other(below, x, y) == "H", other(above, x, y) == "H"
                    if not down and not up:
                        raise MapError(f"{name}: ladder at {x},{y} needs an 'H' in the same cell of the deck above or below")
                    cover = "hatch" if down else "ladder"
                if cover:
                    piece = cover + piece[5:]
            elif c == "A":
                if not (n and s) or e or wst:
                    raise MapError(f"{name}: airlock at {x},{y} must sit inside a vertical wall")
                if at(x, y - 1) == "A" or at(x, y + 1) == "A":
                    raise MapError(f"{name}: airlock at {x},{y} touches another airlock")
                piece = "airlock"
                doors.append([x, y, "A"])
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
                               "4": "console_4", "5": "console_5", "6": "engine", "7": "air_plant", "8": "locker", "9": "lock_pump"}
                    if c in special:
                        if not (e and wst) or n or s:
                            raise MapError(f"{name}: '{c}' at {x},{y} needs plain wall on both sides and none above/below")
                        # a door needs floor on both sides; the outer door of an airlock
                        # chamber has open space on one of them
                        up, down = at(x, y - 1), at(x, y + 1)
                        if c == "D" and not (up in FLOOR_CHARS and down in FLOOR_CHARS or
                                             up in FLOOR_CHARS and down == " " or up == " " and down in FLOOR_CHARS):
                            raise MapError(f"{name}: door at {x},{y} needs floor above and below (or space on one side)")
                        if c == "<" and at(x + 1, y) != ">" or c == ">" and at(x - 1, y) != "<":
                            raise MapError(f"{name}: wide window at {x},{y} needs both halves '<>'")
                        piece = special[c]
                        if c == "D":
                            doors.append([x, y, "D"])
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
    return cells, spawns, doors


def read_decks(name, lines):
    """Splits a drawing into decks: [(deck name, lines)], top deck first."""
    decks = []
    for l in lines:
        if l.startswith("="):
            decks.append((l[1:].strip() or "Палуба %d" % (len(decks) + 1), []))
        elif decks:
            decks[-1][1].append(l)
        elif l.strip():
            decks.append(("Палуба", [l]))
    for _, rows in decks:
        while rows and not rows[-1].strip():
            rows.pop()
    if not decks or not all(rows for _, rows in decks):
        raise MapError(f"{name}: an empty deck")
    return decks


def resolve_ship(name, lines, ids):
    decks = read_decks(name, lines)
    w = max(len(l) for _, rows in decks for l in rows)
    h = max(len(rows) for _, rows in decks)
    stride = ((h + 1 + 15) // 16) * 16
    total = stride * (len(decks) - 1) + h
    cells = [-1] * (w * total)
    spawns, doors = [], []
    for d, (_, rows) in enumerate(decks):
        above = decks[d - 1][1] if d > 0 else None
        below = decks[d + 1][1] if d + 1 < len(decks) else None
        deck_cells, deck_spawns, deck_doors = resolve_map("%s, deck %d" % (name, d + 1), rows, ids, w, h, above, below)
        cells[d * stride * w:d * stride * w + w * h] = deck_cells
        spawns += [[x, y + d * stride] for x, y in deck_spawns]
        doors += [[x, y + d * stride, k] for x, y, k in deck_doors]
    if not spawns and not name.startswith("derelict"):
        raise MapError(f"{name}: no spawn points ('s')")
    return {"name": name, "width": w, "height": total, "deck_height": h, "deck_stride": stride,
            "decks": [n for n, _ in decks], "cells": cells, "spawns": spawns, "doors": doors}


def build_maps(images, ids):
    names = {i: n for n, i in ids.items()}
    for fn in sorted(os.listdir(MAPS)):
        if not fn.endswith(".txt"):
            continue
        name = fn[:-4]
        with open(os.path.join(MAPS, fn), encoding="utf-8") as f:
            lines = [l.rstrip("\n") for l in f if not l.startswith(";")]
        m = resolve_ship(name, lines, ids)
        with open(os.path.join(MAPS, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(m, f, separators=(",", ":"))
        # preview picture for a quick look: the decks one under another, the top one first
        n_decks, dh, stride = len(m["decks"]), m["deck_height"], m["deck_stride"]
        prev = Image.new("RGBA", (m["width"] * T, (n_decks * (dh + 1) - 1) * T), (12, 12, 20, 255))
        for i, t in enumerate(m["cells"]):
            if t >= 0:
                x, y = i % m["width"], i // m["width"]
                prev.alpha_composite(images[names[t]], (x * T, (y % stride + (y // stride) * (dh + 1)) * T))
        os.makedirs(os.path.join(ROOT, "tools", "preview"), exist_ok=True)
        prev.resize((prev.width * 2, prev.height * 2), Image.NEAREST).save(
            os.path.join(ROOT, "tools", "preview", name + ".png"))
        walk = sum(1 for t in m["cells"] if t >= 0 and TILES[t][2] != "wall")
        print(f"map {name}: {m['width']}x{dh}, decks {n_decks}, walkable tiles {walk}, spawns {len(m['spawns'])}")


# ------------------------------------------------------------ characters
#
# Placeholder crew drawn in code: a suited figure with a gas mask and an
# orange visor, loosely after the reference sheet (which has one pose and
# cropped feet, so it cannot be used directly). One 32x48 frame per
# (direction, pose); one row of 12 frames per suit colour.
#   directions in order: down, up, left, right;  poses: stand, step A, step B
# Every frame sits in a cell with a transparent border of CHAR_PAD pixels, so a
# graphics card that samples a hair outside a frame picks up nothing (without
# it, the shadow of the frame above showed as a thin line over the head).

CHAR_W, CHAR_H = 32, 48
CHAR_PAD = 1
CELL_W, CELL_H = CHAR_W + 2 * CHAR_PAD, CHAR_H + 2 * CHAR_PAD
SUIT_COLOURS = [
    ("red", (200, 55, 45)), ("blue", (47, 111, 208)), ("green", (58, 154, 74)),
    ("yellow", (217, 165, 32)), ("purple", (138, 79, 200)), ("orange", (217, 112, 42)),
    ("cyan", (42, 169, 184)), ("white", (201, 204, 212)),
    # pirates (Net.PIRATE_COLOURS rows after the crew's): brown, blood red, near black
    ("pirate_brown", (112, 72, 40)), ("pirate_red", (128, 28, 24)), ("pirate_black", (44, 40, 46)),
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
    sheet = Image.new("RGBA", (CELL_W * 12, CELL_H * len(SUIT_COLOURS)), (0, 0, 0, 0))
    for row, (_, colour) in enumerate(SUIT_COLOURS):
        for d in range(4):
            for pose in range(3):
                sheet.paste(draw_char(colour, d, pose), ((d * 3 + pose) * CELL_W + CHAR_PAD, row * CELL_H + CHAR_PAD))
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


# What the states of hud.dmi are, in file order (they carry no names).
# The first eight are the heartbeat monitor from full health down to death,
# the same eight steps Space Station 13 uses; the rest are warning lamps.
HUD_HEALTH_STATES = 8
HUD_ALERTS = ["overfeed", "hungry", "starving", "kpa_low1", "kpa_low2", "kpa_high1", "kpa_high2",
              "o2_low", "o2_high", "toxic_air", "o2_on", "o2_off"]


def build_hud():
    path = os.path.join(SRC, "hud.dmi")
    fw, fh, states = read_dmi_states(path)
    sheet = Image.open(path).convert("RGBA")
    cols = sheet.width // fw

    def frame(i):
        return sheet.crop(((i % cols) * fw, (i // cols) * fh, (i % cols + 1) * fw, (i // cols + 1) * fh))

    starts, at = [], 0
    for st in states:
        starts.append(at)
        at += st["frames"] * st["dirs"]
    if len(states) != HUD_HEALTH_STATES + len(HUD_ALERTS):
        raise MapError(f"hud.dmi has {len(states)} states, expected {HUD_HEALTH_STATES + len(HUD_ALERTS)}")

    # monitor: one row per health state
    n = states[0]["frames"]
    grid = Image.new("RGBA", (fw * n, fh * HUD_HEALTH_STATES), (0, 0, 0, 0))
    for row in range(HUD_HEALTH_STATES):
        if states[row]["frames"] != n:
            raise MapError("hud.dmi: the monitor states differ in length")
        for i in range(n):
            grid.paste(frame(starts[row] + i), (i * fw, row * fh))
    grid.save(os.path.join(OUT, "hud_monitor.png"))
    delay = states[0]["delay"][0] if states[0]["delay"] else 1.0

    # warning lamps: each cut down to what is drawn, one after another in a strip
    lamps, x = {}, 0
    cut_frames = []
    for k, name in enumerate(HUD_ALERTS):
        st = states[HUD_HEALTH_STATES + k]
        frames = [frame(starts[HUD_HEALTH_STATES + k] + i) for i in range(st["frames"])]
        boxes = [f.getbbox() for f in frames if f.getbbox()]
        box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        w, h = box[2] - box[0], box[3] - box[1]
        lamps[name] = {"x": x, "w": w, "h": h, "frames": len(frames),
                       "frame_seconds": (st["delay"][0] / 10.0) if st["delay"] else 0.0}
        for f in frames:
            cut_frames.append((x, f.crop(box)))
            x += w + 1
    strip = Image.new("RGBA", (x, max(v["h"] for v in lamps.values())), (0, 0, 0, 0))
    for px, im in cut_frames:
        strip.paste(im, (px, 0))
    strip.save(os.path.join(OUT, "hud_alerts.png"))

    with open(os.path.join(OUT, "hud_monitor.json"), "w", encoding="utf-8") as f:
        json.dump({"frame_width": fw, "frame_height": fh, "frames": n, "states": HUD_HEALTH_STATES,
                   "frame_seconds": delay / 10.0, "alerts": lamps}, f, indent=1)
    print(f"hud: monitor {HUD_HEALTH_STATES} states x {n} frames of {fw}x{fh}, {len(lamps)} warning lamps")


# ---------------------------------------------------------------- effects

def build_fx():
    """A hull breach, drawn over the wall or window tile it tore through: a
    ragged hole with space behind it and bent metal around the edge."""
    import math
    import random
    rng = random.Random(7)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    px = im.load()
    cx, cy = 15.5, 15.5
    # radius varies with the angle to make the outline ragged
    spikes = [rng.uniform(0.72, 1.18) for _ in range(14)]

    def radius(a):
        k = (a % (2 * math.pi)) / (2 * math.pi) * len(spikes)
        i, f = int(k) % len(spikes), k - int(k)
        return 10.5 * (spikes[i] * (1 - f) + spikes[(i + 1) % len(spikes)] * f)

    for y in range(T):
        for x in range(T):
            dx, dy = x - cx, y - cy
            d = math.hypot(dx, dy)
            r = radius(math.atan2(dy, dx))
            if d < r - 1.6:
                px[x, y] = (9, 10, 18, 255)            # space
            elif d < r:
                px[x, y] = (26, 27, 36, 255)           # the torn edge in shadow
            elif d < r + 1.2:
                px[x, y] = (196, 200, 210, 255) if dy < 0 else (70, 72, 86, 255)   # bent rim, lit from above
            elif d < r + 2.2 and rng.random() < 0.45:
                px[x, y] = (44, 46, 58, 200)           # scorch marks
    for sx, sy, c in ((12, 13, (150, 160, 200, 255)), (18, 17, (110, 120, 160, 255)), (15, 10, (90, 100, 140, 255)), (19, 12, (200, 210, 240, 255))):
        px[sx, sy] = c                                 # a few stars seen through the hole
    im.save(os.path.join(OUT, "breach.png"))
    print("fx: assets/breach.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(ROOT, "tools", "preview"), exist_ok=True)
    images, ids = build_tiles()
    print(f"tiles: {len(ids)} -> assets/tiles.png")
    build_maps(images, ids)
    build_chars()
    build_hud()
    build_fx()


if __name__ == "__main__":
    try:
        main()
    except MapError as e:
        print("MAP ERROR:", e)
        sys.exit(1)
