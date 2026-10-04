# Round 2: player scaling results (2026-10-01 → 10-02)

Matrix: 7 combos × players {25,50,100,150} × 3 reps = 84 runs, workload mixed, warmup 600s / measure 600s,
heap -Xms16G -Xmx16G (all, incl. baselines which carry no GC flag), server cores 0-7, bot shards (≤50/proc) cores 8-15,
bots contained within pregen r=400, join ramp ~1 bot/s for p>100. **84/84 done, 0 failures, 0 bot kicks in any run.**

## Mean MSPT (ms, median of 3 reps)

| combo | p25 | p50 | p100 | p150 |
|---|---|---|---|---|
| openjdk25 默认 | 7.98 | 9.00 | 16.48 | 73.96 |
| oracle25 默认 | **6.92** | 9.62 | 16.75 | 78.88 |
| temurin25+g1 | 7.59 | 10.35 | 16.48 | 68.73 |
| temurin25+shenandoah | 8.32 | 10.01 | 15.81 | **48.00** |
| temurin25+parallel | 7.69 | 9.28 | 16.79 | 90.28 |
| temurin25+zgc | 9.42 | 10.82 | 16.05 | **47.60** |
| graalvmce25+g1 | 7.05 | **8.57** | 15.88 | 68.75 |

## Achieved tick rate (=TPS, 20 = healthy)

| combo | p25 | p50 | p100 | p150 |
|---|---|---|---|---|
| shenandoah | 20 | 20 | 20 | **19.2** |
| zgc | 20 | 20 | 20 | **18.8** |
| temurin g1 | 20 | 20 | 20 | 14.5 |
| graalvmce g1 | 20 | 20 | 20 | 14.5 |
| openjdk 默认 | 20 | 20 | 20 | 13.5 |
| oracle 默认 | 20 | 20 | 20 | 12.7 |
| parallel | 20 | 20 | 20 | 11.1 |

## Tail at p150 (ms)

| combo | p99 | max |
|---|---|---|
| zgc | **98.7** | **159** |
| shenandoah | 104.2 | 290 |
| oracle 默认 | 147.8 | 305 |
| temurin g1 | 150.4 | 330 |
| graalvmce g1 | 154.4 | 343 |
| openjdk 默认 | 161.0 | 319 |
| parallel | 192.9 | 414 |

## Findings

1. **Overload point: between 100 and 150 players** (8 server cores, this box). p≤100 every combo holds 20 TPS
   with mean ≤17ms; at p150 all overload, only severity differs. Probe at p200 showed full collapse
   (multi-second ticks, keepalive mass-kicks) — beyond measurable range.
2. **p≤100: vendor/GC choice nearly irrelevant** (mean spread <2ms within a level; rep spread 3-34% at p25
   makes sub-ms differences noise). G1(default) ≈ ZGC ≈ Shen at p50/p100 means.
3. **p150 splits by GC**: ZGC 47.6 / Shenandoah 48.0 mean ≈ 30-35% better than G1-family (68.7-74.0),
   Parallel worst (90.3, TPS 11.1). Max spikes: ZGC 159ms vs G1 330 / Parallel 414.
4. **Baselines answer the tuning question**: openjdk25/oracle25 with zero flags behave ≈ temurin25+g1 at 16G
   heap at every level (default G1 + ~15.6G heap auto-sized). No vendor magic; the wins come from GC choice.
5. **Stability caveat**: shenandoah p150 rep means 31/48/101 (bimodal — near tipping point, once TPS slips
   load feedback deepens it); zgc 34/48/55; parallel is consistently bad (88/90/92). Rank order
   ZGC≈Shen > G1 > Parallel holds in every rep ordering of medians.
6. ZGC shows a small throughput tax at low load (p25 mean 9.42 vs ~7.6 for G1, +~1.8ms).

## Recommendation for Paper 26.2 on this hardware

- ≤100 players: any combo; default openjdk/temurin G1 is fine.
- 100-150 players (near overload): `-XX:+UseZGC -Xms16G -Xmx16G` (or Shenandoah) — holds ~19 TPS where
  G1 falls to 13-14.
- Absolute ceiling on this box: ~150 concurrent mixed-workload players; 200 collapses.

Raw data: `runs/20261001-164551..20261002-204827-*-ws0` (84 dirs); per-run metadata in metadata.json;
tick series mspt.csv; GC logs gc.log; process samples proc.txt.
