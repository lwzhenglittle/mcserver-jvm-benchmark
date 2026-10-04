#!/usr/bin/env bash
# run-min-bench.sh — single benchmark run: 1 runtime, 1 GC, 1 workload, N bots.
# Pipeline: restore golden world -> start server -> wait ready -> bots+warmup ->
#           measure (TickLogger per-tick + spark + /proc) -> stop -> archive.
# Usage: run-min-bench.sh [--runtime temurin25] [--gc g1] [--workload mixed]
#        [--players 10] [--warmup 600] [--measure 900] [--seed 20260930]
#        [--workspace <dir>] [--port 25565] [--cores 0-7] [--botcores 8-15]
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$HOME/.sdkman/candidates/java"

RUNTIME=temurin25; GC=g1; PLAYERS=10; WARMUP=600; MEASURE=900; SEED=20260930
WORKLOAD=mixed; WS="$ROOT"; PORT=25565; CORES="0-7"; BOTCORES="8-15"; HEAP=8G
while [[ $# -gt 1 ]]; do
  case "$1" in
    --runtime) RUNTIME=$2;; --gc) GC=$2;; --players) PLAYERS=$2;; --workload) WORKLOAD=$2;;
    --warmup) WARMUP=$2;; --measure) MEASURE=$2;; --seed) SEED=$2;;
    --workspace) WS=$2;; --port) PORT=$2;; --cores) CORES=$2;; --botcores) BOTCORES=$2;; --heap) HEAP=$2;;
    *) echo "unknown arg $1"; exit 1;;
  esac
  shift 2
done

# resolve runtime -> java home + gc flag (kept in sync with config/jdks.yaml)
declare -A HOMES=(
  [temurin25]=25.0.4-tem [corretto25]=25.0.4-amzn [microsoft25]=25.0.4+1-ms
  [oracle25]=25.0.4-oracle [zulu25]=25.0.4+1.1-zulu [liberica25]=25.0.4+1.1-librca
  [sapmachine25]=25.0.4+1-sapmchn [graalvmce25]=25.3.4+1.r25-graalce
  [graalvmoracle25]=25.0.4-graal [semeru25]=25.0.4-sem [openjdk25]=25.0.2-open
)
declare -A FAMILY=(
  [temurin25]=hotspot [corretto25]=hotspot [microsoft25]=hotspot
  [oracle25]=hotspot [zulu25]=hotspot [liberica25]=hotspot
  [sapmachine25]=hotspot [graalvmce25]=hotspot [graalvmoracle25]=hotspot
  [semeru25]=openj9 [openjdk25]=hotspot
)
HOME_ID=${HOMES[$RUNTIME]:-}; [[ -z "$HOME_ID" ]] && { echo "unknown runtime $RUNTIME"; exit 1; }
JAVA="$SDK/$HOME_ID/bin/java"

# workspace must be absolute: we cd into it later, relative paths would double
WS=$(cd "$WS" && pwd)

if [[ ${FAMILY[$RUNTIME]} == openj9 ]]; then
  GCFLAG="-Xgcpolicy:$GC"
else
  case "$GC" in
    g1) GCFLAG="-XX:+UseG1GC";; zgc) GCFLAG="-XX:+UseZGC";;
    parallel) GCFLAG="-XX:+UseParallelGC";; shenandoah) GCFLAG="-XX:+UseShenandoahGC";;
    serial) GCFLAG="-XX:+UseSerialGC";;
    default) GCFLAG="";;   # out-of-box baseline: JVM picks its own default GC
    *) echo "unknown gc $GC"; exit 1;;
  esac
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-${RUNTIME}-${GC}-${WORKLOAD}-p${PLAYERS}-$(basename "$WS")"
RD="$ROOT/runs/$RUN_ID"
mkdir -p "$RD"
if [[ ${FAMILY[$RUNTIME]} == openj9 ]]; then
  GCLOG_FLAG=(-Xverbosegclog:"$RD/gc.log")
else
  GCLOG_FLAG=(-Xlog:gc*:file="$RD/gc.log:time,uptime,level,tags")
fi

cd "$WS"

# --- 1. restore golden world into workspace ---
T_RS=$(date +%s)
rsync -a --delete "$ROOT/worlds/golden/world/" "$WS/world/"
WORLD_RESTORE_S=$(( $(date +%s) - T_RS ))

# --- 2. start server ---
"$JAVA" -version > "$RD/java-version.txt" 2>&1
CMDFIFO="$RD/cmd.fifo"; mkfifo "$CMDFIFO"
exec 9<>"$CMDFIFO"   # keep fifo writer open for the whole run
taskset -c "$CORES" "$JAVA" -Xms$HEAP -Xmx$HEAP $GCFLAG "${GCLOG_FLAG[@]}" \
  -Dticklogger.out="$RD/mspt.csv" \
  -jar "$ROOT/paper-26.2-129.jar" --port "$PORT" nogui < "$CMDFIFO" > "$RD/server.log" 2>&1 &
SPID=$!

# wait for ready (max 180 s)
T_BOOT=$(date +%s)
for _ in $(seq 1 180); do
  grep -q "Done (" "$RD/server.log" && break
  kill -0 $SPID 2>/dev/null || { echo "server died, see $RD/server.log"; exit 1; }
  sleep 1
done
grep -q "Done (" "$RD/server.log" || { echo "server not ready in 180s"; kill $SPID; exit 1; }
STARTUP_S=$(( $(date +%s) - T_BOOT ))
echo "server ready in ${STARTUP_S}s (pid $SPID, port $PORT, cores $CORES)"
# SPID may be a wrapper subshell that did not exec java; resolve real pid by port
JPID=$(pgrep -f "paper-26.2-129.jar --port $PORT nogui" | head -1)
[[ -n "${JPID:-}" && "$JPID" != "$SPID" ]] && { echo "resolved java pid $JPID (was $SPID)"; SPID=$JPID; }

# --- 3. collectors ---
"$ROOT/scripts/proc-collect.sh" $SPID 5 "$RD/proc.txt" &
CPID=$!

# --- 4. bots on immediately (warmup must be under load; JIT warms on real work) ---
# shard bots into <=50-per-node-process (single node proc bottlenecks >50 bots)
SHARDS=$(( (PLAYERS + 49) / 50 ))
BPIDS=()
for s in $(seq 0 $((SHARDS-1))); do
  off=$((s*50)); cnt=$((PLAYERS - off)); (( cnt > 50 )) && cnt=50
  # join ramp: >100 players -> global ~1 bot/s to avoid login-storm keepalive kicks
  STAGGER=500; (( PLAYERS > 100 )) && STAGGER=$((SHARDS*1000))
  ( cd "$ROOT/bots" && taskset -c "$BOTCORES" node bot.js --count "$cnt" --port "$PORT" \
      --seed "$SEED" --mode "$WORKLOAD" --offset "$off" --stagger "$STAGGER" ) > "$RD/bots.$s.log" 2>&1 &
  BPIDS+=($!)
done
echo "--- cold start boundary $(date -Is) ---" >> "$RD/markers.log"
( sleep 300; echo "--- cold/warmup boundary $(date -Is) ---" >> "$RD/markers.log" ) &

# --- 5. warmup under load ---
sleep "$WARMUP"
echo "spark tps" >&9; sleep 2
echo "--- measurement window start $(date -Is) ---" >> "$RD/markers.log"

# --- 6. measurement ---
echo "spark tickmonitor --threshold-tick 25 --without-gc" >&9
ELAPSED=0
while [[ $ELAPSED -lt $MEASURE ]]; do
  sleep 60; ELAPSED=$((ELAPSED+60))
  if [[ $WORKLOAD == explore-existing ]]; then
    echo "spreadplayers 0 0 50 400 false @a" >&9   # keep bots inside pregen area
  fi
  echo "spark tps" >&9   # TPS + tick duration summary lands in server.log
done
echo "--- measurement window end $(date -Is) ---" >> "$RD/markers.log"

# --- 7. stop ---
for b in "${BPIDS[@]}"; do kill $b 2>/dev/null; done
echo "stop" >&9
for _ in $(seq 1 60); do kill -0 $SPID 2>/dev/null || break; sleep 1; done
kill -0 $SPID 2>/dev/null && kill -9 $SPID
kill $CPID 2>/dev/null
exec 9>&-

# --- 8. metadata ---
WCSUM=$(cd "$ROOT/worlds/golden" && find world -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)
cat > "$RD/metadata.json" <<EOF
{
  "run_id": "$RUN_ID",
  "runtime": "$RUNTIME",
  "java_home_id": "$HOME_ID",
  "gc": "$GC",
  "heap": "$HEAP",
  "players": $PLAYERS,
  "seed": $SEED,
  "workload": "$WORKLOAD",
  "warmup_s": $WARMUP,
  "measure_s": $MEASURE,
  "startup_s": $STARTUP_S,
  "world_restore_s": $WORLD_RESTORE_S,
  "world_checksum": "$WCSUM",
  "paper_jar": "paper-26.2-129.jar",
  "paper_sha256": "b1d8f6bfa1b6101fa8e947b53041cb3bdf5540e7b83b6547ca19ba7edefeb083",
  "plugins": ["ViaVersion-5.12.1-SNAPSHOT+1080", "ViaBackwards-5.12.1-SNAPSHOT+643", "Chunky-Bukkit-1.5.3", "TickLogger-1.0"],
  "bot_client_version": "26.1 (via ViaBackwards, server 26.2 protocol 776)",
  "port": $PORT,
  "workspace": "$(basename "$WS")",
  "cores": "$CORES",
  "botcores": "$BOTCORES",
  "os": "$(uname -sr)",
  "cpu": "$(LANG=C lscpu | grep 'Model name' | cut -d: -f2 | xargs)",
  "date": "$(date -Is)"
}
EOF
echo "archived: $RD"
