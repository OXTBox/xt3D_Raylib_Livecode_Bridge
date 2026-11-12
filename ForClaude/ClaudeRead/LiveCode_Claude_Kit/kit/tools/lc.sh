#!/usr/bin/env bash
# lc.sh - talk to the running LiveCode IDE through LIB_DEVSERVER.
#
#   tools/lc.sh ping
#   tools/lc.sh list                         stack + cards that have scripts
#   tools/lc.sh pull-all                     every script -> scripts/ (run before editing!)
#   tools/lc.sh pull <target|file>           one script from LiveCode -> its file
#   tools/lc.sh push <file>                  file -> LiveCode (prints OK or COMPILE ERROR)
#   tools/lc.sh run  '<statements>'          run in the stack script ("-" = read stdin)
#   tools/lc.sh eval '<expression>'
#   tools/lc.sh report [filter]              Report.Compact, e.g. report 'Play.*'
#   tools/lc.sh lib <NAME>                   Lib.Load NAME
#   tools/lc.sh llm '<prompt>'               ask LM Studio directly (no LiveCode)
#
# Targets and files:  stack       <-> scripts/stack.livecodescript
#                     card:<name> <-> scripts/cards/<name>.livecodescript
# Token: .lc_devtoken next to the stack file (line 1 token, line 2 port).
#   Override with LC_TOKEN_FILE=path, or LC_TOKEN / LC_PORT.

set -euo pipefail
cd "$(dirname "$0")/.."

TOKEN_FILE="${LC_TOKEN_FILE:-.lc_devtoken}"
if [[ -z "${LC_TOKEN:-}" ]]; then
  [[ -f "$TOKEN_FILE" ]] || { echo "No $TOKEN_FILE: start DevServer in LiveCode (DevServer.Start)" >&2; exit 2; }
  LC_TOKEN="$(sed -n 1p "$TOKEN_FILE" | tr -d '\r')"
  LC_PORT="${LC_PORT:-$(sed -n 2p "$TOKEN_FILE" | tr -d '\r')}"
fi
LC_PORT="${LC_PORT:-8765}"
BASE="http://127.0.0.1:$LC_PORT"
LLM_URL="${LLM_URL:-http://localhost:1234}"

urlenc() {
  local s="$1" out="" c i
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in [a-zA-Z0-9.~_-]) out+="$c" ;; *) out+=$(printf '%%%02X' "'$c") ;; esac
  done
  printf '%s' "$out"
}

# req METHOD PATH [BODYFILE]  -> prints the answer, fails on non-200
req() {
  local tmp code
  tmp="$(mktemp)"
  if [[ -n "${3:-}" ]]; then
    code=$(curl -sS -o "$tmp" -w '%{http_code}' -X "$1" -H "X-Token: $LC_TOKEN" -H "Expect:" \
      -H "Content-Type: text/plain; charset=utf-8" --data-binary @"$3" "$BASE$2") || { rm -f "$tmp"; echo "LiveCode not answering on $BASE" >&2; exit 3; }
  else
    code=$(curl -sS -o "$tmp" -w '%{http_code}' -X "$1" -H "X-Token: $LC_TOKEN" "$BASE$2") \
      || { rm -f "$tmp"; echo "LiveCode not answering on $BASE" >&2; exit 3; }
  fi
  cat "$tmp"; echo
  rm -f "$tmp"
  [[ "$code" == "200" ]] || { echo "[HTTP $code]" >&2; return 1; }
}

target_to_file() {
  case "$1" in
    stack) echo "scripts/stack.livecodescript" ;;
    card:*) echo "scripts/cards/${1#card:}.livecodescript" ;;
    *) echo "bad target: $1" >&2; exit 2 ;;
  esac
}
file_to_target() {
  local f="${1#./}"
  case "$f" in
    scripts/stack.livecodescript) echo "stack" ;;
    scripts/cards/*.livecodescript) f="${f#scripts/cards/}"; echo "card:${f%.livecodescript}" ;;
    *) echo "not a script file: $1" >&2; exit 2 ;;
  esac
}

pull_one() {
  local target="$1" file
  file="$(target_to_file "$target")"
  mkdir -p "$(dirname "$file")"
  local tmp; tmp="$(mktemp)"
  curl -sS -f -H "X-Token: $LC_TOKEN" "$BASE/script?target=$(urlenc "$target")" -o "$tmp" \
    || { rm -f "$tmp"; echo "pull failed: $target" >&2; return 1; }
  mv "$tmp" "$file"
  echo "pulled $target -> $file"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  ping)   req GET /ping ;;
  list)   req GET /list ;;
  report) req GET "/report?filter=$(urlenc "${1:-}")" ;;
  lib)    req POST "/lib?name=$(urlenc "$1")" ;;
  pull)
    t="$1"; [[ "$t" == *.livecodescript ]] && t="$(file_to_target "$t")"
    pull_one "$t" ;;
  pull-all)
    tmp="$(mktemp)"; req GET /list > "$tmp"
    while IFS= read -r t; do t="${t%$'\r'}"; [[ -n "$t" ]] && pull_one "$t"; done < "$tmp"
    rm -f "$tmp" ;;
  push)
    f="$1"; t="$(file_to_target "$f")"
    req POST "/script?target=$(urlenc "$t")" "$f" ;;
  run|eval)
    tmp="$(mktemp)"
    if [[ "${1:-}" == "-" ]]; then cat > "$tmp"; else printf '%s' "$1" > "$tmp"; fi
    rc=0; req POST "/$cmd" "$tmp" || rc=$?; rm -f "$tmp"; exit $rc ;;
  llm)
    body=$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps({"model":"local-model","messages":[{"role":"user","content":sys.stdin.read()}],"max_tokens":600}))' 2>/dev/null) \
      || { echo "llm needs python3 (or call curl yourself)" >&2; exit 2; }
    curl -sS "$LLM_URL/v1/chat/completions" -H "Content-Type: application/json" -d "$body" ;;
  *) sed -n '2,18p' "$0"; exit 1 ;;
esac
