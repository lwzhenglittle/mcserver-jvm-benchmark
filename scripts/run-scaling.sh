#!/usr/bin/env bash
# run-scaling.sh — round 2: player-count scaling to find overload points.
# 7 combos x players{25,50,100,200} x 3 reps x workload mixed = 84 runs.
# Single instance, full machine: server cores 0-7, bot shards on 8-15.
# Baselines (openjdk25/oracle25 "default") = -Xms8G -Xmx8G, JVM-default GC.
# Deterministic shuffle, seed 20260930. ~28h sequential.
# Usage: run-scaling.sh [--dry-run] [--runs 3]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SEED=20260930
RUNS=3; DRY=0; WS=ws0; PORT=25565; BOTVER=26.1; LOGSUFFIX=""; RESUME_AFTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) RUNS=$2; shift 2;; --dry-run) DRY=1; shift;;
    --workspace) WS=$2; shift 2;; --port) PORT=$2; shift 2;;
    --botversion) BOTVER=$2; LOGSUFFIX="-novia"; shift 2;;
    --resume-after) RESUME_AFTER=$2; shift 2;;  # skip cells already having $RUNS complete runs with dir timestamp >= this (e.g. 20261008-142344)
    *) echo "unknown arg $1"; exit 1;;
  esac
done

CONFIGS=(
  openjdk25:default oracle25:default
  temurin25:g1 temurin25:shenandoah temurin25:parallel temurin25:zgc
  graalvmce25:g1
)
PLAYER_LEVELS=(25 50 100 150)   # 200 probed 2026-10-01: server collapses (multi-sec ticks), bots kicked -> unmeasurable
WL=mixed

PLAN=()
for cfg in "${CONFIGS[@]}"; do
  for p in "${PLAYER_LEVELS[@]}"; do
    for r in $(seq 1 "$RUNS"); do
      h=$(echo "$SEED|r4|$cfg|$p|$r" | md5sum | cut -d' ' -f1)
      PLAN+=("$h $cfg $p $r")
    done
  done
done
IFS=$'\n' SORTED=($(printf '%s\n' "${PLAN[@]}" | sort)); unset IFS
TOTAL=${#SORTED[@]}

LOG="$ROOT/runs/scaling$LOGSUFFIX.log"
mkdir -p "$ROOT/runs"
[[ $DRY -eq 0 ]] && echo "# scaling start $(date -Is) seed=$SEED total=$TOTAL combos=7 levels=${PLAYER_LEVELS[*]} reps=$RUNS warmup=600 measure=600 resume_after=$RESUME_AFTER" >> "$LOG"

# count completed runs for a cell: dir ts >= RESUME_AFTER and measurement window finished
declare -A LAUNCHED=()
cell_done() {
  local rt=$1 gc=$2 p=$3 d n=0
  for d in "$ROOT"/runs/*-"$rt-$gc-$WL-p$p-$WS"; do
    [[ -d $d ]] || continue
    [[ ${d##*/} > "$RESUME_AFTER" || ${d##*/} == "$RESUME_AFTER"* ]] || continue
    grep -q "measurement window end" "$d/markers.log" 2>/dev/null && n=$((n+1))
  done
  echo $n
}

i=0
for line in "${SORTED[@]}"; do
  read -r _ cfg p r <<<"$line"
  runtime=${cfg%%:*}; gc=${cfg#*:}
  i=$((i+1))
  if [[ -n $RESUME_AFTER ]]; then
    key="$cfg-$p"; have=$(cell_done "$runtime" "$gc" "$p"); done_n=$((have + ${LAUNCHED[$key]:-0}))
    if [[ $done_n -ge $RUNS ]]; then
      [[ $DRY -eq 1 ]] && echo "[$i/$TOTAL] $runtime $gc p$p rep$r SKIP ($have done)"
      [[ $DRY -eq 0 ]] && echo "[$i/$TOTAL] $(date -Is) $runtime $gc p$p rep$r SKIP ($have done)" >> "$LOG"
      continue
    fi
    LAUNCHED[$key]=$(( ${LAUNCHED[$key]:-0} + 1 ))
  fi
  if [[ $DRY -eq 1 ]]; then echo "[$i/$TOTAL] $runtime $gc p$p rep$r"; continue; fi
  echo "[$i/$TOTAL] $(date -Is) $runtime $gc p$p rep$r START" >> "$LOG"
  if "$ROOT/scripts/run-min-bench.sh" --runtime "$runtime" --gc "$gc" --workload "$WL" \
       --players "$p" --warmup 600 --measure 600 --seed "$SEED" --heap 16G --botversion "$BOTVER" \
       --workspace "$ROOT/workspaces/$WS" --port "$PORT" \
       --cores 0-7 --botcores 8-15 >> "$LOG" 2>&1; then
    echo "[$i/$TOTAL] $runtime $gc p$p rep$r DONE" >> "$LOG"
  else
    echo "[$i/$TOTAL] $runtime $gc p$p rep$r FAILED" >> "$LOG"
  fi
done
echo "# scaling end $(date -Is)" >> "$LOG"
