# Research: networking, threads, atmosphere

Measurements that the project's technical decisions rest on. This folder is not part of the game
itself (Godot ignores it because of the `.gdignore` file). Everything was measured on Godot 4.7.2,
on a dual-core machine, in October 2026. Raw results are in `results/`.

## What we decided

- **The game runs on one thread.** Threads speed up the server but don't reduce the total load,
  and they add a class of bugs that are hard to catch (see below).
- **The server sends only changes**, not the whole world every tick. This approach was carried over into the game.
- **Threads are worth revisiting** if one server gets more than 128 players or a server tick
  starts taking more than 25 ms (half of the 50 ms budget per tick).
- **Atmosphere on large maps** will need either computing only "active" cells,
  or moving the calculation into a module in a compiled language.

## Networking: version 1 vs version 2

Test world: a 128×96 cell map, 20 server ticks per second, atmosphere 10 times per second,
each client receives what happens in the neighbouring chunks of the map.

- **Version 1** (`server.gd`, `bots.gd`): every tick each client gets a full snapshot
  of its surroundings; the client sends input 20 times per second; everything on one thread.
- **Version 2** (`server2.gd`, `bots2.gd`): the client gets only changes; input is sent
  when it changes; networking and atmosphere run on separate threads.

Players spread across the map:

| Players | Traffic per player, version 1 | Version 2 | Server tick, version 1 | Version 2 | Core load, version 1 | Version 2 |
|---|---|---|---|---|---|---|
| 128 | 36.7 kbit/s | 10.1 kbit/s | 5.8 ms | 1.2 ms | 13.2% | 19.7% |
| 256 | 59 kbit/s | 15.2 kbit/s | 7.9 ms | 2.2 ms | 19% | 23.8% |
| 512 | 104 kbit/s | 25.0 kbit/s | 12.5 ms | 4.0 ms | 30% | 32.4% |

Version 1 at 256 and 512 players was measured with extra tuning (the server polls the network several
times per frame): without it not all clients connected.

All players in one room (worst case):

| Players | Traffic per player, version 1 | Version 2 |
|---|---|---|
| 128 | 157 kbit/s | 28.8 kbit/s |
| 256 | 307 kbit/s | 54.0 kbit/s |

What else the measurements showed:

- **State check.** Some bots rebuilt the world from changes and compared it with the server's
  checksums: there were no mismatches in any run.
- **Threads don't save CPU.** At 64 players the server tick dropped from 5.1 to 0.7 ms,
  but total load rose from 11.7% to 17.1% of a core: the work didn't disappear, it moved.
- **Beyond 128 players you hit system settings.** Without a separate network thread
  only 307 of 512 clients connected: the operating system was dropping incoming packets.
  Either a network thread or a larger receive buffer (`net.core.rmem_default`) helps.
- **ENet compression** cuts traffic by 14% (from 10.1 to 8.7 kbit/s at 128 players).
- **Bad connection.** With 40±10 ms delay each way, half of the updates arrive
  within 53 ms. With 2% packet loss, 1.9% of updates are more than 150 ms late;
  with 5% loss, 6.5% are.

## Atmosphere: the cost of one step

Model: three gases per cell, exchange with neighbours, every cell computed with no optimizations.

| Map | GDScript, one thread | GDScript, two cores | Rust |
|---|---|---|---|
| 60×40 | 1.3 ms | no gain | 0.02 ms |
| 128×96 | 7–11 ms | 4–6 ms | 0.10 ms |
| 255×255 (FTL13 map size) | 38–43 ms | 20 ms | 0.57 ms |

The `atmos2.gd` code is suitable as a basis for step 2 of the game: it computes into a spare buffer
and marks which chunks of the map had pressure changes, so only those need to be sent.

## Why threads are dangerous

- **Lost updates** (`race_demo.gd`). Two threads each add one to the same number
  a million times. Instead of 2,000,000 you get 1.3 to 1.5 million: a quarter
  to a third of the additions are lost. With a lock the result is correct, but the test runs
  13–15 times longer.
- **The result depends on machine load** (`det_test.gd`). If the atmosphere is computed in the background
  and the server takes the result "when ready", then over 200 server ticks an idle machine applies
  99 atmosphere steps, and a busy one 77–81, and the outcome differs every time.
  If the server tick waits for the result, the outcome is always the same.

## How to reproduce

You need Godot 4.7.2. Run the commands from the repository root:

    export GODOT=/path/to/godot

    # atmosphere and threads
    $GODOT --headless --path research/bench --script res://atmos_bench.gd
    $GODOT --headless --path research/bench --script res://atmos_bench2.gd
    $GODOT --headless --path research/bench --script res://race_demo.gd
    $GODOT --headless --path research/bench --script res://det_test.gd -- mode=async w=255 h=255
    rustc -O research/native/atmos.rs -o research/native/atmos_native && research/native/atmos_native

    # networking: version 1 (128 players, 20 seconds) and version 2 (128 players)
    research/bench/run_one.sh 128 0 0 20 24600
    research/bench/run3.sh 128 0 24610 netthread=1 async=1

    # networking over a bad connection: 64 players, 40±10 ms delay, 2% loss
    rustc -O tools/lagproxy.rs -o tools/lagproxy
    research/bench/run_lag.sh 64 24620 40 10 2 netthread=1 async=1

Run logs are written to `research/bench/logs/` and are not committed to the repository.
