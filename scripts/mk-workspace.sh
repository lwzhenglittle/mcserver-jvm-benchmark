#!/usr/bin/env bash
# mk-workspace.sh — create an isolated server workspace for parallel matrix lanes.
# Usage: mk-workspace.sh <id> <port>
# Copies configs/plugins (small), hardlinks paperclip cache (big), no world
# (run-min-bench.sh restores golden world into the workspace per run).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID=$1; PORT=$2
WS="$ROOT/workspaces/ws$ID"
mkdir -p "$WS"

# config copies (port differs per lane); sources live in config/server/ and config/
for f in server.properties spigot.yml bukkit.yml eula.txt; do
  cp "$ROOT/config/server/$f" "$WS/$f"
done
sed -i "s/^server-port=.*/server-port=$PORT/" "$WS/server.properties"
grep -q "^server-port=" "$WS/server.properties" || echo "server-port=$PORT" >> "$WS/server.properties"
cp -r "$ROOT/config" "$WS/config"
rm -rf "$WS/plugins"; cp -r "$ROOT/plugins" "$WS/plugins"

# paperclip runtime dirs: hardlink (read-only at runtime)
for d in cache libraries versions; do
  rm -rf "$WS/$d"; cp -al "$ROOT/$d" "$WS/$d"
done
echo "workspace ready: $WS (port $PORT)"
