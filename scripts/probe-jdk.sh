#!/usr/bin/env bash
# probe-jdk.sh — collect version/VM settings/GC capabilities for all Java 25 runtimes.
# Output: probe/<runtime>/{version.txt,vmsettings.txt} and probe/capabilities.json
set -u
SDKMAN_JAVA_DIR="$HOME/.sdkman/candidates/java"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/probe"
mkdir -p "$OUT_DIR"

# runtime_key|sdkman_id|family
RUNTIMES=(
  "temurin25|25.0.4-tem|hotspot"
  "corretto25|25.0.4-amzn|hotspot"
  "microsoft25|25.0.4+1-ms|hotspot"
  "oracle25|25.0.4-oracle|hotspot"
  "zulu25|25.0.4+1.1-zulu|hotspot"
  "liberica25|25.0.4+1.1-librca|hotspot"
  "sapmachine25|25.0.4+1-sapmchn|hotspot"
  "graalvmce25|25.3.4+1.r25-graalce|graalvm"
  "graalvmoracle25|25.0.4-graal|graalvm"
  "semeru25|25.0.4-sem|openj9"
)

HOTSPOT_GCS=("G1:-XX:+UseG1GC" "ZGC:-XX:+UseZGC" "Parallel:-XX:+UseParallelGC" "Shenandoah:-XX:+UseShenandoahGC" "Serial:-XX:+UseSerialGC")
OPENJ9_GCS=("gencon:-Xgcpolicy:gencon" "balanced:-Xgcpolicy:balanced" "optavgpause:-Xgcpolicy:optavgpause" "optthruput:-Xgcpolicy:optthruput")

CAPS="{"
first_rt=1
for entry in "${RUNTIMES[@]}"; do
  IFS='|' read -r key id family <<<"$entry"
  JAVA="$SDKMAN_JAVA_DIR/$id/bin/java"
  rt_dir="$OUT_DIR/$key"
  mkdir -p "$rt_dir"
  if [[ ! -x "$JAVA" ]]; then
    echo "MISSING $key ($id)"
    continue
  fi

  "$JAVA" -version >"$rt_dir/version.txt" 2>&1
  "$JAVA" -XshowSettings:vm -version >"$rt_dir/vmsettings.txt" 2>&1

  gcs=()
  if [[ "$family" == "openj9" ]]; then
    probes=("${OPENJ9_GCS[@]}")
  else
    probes=("${HOTSPOT_GCS[@]}")
  fi
  for p in "${probes[@]}"; do
    name="${p%%:*}"; flag="${p#*:}"
    if "$JAVA" $flag -version >/dev/null 2>&1; then
      gcs+=("\"$name\"")
    else
      echo "  $key: GC $name NOT accepted"
    fi
  done

  [[ $first_rt -eq 0 ]] && CAPS+=","
  first_rt=0
  CAPS+=$'\n'"  \"$key\": {\"sdkman_id\": \"$id\", \"family\": \"$family\", \"gcs\": [$(IFS=,; echo "${gcs[*]}")]}"

  jit="c2"
  grep -qi graalvm "$rt_dir/version.txt" && jit="graal"
  [[ "$family" == "openj9" ]] && jit="openj9"
  echo "OK $key jit=$jit gcs=[$(IFS=,; echo "${gcs[*]}")]"
done
CAPS+=$'\n'"}"
echo "$CAPS" > "$OUT_DIR/capabilities.json"
echo "written: $OUT_DIR/capabilities.json"
