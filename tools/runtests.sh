#!/bin/bash
# Runs every check that needs no network or window, one after another, and
# fails if any of them fails. GitHub Actions runs this on every push.
# usage: tools/runtests.sh            (GODOT=/path/to/godot to pick the engine)
#   Each test runs with a time limit: a test that crashed with a script error
#   does not exit by itself. Its output goes to $OUT/NAME.log.
set -u
GODOT=${GODOT:-godot}; OUT=${OUT:-/tmp/runtests}; LIMIT=${LIMIT:-600}
TESTS="airtest machinetest spacetest itemtest sighttest fighttest locktest derelicttest weartest guntest crewtest savetest admintest holotest shiptest dronetest stationtest flagshiptest tiertest geartest worktest powertest enemytest storytest roadtest airlocktest salvagetest crewfighttest fixtest peopletest upkeeptest bottest walktest polishtest eveningtest quartertest defencetest fullruntest edittest hosttest fleettest wingtest shuttletest windowtest arenatest armourtest eyestest fluxtest flighttest podtest placetest arsenaltest asteroidtest spritetest turrettest followtest heattest"
# SLOW tests run beside the rest, each with its own user:// folder (they would share saves and
# logs) and its own ports: directortest alone was half of the whole run (2026-11-03 test review).
SLOW="directortest"
cd "$(dirname "$0")/.."; rm -rf "$OUT"; mkdir -p "$OUT"
bad=0
for t in $SLOW; do
  mkdir -p "$OUT/$t.data"
  ( start=$(date +%s)
    XDG_DATA_HOME="$OUT/$t.data" timeout "$LIMIT" "$GODOT" --headless --path . --script "res://tools/$t.gd" > "$OUT/$t.log" 2>&1
    echo "$? $(( $(date +%s) - start ))" > "$OUT/$t.code" ) &
done
report() {   # report NAME EXIT SECONDS
  local t=$1 code=$2 took=$3
  # a script error does not always change the exit code: look for it in the output too
  if [ $code -eq 0 ] && grep -q -E "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT/$t.log"; then code=99; fi
  if [ $code -eq 0 ]; then
    echo "ok    $t (${took}s)"
  else
    bad=$((bad + 1))
    echo "FAIL  $t (exit $code, ${took}s); the end of its output:"
    tail -n 25 "$OUT/$t.log" | sed 's/^/      /'
  fi
}
for t in $TESTS; do
  start=$(date +%s)
  timeout "$LIMIT" "$GODOT" --headless --path . --script "res://tools/$t.gd" > "$OUT/$t.log" 2>&1
  report "$t" $? $(( $(date +%s) - start ))
done
wait
for t in $SLOW; do
  read -r code took < "$OUT/$t.code"
  report "$t" "$code" "$took"
done
echo "failed: $bad of $(echo $TESTS $SLOW | wc -w)"
[ $bad -eq 0 ]
