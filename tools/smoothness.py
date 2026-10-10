#!/usr/bin/env python3
"""Reads a trace written by the game (option trace=FILE) and reports how evenly
characters moved on screen: speed inside runs, one-frame stalls, jumps.
usage: smoothness.py TRACE MY_ID"""
import collections, sys
rows = [l.split() for l in open(sys.argv[1])]
me = int(sys.argv[2])
series = collections.defaultdict(list)
for r in rows:
    t = int(r[0]) / 1e6
    for item in r[1:]:
        if item.startswith('w'):
            continue
        i, x, y = item.split(':'); series[int(i)].append((t, float(x), float(y)))
dts = [b[0] - a[0] for a, b in zip(series[me], series[me][1:])]
print(f"frames {len(rows)}, frame time avg {1000*sum(dts)/len(dts):.1f} ms, max {1000*max(dts):.1f} ms")
for i, pts in sorted(series.items()):
    v = []
    for a, b in zip(pts, pts[1:]):
        dt = b[0] - a[0]
        v.append(((b[1] - a[1]) / dt, (b[2] - a[2]) / dt, abs(b[1] - a[1]) + abs(b[2] - a[2])))
    sp = [abs(x) + abs(y) for x, y, _ in v]
    # frames well inside a straight run: two neighbours on each side move the same way
    def same(a, b): return a[0] * b[0] + a[1] * b[1] > 1.0
    inner = [sp[k] for k in range(2, len(v) - 2) if all(same(v[k], v[j]) for j in (k - 2, k - 1, k + 1, k + 2))]
    stalls = sum(1 for k in range(1, len(v) - 1) if sp[k] < 0.01 and same(v[k - 1], v[k + 1]))
    jumps = sum(1 for _, _, d in v if d > 0.35)
    who = 'own character (predicted)' if i == me else f'other #{i} (interpolated)'
    if inner:
        print(f"{who}: speed inside straight runs {min(inner):.2f}..{max(inner):.2f} tiles/s, avg {sum(inner)/len(inner):.2f} (nominal 5.00); one-frame stalls {stalls}; jumps {jumps}")
    else:
        print(f"{who}: no straight runs recorded; stalls {stalls}; jumps {jumps}")

# reaction time: from the moment a direction key goes down to the first frame the own character moves
want = [(int(r[0]) / 1e6, int(r[1][1:])) for r in rows if len(r) > 1 and r[1].startswith('w')]
if want:
    pos = {t: (x, y) for t, x, y in series[me]}
    times = sorted(pos)
    delays = []
    for (t0, w0), (t1, w1) in zip(want, want[1:]):
        if w0 == 0 and w1 != 0:
            start = pos.get(t1)
            for t in times:
                if t > t1 and start is not None and pos[t] != start:
                    delays.append((t - t1) * 1000.0); break
    if delays:
        print(f"key press to visible movement: {min(delays):.0f}..{max(delays):.0f} ms, avg {sum(delays)/len(delays):.0f} ms over {len(delays)} presses")
