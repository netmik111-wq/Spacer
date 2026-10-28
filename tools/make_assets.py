#!/usr/bin/env python3
"""Builds the game's art and map files from the reference images in art_src/.

  art_src/tileset/Tile_set_1.png + .json -> assets/tiles.png + assets/tiles.json   (v90: the author's tile set, an
                                                                     Aseprite sheet with named slices; machines it has
                                                                     no picture for are still drawn in code on its wall.
                                                                     art_src/old/ keeps the v89 mockup and sheet)
  maps/*.txt (ASCII)      -> maps/*.json                            (wall pieces picked automatically;
                                                                     one drawing per deck)
  (generated in code)     -> assets/chars.png                       (robots, heavy boarders; the old drawn crew)
  art_src/body.png        -> assets/body.png                        (v87: the author's base bodies, woman and man, 4 ways of 32x48)
  art_src/suit_man.png, suit_woman.png -> assets/                   (v88: the suited man and woman, 3 visors x 4 ways of 32x48)
  art_src/hud.dmi         -> assets/hud_monitor.png                 (heartbeat monitor animation)

Run from the project folder:  python3 tools/make_assets.py
Needs Pillow. The game itself never runs this; it only reads the outputs.
"""
import json
import os
import struct
import sys
import zlib

from PIL import Image, ImageDraw, ImageOps

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
TILES.append(("gun", None, "wall"))
TILES.append(("intercom", None, "wall"))
TILES.append(("holo", None, "wall"))
TILES.append(("shield", None, "wall"))
TILES.append(("bench", None, "wall"))
TILES.append(("bay", None, "wall"))
TILES.append(("autodoc", None, "wall"))
TILES.append(("scanner", None, "wall"))
TILES.append(("smes", None, "wall"))
TILES.append(("smes_small", None, "wall"))
TILES.append(("comms", None, "wall"))
TILES.append(("tray", None, "wall"))
TILES.append(("cryo", None, "wall"))
TILES.append(("stove", None, "wall"))
# The pirate ship is every tile again in the pirates' colours (the author's
# words: brown, red, dark black). A map named pirate* is laid in these.
PIRATE = "pirate_"
for _name, _src, _kind in list(TILES):
    TILES.append((PIRATE + _name, None, _kind))
# (v81, the author's "And asteroids!") An asteroid's pieces, put last so every older tile keeps its
# place in the sheet (a «sprites/tiles.png» drawn for an older build still fits over the top).
ROCKS = ["rock_1", "rock_2", "rock_3"]
for _rock in ROCKS:
    TILES.append((_rock, None, "wall"))
TILES.append(("rock_ore", None, "wall"))
TILES.append(("rock_ground", None, "floor"))
# (v81, the author: "more than 2 tiles") the floor of a room's middle rows, for rooms taller than two,
# with its see-through kinds and the pirates' colours, all after the rest for the same reason
MIDDLES = ["floor_l_m", "floor_m_m", "floor_r_m"]
for _piece in MIDDLES:
    TILES.append((_piece, None, "floor"))
for _cover in COVERS:
    for _piece in MIDDLES:
        TILES.append((_cover + _piece[5:], None, _cover))
for _name, _src, _kind in list(TILES[-len(MIDDLES) * (len(COVERS) + 1):]):
    TILES.append((PIRATE + _name, None, _kind))
# (v86, the author's N1) the shuttle's hangar: a force field in the hull that holds the air in and lets
# light through (a window to the game), and the shuttle's dock console beside it; last, as above
TILES.append(("window_field", None, "wall"))
TILES.append(("dock", None, "wall"))
# (v90, the author's tile set) Pictures the client puts in place of a cell's own tile when it lays the
# map (WorldView._look): nothing in the maps changes. Each block goes last, as above.
#   window_m             a window between two others (a row of windows, "WWW", is one long pane)
#   window*_s2..s5       a window's shutter closing (s1 is the plain window); window_v* the same in a
#                        vertical wall (not used yet: kept for the author's answer)
#   <machine>_up         a machine whose front is the room above it (seen from behind)
#   <machine>_wK_I       piece I of a machine drawn K tiles wide, for a row of K of them ("33" = one wide helm)
#   door_<type>_<h|v>_<lamp>, _open1.._open3   doors by type (base, tech, cargo, herm), in a horizontal
#                        (h, "D") or vertical (v, "A") wall, shut with a green, yellow or red lamp, or opening
DOOR_TYPES = ["base", "tech", "cargo", "herm"]
DOOR_LAMPS = ["green", "yellow", "red"]
DOOR_OPEN = {"h": 3, "v": 2}
WINDOW_PIECES = ["", "_l", "_m", "_r"]
WINDOW_V_PIECES = ["up", "m", "down", "single"]
# machine -> (picture facing down, picture facing up or None, width in tiles)
# (v93, the author's note "it looks at the walls, it needs to look inside") his "_up" picture is the machine at
# the top wall, its front to the room below (we see its screen), and "_down" the one at the bottom wall
MACHINE_ART = {
    "console_1": ("holo_map_small", None, 2),
    "console_3": ("pilot_terminal_up", "pilot_terminal_down", 2),
    "console_4": ("gun_terminal_up", "gun_terminal_down", 3),
    "console_5": ("drone_terminal_up", "drone_terminal_down", 1),
    "comms": ("communications_terminal_up", "communications_terminal_down", 2),
    "holo": ("ship_map", None, 2),
    "locker": ("Locker_up", "Locker_down", 1),
    "intercom": ("intercom", None, 1),
    "smes": ("SMES_big", None, 2),
    "smes_small": ("SMES", None, 1),
}
LOOKS = [("window_m", None, "wall")]
for _piece in WINDOW_PIECES:
    for _stage in range(2, 6):
        LOOKS.append(("window%s_s%d" % (_piece, _stage), None, "wall"))
for _piece in WINDOW_V_PIECES:
    for _stage in range(1, 6):
        LOOKS.append(("window_v_%s_s%d" % (_piece, _stage), None, "wall"))
for _m, (_down, _up, _k) in MACHINE_ART.items():
    LOOKS.append((_m + "_up", None, "wall"))
    if _k > 1:
        for _side in ("", "_up"):
            for _i in range(_k):
                LOOKS.append(("%s%s_w%d_%d" % (_m, _side, _k, _i), None, "wall"))
for _type in DOOR_TYPES:
    for _o in ("h", "v"):
        for _lamp in DOOR_LAMPS:
            LOOKS.append(("door_%s_%s_%s" % (_type, _o, _lamp), None, "door"))
        for _i in range(1, DOOR_OPEN[_o] + 1):
            LOOKS.append(("door_%s_%s_open%d" % (_type, _o, _i), None, "door"))
TILES += LOOKS
TILES += [(PIRATE + _name, None, _kind) for _name, _src, _kind in LOOKS]
# (v90.1, the author: "Wall dont have cross connection") a horizontal wall that a vertical one meets
# from above only (a turned T); last, as above
TILES.append(("wall_tup", None, "wall"))
TILES.append((PIRATE + "wall_tup", None, "wall"))
# (v91) a vertical wall going on past a band that leaves it to one side (├ and ┤): his internal corners
TILES += [("wall_jr", None, "wall"), ("wall_jl", None, "wall"), (PIRATE + "wall_jr", None, "wall"), (PIRATE + "wall_jl", None, "wall")]
# (v91, his W3) a window in a side wall ('W' in a vertical wall); the client lays a column of them in his pieces
TILES += [("window_v", None, "wall"), (PIRATE + "window_v", None, "wall")]
# (v91, the author: "now it's not walls, it's on the ground") a machine standing on the floor is laid in two
# tiles: the floor under it (the map's "things") and its picture alone, over the floor (WorldView._paint_decks):
#   <machine>_fl, _fl_up, _fl_r, _fl_l   facing down (seen from the front), up (from behind), left (its back to
#                                        a wall on its right: his "_r" pictures) and right
#   <machine>_fl<side>_wK_I              piece I of one K tiles wide (from the top down for _r and _l)
#   console_1_fl_t_I                     piece I (along the rows) of the star chart's big holo table, two by two
FLOOR_MACHINES = ["console_1", "console_3", "console_4", "console_5", "engine", "air_plant", "locker", "holo", "shield",
                  "bench", "bay", "autodoc", "scanner", "smes", "smes_small", "comms", "tray", "cryo", "stove"]
FLOOR_SIDE = {"console_3": ("pilot_terminal_r", None), "console_4": ("gun_terminal_r", None),
              "comms": ("communications_terminal_r", None), "console_5": ("drone_terminal_r", "drone_terminal_l"),
              "locker": ("Locker_r", "Locker_l")}
FLOOR_LOOKS = []
for _m in FLOOR_MACHINES:
    _k = MACHINE_ART[_m][2] if _m in MACHINE_ART else 1
    for _side in ("", "_up", "_r", "_l"):
        FLOOR_LOOKS.append((_m + "_fl" + _side, None, "wall"))
        if _k > 1:
            for _i in range(_k):
                FLOOR_LOOKS.append(("%s_fl%s_w%d_%d" % (_m, _side, _k, _i), None, "wall"))
for _i in range(4):
    FLOOR_LOOKS.append(("console_1_fl_t_%d" % _i, None, "wall"))
TILES += FLOOR_LOOKS
TILES += [(PIRATE + _name, None, _kind) for _name, _src, _kind in FLOOR_LOOKS]
# (v91, the author's F2 and D2b) lamps on the floor by a door (green opens, yellow open or opening, orange
# broken, red blocked), the danger line inside an airlock's outer door and a room's air vent, each alone on a
# clear tile, laid over the floor by the client. (A door's own yellow frame, from v90, is no longer laid: his
# yellow lamp is in his open frames.)
MARKS = [("lamp_" + _c, None, "floor") for _c in ("green", "yellow", "orange", "red")]
MARKS += [("danger_line", None, "floor"), ("vent", None, "floor")]
TILES += MARKS
TILES += [(PIRATE + _name, None, _kind) for _name, _src, _kind in MARKS]
# (v91, his W2; v93, his note "outer windows without shutters") a window between rooms is his "v1" pane, which
# has no shutter; one onto open space is his "v2", whose shutter comes down in his stages. Laid by the client in
# place of the map's window, by what is on its other side
OUTER_PANES = [("window_in" + _piece, None, "wall") for _piece in WINDOW_PIECES]
TILES += OUTER_PANES
TILES += [(PIRATE + _name, None, _kind) for _name, _src, _kind in OUTER_PANES]
# (v91, his M7) things on a wall: the first-aid box and the spare parts box (each hands out what the supply
# locker keeps of them), the fire box (only a picture until there is fire) and a wall light
WALL_BOX_ART = {"med_box": "med_box", "tech_box": "tex_box", "fire_box": "fire_box", "wall_light": "wall_light_horizontal"}
TILES += [(_name, None, "wall") for _name in WALL_BOX_ART]
TILES += [(PIRATE + _name, None, "wall") for _name in WALL_BOX_ART]
# (v91, his M5) his five ship pictures for the star chart, white (the chart tints them; ours in his colour)
MAP_SHIPS = [("map_ship_%d" % _i, None, "floor") for _i in range(1, 6)]
TILES += MAP_SHIPS
TILES += [(PIRATE + _name, None, _kind) for _name, _src, _kind in MAP_SHIPS]
# (v91, the author's F3: "dark stairs go down, white go up") a flight of stairs ('/', two cells on a deck and the
# same two on the deck below): its cells are plain floor ("stairs"); his picture is laid over them by the client
# (WorldView._lay_marks) in pieces, a flight along a row as 2x2 (the row above takes the top of the railing),
# one along a column as 1x2, drawn going down to the right or downwards and flipped for the other way
STAIRS = [("stairs", None, "floor")]
for _k in ("dn", "up"):
    STAIRS += [("stairs_%s_h_%d" % (_k, _i), None, "floor") for _i in range(4)]
    STAIRS += [("stairs_%s_v_%d" % (_k, _i), None, "floor") for _i in range(2)]
TILES += STAIRS
TILES += [(PIRATE + _name, None, _kind) for _name, _src, _kind in STAIRS]
# (v93, the author's note) the star chart's globe floats a tile above its table: its upper half, two pieces laid
# over the floor of the row above the table (WorldView._paint_decks); last, as above
GLOBE = [("holo_globe_%d" % _i, None, "floor") for _i in range(2)]
TILES += GLOBE
TILES += [(PIRATE + _name, None, _kind) for _name, _src, _kind in GLOBE]
ATLAS_COLS = 8


def pirate_tint(im):
    """Repaints a tile by brightness: shadows near black, middles brown, lights rust red."""
    stops = [(0.0, (10, 9, 11)), (0.4, (40, 30, 28)), (0.68, (84, 54, 36)), (0.86, (128, 42, 34)), (1.0, (176, 74, 52))]
    out = im.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255.0
            for (l0, c0), (l1, c1) in zip(stops, stops[1:]):
                if lum <= l1:
                    k = (lum - l0) / (l1 - l0)
                    px[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3)) + (a,)
                    break
    return out


def load_mockup():
    im = Image.open(os.path.join(SRC, "old", "map_mockup.png")).convert("RGBA")
    return im.resize((im.width // MOCK_SCALE, im.height // MOCK_SCALE), Image.NEAREST)


def cut(mock, col, row):
    x, y = MOCK_OX + col * T, MOCK_OY + row * T
    return mock.crop((x, y, x + T, y + T))


# ------------------------------------------------------- (v90) the author's tile set
TILESET = os.path.join(SRC, "tileset", "Tile_set_1")


def load_tileset():
    """The author's Aseprite sheet cut by its named slices: name -> picture. The export is read
    leniently, as Aseprite wrote it: a name with stray line breaks is trimmed, a one-tile slice a
    pixel off the 32-pixel grid is put back on it, and a name given twice (a right piece whose
    name was copied for the left one) is told apart by place: the one further left is the "_l"."""
    with open(TILESET + ".json", encoding="utf-8") as f:
        meta = json.loads(f.read(), strict=False)["meta"]
    sheet = Image.open(TILESET + ".png").convert("RGBA")
    found = {}
    for sl in meta["slices"]:
        b = sl["keys"][0]["bounds"]
        x, y, w, h = b["x"], b["y"], b["w"], b["h"]
        if w == T and h == T:
            x, y = round(x / T) * T, round(y / T) * T
        found.setdefault(sl["name"].strip(), []).append((x, y, w, h))
    places = {}
    for name, at in found.items():
        at.sort()
        if len(at) == 2 and name.endswith("_r") and name[:-2] + "_l" not in found:
            places[name[:-2] + "_l"] = at[0]
            places[name] = at[1]
        else:
            places[name] = at[0]
    return {name: sheet.crop((x, y, x + w, y + h)) for name, (x, y, w, h) in places.items()}


# old tile -> the author's piece. Walls and floors as they look, checked on the ship previews
# (tools/preview); a horizontal piece he named "_r" is the left end of a row and the other way
# round (its frame is on that side), so windows take them crosswise.
NEW_ART = {
    "wall_h": "horizontal_wall",
    "wall_tl": "horizontal_corner_l",
    "wall_tr": "horizontal_corner_r",
    "wall_bl": "external_corner_l",
    "wall_br": "external_corner_r",
    "wall_tdown": "T-shaped_corner",
    # (v90.1, his drawing of which pieces join) the wall above a crossing or a turned T ends in his
    # vertical_wall_to_T-shaped_corner, whose foot opens into the band's top: under it the crossing is his
    # T and the turned T is the plain horizontal wall
    "wall_cross": "T-shaped_corner",
    "wall_tup": "horizontal_wall",
    "wall_jr": "internal_corner_r",
    "wall_jl": "internal_corner_l",
    "wall_v": "vertical_wall",
    "wall_v_end": "vertical_wall_to_T-shaped_corner",
    "wall_v_end_l": "vertical_wall_to_internal_corner_r",
    "wall_v_end_r": "vertical_wall_to_internal_corner_l",
    "wall_v_end_a": "vertical_wall_door_up",
    "door": "Door_horizontal_base_unlock",
    "airlock_closed": "Door_vertical_base_unlock",
    "airlock_half": "Door_vertical_base_open_stage_1",
    "airlock": "Door_vertical_base_open_stage_2",
}
FLOOR_SETS = {"floor": "floor", "glass": "glass_floor", "grate": "grated_floor", "hatch": "ladder_floor_down",
              "ladder": "ladder_floor_up"}
FLOOR_SPOTS = {"l_t": "internal_corner_l", "m_t": "up", "r_t": "internal_corner_r", "l_m": "l", "m_m": "m",
               "r_m": "r", "l_b": "external_corner_l", "m_b": "down", "r_b": "external_corner_r"}
WINDOW_SPOTS = {"": "single", "_l": "r", "_m": "m", "_r": "l"}


def art_floor(art, family, spot):
    """A floor piece of the tile set: one of nine by its place in the room, or (n) a column one tile wide."""
    base = FLOOR_SETS[family]
    if spot == "n":
        left, right = art[base + "_l"], art[base + "_r"]
        out = left.copy()
        out.paste(right.crop((T // 2, 0, T, T)), (T // 2, 0))
        return out
    name = base + "_" + FLOOR_SPOTS[spot]
    return art[name] if name in art else art[base + "_5"]      # his glass floor's middle is "_5"


def art_on(under, top):
    out = under.copy()
    out.alpha_composite(top)
    return out


def art_machine(art, wall, picture, k, i=-1):
    """A machine's picture on the plain wall: piece i of one k tiles wide, or (i = -1) the whole of it
    in one tile (a wide one keeps its two ends)."""
    if k == 1:
        return art_on(wall, art[picture])
    full = art[picture]
    if i >= 0:
        return art_on(wall, full.crop((i * T, 0, i * T + T, T)))
    one = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    one.paste(full.crop((0, 0, T // 2, T)), (0, 0))
    one.paste(full.crop((full.width - T // 2, 0, full.width, T)), (T // 2, 0))
    return art_on(wall, one)


def art_transplant(old, old_wall, wall):
    """What the old sheet drew on its wall (a console the tile set has no picture for), put on the new wall."""
    out = wall.copy()
    for y in range(T):
        for x in range(T):
            p = old.getpixel((x, y))
            if p != old_wall.getpixel((x, y)):
                out.putpixel((x, y), p)
    return out


def art_standing(art, name):
    """(v91) A machine standing on the floor, alone on a clear tile (FLOOR_LOOKS), or None for another name."""
    m = next((m for m in FLOOR_MACHINES if name.startswith(m + "_fl")), None)
    if m is None:
        return None
    rest = name[len(m) + 3:]
    clear = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    if rest.startswith("_t_"):
        i = int(rest[3:])
        return holo_table(art).crop((i % 2 * T, (i // 2 + 1) * T, i % 2 * T + T, (i // 2 + 2) * T))
    side, i = rest, -1
    if "_w" in rest:
        side, wide = rest.split("_w")
        i = int(wide.split("_")[1])
    k = MACHINE_ART[m][2] if m in MACHINE_ART else 1
    if m == "tray":
        full = art["hydroponic_floor_single"]                       # (his F1) a garden bed of soil
    elif m in MACHINE_ART:
        down, up, _ = MACHINE_ART[m]
        full = art[up or down] if side == "_up" else art[down]
        if side in ("_r", "_l"):
            r, l = FLOOR_SIDE.get(m, (None, None))
            if r is None:
                full = full.rotate(90 if side == "_r" else -90, expand=True)   # no side view drawn: the front turned
            elif side == "_r":
                full = art[r]
            else:
                full = art[l] if l else ImageOps.mirror(art[r])
    else:
        full = make_machine(clear, m)                               # the game's own drawing, without the wall
    tall = side in ("_r", "_l") and full.height > full.width
    if k == 1 or full.size == (T, T):
        return art_on(clear, full.crop((0, 0, T, T)) if full.size != (T, T) else full)
    if i >= 0:
        box = (0, i * T, T, i * T + T) if tall else (i * T, 0, i * T + T, T)
        return art_on(clear, full.crop(box))
    one = clear.copy()                                              # one cell of a wide machine: its two ends
    if tall:
        one.paste(full.crop((0, 0, T, T // 2)), (0, 0))
        one.paste(full.crop((0, full.height - T // 2, T, full.height)), (0, T // 2))
    else:
        one.paste(full.crop((0, 0, T // 2, T)), (0, 0))
        one.paste(full.crop((full.width - T // 2, 0, full.width, T)), (T // 2, 0))
    return one


def holo_table(art):
    """(v93, the author's note "the blue globe is one tile lower") The star chart's holo table, two by two, with
    its globe floating a tile above the projector: three rows, the top one the globe's upper half alone."""
    table = Image.new("RGBA", (2 * T, 3 * T), (0, 0, 0, 0))
    table.alpha_composite(art["holo_map_big"], (0, T))
    table.alpha_composite(art["holo_map_big_sphere"], (0, 0))
    return table


def art_alone(picture, bare):
    """What a picture of his has that the bare one has not, on a clear tile (a lamp off its floor plate)."""
    out = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    for y in range(T):
        for x in range(T):
            if picture.getpixel((x, y)) != bare.getpixel((x, y)):
                out.putpixel((x, y), picture.getpixel((x, y)))
    return out


def art_tile(art, mock, images, name):
    """The picture for a tile of the sheet from the author's set, or None (drawn as before)."""
    floor = art["floor_m"]
    standing = art_standing(art, name)
    if standing is not None:
        return standing
    if name.startswith("holo_globe_"):
        i = int(name[-1])
        return holo_table(art).crop((i * T, 0, i * T + T, T))
    if name == "stairs":
        return floor
    if name.startswith("stairs_"):
        _, k, o, i = name.split("_")
        i = int(i)
        if o == "h":
            canvas = Image.new("RGBA", (2 * T, 2 * T), (0, 0, 0, 0))
            if k == "dn":
                canvas.alpha_composite(art["stairs_down_horizontal"], (0, T))
            else:
                canvas.alpha_composite(art["stairs_up_horizontal"], (8, 2 * T - 48))
            return canvas.crop(((i % 2) * T, (i // 2) * T, (i % 2 + 1) * T, (i // 2 + 1) * T))
        canvas = Image.new("RGBA", (T, 2 * T), (0, 0, 0, 0))
        if k == "dn":
            canvas.alpha_composite(art["stairs_down_vertical"], (0, 0))
            canvas.alpha_composite(art["stairs_down_vertical"], (0, T))
        else:
            up = art["stairs_up_vertical"]
            canvas.alpha_composite(up, (0, 2 * T - up.height))
            canvas.alpha_composite(up.crop((0, 0, T, 2 * T - up.height)), (0, 0))
        return canvas.crop((0, i * T, T, (i + 1) * T))
    if name.startswith("lamp_"):
        return art_alone(art["floor_door_lamp_" + name[5:]], floor)
    if name.startswith("map_ship_"):
        out = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        for y in range(T):
            for x in range(T):
                if art[name].getpixel((x, y))[3] > 0:
                    out.putpixel((x, y), (255, 255, 255, 255))
        return out
    if name in WALL_BOX_ART:
        return art_on(art["horizontal_wall"], art[WALL_BOX_ART[name]])
    if name == "lock_pump":
        return art_on(art["horizontal_wall"], art["button"])    # (v91, his M7) the airlock pump is his button
    if name == "danger_line":
        return art["floor_danger_line_decal"]
    if name == "vent":
        return art["vent_floor"]
    if name in NEW_ART:
        return art[NEW_ART[name]]
    if name == "door_half":
        return art_on(floor, art["Door_horizontal_base_open_stage_2"])
    if name == "door_open":
        return art_on(floor, art["Door_horizontal_base_open_stage_3"])
    if name == "console_2":
        return art_transplant(cut(mock, 4, 0), cut(mock, 1, 0), art["horizontal_wall"])
    for family in FLOOR_SETS:
        for spot in list(FLOOR_SPOTS) + ["n"]:
            if name == family + "_" + spot:
                return art_floor(art, family, spot)
    if name == "window_v":
        return art["glass_wall_v1_vertical_single_stage_1"]
    if name.startswith("window_in"):
        return art["glass_wall_v1_horizontal_%s" % WINDOW_SPOTS[name[len("window_in"):]]]
    if name.startswith("window") and name != "window_field":
        if name.startswith("window_v_"):
            piece, stage = name[len("window_v_"):].rsplit("_s", 1)
            return art["glass_wall_v1_vertical_%s_stage_%s" % (piece, stage)]
        stage = "1"
        if "_s" in name:
            name, stage = name.rsplit("_s", 1)
        return art["glass_wall_v2_horizontal_%s_stage_%s" % (WINDOW_SPOTS[name[len("window"):]], stage)]
    if name.startswith("door_") and name.count("_") == 3:
        _, kind, o, state = name.split("_")
        way = "horizontal" if o == "h" else "vertical"
        if state in DOOR_LAMPS:
            return art["Door_%s_%s_%s" % (way, kind, {"green": "unlock", "yellow": "lock_1", "red": "lock_2"}[state])]
        stage = int(state[4:])
        if o == "v" and stage == 2:
            return art["Door_vertical_base_open_stage_2"]     # one open frame for every type
        return art_on(floor, art["Door_%s_%s_open_stage_%d" % (way, kind, stage)])
    for m, (down, up, k) in MACHINE_ART.items():
        if name == m:
            return art_machine(art, art["horizontal_wall"], down, k)
        if name == m + "_up":
            return art_machine(art, art["horizontal_wall"], up or down, k)
        if name.startswith(m + "_") and "_w" in name[len(m):]:
            side = up or down if name.startswith(m + "_up_") else down
            return art_machine(art, art["horizontal_wall"], side, k, int(name.rsplit("_", 1)[1]))
    return None


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
    elif what == "gun":
        # a ship's gun set into the hull: a breech block with the barrel through the wall
        rect(7, 5, 24, 24, mid); rect(8, 6, 23, 23, body); rect(8, 6, 23, 7, cap)
        rect(13, 1, 18, 26, dark); rect(14, 0, 17, 27, (70, 72, 84, 255))
        rect(14, 0, 17, 1, (40, 40, 50, 255)); rect(14, 26, 17, 27, (40, 40, 50, 255))
        rect(9, 10, 12, 19, dark); rect(19, 10, 22, 19, dark)
        rect(10, 12, 11, 13, (230, 120, 40, 255)); rect(20, 12, 21, 13, (230, 120, 40, 255))
        for x in range(8, 24):
            o[x, 22] = HAZARD if (x // 2) % 2 == 0 else dark
    elif what == "intercom":
        # an intercom: a small panel with a speaker grille, a talk button and a lamp
        rect(9, 6, 22, 22, mid); rect(10, 7, 21, 21, body); rect(10, 7, 21, 8, cap)
        rect(12, 10, 19, 16, dark)
        for y in range(11, 16, 2):                     # the grille
            rect(13, y, 18, y, mid)
        rect(12, 18, 15, 20, (200, 70, 50, 255))       # the talk button
        rect(18, 18, 19, 19, (90, 220, 110, 255))      # the lamp
    elif what == "holo":
        # the holomap: a wide dark screen with the ship's outline in cyan and a red spot of trouble
        rect(3, 4, 28, 24, mid); rect(4, 5, 27, 23, body); rect(4, 5, 27, 6, cap)
        rect(6, 8, 25, 21, (12, 24, 36, 255))
        line = (70, 200, 230, 255)
        for x in range(9, 23):
            o[x, 11] = line; o[x, 18] = line
        for y in range(11, 19):
            o[9, y] = line; o[22, y] = line
        for x in range(12, 20):
            o[x, 14] = (40, 130, 160, 255); o[x, 15] = (40, 130, 160, 255)
        rect(19, 12, 20, 13, (240, 80, 60, 255))
        rect(14, 22, 17, 22, (90, 220, 110, 255))      # a lamp under the screen
    elif what == "shield":
        # the shield generator: a housing with a blue emitter ring and coils either side
        rect(4, 3, 27, 24, body); rect(4, 3, 27, 4, cap); rect(4, 24, 27, 24, mid)
        rect(6, 6, 25, 22, dark)
        for y in range(6, 22):
            for x in range(9, 23):
                d = ((x - 15.5) ** 2 + (y - 13.5) ** 2) ** 0.5
                if 5.0 < d < 6.6:
                    o[x, y] = (110, 170, 255, 255)
                elif 3.4 < d <= 5.0:
                    o[x, y] = (40, 80, 170, 255)
                elif d <= 1.8:
                    o[x, y] = (200, 230, 255, 255)
        for y in range(8, 21, 2):                      # coils
            rect(6, y, 8, y, (184, 120, 52, 255)); rect(23, y, 25, y, (184, 120, 52, 255))
        rect(14, 22, 17, 22, (90, 220, 110, 255))      # a lamp
        for x in range(6, 26):
            o[x, 23] = HAZARD if (x // 2) % 2 == 0 else dark
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
    elif what == "bench":
        # the workbench: a heavy top with a vise, tools hung on the wall above it, a lamp
        rect(3, 4, 28, 9, mid); rect(4, 5, 27, 8, dark)
        for tx, col in ((6, (200, 200, 205, 255)), (10, (184, 120, 52, 255)), (14, (200, 200, 205, 255))):
            rect(tx, 5, tx + 1, 8, col)                 # spanners and a hammer on the board
        rect(19, 5, 25, 6, (184, 120, 52, 255)); rect(21, 6, 22, 8, (200, 200, 205, 255))
        rect(2, 13, 29, 16, cap); rect(2, 16, 29, 17, body); rect(2, 17, 29, 17, mid)   # the top
        rect(4, 18, 6, 26, mid); rect(25, 18, 27, 26, mid)                              # legs
        rect(9, 10, 14, 13, body); rect(10, 11, 13, 12, dark); rect(15, 11, 17, 12, cap)  # the vise
        rect(18, 11, 23, 13, (110, 116, 126, 255))                                      # a part in it
        rect(8, 21, 23, 23, (70, 72, 84, 255))                                          # a shelf
        rect(26, 10, 27, 11, (90, 220, 110, 255))                                       # a lamp
        for x in range(4, 28):
            o[x, 26] = HAZARD if (x // 2) % 2 == 0 else dark
    elif what == "bay":
        # the module bay: a rack with two slots side by side, each with a lamp and a latch
        rect(4, 3, 27, 25, body); rect(4, 3, 27, 4, cap); rect(4, 25, 27, 25, mid)
        for sx in (6, 17):
            rect(sx, 7, sx + 8, 20, dark)                       # the slot
            rect(sx + 1, 8, sx + 7, 9, mid)                     # its rails
            rect(sx + 1, 18, sx + 7, 19, mid)
            rect(sx + 2, 11, sx + 6, 16, (70, 96, 120, 255))    # a module in it
            rect(sx + 3, 12, sx + 5, 13, (111, 190, 240, 255))
            rect(sx + 3, 22, sx + 5, 22, (90, 220, 110, 255))   # its lamp
        for x in range(4, 28):
            o[x, 24] = HAZARD if (x // 2) % 2 == 0 else dark
    elif what == "autodoc":
        # (v60) the autodoc: a white bed-head housing with a green cross, arms and a lamp over the bed in front
        white, pale = (214, 222, 228, 255), (176, 186, 196, 255)
        rect(4, 3, 27, 25, pale); rect(5, 4, 26, 24, white); rect(5, 4, 26, 5, (240, 244, 248, 255))
        rect(13, 7, 18, 18, (60, 190, 110, 255)); rect(9, 11, 22, 14, (60, 190, 110, 255))     # the cross
        rect(14, 8, 17, 17, (120, 230, 160, 255)); rect(10, 12, 21, 13, (120, 230, 160, 255))
        rect(6, 20, 25, 23, (90, 100, 112, 255))                                              # the arms' rail
        for ax in (8, 23):
            rect(ax, 18, ax + 1, 23, (70, 76, 88, 255))
        rect(24, 6, 25, 7, (90, 220, 110, 255))                                               # a lamp
        for x in range(4, 28):
            o[x, 26] = (60, 190, 110, 255) if (x // 2) % 2 == 0 else dark
    elif what == "scanner":
        # (v60) the body scanner: a tall frame with a scan bar and a small screen with a body outline
        rect(5, 3, 26, 25, body); rect(5, 3, 26, 4, cap); rect(5, 25, 26, 25, mid)
        rect(8, 6, 23, 16, (12, 24, 36, 255))                                                 # the screen
        cyan = (70, 200, 230, 255)
        rect(15, 7, 16, 8, cyan); rect(14, 9, 17, 12, cyan); rect(12, 9, 13, 11, cyan); rect(18, 9, 19, 11, cyan)
        rect(14, 13, 14, 15, cyan); rect(17, 13, 17, 15, cyan)                                # a body on it
        rect(8, 11, 23, 11, (240, 80, 60, 255))                                               # the scan line
        rect(7, 19, 24, 21, dark); rect(8, 20, 23, 20, (111, 190, 240, 255))                  # the scan bar
        rect(21, 23, 22, 23, (90, 220, 110, 255))
    elif what in ("smes", "smes_small"):
        # (v61) the SMES: a tall cabinet of storage coils with a charge gauge; the bridge's backup is a half-height one
        top = 3 if what == "smes" else 9
        rect(4, top, 27, 25, body); rect(4, top, 27, top + 1, cap); rect(4, 25, 27, 25, mid)
        rect(6, top + 3, 20, 23, dark)
        coil = (200, 150, 60, 255)
        for cx in (8, 13, 18) if what == "smes" else (9, 15):
            rect(cx, top + 4, cx + 1, 22, (120, 90, 40, 255))
            for y in range(top + 4, 23, 2):
                rect(cx - 1, y, cx + 2, y, coil)                   # copper turns
        rect(22, top + 3, 25, 23, dark)                               # the gauge
        rect(23, top + 10 if what == "smes" else top + 7, 24, 22, (90, 220, 110, 255))
        rect(22, top + 1, 23, top + 1, (240, 200, 60, 255))           # a lamp
        for x in range(4, 28):
            o[x, 26] = HAZARD if (x // 2) % 2 == 0 else dark
    elif what == "comms":
        # (v63) the comms console: a screen of text lines with a dish lamp and a row of answer keys
        rect(4, 4, 27, 24, body); rect(4, 4, 27, 5, cap); rect(4, 24, 27, 24, mid)
        rect(6, 7, 25, 17, (10, 22, 30, 255))
        amber = (240, 190, 80, 255)
        for y, w in ((9, 15), (11, 12), (13, 16), (15, 9)):
            rect(8, y, 8 + w, y, amber)                                                       # lines of a message
        for k, kx in enumerate((7, 12, 17, 22)):
            rect(kx, 19, kx + 3, 21, (70, 150, 230, 255) if k == 1 else dark)                 # the answer keys
        rect(23, 9, 24, 10, (90, 220, 110, 255))                                              # the link lamp
    elif what == "dock":
        # (v86) the shuttle's dock console: a screen with the shuttle's outline, a lamp and a call key
        rect(4, 4, 27, 24, body); rect(4, 4, 27, 5, cap); rect(4, 24, 27, 24, mid)
        rect(6, 7, 25, 18, (10, 22, 30, 255))
        blue = (110, 200, 255, 255)
        rect(10, 11, 20, 14, blue); rect(21, 12, 22, 13, blue); rect(8, 12, 9, 13, (240, 190, 80, 255))
        rect(12, 9, 14, 10, blue); rect(12, 15, 14, 16, blue)                                # its wings
        rect(7, 20, 12, 22, (70, 200, 120, 255)); rect(19, 20, 24, 22, dark)                  # the keys
        # (v63) a hydroponic tray: a long trough of dark soil under a strip of grow lights
        rect(3, 5, 28, 25, mid); rect(3, 5, 28, 6, cap)
        rect(4, 7, 27, 9, (60, 60, 80, 255))                                                  # the lamp housing
        for x in range(5, 27, 3):
            rect(x, 8, x + 1, 8, (230, 120, 230, 255))                                        # grow lights
        rect(4, 18, 27, 25, body); rect(5, 19, 26, 22, (70, 50, 35, 255))                     # the trough of soil
        rect(5, 19, 26, 19, (95, 70, 48, 255))
        for x in (6, 12, 18, 24):
            rect(x, 23, x + 1, 24, (60, 130, 210, 255))                                       # water nozzles
    elif what == "cryo":
        # (v63) a cryosleep pod: a frosted capsule stood in the wall, a sleeper's outline, a blue lamp
        rect(7, 2, 24, 26, body); rect(7, 2, 24, 3, cap)
        rect(9, 5, 22, 23, (150, 200, 225, 255)); rect(10, 6, 21, 22, (190, 228, 245, 255))
        rect(14, 8, 17, 10, (120, 150, 175, 255)); rect(13, 11, 18, 18, (120, 150, 175, 255))   # a sleeper
        rect(13, 19, 14, 21, (120, 150, 175, 255)); rect(17, 19, 18, 21, (120, 150, 175, 255))
        rect(15, 24, 16, 25, (80, 170, 255, 255))                                             # the lamp
        for x in range(7, 25):
            o[x, 26] = (80, 170, 255, 255) if (x // 2) % 2 == 0 else dark
    elif what == "stove":
        # (v71) the galley's stove: a hob with two burners and a pot, an oven door, a hood above
        rect(4, 2, 27, 6, mid); rect(6, 6, 25, 7, dark)                                      # the hood
        rect(4, 11, 27, 26, body); rect(4, 11, 27, 12, cap)
        for bx in (10, 21):                                                                   # burners
            for y in range(12, 16):
                for x in range(bx - 4, bx + 5):
                    d = ((x - bx) ** 2 + ((y - 13.5) * 1.8) ** 2) ** 0.5
                    if 2.0 < d < 3.6:
                        o[x, y] = (230, 110, 40, 255)
        rect(17, 7, 25, 12, (150, 155, 165, 255)); rect(18, 8, 24, 9, (95, 60, 35, 255))    # a pot on one
        rect(16, 8, 16, 9, dark); rect(26, 8, 26, 9, dark)                                   # its handles
        rect(7, 17, 24, 24, dark); rect(8, 18, 23, 19, mid)                                  # the oven door
        rect(10, 20, 21, 23, (60, 40, 30, 255))
        rect(25, 17, 26, 18, (90, 220, 110, 255))                                            # a lamp
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


def make_field(wall):
    """(v86) A force field set into the hull: two emitters at the ends of a band of see-through blue
    shimmer (light and sight pass, air does not)."""
    out = wall.copy()
    o = out.load()
    for y in range(6, 26):
        for x in range(T):
            t = abs(y - 15.5) / 10.0
            a = int(70 + 60 * (1.0 - t)) if (y % 3) else 170
            o[x, y] = (90, 190, 255, a)
    for y in range(4, 28):
        for x in (0, 1, T - 2, T - 1):
            o[x, y] = (60, 70, 90, 255)
    return out


def make_middle(bottom):
    """(v81) A floor piece of a middle row: the bottom row's piece without its lower edge
    (the rows above the edge carried down)."""
    out = bottom.copy()
    for y in range(24, T):
        for x in range(T):
            out.putpixel((x, y), bottom.getpixel((x, y - 8)))
    return out


def make_rock(seed, ore=False, ground=False):
    """(v81) A block of an asteroid's rock (three of them, told apart by their cracks), a vein of
    ore in it, or the bare rock ground one can walk on. Simple base pictures for the artist."""
    import random
    rnd = random.Random(seed * 7919)
    out = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    o = out.load()
    base = (58, 54, 52) if ground else (92, 86, 80)
    for y in range(T):
        for x in range(T):
            n = rnd.randint(-9, 9)
            o[x, y] = (base[0] + n, base[1] + n, base[2] + n, 255)
    for _ in range(3 if not ground else 5):        # pits and cracks
        cx, cy, r = rnd.randint(4, 27), rnd.randint(4, 27), rnd.randint(2, 4)
        for y in range(max(0, cy - r), min(T, cy + r + 1)):
            for x in range(max(0, cx - r), min(T, cx + r + 1)):
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d <= r:
                    k = 0.65 if d < r - 1 else 1.15
                    c = o[x, y]
                    o[x, y] = (min(255, int(c[0] * k)), min(255, int(c[1] * k)), min(255, int(c[2] * k)), 255)
    if ore:
        for _ in range(5):                         # lumps of ore with a glint
            cx, cy = rnd.randint(7, 24), rnd.randint(7, 24)
            for y in range(cy - 3, cy + 4):
                for x in range(cx - 3, cx + 4):
                    d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                    if d < 2.2:
                        o[x, y] = (232, 178, 80, 255)
                    elif d < 3.2:
                        o[x, y] = (150, 104, 44, 255)
            o[cx - 1, cy - 1] = (255, 236, 170, 255)
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
        "gun": lambda: make_machine(images["wall_h"], "gun"),
        "intercom": lambda: make_machine(images["wall_h"], "intercom"),
        "holo": lambda: make_machine(images["wall_h"], "holo"),
        "shield": lambda: make_machine(images["wall_h"], "shield"),
        "bench": lambda: make_machine(images["wall_h"], "bench"),
        "bay": lambda: make_machine(images["wall_h"], "bay"),
        "autodoc": lambda: make_machine(images["wall_h"], "autodoc"),
        "scanner": lambda: make_machine(images["wall_h"], "scanner"),
        "smes": lambda: make_machine(images["wall_h"], "smes"),
        "smes_small": lambda: make_machine(images["wall_h"], "smes_small"),
        "comms": lambda: make_machine(images["wall_h"], "comms"),
        "tray": lambda: make_machine(images["wall_h"], "tray"),
        "cryo": lambda: make_machine(images["wall_h"], "cryo"),
        "stove": lambda: make_machine(images["wall_h"], "stove"),
        "dock": lambda: make_machine(images["wall_h"], "dock"),
        "window_field": lambda: make_field(images["wall_h"]),
        "floor_l_m": lambda: make_middle(images["floor_l_b"]),
        "floor_m_m": lambda: make_middle(images["floor_m_b"]),
        "floor_r_m": lambda: make_middle(images["floor_r_b"]),
        "rock_1": lambda: make_rock(1),
        "rock_2": lambda: make_rock(2),
        "rock_3": lambda: make_rock(3),
        "rock_ore": lambda: make_rock(4, ore=True),
        "rock_ground": lambda: make_rock(5, ground=True),
    }
    art = load_tileset()
    for i, (name, src, kind) in enumerate(TILES):
        if name.startswith(PIRATE):
            im = pirate_tint(images[name[len(PIRATE):]])
        elif art_tile(art, mock, images, name) is not None:
            im = art_tile(art, mock, images, name)
        elif kind in COVERS:
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
#   '/'  (v91) stairs: two cells in a row on a deck and the same two on the deck below; the upper
#        flight ends at a wall, the lower one at the room's floor (ShipMap._find_stairs)
#   '#'  wall (piece chosen from its neighbours)
#   'D'  door in a horizontal wall      'A'  airlock in a vertical wall
#   'W'  window    '<' '>'  wide window (left, right half)
#   '1'..'5'  wall with a console on it
#   '6'  wall with the engine in it          '7'  wall with the air plant in it
#   '8'  wall with the supply locker in it
#   'T'  a ship's gun in the hull (fired from the gun console, '4' on the bridge)
#   '9'  wall with an airlock pump in it: the floor in front is the chamber; its outer 'D' opens into space
#   'I'  wall with an intercom panel on it
#   'M'  wall with a holomap monitor on it (the whole ship: air, holes, what is broken)
#   'Z'  wall with the shield generator in it
#   'B'  (v58) wall with the workbench at it: engineers take guns apart, mend and upgrade them there
#   'U'  (v59) wall with the module bay in it: two free slots for ship modules (armour, focusing array, phase drive)
#   'Y'  (v60) wall with an autodoc at it: whoever lies or stands in front of it is healed while the ship has power
#   'X'  (v60) wall with a body scanner on it: shows the health of whoever is on the nearest autodoc (or of oneself)
#   'S'  (v61) wall with the ship's SMES in it: stores the engine's power and carries the ship when the engine stops
#   'Q'  (v61) wall with the small backup SMES of the bridge: keeps the room it faces lit and its consoles working
#   'K'  (v63) wall with the comms console: calls, text events with choices, quests
#   'P'  (v63) wall with a hydroponic tray: plants grow in it (two side by side may cross)
#   'C'  (v63) wall with a cryosleep pod: the crew reserve sleeps in them and wakes from them
#   'G'  (v71) wall with the galley's stove: meals are cooked there from rations
#   'F'  (v86) a force field in the hull: air stays in, light and sight pass; the shuttle parks outside it
#   'V'  (v86) wall with the shuttle's dock console: board the shuttle here or call it (a fleet's ships)
#   'E'  (v91) wall with a first-aid box: E takes a first-aid kit the supply locker keeps (or puts one back)
#   'J'  (v91) wall with a spare parts box: the same with spare parts (and circuit boards)
#   'N'  (v91) wall with a fire box (a picture until there is fire)   'L'  (v91) a wall light
#   'R'  (v81) an asteroid's rock      'O'  (v81) a vein of ore in the rock      ','  (v81) bare rock ground
#        (rock and ground follow no room rule: draw them any shape)
#
# (v81) A line "; kind = ship|pirate|derelict|asteroid" says what the drawing is (the ship editor writes
# it); without one the file's name says (pirate*, derelict*, asteroid*, else our own ship).
#
# Rooms with restricted access are named by a line of their own anywhere in the file:
#   @ <deck number, from 1> <x> <y> <access>
# x, y is any floor cell of the room (counted in the deck's drawing, first row 0). Every door of
# that room then opens only for those whose job gives that access (see Net.ACCESS_*).
# (v75) The access "brig" is no lock: it marks a brig cell, where a prisoner never slips the cuffs.
#
# (v91, the author's D1) A door is drawn by its room's kind (hermetic at an airlock or into space, technical
# where only some jobs pass, cargo into a room with the supply locker or the module bay, else the plain one);
# a line of its own gives one door the look of another kind:
#   & <deck number, from 1> <x> <y> <base|tech|cargo|herm>
# where x, y is the door's cell (the ship editor's door marks).
#
# A ship others fight (the pirate ship) names the rooms its systems stand in, the same way:
#   % <deck number, from 1> <x> <y> <system>
# where system is one of SYSTEMS below; the room's floor cells become that system's zone, where
# the crew's guns can aim (see Gunnery).
#
# A ship with several decks is drawn deck by deck, the top one first. Each
# deck starts with a line "= its name"; all are laid over one another from
# the same corner. In the .json the decks sit in one grid, one below the
# other, `deck_stride` rows apart (a multiple of 16, with at least one empty
# row between decks), so a cell is still just x and y everywhere in the game.
#
# The tile art is made for rooms two tiles tall separated by horizontal wall
# bands, so maps follow that pattern and the script refuses anything else.

BAND_CHARS = set("#DW<>123456789TIMZBUYXSQKPCGFVEJNL")
ACCESS_BITS = {"bridge": 1, "engine": 2, "medbay": 4, "armory": 8, "guns": 16}   # as Net.ACCESS_*
SYSTEMS = ["weapons", "helm", "engine", "crew", "jump", "shields"]                                  # as Net.ESYS_*
FLOOR_CHARS = set(".sgcH/")
# (v91, the author: "it's not walls, it's on the ground") machines stand on the floor: a machine sign is
# in the wall only in a row of machines between two pieces of wall with nothing solid above or below it
# (the old way, still read); anywhere else it is a thing on the floor, the floor going on under it
MACHINE_SIGNS = set("1345678MZBUYXSQKGCP")
COVER_OF = {"g": "glass", "c": "grate"}
ROCK_CHARS = set("RO,")


MACHINE_OF = {"D": "door_open", "W": "window", "<": "window_l", ">": "window_r",
              "1": "console_1", "2": "console_2", "3": "console_3",
              "4": "console_4", "5": "console_5", "6": "engine", "7": "air_plant", "8": "locker", "9": "lock_pump", "T": "gun", "I": "intercom", "M": "holo", "Z": "shield", "B": "bench", "U": "bay", "Y": "autodoc", "X": "scanner", "S": "smes", "Q": "smes_small", "K": "comms", "P": "tray", "C": "cryo", "G": "stove", "F": "window_field", "V": "dock",
              "E": "med_box", "J": "tech_box", "N": "fire_box", "L": "wall_light"}


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

    def raw_solid(x, y):
        return at(x, y) in BAND_CHARS or at(x, y) == "A"

    things = set()                               # (v91) machines standing on the floor
    for y in range(h):
        x = 0
        while x < w:
            if at(x, y) not in MACHINE_SIGNS:
                x += 1
                continue
            x1 = x
            while at(x1 + 1, y) in MACHINE_SIGNS:
                x1 += 1
            ends = [at(x - 1, y), at(x1 + 1, y)]
            in_wall = all((e in BAND_CHARS or e == "A") and e not in MACHINE_SIGNS for e in ends) and \
                not any(raw_solid(i, y - 1) or raw_solid(i, y + 1) for i in range(x, x1 + 1))
            if not in_wall:
                things.update((i, y) for i in range(x, x1 + 1))
            x = x1 + 1

    def solid(x, y):  # anything that is part of the wall structure
        return raw_solid(x, y) and (x, y) not in things

    def floor(x, y):
        return at(x, y) in FLOOR_CHARS or (x, y) in things

    cells = [-1] * (w * h)
    spawns = []
    doors = []                                   # [x, y, "D" or "A"]
    under = []                                   # (v91) [x, y, the floor's tile] under each thing on the floor
    for y in range(h):
        for x in range(w):
            c = at(x, y)
            n, s, e, wst = solid(x, y - 1), solid(x, y + 1), solid(x + 1, y), solid(x - 1, y)
            piece = None
            if c == " ":
                continue
            if c in FLOOR_CHARS or (x, y) in things:
                if c == "s":
                    spawns.append([x, y])
                left = floor(x - 1, y)
                right = floor(x + 1, y)
                top = not floor(x, y - 1)
                bottom = not floor(x, y + 1)
                if top and bottom:
                    raise MapError(f"{name}: floor at {x},{y} is in a room one tile tall (rooms are two or more)")
                row = "t" if top else ("b" if bottom else "m")   # (v81) rooms may be taller than two
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
                if c == "/":
                    if other(below, x, y) != "/" and other(above, x, y) != "/":
                        raise MapError(f"{name}: stairs at {x},{y} need a '/' in the same cell of the deck above or below")
                    piece = "stairs"
                if (x, y) in things:
                    if not any(at(x + dx, y + dy) in FLOOR_CHARS for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))):
                        raise MapError(f"{name}: machine '{c}' at {x},{y} has no floor beside it to be used from")
                    if "D" in (at(x, y - 1), at(x, y + 1)) or "A" in (at(x - 1, y), at(x + 1, y)):
                        raise MapError(f"{name}: machine '{c}' at {x},{y} stands in a doorway")
                    under.append([x, y, ids[piece]])
                    piece = MACHINE_OF[c]
            elif c in ROCK_CHARS:
                piece = {"R": "rock_%d" % ((x * 7 + y * 13) % 3 + 1), "O": "rock_ore", ",": "rock_ground"}[c]
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
                    if c == "W" and n and s:
                        piece = "window_v"   # (v91, the author's W3) a window in a side wall
                        cells[y * w + x] = ids[piece]
                        continue
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
                    special = MACHINE_OF
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
                        piece = "wall_cross" if (n and s) else ("wall_tdown" if s else ("wall_tup" if n else "wall_h"))
                    elif e and not wst:
                        if n and s:
                            piece = "wall_jr"    # (v91) a vertical wall going on past a band that leaves it to the right
                        elif n == s:
                            raise MapError(f"{name}: wall end at {x},{y} has no matching corner piece")
                        else:
                            piece = "wall_tl" if s else "wall_bl"
                    else:
                        if n and s:
                            piece = "wall_jl"
                        elif n == s:
                            raise MapError(f"{name}: wall end at {x},{y} has no matching corner piece")
                        else:
                            piece = "wall_tr" if s else "wall_br"
            else:
                raise MapError(f"{name}: unknown character '{c}' at {x},{y}")
            cells[y * w + x] = ids[piece]
    return cells, spawns, doors, under


def read_decks(name, lines):
    """Splits a drawing into decks: [(deck name, lines)], top deck first."""
    decks = []
    for l in lines:
        if l.startswith("@") or l.startswith("%") or l.startswith("&"):
            continue
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
    if name.startswith("pirate"):
        ids = {k: ids.get(PIRATE + k, v) for k, v in ids.items()}
    decks = read_decks(name, lines)
    w = max(len(l) for _, rows in decks for l in rows)
    h = max(len(rows) for _, rows in decks)
    stride = ((h + 1 + 15) // 16) * 16
    total = stride * (len(decks) - 1) + h
    cells = [-1] * (w * total)
    spawns, doors, under = [], [], []
    for d, (_, rows) in enumerate(decks):
        above = decks[d - 1][1] if d > 0 else None
        below = decks[d + 1][1] if d + 1 < len(decks) else None
        deck_cells, deck_spawns, deck_doors, deck_under = resolve_map("%s, deck %d" % (name, d + 1), rows, ids, w, h, above, below)
        cells[d * stride * w:d * stride * w + w * h] = deck_cells
        spawns += [[x, y + d * stride] for x, y in deck_spawns]
        doors += [[x, y + d * stride, k] for x, y, k in deck_doors]
        under += [[x, y + d * stride, t] for x, y, t in deck_under]
    if not spawns and not name.startswith("derelict") and not name.startswith("pirate") and not name.startswith("asteroid"):
        raise MapError(f"{name}: no spawn points ('s')")
    door_access = [0] * len(doors)
    access_rooms = []                    # (v69) a floor cell of each restricted room and its access: leaving it is free
    brig_rooms = []                      # (v75) a floor cell of each brig cell (a line "@ deck x y brig")
    for l in lines:
        if not l.startswith("@"):
            continue
        parts = l[1:].split()
        if len(parts) == 4 and parts[3] == "brig":
            d, x0, y0 = int(parts[0]) - 1, int(parts[1]), int(parts[2])
            if decks[d][1][y0][x0:x0 + 1] not in FLOOR_CHARS or decks[d][1][y0][x0:x0 + 1] == "":
                raise MapError(f"{name}: brig line '{l}' does not point at a floor cell")
            brig_rooms.append([x0, y0 + d * stride])
            continue
        if len(parts) != 4 or parts[3] not in ACCESS_BITS:
            raise MapError(f"{name}: bad access line '{l}'")
        d, x0, y0 = int(parts[0]) - 1, int(parts[1]), int(parts[2])
        access_rooms.append([x0, y0 + d * stride, ACCESS_BITS[parts[3]]])
        rows = [r.ljust(w) for r in decks[d][1]]
        def at(x, y):
            return rows[y][x] if 0 <= y < len(rows) and 0 <= x < w else " "
        if at(x0, y0) not in FLOOR_CHARS:
            raise MapError(f"{name}: access line '{l}' does not point at a floor cell")
        seen, todo = {(x0, y0)}, [(x0, y0)]
        while todo:
            x, y = todo.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c = at(x + dx, y + dy)
                if c in FLOOR_CHARS and (x + dx, y + dy) not in seen:
                    seen.add((x + dx, y + dy))
                    todo.append((x + dx, y + dy))
                elif c in "DA":
                    for k, (dx2, dy2, _) in enumerate(doors):
                        if dx2 == x + dx and dy2 == y + dy + d * stride:
                            door_access[k] |= ACCESS_BITS[parts[3]]
    zones = []
    for l in lines:
        if not l.startswith("%"):
            continue
        parts = l[1:].split()
        if len(parts) != 4 or parts[3] not in SYSTEMS:
            raise MapError(f"{name}: bad system line '{l}'")
        d, x0, y0 = int(parts[0]) - 1, int(parts[1]), int(parts[2])
        rows = [r.ljust(w) for r in decks[d][1]]
        def at(x, y):
            return rows[y][x] if 0 <= y < len(rows) and 0 <= x < w else " "
        if at(x0, y0) not in FLOOR_CHARS:
            raise MapError(f"{name}: system line '{l}' does not point at a floor cell")
        seen, todo = {(x0, y0)}, [(x0, y0)]
        while todo:
            x, y = todo.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if at(x + dx, y + dy) in FLOOR_CHARS and (x + dx, y + dy) not in seen:
                    seen.add((x + dx, y + dy))
                    todo.append((x + dx, y + dy))
        zones.append([SYSTEMS.index(parts[3]), sorted((y + d * stride) * w + x for x, y in seen)])
    door_looks = []                      # (v91, the author's D1) "& deck x y kind": that door drawn as base, tech, cargo or herm
    for l in lines:
        if not l.startswith("&"):
            continue
        parts = l[1:].split()
        if len(parts) != 4 or parts[3] not in DOOR_TYPES:
            raise MapError(f"{name}: bad door line '{l}'")
        d, x0, y0 = int(parts[0]) - 1, int(parts[1]), int(parts[2])
        if not any(dx == x0 and dy == y0 + d * stride for dx, dy, _ in doors):
            raise MapError(f"{name}: door line '{l}' does not point at a door")
        door_looks.append([x0, y0 + d * stride, parts[3]])
    return {"name": name, "width": w, "height": total, "deck_height": h, "deck_stride": stride,
            "decks": [n for n, _ in decks], "cells": cells, "spawns": spawns, "doors": doors,
            "door_access": door_access, "access_rooms": access_rooms, "brig_rooms": brig_rooms, "zones": zones,
            "things": under, "door_looks": door_looks}


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
    # (v62) Net.ROBOT_COLOUR, OUR_ROBOT_COLOUR, ARMOUR_COLOUR: an enemy robot (red eye), our security
    # robot (green eye), a heavy-armoured boarder (steel plates over a jumpsuit, no sealed suit).
    # These rows look the same whatever the outfit: a machine wears nothing.
    ("robot_enemy", (96, 92, 96)), ("robot_ours", (112, 120, 130)), ("armour", (104, 110, 122)),
]
ROBOT_EYES = {"robot_enemy": (255, 60, 50, 255), "robot_ours": (90, 255, 120, 255)}
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


OUTFITS = 3                  # 0 = spacesuit, 1 = jumpsuit only, 2 = neither (a grey undersuit); see Net.OUTFIT_*
SKIN = (222, 178, 138, 255)
SKIN_D = (180, 136, 100, 255)
HAIR = (62, 42, 30, 255)
PACK = (122, 92, 52, 255)
PACK_D = (88, 64, 34, 255)
UNDERSUIT = (138, 140, 146)
SHOE = (44, 40, 40, 255)


# (v74, the author's N4) the four slants: a front or back view with the head and body
# leaning towards the side it turns to. Simple base pictures: an artist replaces them
# through the «sprites» folder. direction 4..7 = down-left, down-right, up-left, up-right.
SLANT_BASE = {4: (0, -1), 5: (0, 1), 6: (1, -1), 7: (1, 1)}


def lean(im, side, top):
    # a turned look: the figure narrowed to 4/5 (seen at an angle), the head 2 pixels and the
    # body 1 pixel towards that side (legs stay); before the outline is drawn
    narrow = im.resize((CHAR_W * 4 // 5, CHAR_H), Image.NEAREST)
    im.paste((0, 0, 0, 0), (0, 0, CHAR_W, CHAR_H))
    im.paste(narrow, ((CHAR_W - narrow.width) // 2, 0))
    px = im.load()
    rows = {y: [px[x, y] for x in range(CHAR_W)] for y in range(CHAR_H)}
    for y in range(CHAR_H):
        k = 2 * side if y <= top + 11 else (side if y <= 32 else 0)
        if k == 0:
            continue
        for x in range(CHAR_W):
            sx = x - k
            px[x, y] = rows[y][sx] if 0 <= sx < CHAR_W else (0, 0, 0, 0)


def outline(im):
    px = im.load()
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


def draw_char(colour, direction, pose, outfit=0, pack=False):
    side = 0
    if direction in SLANT_BASE:
        direction, side = SLANT_BASE[direction]
    im = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    px = im.load()
    suited = outfit == 0
    if outfit == 2:
        colour = UNDERSUIT
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
    stripe = STRIPE if suited else base
    glove = GLOVE if suited else SKIN
    boot = BOOT if suited else SHOE
    if direction in (0, 1):               # facing the camera / away from it
        # legs
        l_up = 2 if pose == 1 else 0
        r_up = 2 if pose == 2 else 0
        rect(11, 33, 15, 42 - l_up, base); rect(11, 33, 12, 42 - l_up, dark)
        rect(17, 33, 21, 42 - r_up, base); rect(20, 33, 21, 42 - r_up, dark)
        rect(11, 39 - l_up, 15, 39 - l_up, stripe); rect(17, 39 - r_up, 21, 39 - r_up, stripe)
        rect(10, 43 - l_up, 15, 45 - l_up, boot); rect(17, 43 - r_up, 22, 45 - r_up, boot)
        # torso
        rect(10, top + 12, 22, top + 25, base)
        rect(10, top + 12, 11, top + 25, dark); rect(21, top + 12, 22, top + 25, dark)
        rect(10, top + 25, 22, top + 25, shade(colour, 0.55))
        # arms swing opposite to the legs
        la = 1 if pose == 2 else 0
        ra = 1 if pose == 1 else 0
        rect(7, top + 13, 9, top + 22 - la, base); rect(7, top + 13, 7, top + 22 - la, dark)
        rect(23, top + 13, 25, top + 22 - ra, base); rect(25, top + 13, 25, top + 22 - ra, dark)
        rect(7, top + 16, 9, top + 16, stripe); rect(23, top + 16, 25, top + 16, stripe)
        rect(7, top + 23 - la, 9, top + 24 - la, glove); rect(23, top + 23 - ra, 25, top + 24 - ra, glove)
        # head
        if not suited:
            rect(12, top + 1, 20, top + 10, SKIN)
            rect(12, top + 9, 20, top + 10, SKIN_D)
            if direction == 0:
                rect(12, top + 1, 20, top + 3, HAIR)
                rect(14, top + 5, 14, top + 6, OUTLINE); rect(18, top + 5, 18, top + 6, OUTLINE)
                rect(15, top + 8, 17, top + 8, SKIN_D)
                if pack:
                    rect(10, top + 12, 11, top + 20, PACK_D); rect(21, top + 12, 22, top + 20, PACK_D)   # straps
            else:
                rect(12, top + 1, 20, top + 8, HAIR)
                if pack:
                    rect(11, top + 13, 21, top + 24, PACK); rect(11, top + 13, 21, top + 14, PACK_D)
                    rect(13, top + 18, 19, top + 19, PACK_D)
        elif direction == 0 and pack:
            rect(10, top + 12, 11, top + 20, PACK_D); rect(21, top + 12, 22, top + 20, PACK_D)
        if not suited:
            pass
        elif True:
            rect(11, top, 21, top + 10, HELM)
            rect(11, top, 21, top + 1, HELM_L)
            rect(11, top + 9, 21, top + 10, HELM_D)
        if not suited:
            pass
        elif direction == 0:
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
            if pack:
                rect(11, top + 15, 21, top + 25, PACK); rect(11, top + 15, 21, top + 16, PACK_D)
                rect(13, top + 20, 19, top + 21, PACK_D)
    else:                                  # profile, drawn facing left
        # legs: scissor while stepping
        if pose == 0:
            rect(13, 33, 18, 42, base); rect(17, 33, 18, 42, dark)
            rect(13, 39, 18, 39, stripe)
            rect(12, 43, 18, 45, boot)
        else:
            f = -3 if pose == 1 else 3     # front leg offset
            rect(13 + f, 33, 17 + f, 41, base); rect(13 + f, 38, 17 + f, 38, stripe)
            rect(12 + f, 42, 17 + f, 44, boot)
            rect(14 - f, 33, 18 - f, 42, dark)
            rect(13 - f, 43, 18 - f, 45, boot)
            rect(13, 33, 18, 35, base)
        # torso
        rect(12, top + 12, 19, top + 25, base)
        rect(18, top + 12, 19, top + 25, dark)
        rect(12, top + 25, 19, top + 25, shade(colour, 0.55))
        if suited:
            rect(20, top + 14, 22, top + 22, TANK); rect(22, top + 14, 22, top + 22, TANK_D)   # tank on the back
        if pack:
            rect(20, top + 13, 24, top + 24, PACK); rect(24, top + 13, 24, top + 24, PACK_D)
            rect(20, top + 13, 24, top + 14, PACK_D)
        # near arm
        sw = 0 if pose == 0 else (-2 if pose == 1 else 2)
        rect(14 - sw, top + 13, 16 - sw, top + 22, base); rect(16 - sw, top + 13, 16 - sw, top + 22, dark)
        rect(14 - sw, top + 16, 16 - sw, top + 16, stripe)
        rect(14 - sw, top + 23, 16 - sw, top + 24, glove)
        # head
        if suited:
            rect(11, top, 20, top + 10, HELM)
            rect(11, top, 20, top + 1, HELM_L)
            rect(11, top + 9, 20, top + 10, HELM_D)
            rect(10, top + 3, 15, top + 5, VISOR); rect(10, top + 3, 15, top + 3, VISOR_L)
            rect(9, top + 7, 13, top + 10, HELM_D)                         # mask snout
            rect(16, top + 6, 18, top + 8, HELM_D)                         # side filter
        else:
            rect(11, top + 1, 19, top + 10, SKIN)
            rect(11, top + 9, 19, top + 10, SKIN_D)
            rect(13, top + 1, 19, top + 4, HAIR); rect(16, top + 1, 19, top + 8, HAIR)
            rect(12, top + 5, 12, top + 6, OUTLINE)
    if side:
        lean(im, side, top)
    # outline around the silhouette
    outline(im)
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


def draw_robot(colour, eye, direction, pose):
    # (v62) a squat machine on two thick legs: a box of a body, a head with one eye, a gun arm
    side = 0
    if direction in SLANT_BASE:
        direction, side = SLANT_BASE[direction]
    im = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    px = im.load()
    base = colour + (255,)
    dark = shade(colour, 0.65)
    lite = shade(colour, 1.3)

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < CHAR_W and 0 <= y < CHAR_H:
                    px[x, y] = c

    bob = 1 if pose != 0 else 0
    top = 12 + bob
    if direction in (0, 1):
        l_up = 2 if pose == 1 else 0
        r_up = 2 if pose == 2 else 0
        rect(10, 34, 14, 44 - l_up, dark); rect(18, 34, 22, 44 - r_up, dark)
        rect(9, 43 - l_up, 15, 45 - l_up, BOOT); rect(17, 43 - r_up, 23, 45 - r_up, BOOT)
        rect(8, top + 8, 24, top + 22, base)                         # body
        rect(8, top + 8, 24, top + 9, lite); rect(8, top + 21, 24, top + 22, dark)
        rect(5, top + 10, 7, top + 18, dark); rect(25, top + 10, 27, top + 18, dark)   # arms
        rect(25, top + 18, 27, top + 21, OUTLINE)                    # the gun's muzzle
        rect(11, top, 21, top + 7, base); rect(11, top, 21, top, lite)  # head
        if direction == 0:
            rect(12, top + 2, 20, top + 5, OUTLINE)
            rect(15, top + 3, 17, top + 4, eye)
            rect(12, top + 12, 20, top + 18, dark)                   # a chest plate
        else:
            rect(12, top + 11, 20, top + 19, dark)                   # the power pack
            rect(14, top + 13, 18, top + 14, eye)
    else:
        f = 0 if pose == 0 else (-2 if pose == 1 else 2)
        rect(12 + f, 34, 16 + f, 44, dark); rect(15 - f, 34, 19 - f, 44, shade(colour, 0.5))
        rect(11 + f, 43, 17 + f, 45, BOOT)
        rect(10, top + 8, 21, top + 22, base)
        rect(10, top + 8, 21, top + 9, lite); rect(10, top + 21, 21, top + 22, dark)
        rect(5, top + 12, 13, top + 14, dark)                        # the gun arm, pointing ahead
        rect(4, top + 12, 5, top + 14, OUTLINE)
        rect(11, top, 20, top + 7, base); rect(11, top, 20, top, lite)
        rect(11, top + 2, 15, top + 5, OUTLINE); rect(12, top + 3, 13, top + 4, eye)
    if side:
        lean(im, side, top - 4)
    outline(im)
    if direction == 3:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    out = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
    sp = out.load()
    for y in range(43, 48):
        half = (10, 12, 12, 11, 8)[y - 43]
        for x in range(16 - half, 16 + half):
            sp[x, y] = (0, 0, 0, 80)
    out.alpha_composite(im)
    return out


def draw_armoured(colour, direction, pose):
    # (v62) a heavy stormtrooper: a jumpsuit-cut figure in steel, with plates on the
    # shoulders and chest and an open steel helmet over the face (no sealed suit: it breathes our air)
    if direction in SLANT_BASE:
        # (v74) the slants: the plated front or back, leaning (the plates go with the body)
        base, side = SLANT_BASE[direction]
        im = draw_armoured(colour, base, pose)
        top = 7 + (1 if pose != 0 else 0)
        body = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
        body.paste(im.crop((0, 0, CHAR_W, 43)), (0, 0))
        lean(body, side, top)
        out = Image.new("RGBA", (CHAR_W, CHAR_H), (0, 0, 0, 0))
        out.paste(im.crop((0, 43, CHAR_W, CHAR_H)), (0, 43))
        out.alpha_composite(body)
        return out
    im = draw_char(colour, direction, pose, 1, False)
    px = im.load()
    plate = (150, 156, 168, 255)
    plate_d = (80, 84, 94, 255)
    top = 7 + (1 if pose != 0 else 0)

    def rect(x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < CHAR_W and 0 <= y < CHAR_H and px[x, y][3] > 0:
                    px[x, y] = c

    if direction in (0, 1):
        rect(6, top + 12, 10, top + 15, plate); rect(22, top + 12, 26, top + 15, plate)
        rect(12, top + 14, 20, top + 21, plate); rect(12, top + 21, 20, top + 21, plate_d)
        rect(11, top, 21, top + 2, plate); rect(11, top, 12, top + 8, plate_d); rect(20, top, 21, top + 8, plate_d)
    else:
        # (the profile was flipped for direction 3 by draw_char: mirror the plates too)
        flip = direction == 3
        def fx(a, b):
            return (CHAR_W - 1 - b, CHAR_W - 1 - a) if flip else (a, b)
        a, b = fx(12, 20); rect(a, top + 12, b, top + 15, plate)
        a, b = fx(12, 19); rect(a, top + 16, b, top + 22, plate)
        a, b = fx(11, 20); rect(a, top, b, top + 2, plate)
        a, b = fx(17, 20); rect(a, top, b, top + 8, plate_d)
    return im


def build_chars():
    # one row per colour, outfit and backpack: row = colour * OUTFITS * 2 + outfit * 2 + (1 with a backpack)
    rows = len(SUIT_COLOURS) * OUTFITS * 2
    # (v74) 8 directions of 3 frames: down, up, left, right, then the slants (see SLANT_BASE)
    sheet = Image.new("RGBA", (CELL_W * 24, CELL_H * rows), (0, 0, 0, 0))
    for ci, (name, colour) in enumerate(SUIT_COLOURS):
        for outfit in range(OUTFITS):
            for pack in (False, True):
                row = ci * OUTFITS * 2 + outfit * 2 + (1 if pack else 0)
                for d in range(8):
                    for pose in range(3):
                        if name in ROBOT_EYES:
                            frame = draw_robot(colour, ROBOT_EYES[name], d, pose)
                        elif name == "armour":
                            frame = draw_armoured(colour, d, pose)
                        else:
                            frame = draw_char(colour, d, pose, outfit, pack)
                        sheet.paste(frame, ((d * 3 + pose) * CELL_W + CHAR_PAD, row * CELL_H + CHAR_PAD))
    sheet.save(os.path.join(OUT, "chars.png"))
    prev = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    bg = Image.new("RGBA", prev.size, (74, 78, 88, 255))
    bg.alpha_composite(prev)
    bg.save(os.path.join(ROOT, "tools", "preview", "chars.png"))
    print(f"chars: {len(SUIT_COLOURS)} colours x {OUTFITS * 2} outfits x 24 frames -> assets/chars.png")


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


BODY_CELL = (32, 48)        # (v87) a frame of the author's base bodies: 4 ways (front, right, back, left) x 2 (woman, man)


def build_body():
    # (v87) his sheet as he drew it, checked for its size (src/client/crew_art.gd reads it)
    src = Image.open(os.path.join(SRC, "body.png")).convert("RGBA")
    want = (BODY_CELL[0] * 4, BODY_CELL[1] * 2)
    assert src.size == want, f"art_src/body.png is {src.size}, {want} is needed"
    src.save(os.path.join(OUT, "body.png"))
    print(f"body: assets/body.png {src.width}x{src.height}")
    # (v88) his suited man and woman: 3 x 4 frames of 32x48 each (see SUIT_AT in src/client/crew_art.gd)
    for name in ("suit_man.png", "suit_woman.png"):
        suit = Image.open(os.path.join(SRC, name)).convert("RGBA")
        want = (BODY_CELL[0] * 3, BODY_CELL[1] * 4)
        assert suit.size == want, f"art_src/{name} is {suit.size}, {want} is needed"
        suit.save(os.path.join(OUT, name))
        print(f"suit: assets/{name} {suit.width}x{suit.height}")


def build_shuttle():
    """(v86, the author's N1) The fleet's shuttle, seen from above, nose up: 4 x 3 tiles. A simple base
    picture for the artist («sprites/shuttle.png» of the same size replaces it)."""
    w, h = 4 * T, 3 * T
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    hull, edge, dark, glass = (150, 158, 170, 255), (90, 96, 110, 255), (50, 54, 66, 255), (90, 190, 255, 255)
    d.polygon([(16, 70), (40, 34), (88, 34), (112, 70), (100, 82), (28, 82)], fill=edge)        # the wings
    d.rounded_rectangle((40, 10, 88, 88), radius=18, fill=hull, outline=edge, width=2)           # the body
    d.polygon([(52, 8), (76, 8), (64, 0)], fill=hull)                                              # the nose
    d.rounded_rectangle((52, 14, 76, 32), radius=8, fill=glass, outline=dark, width=2)           # the cockpit
    for k in range(4):                                                                             # the seats' windows
        y = 40 + k * 10
        d.rectangle((46, y, 50, y + 5), fill=glass)
        d.rectangle((78, y, 82, y + 5), fill=glass)
    d.rectangle((60, 36, 68, 80), fill=dark)                                                       # the hatch's line
    for x in (46, 74):                                                                             # two engines, glowing
        d.rectangle((x, 86, x + 8, 93), fill=dark)
        d.rectangle((x + 2, 90, x + 6, 95), fill=(255, 170, 70, 255))
    d.rectangle((18, 68, 22, 72), fill=(230, 60, 50, 255))                                       # wing lamps
    d.rectangle((106, 68, 110, 72), fill=(60, 220, 110, 255))
    im.save(os.path.join(OUT, "shuttle.png"))
    print("shuttle: assets/shuttle.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(ROOT, "tools", "preview"), exist_ok=True)
    images, ids = build_tiles()
    print(f"tiles: {len(ids)} -> assets/tiles.png")
    build_maps(images, ids)
    build_chars()
    build_body()
    build_hud()
    build_fx()
    build_shuttle()


if __name__ == "__main__":
    try:
        main()
    except MapError as e:
        print("MAP ERROR:", e)
        sys.exit(1)
