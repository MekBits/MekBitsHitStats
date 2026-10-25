#!/usr/bin/env bash
# Syntax check (luac 5.1) and harness, in a throwaway Alpine container with Lua 5.1.
# usage: test/run.sh        (from anywhere; mounts the addon directory read-only)
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MSYS_NO_PATHCONV=1 docker run --rm -v "$dir:/addon:ro" -w /addon alpine:3.20 sh -c '
  apk add --no-cache lua5.1 >/dev/null
  lua5.1 -v
  for f in Data.lua Calc.lua UI.lua test/mocks.lua test/run.lua test/dbc_expected.lua; do luac5.1 -p "$f" && echo "luac -p ok: $f"; done
  lua5.1 test/run.lua'
