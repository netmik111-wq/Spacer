#!/bin/bash
# Runs every check that needs no network or window, one after another, and
# fails if any of them fails. GitHub Actions runs this on every push.
# usage: tools/runtests.sh            (GODOT=/path/to/godot to pick the engine)
#   Each test runs with a time limit: a test that crashed with a script error
#   does not exit by itself. Its output goes to $OUT/NAME.log.
set -u
GODOT=${GODOT:-godot}; OUT=${OUT:-/tmp/runtests}; LIMIT=${LIMIT:-600}
TESTS="airtest directortest machinetest spacetest itemtest sighttest fighttest locktest derelicttest weartest guntest crewtest savetest admintest holotest shiptest dronetest stationtest"
cd "$(dirname "$0")/.."; rm -rf "$OUT"; mkdir -p "$OUT"
bad=0
for t in $TESTS; do
  start=$(date +%s)
  timeout "$LIMIT" "$GODOT" --headless --path . --script "res://tools/$t.gd" > "$OUT/$t.log" 2>&1
  code=$?
  took=$(( $(date +%s) - start ))
  # a script error does not always change the exit code: look for it in the output too
  if [ $code -eq 0 ] && grep -q -E "SCRIPT ERROR|Parse Error|Failed to load script" "$OUT/$t.log"; then code=99; fi
  if [ $code -eq 0 ]; then
    echo "ok    $t (${took}s)"
  else
    bad=$((bad + 1))
    echo "FAIL  $t (exit $code, ${took}s); the end of its output:"
    tail -n 25 "$OUT/$t.log" | sed 's/^/      /'
  fi
done
echo "failed: $bad of $(echo $TESTS | wc -w)"
[ $bad -eq 0 ]
