#!/usr/bin/env python3
"""compare-novia.py — diff the Via (ws0) and native-26.2 no-Via (wsN) round-2 matrices.

Usage: python3 scripts/compare-novia.py
Reads results/round2-runs.csv (Via) and results/round2-novia-runs.csv (no-Via,
generate with: python3 scripts/aggregate.py 'runs/202610*-wsN').
Emits per-cell deltas and flags rank reversals / overload-point shifts.
"""
import csv, statistics, sys, collections

def load(path):
    cells = collections.defaultdict(list)
    with open(path) as f:
        for r in csv.DictReader(f):
            cells[(r['runtime'], r['gc'], int(r['players']))].append(r)
    out = {}
    for k, rows in cells.items():
        out[k] = {m: statistics.median(float(r[m]) for r in rows) for m in
                  ('mean_mspt', 'p95_mspt', 'p99_mspt', 'max_mspt', 'tps')}
    return out

import os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
via = load(os.path.join(ROOT, 'results/round2-runs.csv'))
novia = load(os.path.join(ROOT, 'results/round2-novia-runs.csv'))


LEVELS = [25, 50, 100, 150]
combos = sorted({(k[0], k[1]) for k in novia})
missing = [k for k in via if k not in novia] + [k for k in novia if k not in via]
if missing:
    print(f'WARN incomplete cells: {missing}', file=sys.stderr)

for metric in ('mean_mspt', 'p99_mspt', 'tps'):
    print(f'\n== {metric}: noVia vs Via (delta %) ==')
    print(f"{'combo':<26}" + ''.join(f'p{p:>3}'.rjust(16) for p in LEVELS))
    for rt, gc in combos:
        row = f'{rt}+{gc:<12}'
        for p in LEVELS:
            a, b = via.get((rt, gc, p)), novia.get((rt, gc, p))
            if a and b:
                d = 100 * (b[metric] - a[metric]) / a[metric]
                row += f"{b[metric]:7.2f}({d:+5.1f}%)".rjust(16)
            else:
                row += '-'.rjust(16)
        print(row)

# rank reversal check at each level on mean_mspt
print('\n== rank by mean_mspt (lower=better): Via -> noVia ==')
for p in LEVELS:
    rv = sorted((c for c in combos if (c[0], c[1], p) in via), key=lambda c: via[(c[0], c[1], p)]['mean_mspt'])
    rn = sorted((c for c in combos if (c[0], c[1], p) in novia), key=lambda c: novia[(c[0], c[1], p)]['mean_mspt'])
    rv = [f'{a}+{b}' for a, b in rv]; rn = [f'{a}+{b}' for a, b in rn]
    flag = '' if rv == rn else '  <-- RANK CHANGE'
    print(f'p{p}: {" > ".join(rv)}\n      {" > ".join(rn)}{flag}')

# overload health: tps<20 or kicks>0
print('\n== overload / health flags ==')
for k in sorted(novia):
    n = novia[k]
    if n['tps'] < 19.9 or n['kicks'] > 0:
        v = via.get(k)
        print(f'{k}: noVia tps={n["tps"]:.1f} kicks={n["kicks"]} | Via tps={v["tps"]:.1f} kicks={v["kicks"] if v else "?"}')
