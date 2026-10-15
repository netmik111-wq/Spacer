#!/bin/bash
# Load benchmark: one dedicated server and N real game clients without a
# window, all wandering about. Measures how long a client takes to get aboard
# and how long the server takes over each tick (it has 50 ms per tick at 20 ticks a second).
# usage: tools/bench.sh CLIENTS SECONDS        e.g. tools/bench.sh 32 60
#   GODOT=/path/to/godot
#   STAGGER=0.05     seconds between starting one client and the next (0 = all at once)
#   PIN=1            keep the server on CPU 0 and the clients on the other CPUs (needs taskset),
#                    so the clients do not steal the server's time
#   PORT=24800  OUT=/tmp/bench
set -u
N=${1:-16}; SECS=${2:-60}
GODOT=${GODOT:-godot}; PORT=${PORT:-24800}; OUT=${OUT:-/tmp/bench}; STAGGER=${STAGGER:-0.05}; PIN=${PIN:-1}
cd "$(dirname "$0")/.."; rm -rf "$OUT"; mkdir -p "$OUT"
CPUS=$(nproc)
SPIN=""; CPIN=""
if [ "$PIN" = "1" ] && [ "$CPUS" -gt 1 ] && command -v taskset > /dev/null; then
  SPIN="taskset -c 0"; CPIN="taskset -c 1-$((CPUS - 1))"
fi
LAST=$(python3 -c "print(int(1.5 + $N * $STAGGER + 4))")   # every client is aboard by then
$SPIN "$GODOT" --headless --path . -- --server --no-events campaign=off port=$PORT bots=0 \
  bench="$OUT/server.json" quit_after=$((SECS + LAST + 15)) > "$OUT/server.log" 2>&1 & SP=$!
sleep 1.5
CP=""
for i in $(seq 1 $N); do
  $CPIN "$GODOT" --headless --path . -- join=127.0.0.1 port=$PORT name=Бот$i --demo --respawn \
    demo_until=$((SECS + LAST)) quit_after=$((SECS + LAST + 2)) stats="$OUT/c$i.json" > "$OUT/c$i.log" 2>&1 & CP="$CP $!"
  sleep "$STAGGER"
done
wait $SP $CP
python3 - "$OUT" "$N" "$CPUS" "$SPIN" <<'PY'
import json, sys, os, glob, statistics, platform
out, n, cpus, pinned = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4] != ""
def pct(v, p):
    if not v: return float("nan")
    v = sorted(v); return v[min(len(v) - 1, int(round(p / 100.0 * (len(v) - 1))))]
rows = []
for i in range(1, n + 1):
    p = os.path.join(out, f"c{i}.json")
    rows.append(json.load(open(p)) if os.path.exists(p) else None)
ok = [r for r in rows if r]
s = json.load(open(os.path.join(out, "server.json")))
ticks = [u / 1000.0 for u in s["tick_usec"]]
full = [t for t, p in zip(ticks, s["tick_players"]) if p >= n]
login = [r["login_ms"] for r in ok if r.get("login_ms", -1) >= 0]
world = [r["in_world_ms"] for r in ok if r.get("in_world_ms", -1) >= 0]
hello = [u / 1000.0 for u in s["hello_usec"]]
errs = sum(open(f, errors="replace").read().count("SCRIPT ERROR") for f in glob.glob(os.path.join(out, "*.log")))
print(f"machine: {s['cpu']}, {cpus} CPUs ({'server on CPU 0, clients on the rest' if pinned else 'not pinned'})")
print(f"clients: {len(ok)}/{n} reported, {len(login)} got aboard; state checks {sum(r['checks_ok'] for r in ok)} ok, "
      f"{sum(r['checks_bad'] for r in ok)} bad; script errors in logs: {errs}")
def line(name, v, unit="ms"):
    if not v: print(f"{name}: no data"); return
    print(f"{name}: mean {statistics.mean(v):.2f}, median {pct(v,50):.2f}, p95 {pct(v,95):.2f}, p99 {pct(v,99):.2f}, max {max(v):.2f} {unit} (n={len(v)})")
line("login (connect -> welcome), client side", login)
line("login (connect -> first own state in the world)", world)
line("server work per login (hello)", hello)
line("server tick, whole run", ticks)
line(f"server tick, all {n} clients aboard", full)
over = sum(1 for t in full if t > 50.0)
print(f"ticks over the 50 ms budget while all aboard: {over} of {len(full)}")
parts = s.get("parts", {})
if parts:
    print("where the tick time went: " + ", ".join(f"{k} {v / max(s.get('part_ticks', 1), 1) / 1000.0:.2f} ms" for k, v in sorted(parts.items())) + " (mean per tick)")
json.dump({"clients": n, "cpus": cpus, "cpu": s["cpu"], "login_ms": login, "in_world_ms": world,
           "tick_ms_full": full}, open(os.path.join(out, "summary.json"), "w"))
PY
