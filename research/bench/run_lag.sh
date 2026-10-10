#!/bin/bash
# Second version of the load test through a bad link: how late do updates reach the clients?
# usage: GODOT=/path/to/godot run_lag.sh N PORT DELAY_MS JITTER_MS LOSS_PCT [extra server args]   (DELAY<0 = no relay)
#   needs the relay built first: rustc -O tools/lagproxy.rs -o tools/lagproxy   (or set LAGPROXY=/path/to/it)
cd "$(dirname "$0")" && mkdir -p logs
N=$1; PORT=$2; DELAY=$3; JIT=$4; LOSS=$5; shift 5; EXTRA="$*"; DUR=${DUR:-20}
TAG=lag_${N}_${DELAY}_${JIT}_${LOSS}_$(echo "$EXTRA" | tr ' =' '__')
"$GODOT" --headless --path . --script res://server2.gd -- n=$N duration=$DUR port=$PORT stamp=1 $EXTRA > logs/s_$TAG.log 2>&1 & SP=$!
CP=0; PP=""
if [ "$DELAY" -ge 0 ]; then CP=$((PORT+1)); "${LAGPROXY:-../../tools/lagproxy}" $CP $PORT $DELAY $JIT $LOSS 2> logs/p_$TAG.log & PP=$!; fi
sleep 1.5
"$GODOT" --headless --path . --script res://bots2.gd -- n=$N duration=$DUR port=$PORT cport=$CP stamp=1 spawn=2 $BOTARGS > logs/b_$TAG.log 2>&1 & BP=$!
wait $SP; sleep 2; kill $BP $PP 2>/dev/null; wait $BP 2>/dev/null
grep -h -E "RESULT2|net:|FAIL|ERROR|SCRIPT" logs/s_$TAG.log | sed -E 's/RESULT2 (clients=[0-9]+).*/RESULT2 \1/' | head -5
grep -h -E "BOTS2|LATENCY|FAIL|ERROR|SCRIPT" logs/b_$TAG.log | sed -E 's/ \| avg entities.*//' | head -5
[ -n "$PP" ] && tail -1 logs/p_$TAG.log
