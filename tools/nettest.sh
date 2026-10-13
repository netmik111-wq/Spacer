#!/bin/bash
# Network self-test: one dedicated server, N real game clients without a
# window, each wandering for a while. Optionally through tools/lagproxy,
# which delays and drops packets like a real internet link.
# usage: tools/nettest.sh CLIENTS SECONDS [DELAY_MS JITTER_MS LOSS_PERCENT [STALL_MS STALL_EVERY_MS]]
#   GODOT=/path/to/godot  LAGPROXY=/path/to/lagproxy
#   BREACH=SECONDS  tear a hole in the hull that long after the start (default 6; 0 = never)
set -u
N=${1:-4}; SECS=${2:-20}; DELAY=${3:--1}; JIT=${4:-0}; LOSS=${5:-0}; STALL=${6:-0}; EVERY=${7:-1000}
GODOT=${GODOT:-godot}; PORT=${PORT:-24700}; OUT=${OUT:-/tmp/nettest}; BREACH=${BREACH:-6}
BARG=""; [ "$BREACH" != "0" ] && BARG="breach_after=$BREACH"
cd "$(dirname "$0")/.."; rm -rf "$OUT"; mkdir -p "$OUT"
"$GODOT" --headless --path . -- --server --no-events port=$PORT bots=2 $BARG quit_after=$((SECS + 8)) > "$OUT/server.log" 2>&1 & SP=$!
CPORT=$PORT; PP=""
if [ "$DELAY" -ge 0 ]; then CPORT=$((PORT + 1)); "$LAGPROXY" $CPORT $PORT $DELAY $JIT $LOSS $STALL $EVERY 2> "$OUT/proxy.log" & PP=$!; fi
sleep 1.5
for i in $(seq 1 $N); do
  "$GODOT" --headless --path . -- join=127.0.0.1 port=$CPORT name=Тест$i --demo --respawn demo_until=$((SECS - 3)) quit_after=$SECS stats="$OUT/c$i.json" > "$OUT/c$i.log" 2>&1 &
  sleep 0.2
done
wait $SP
[ -n "$PP" ] && kill $PP 2>/dev/null
python3 - "$OUT" "$N" <<'PY'
import json, sys, glob, os
out, n = sys.argv[1], int(sys.argv[2])
rows = []
for i in range(1, n + 1):
    p = os.path.join(out, f"c{i}.json")
    rows.append(json.load(open(p)) if os.path.exists(p) else None)
ok = [r for r in rows if r]
errs = sum(open(f, errors="replace").read().count("ERROR") for f in glob.glob(os.path.join(out, "*.log")))
steps = sum(r["steps_predicted"] for r in ok); mis = sum(r["mispredicts"] for r in ok)
print(f"clients reporting: {len(ok)}/{n}, all in game: {all(r['phase'] == 3 for r in ok)}")
print(f"predicted steps: {steps}, corrected by the server: {mis} ({100.0 * mis / max(steps, 1):.2f}%)")
print(f"state checks: {sum(r['checks_ok'] for r in ok)} ok, {sum(r['checks_bad'] for r in ok)} bad "
      f"(of the bad ones, doors/hull/air: {sum(r['ship_checks_bad'] for r in ok)}); holes seen by clients: {sorted(set(r['holes'] for r in ok))}")
print(f"health of the clients at the end: {sorted(r['health'] for r in ok)}; down or dead: {sum(1 for r in ok if r['cond'] != 0)}")
print(f"clients on each deck at the end (0 = top): {sorted(r.get('deck', 0) for r in ok)}")
print(f"cells with things on the floor seen by clients: {sorted(set(r.get('floor', 0) for r in ok))}")
print(f"ended where the server says: {sum(1 for r in ok if (r['pred_x'], r['pred_y']) == (r['auth_x'], r['auth_y']))}/{len(ok)}")
print(f"ping seen by clients: {min(r['rtt_ms'] for r in ok):.0f}..{max(r['rtt_ms'] for r in ok):.0f} ms; errors in logs: {errs}")
PY
grep -h -E "SCRIPT ERROR|Parse Error" "$OUT"/*.log | head -5
