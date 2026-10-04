#!/usr/bin/env bash
# run-matrix.sh — P7 full matrix runner, 2 parallel lanes.
# 11 configs x 3 workloads x 3 runs = 99 runs, deterministic shuffle
# (seed 20260930), lane = global_index % 2 (keeps per-lane randomization).
# Lane 0: server cores 0-3,  bots 12-15, port 25565, workspace ws0
# Lane 1: server cores 4-7,  bots 8-11,  port 25566, workspace ws1
# (bots never share a physical core with their own server; cross-lane SMT
#  sharing is recorded in metadata via cores/botcores fields)
# Timing per run: warmup 600s under load + measure 600s (~20 min).
# (user decision 2026-09-30: 3 reps; measure 600s validated non-inferior to
#  900s; warmup must stay >=600s — JIT still active at 5min)
# Usage: run-matrix.sh [--dry-run] [--runs 3]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED=20260930
RUNS=3; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) RUNS=$2; shift 2;; --dry-run) DRY=1; shift;;
    *) echo "unknown arg $1"; exit 1;;
  esac
done

CONFIGS=(
  temurin25:g1 temurin25:zgc temurin25:parallel temurin25:shenandoah
  graalvmce25:g1 graalvmce25:zgc
  semeru25:gencon semeru25:balanced semeru25:optavgpause semeru25:optthruput
  corretto25:g1
)
WORKLOADS=(mixed explore entity)

# full plan, deterministic shuffle via md5(seed|entry)
PLAN=()
for cfg in "${CONFIGS[@]}"; do
  for wl in "${WORKLOADS[@]}"; do
    for r in $(seq 1 "$RUNS"); do
      h=$(echo "$SEED|$cfg|$wl|$r" | md5sum | cut -d' ' -f1)
      PLAN+=("$h $cfg $wl $r")
    done
  done
done
IFS=$'\n' SORTED=($(printf '%s\n' "${PLAN[@]}" | sort)); unset IFS
TOTAL=${#SORTED[@]}

LANE_CORES=("0-3" "4-7")
LANE_BOTCORES=("12-15" "8-11")
LANE_PORTS=(25565 25566)

run_lane() {
  local lane=$1
  local log="$ROOT/runs/matrix-lane$lane.log"
  local i=0
  for line in "${SORTED[@]}"; do
    local gidx=$i; i=$((i+1))
    (( gidx % 2 == lane )) || continue
    read -r _ cfg wl r <<<"$line"
    local runtime=${cfg%%:*} gc=${cfg#*:}
    if [[ $DRY -eq 1 ]]; then echo "lane$lane [$gidx/$TOTAL] $runtime $gc $wl rep$r"; continue; fi
    echo "[lane$lane $gidx/$TOTAL] $(date -Is) $runtime $gc $wl rep$r START" >> "$log"
    if "$ROOT/scripts/run-min-bench.sh" --runtime "$runtime" --gc "$gc" --workload "$wl" \
         --players 25 --warmup 600 --measure 600 --seed "$SEED" \
         --workspace "$ROOT/workspaces/ws$lane" --port "${LANE_PORTS[$lane]}" \
         --cores "${LANE_CORES[$lane]}" --botcores "${LANE_BOTCORES[$lane]}" >> "$log" 2>&1; then
      echo "[lane$lane $gidx/$TOTAL] $runtime $gc $wl rep$r DONE" >> "$log"
    else
      echo "[lane$lane $gidx/$TOTAL] $runtime $gc $wl rep$r FAILED" >> "$log"
    fi
  done
  echo "[lane$lane] finished $(date -Is)" >> "$log"
}

mkdir -p "$ROOT/runs"
echo "# matrix start $(date -Is) seed=$SEED total=$TOTAL lanes=2 warmup=600 measure=600 players=25 reps=$RUNS" >> "$ROOT/runs/matrix.log"
run_lane 0 & L0=$!
run_lane 1 & L1=$!
wait $L0 $L1
echo "# matrix end $(date -Is)" >> "$ROOT/runs/matrix.log"
