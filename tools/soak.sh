#!/bin/bash
# (v75) The soak test: two hours of game time with a full crew of bots, campaign after
# campaign, watching the server's tick time, memory and stuck bots (tools/playthrough.gd, SOAK=1).
#   GODOT=... tools/soak.sh [hours] [bots]
# Prints the soak lines; exit code 1 when something looks wrong.
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
HOURS=${1:-2}
OUT=$(mktemp -d)
SOAK=1 BOTS=${2:-7} timeout $((HOURS * 3600)) "$GODOT" --headless --path . --script res://tools/playthrough.gd -- "$OUT" 1 1 normal "$HOURS" 60 > "$OUT/soak.out" 2>&1
code=$?
grep -E "^(run|soak)" "$OUT/soak.out"
if grep -q -E "SCRIPT ERROR|Parse Error" "$OUT/soak.out"; then
	grep -m 5 -A 3 -E "SCRIPT ERROR|Parse Error" "$OUT/soak.out"
	echo "soak: bad (script errors)"
	code=1
fi
echo "records in $OUT"
exit $code
