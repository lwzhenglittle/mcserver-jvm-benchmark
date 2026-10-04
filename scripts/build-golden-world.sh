#!/usr/bin/env bash
# build-golden-world.sh — build golden world v2:
#   1. pregenerate 512-block radius (chunky) around spawn
#   2. construct entity-redstone area at (256..312, 256..312):
#      observer clocks + repeater loops + piston array + persistent mob pen
#   3. save, snapshot to worlds/golden/world, print checksum
# Run once; result must be treated as immutable afterwards.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAVA="$HOME/.sdkman/candidates/java/25.0.4-tem/bin/java"
cd "$ROOT"

rm -rf world world_nether world_the_end   # rebuild from scratch
FIFO=/tmp/golden-build.fifo; rm -f "$FIFO"; mkfifo "$FIFO"
exec 9<>"$FIFO"
"$JAVA" -Xms4G -Xmx4G -XX:+UseG1GC -jar paper-26.2-129.jar nogui < "$FIFO" > /tmp/golden-build.log 2>&1 &
SPID=$!
trap 'kill $SPID 2>/dev/null' EXIT

for _ in $(seq 1 180); do grep -q "Done (" /tmp/golden-build.log && break; sleep 1; done
grep -q "Done (" /tmp/golden-build.log || { echo "server failed to start"; exit 1; }
echo "server up, pregenerating..."

echo "chunky center 0 0 world" >&9
echo "chunky radius 512" >&9
echo "chunky start" >&9
for _ in $(seq 1 600); do
  grep -q "Task finished\|finished.*100" /tmp/golden-build.log && break
  sleep 5
done
grep -i "chunky" /tmp/golden-build.log | tail -2

echo "constructing entity-redstone area..."
# chunks must be LOADED before setblock/fill, else "That position is not loaded"
echo "forceload add 240 240 320 320" >&9
sleep 5
# flatten platform 240..320 (fill limit 32768 blocks -> 4-layer slices)
for y in $(seq 61 4 100); do
  echo "fill 240 $y 240 320 $((y+3)) 320 minecraft:air" >&9
done
echo "fill 240 60 240 320 60 320 minecraft:stone" >&9
# observer clock grid (5x5 pairs = 50 observers, constant block updates)
for x in $(seq 244 4 316); do for z in $(seq 244 4 316); do
  echo "setblock $x 61 $z minecraft:observer[facing=east]" >&9
  echo "setblock $((x+1)) 61 $z minecraft:observer[facing=west]" >&9
done; done
# repeater loops (4x)
for z in 246 262 278 294; do
  echo "fill 250 61 $z 269 61 $z minecraft:repeater" >&9

  echo "fill 251 61 $z 269 61 $z minecraft:redstone_wire" >&9
  echo "fill 250 61 $((z+1)) 269 61 $((z+1)) minecraft:redstone_wire" >&9
done
# piston array driven by a clock (20 pistons)
for x in $(seq 244 2 282); do
  echo "setblock $x 61 310 minecraft:piston[facing=up]" >&9
done
# mob pen: 150 persistent sheep in a fenced box
echo "fill 285 60 244 315 64 264 minecraft:air" >&9
echo "fill 285 60 244 315 60 264 minecraft:grass_block" >&9
echo "fill 285 61 244 315 61 244 minecraft:oak_fence" >&9
echo "fill 285 61 264 315 61 264 minecraft:oak_fence" >&9
echo "fill 285 61 244 285 61 264 minecraft:oak_fence" >&9
echo "fill 315 61 244 315 61 264 minecraft:oak_fence" >&9
for i in $(seq 1 150); do
  x=$((287 + RANDOM % 26)); z=$((246 + RANDOM % 16))
  echo "summon minecraft:sheep $x 62 $z {PersistenceRequired:1b}" >&9
done
# self-check: abort instead of snapshotting a broken golden world
echo "execute if block 244 61 244 minecraft:observer run say CHECK-OBSERVER-OK" >&9
echo "execute if block 260 61 246 minecraft:redstone_wire run say CHECK-WIRE-OK" >&9
echo "execute if block 244 61 310 minecraft:piston run say CHECK-PISTON-OK" >&9
echo "execute if block 285 61 244 minecraft:oak_fence run say CHECK-FENCE-OK" >&9
sleep 5
for c in OBSERVER WIRE PISTON FENCE; do
  grep -q "CHECK-$c-OK" /tmp/golden-build.log || { echo "CONSTRUCTION CHECK FAILED: $c"; exit 1; }
done
echo "construction self-checks passed"
sleep 10
echo "save-all" >&9
sleep 10
echo "stop" >&9
for _ in $(seq 1 60); do kill -0 $SPID 2>/dev/null || break; sleep 1; done
exec 9>&-

# snapshot
rm -rf "$ROOT/worlds/golden/world"
mkdir -p "$ROOT/worlds/golden"
cp -a "$ROOT/world" "$ROOT/worlds/golden/world"
CSUM=$(cd "$ROOT/worlds/golden" && find world -type f | sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
echo "golden v2 checksum: $CSUM"
du -sh "$ROOT/worlds/golden/world"
grep -ci "unknown or incomplete command\|error" /tmp/golden-build.log || true
