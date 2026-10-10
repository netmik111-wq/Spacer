#!/bin/bash
# Second version of the load test (server2.gd + bots2.gd), with CPU use per thread.
# usage: GODOT=/path/to/godot run3.sh N crowded port [extra server args...]   (env: DUR, BOTARGS)
#   extra server args: netthread=0/1  async=0/1  compress=1  sendevery=2
cd "$(dirname "$0")" && mkdir -p logs
N=$1; CROWD=$2; PORT=$3; shift 3; EXTRA="$*"; DUR=${DUR:-20}
TAG=v2_${N}_${CROWD}_$(echo "$EXTRA" | tr ' =' '__')
drops() { awk -v p=$PORT 'NR>1 && $2 ~ ":"sprintf("%04X",p)"$" {print $NF}' /proc/net/udp; }
snap() { for t in /proc/$SP/task/*; do awk -v tid=$(basename $t) '{n=split($0,a,") "); split(a[n],f," "); c=$2; sub(/^\(/,"",c); printf "%s %s %d\n", tid, c, f[12]+f[13]}' $t/stat 2>/dev/null; done | sort; }
"$GODOT" --headless --path . --script res://server2.gd -- n=$N crowded=$CROWD duration=$DUR port=$PORT $EXTRA > logs/s_$TAG.log 2>&1 & SP=$!
sleep 1.5
"$GODOT" --headless --path . --script res://bots2.gd -- n=$N duration=$DUR port=$PORT $BOTARGS > logs/b_$TAG.log 2>&1 & BP=$!
D0=""; D1=0; T0=""
while kill -0 $SP 2>/dev/null; do
  if [ -z "$D0" ] && grep -q MEASURE_START logs/s_$TAG.log; then D0=$(drops); snap > logs/t0_$TAG.txt; T0=$(date +%s.%N); fi
  d=$(drops); [ -n "$d" ] && D1=$d
  if [ -n "$T0" ]; then snap > logs/t1_$TAG.tmp 2>/dev/null && [ -s logs/t1_$TAG.tmp ] && { mv logs/t1_$TAG.tmp logs/t1_$TAG.txt; T1=$(date +%s.%N); }; fi
  sleep 0.5
done
wait $SP; sleep 2; kill $BP 2>/dev/null; wait $BP 2>/dev/null
grep -h -E "RESULT2|tick ms|server process|net:|inputs|FAIL|ERROR|SCRIPT" logs/s_$TAG.log | head -10
if [ -s logs/t0_$TAG.txt ] && [ -s logs/t1_$TAG.txt ]; then
  join logs/t0_$TAG.txt logs/t1_$TAG.txt | awk -v dt=$(echo "$T1 - $T0" | bc) '{d=($5-$3)/dt; if ($2 ~ /net_loop/) n+=d; else if ($2 ~ /Worker/) w+=d; else m+=d} END{printf "  threads (%% of a core): main+others=%.1f  network thread=%.1f  worker threads=%.1f\n", m, n, w}'
fi
grep -h -E "BOTS2|FAIL|ERROR|SCRIPT" logs/b_$TAG.log | head -6
echo "  server socket drops: total=$D1, during measured window=$(( D1 - ${D0:-$D1} ))"
