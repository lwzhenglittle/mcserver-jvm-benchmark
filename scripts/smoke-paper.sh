#!/usr/bin/env bash
# smoke-paper.sh — start Paper 26.2 on each runtime with its determined GC config.
# Usage: smoke-paper.sh [runtime ...]   (default: all from config/jdks.yaml order)
# Writes smoke/<runtime>.log; prints per-runtime PASS/FAIL summary.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAR="$ROOT/paper-26.2-129.jar"
SDKMAN_JAVA_DIR="$HOME/.sdkman/candidates/java"
mkdir -p "$ROOT/smoke"

# runtime|sdkman_id|gcflags
ALL=(
  "temurin25|25.0.4-tem|-XX:+UseG1GC"
  "corretto25|25.0.4-amzn|-XX:+UseG1GC"
  "microsoft25|25.0.4+1-ms|-XX:+UseG1GC"
  "oracle25|25.0.4-oracle|-XX:+UseG1GC"
  "zulu25|25.0.4+1.1-zulu|-XX:+UseG1GC"
  "liberica25|25.0.4+1.1-librca|-XX:+UseG1GC"
  "sapmachine25|25.0.4+1-sapmchn|-XX:+UseG1GC"
  "graalvmce25|25.3.4+1.r25-graalce|-XX:+UseG1GC"
  "graalvmoracle25|25.0.4-graal|-XX:+UseG1GC"
  "semeru25|25.0.4-sem|-Xgcpolicy:gencon"
)

cd "$ROOT"
for entry in "${ALL[@]}"; do
  IFS='|' read -r key id gcflag <<<"$entry"
  if [[ $# -gt 0 ]]; then
    skip=1
    for want in "$@"; do [[ "$want" == "$key" ]] && skip=0; done
    [[ $skip -eq 1 ]] && continue
  fi
  JAVA="$SDKMAN_JAVA_DIR/$id/bin/java"
  LOG="$ROOT/smoke/$key.log"
  echo "=== $key ($id $gcflag) ==="
  ( sleep 45; echo stop ) | timeout 150 "$JAVA" -Xms8G -Xmx8G $gcflag -jar "$JAR" nogui >"$LOG" 2>&1
  done_line=$(grep -o "Done ([^)]*)!" "$LOG" | head -1)
  if [[ -n "$done_line" ]]; then
    echo "PASS $key $done_line"
  else
    echo "FAIL $key"
    grep -m3 -Ei "error|exception|unsupported|requires" "$LOG" | sed 's/^/    /'
  fi
done
