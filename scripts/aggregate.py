#!/usr/bin/env python3
"""aggregate.py — scan runs/ and emit one CSV row per benchmark run.

Usage: python3 scripts/aggregate.py [runs_glob] > results/round2-runs.csv
Each run dir must contain metadata.json, markers.log, mspt.csv (TickLogger),
gc.log, proc.txt and bots.*.log (produced by scripts/run-min-bench.sh).
"""
import csv, glob, json, os, re, subprocess, sys
from datetime import datetime


runs_glob = sys.argv[1] if len(sys.argv) > 1 else 'runs/*'
PAUSE_MS = re.compile(r'Pause\b.*?([0-9.]+)ms')

def window(markers):
    txt = open(markers).read()
    f = lambda s: datetime.fromisoformat(s).timestamp() * 1000
    return (f(re.search(r'measurement window start (\S+)', txt).group(1)),
            f(re.search(r'measurement window end (\S+)', txt).group(1)))

def pct(v, q):
    v = sorted(v)
    return v[min(len(v) - 1, int(len(v) * q / 100))]

rows = []
for d in sorted(d for d in glob.glob(runs_glob) if os.path.isdir(d)):
    try:
        meta = json.load(open(f'{d}/metadata.json'))
        ws, we = window(f'{d}/markers.log')
        ticks = []
        with open(f'{d}/mspt.csv') as fh:
            r = csv.reader(fh); next(r)
            for row in r:
                if ws <= int(row[1]) <= we:
                    ticks.append(float(row[2]))
        pauses = [float(m.group(1)) for line in open(f'{d}/gc.log', errors='ignore')
                  for m in [PAUSE_MS.search(line)] if m]
        cpu = rss = 0.0
        for line in open(f'{d}/proc.txt'):
            p = line.split()
            if len(p) >= 3 and p[0].lstrip('-').isdigit():
                cpu = max(cpu, float(p[1])); rss = max(rss, float(p[2]))
        kicks = subprocess.run(['bash', '-c',
            f'grep -h -c -E "keepAliveError|DIED" {d}/bots*.log 2>/dev/null | paste -sd+ | bc'],
            capture_output=True, text=True).stdout.strip() or '0'
        n = len(ticks); s = sorted(ticks)
        rows.append(dict(
            run_id=meta['run_id'], runtime=meta['runtime'], gc=meta['gc'],
            heap=meta['heap'], workload=meta['workload'], players=meta['players'],
            seed=meta['seed'], warmup_s=meta['warmup_s'], measure_s=meta['measure_s'],
            ticks=n, tps=round(n / meta['measure_s'], 2),
            mean_mspt=round(sum(ticks) / n, 3), p50_mspt=pct(s, 50), p95_mspt=pct(s, 95),
            p99_mspt=pct(s, 99), max_mspt=round(s[-1], 1),
            over50_pct=round(100 * sum(x > 50 for x in ticks) / n, 3),
            gc_pauses=len(pauses),
            gc_mean_ms=round(sum(pauses) / len(pauses), 2) if pauses else '',
            gc_max_ms=max(pauses) if pauses else '',
            rss_peak_mb=round(rss / 1024), cpu_peak_pct=round(cpu, 1), bot_kicks=int(kicks),
            date=meta['date'][:19]))
    except (FileNotFoundError, KeyError, json.JSONDecodeError, AttributeError) as e:
        print(f'skip {d}: {e}', file=sys.stderr)

w = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
w.writeheader(); w.writerows(rows)
