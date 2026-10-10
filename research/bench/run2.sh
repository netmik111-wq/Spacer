#!/bin/bash
# First version of the load test, also counting packets the OS dropped at the server socket.
# usage: GODOT=/path/to/godot run2.sh N crowded polls port [duration]   (env: MID=1 polls in the middle of a tick too)
cd "$(dirname "$0")" && mkdir -p logs
N=$1; CROWD=$2; POLLS=$3; PORT=$4; DUR=${5:-20}; TAG=${N}_${CROWD}_p${POLLS}
drops() { awk -v p=$PORT 'NR>1 && $2 ~ ":"sprintf("%04X",p)"$" {print $NF}' /proc/net/udp; }
"$GODOT" --headless --path . --script res://server.gd -- n=$N crowded=$CROWD duration=$DUR port=$PORT polls=$POLLS midtick=${MID:-0} > logs/s_$TAG.log 2>&1 & SP=$!
sleep 1.5
"$GODOT" --headless --path . --script res://bots.gd -- n=$N duration=$DUR port=$PORT spawn=4 > logs/b_$TAG.log 2>&1 & BP=$!
D0=""; D1=0
while kill -0 $SP 2>/dev/null; do
  if [ -z "$D0" ] && grep -q MEASURE_START logs/s_$TAG.log; then D0=$(drops); fi
  d=$(drops); [ -n "$d" ] && D1=$d
  sleep 0.5
done
wait $SP; sleep 2; kill $BP 2>/dev/null; wait $BP 2>/dev/null
grep -h -E "RESULT|tick ms|server process|net:|inputs|FAIL|ERROR" logs/s_$TAG.log | head -8
grep -h -E "BOTS|FAIL|ERROR" logs/b_$TAG.log | head -4
echo "  server socket drops: total=$D1, during measured window=$(( D1 - ${D0:-$D1} )) (connect phase=${D0:-n/a})"
