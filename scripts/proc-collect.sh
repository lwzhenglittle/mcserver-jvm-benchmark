#!/usr/bin/env bash
# proc-collect.sh — sample /proc metrics for a PID every N sec.
# Usage: proc-collect.sh <pid> <interval_sec> <outfile>
# Columns: epoch cpu_pct rss_kb vsz_kb threads minflt majflt ctxt_vol ctxt_nvol
# /proc/<pid>/stat parsing is comm-safe (comm may contain spaces/parens):
# strip everything up to the last ')', then fields shift by -2.
set -u
PID=$1; INT=${2:-5}; OUT=$3
CLK=$(getconf CLK_TCK); PGSZ=$(getconf PAGE_SIZE)

read_stat() {  # sets: MINFLT MAJFLT UTIME STIME THREADS VSZ RSS ; returns 1 if gone
  local line rest
  read -r line < "/proc/$1/stat" 2>/dev/null || return 1
  rest=${line##*) }
  set -- $rest
  # after comm removal: $1=state(f3) $8=minflt(f10) $10=majflt(f12)
  # $12=utime(f14) $13=stime(f15) $18=threads(f20) $21=vsize(f23) $22=rss(f24)
  MINFLT=$8; MAJFLT=${10}; UTIME=${12}; STIME=${13}; THREADS=${18}; VSZ=${21}; RSS=${22}
}

# initial read can race process exec; retry before giving up
read_stat "$PID" || { sleep 1; read_stat "$PID"; } || exit 1
UTIME0=$UTIME; STIME0=$STIME; T0=$(date +%s)
echo "#epoch cpu_pct rss_kb vsz_kb threads minflt majflt ctxt_vol ctxt_nvol" > "$OUT"
while kill -0 "$PID" 2>/dev/null; do
  sleep "$INT"
  read_stat "$PID" || { sleep 1; read_stat "$PID" || break; }
  T1=$(date +%s)
  DT=$((T1 - T0)); [[ $DT -le 0 ]] && DT=1
  CPU=$(awk -v u="$UTIME" -v s="$STIME" -v u0="$UTIME0" -v s0="$STIME0" -v dt="$DT" -v clk="$CLK" \
        'BEGIN{printf "%.1f", ((u+s-u0-s0)/clk)/dt*100}')
  CVOL=$(awk '/voluntary_ctxt_switches/{print $2; exit}' "/proc/$PID/status" 2>/dev/null)
  CNVOL=$(awk '/nonvoluntary_ctxt_switches/{print $2; exit}' "/proc/$PID/status" 2>/dev/null)
  echo "$T1 $CPU $((RSS*PGSZ/1024)) $((VSZ/1024)) $THREADS $MINFLT $MAJFLT ${CVOL:-0} ${CNVOL:-0}" >> "$OUT"
  UTIME0=$UTIME; STIME0=$STIME; T0=$T1
done
