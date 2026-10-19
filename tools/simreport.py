#!/usr/bin/env python3
"""Gathers the records of tools/playthrough.gd runs into tables (2026-10-19).

    python3 tools/simreport.py OUT_DIR LABEL=RUN_DIR [LABEL=RUN_DIR ...]

Each RUN_DIR holds run-NN.json and run-NN.log files from playthrough.gd; LABEL names
that batch (for example "careful" or "hurried"). Writes into OUT_DIR:
  runs.json      one row per game: outcome, time, jumps, credits earned and spent by
                 source, fuel, food, hull, fights, the flagship, crew, calls, quests
  timeline.json  one row per jump of every game: credits, hull, fuel, food, crew reserve
  money.json     one row per game and source of credits earned or thing they were spent on
  summary.md     the same as readable tables, with averages per batch
"""
import json
import pathlib
import re
import sys

# in-game names (Russian) to the words used in the report
NAMES = {
    "Топливо": "fuel", "Паёк": "food", "Пластырь": "hull patches", "ship guns": "ship guns",
    "calls": "comms calls", "other": "other", "exploring": "exploring new systems",
    "fights": "fights (loot, wrecks)", "ransom": "ransoms", "trade": "trade",
    "other (calls, places, loot)": "other (places, loot)",
}


def name(s):
    return NAMES.get(s, s)


def load(label, folder):
    out = []
    for p in sorted(pathlib.Path(folder).glob("run-*.json")):
        r = json.loads(p.read_text())
        log = p.with_suffix(".log")
        r["_events"] = log.read_text().count("[ивентер]") if log.exists() else 0
        r["_batch"] = label
        r["_id"] = "%s-%02d" % (label, r["run"])
        out.append(r)
    return out


def row(r):
    c, fu, fo, h, f, cr = r["credits"], r["fuel"], r["food"], r["hull"], r["fights"], r["crew"]
    eb, so = c["earned_by"], c["spent_on"]
    known_spent = ("Топливо", "Паёк", "ship guns", "calls")
    return {
        "id": r["_id"], "batch": r["_batch"], "run": r["run"], "seed": str(r["seed"]),
        "stay_seconds": r.get("stay_seconds", 0), "outcome": r["outcome"],
        "won": r["outcome"].startswith("won"), "minutes": r["game_minutes"],
        "jumps": r["jumps"], "long_jumps": r["long_jumps"], "cluster_reached": r["clusters_reached"],
        "systems_visited": r["systems_visited"],
        "credits_earned": c["earned"], "credits_spent": c["spent"], "credits_end": c["end"],
        "credits_most_held": c["most_held"],
        "earned_exploring": eb.get("exploring", 0), "earned_calls": eb.get("calls", 0),
        "earned_quests": eb.get("quests", 0), "earned_ransom": eb.get("ransom", 0),
        "earned_fights": eb.get("fights", 0),
        "earned_other": c["earned"] - sum(eb.get(k, 0) for k in ("exploring", "calls", "quests", "ransom", "fights")),
        "spent_fuel": so.get("Топливо", 0), "spent_food": so.get("Паёк", 0),
        "spent_guns": so.get("ship guns", 0), "spent_calls": so.get("calls", 0),
        "spent_other": c["spent"] - sum(so.get(k, 0) for k in known_spent),
        "fuel_bought": fu["bought"], "fuel_used": fu["used"], "fuel_found": fu["found"], "fuel_fetched": fu.get("fetched", 0),
        "food_bought": fo["bought"], "food_eaten": fo["eaten"], "food_found": fo["grown_or_found"], "food_fetched": fo.get("fetched", 0),
        "hull_lost": h["lost"], "hull_mended": h["mended"], "hull_lowest": h["lowest"], "hull_end": h["end"],
        "holes": r["holes_made"], "events": r["_events"],
        "fights": f["total"], "fight_seconds": f["seconds"], "fight_hull_lost": f["hull_lost"],
        "hunter_fights": f["hunters"], "pirates_killed": r["pirates_killed"], "most_boarders": r["boarders_seen"],
        "flagship_met": r["flagship"]["met"], "flagship_growth": r["flagship"]["growth_when_met"],
        "flagship_result": r["flagship"]["result"] or "",
        "crew_deaths": cr["deaths"], "captain_deaths": cr["captain_deaths"], "bot_deaths": cr["bot_deaths"],
        "respawns": cr["respawns"], "hired": cr["hired"],
        "calls_received": r["calls"]["received"], "calls_answered": r["calls"]["answered"],
        "quests_done": r["quests"]["done"], "quests_failed": r["quests"]["failed"],
        "guns_bought": len(r["guns_bought"]),
    }


def main():
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    games = []
    for a in sys.argv[2:]:
        label, folder = a.split("=", 1)
        games += load(label, folder)
    runs = [row(r) for r in games]
    timeline = []
    money = []
    for r in games:
        for t in r["timeline"]:
            timeline.append({"id": r["_id"], "batch": r["_batch"], "run": r["run"], **t})
        for k, v in r["credits"]["earned_by"].items():
            money.append({"id": r["_id"], "batch": r["_batch"], "way": "earned", "what": name(k), "credits": v})
        for k, v in r["credits"]["spent_on"].items():
            money.append({"id": r["_id"], "batch": r["_batch"], "way": "spent", "what": name(k), "credits": v})
    (out / "runs.json").write_text(json.dumps(runs, ensure_ascii=False, indent=1))
    (out / "timeline.json").write_text(json.dumps(timeline, ensure_ascii=False))
    (out / "money.json").write_text(json.dumps(money, ensure_ascii=False, indent=1))
    (out / "summary.md").write_text(summary(runs, games))
    print("%d games, %d jumps on the timeline -> %s" % (len(runs), len(timeline), out))


COLS = [("id", "game"), ("outcome", "how it ended"), ("minutes", "min"), ("jumps", "jumps"),
        ("cluster_reached", "cluster"), ("credits_earned", "earned"), ("credits_spent", "spent"),
        ("credits_end", "left"), ("fuel_used", "fuel used"), ("food_eaten", "food eaten"),
        ("events", "events"), ("fights", "fights"), ("pirates_killed", "pirates killed"),
        ("crew_deaths", "crew deaths"), ("calls_answered", "calls"), ("quests_done", "quests")]


def summary(runs, games):
    lines = ["# Spacer playthrough records", "",
             "Made by `tools/simreport.py` from `tools/playthrough.gd` runs. Times are game minutes.", ""]
    for b in dict.fromkeys(r["batch"] for r in runs):
        rs = [r for r in runs if r["batch"] == b]
        n = len(rs)
        avg = lambda k: sum(r[k] for r in rs) / n
        lines += ["## %s (%d games, the captain stays %ss per system)" % (b, n, rs[0]["stay_seconds"]), "",
                  "Won %d of %d. On average: %.0f min, %.0f jumps, cluster %.1f reached, %.0f credits earned "
                  "(%.0f exploring, %.0f calls, %.0f fights), %.0f spent (%.0f fuel, %.0f food), %.1f fights, "
                  "%.1f director events, %.1f crew deaths." % (
                      sum(r["won"] for r in rs), n, avg("minutes"), avg("jumps"), avg("cluster_reached"),
                      avg("credits_earned"), avg("earned_exploring"), avg("earned_calls"), avg("earned_fights"),
                      avg("credits_spent"), avg("spent_fuel"), avg("spent_food"), avg("fights"), avg("events"),
                      avg("crew_deaths")), "",
                  "| " + " | ".join(c[1] for c in COLS) + " |", "|" + "---|" * len(COLS)]
        for r in rs:
            lines.append("| " + " | ".join(str(r[c[0]]) for c in COLS) + " |")
        lines.append("")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
