#!/usr/bin/env bash
# Builds all offline packs in parallel shards. Run from repo root. Requires `godot` (4.3) on PATH.
set -euo pipefail
SHARDS=${SHARDS:-8}
run() { godot --headless --path . -s tools/build_packs.gd -- "$@"; }
build() { # size tier count
  for k in $(seq 0 $((SHARDS-1))); do run size=$1 tier=$2 count=$3 shard=$k shards=$SHARDS & done; wait
  run merge size=$1 tier=$2 shards=$SHARDS
}
build 9 4 300
build 9 3 300
build 9 2 300
build 9 1 300
# Runtime-fallback packs for 4x4/6x6 (200 per size)
build 4 1 200
build 6 1 100
build 6 2 100
