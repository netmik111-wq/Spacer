# Server benchmark

`tools/bench.sh N SECS` starts one headless server and N headless bot clients on this
machine, lets them walk for SECS seconds, and prints:

- login time on the client: connect -> welcome, and connect -> first own state in the world;
- the server's own work per login (`hello`);
- server tick time (mean, median, p95, p99, max) over the whole run and while all clients are aboard,
  and how many ticks went over the 50 ms budget (20 ticks per second).

It also writes `summary.json` next to the logs.

## How to run it on a high-core machine (Linux)

    GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 PIN=1 tools/bench.sh 16 60
    GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 PIN=1 tools/bench.sh 32 60

`PIN=1` keeps the server on CPU 0 and the clients on the other CPUs, so the clients do not
steal the server's time. Each client is a whole Godot process (about 1 CPU while logging in),
so for clean login numbers have at least as many cores as clients. On Windows run it under WSL,
or start the server with `--headless -- --server bench=report.txt` and the clients by hand.

## Results

Machine: Intel Xeon 2.1 GHz, 4 CPUs (server pinned to one CPU, clients share 3: clients were
CPU-starved, so login times here are pessimistic).

| | v38, 16 | v39, 16 | v38, 32 | v39, 32 |
|---|---|---|---|---|
| login to welcome, median | 68 ms | 71 ms | 121 ms | 118 ms |
| login to first state in world, median | 422 ms | 438 ms | 901 ms | 816 ms |
| server work per login | | 0.55 ms | | 0.62 ms |
| tick mean | 1.00 ms | 3.51 ms | 1.78 ms | 10.71 ms |
| tick p99 | 2.10 ms | 8.44 ms | 3.67 ms | 24.0 ms |
| tick max | 5.97 ms | 11.4 ms | 6.78 ms | 29.7 ms |
| ticks over 50 ms | 0 | 0 | 0 | 0 |

v39 ticks cost more because the server now works out, for every pair of players, who sees whom
(server-side visibility). It is still well inside the 50 ms budget at 32 players. If it grows
past ~25 ms, the first thing to do is to check sight less often for far-away pairs or to cache
lines of sight per cell.

### v50 and v51, 32 clients (same machine, 2026-10-15)

| | v50, 32 | v51, 32 |
|---|---|---|
| login to welcome, median | 131 ms | 122 ms |
| login to first state in world, median | 937 ms | 894 ms |
| server work per login | 0.56 ms | 0.51 ms |
| tick mean, all aboard | 10.76 ms | 5.76 ms |
| tick median, all aboard | 8.41 ms | 4.67 ms |
| tick p99, all aboard | 50.7 ms | 31.4 ms |
| tick max | 247 ms | 84.6 ms |
| ticks over 50 ms, all aboard | 11 of 1046 | 6 of 1303 |

v51 lines of sight are remembered per cell pair and each character's place, look and light are
worked out once a tick instead of once per pair, so the tick costs about half. Where a v51 tick goes
(`bench.sh` now prints it): sending 4.70 ms, of which working out who sees whom 4.04 ms; players
0.63 ms, the ship 0.21 ms, air 0.05 ms. Sight is still most of the tick: the next step, if needed, is
to check far-away pairs less often. The rare ticks over budget in both runs come with the clients
starving this 4-CPU machine (the maximum moves a lot between runs); the server's own work is the mean.
`tools/sightbench.gd` (32 bots, no network) shows the same: 7.4 ms of sight per tick before, about
3.5 ms after.
