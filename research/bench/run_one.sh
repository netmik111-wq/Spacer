#!/bin/bash
# First version of the load test (server.gd + bots.gd).
# usage: GODOT=/path/to/godot run_one.sh N crowded(0/1) compress(0/1) duration port
cd "$(dirname "$0")" && mkdir -p logs
G="$GODOT"; N=$1; CROWD=$2; COMP=$3; DUR=${4:-20}; PORT=${5:-24500}
"$G" --headless --path . --script res://server.gd -- n=$N crowded=$CROWD compress=$COMP duration=$DUR port=$PORT > logs/server_${N}_${CROWD}_${COMP}.log 2>&1 &
SP=$!
sleep 1.5
"$G" --headless --path . --script res://bots.gd -- n=$N compress=$COMP duration=$DUR port=$PORT > logs/bots_${N}_${CROWD}_${COMP}.log 2>&1 &
BP=$!
wait $SP
sleep 2
kill $BP 2>/dev/null; wait $BP 2>/dev/null
grep -h -E "RESULT|tick ms|server process|net:|inputs|SERVER_FAIL|ERROR|SCRIPT" logs/server_${N}_${CROWD}_${COMP}.log | head -12
grep -h -E "BOTS|BOT_FAIL|ERROR|SCRIPT" logs/bots_${N}_${CROWD}_${COMP}.log | head -6
