#!/usr/bin/env bash
# xt3d_dev.sh - talk to the running LiveCode IDE through the xt3d dev server.
#
#   tools/xt3d_dev.sh ping
#   tools/xt3d_dev.sh run  '<statements>'      in the test bench's script ("-" = read stdin)
#   tools/xt3d_dev.sh runs '<statements>'      in the dev server's own script
#   tools/xt3d_dev.sh eval '<expression>'      value, evaluated in the test bench
#   tools/xt3d_dev.sh reload [windows-path]    close and reopen the bench from its file
#   tools/xt3d_dev.sh snap [windows-path]      PNG of the bench (default C:/xt3d/snap.png)
#   tools/xt3d_dev.sh checks                   press "Run checks", print bench_checks.txt
#   tools/xt3d_dev.sh errors [N]               last N entries of C:/xt3d/livecode_errors.txt
#                                              (reads the file; works without the server)
#
# The server listens on Windows' 127.0.0.1, which WSL2 cannot reach directly, so the
# requests go through Windows' own curl.exe. Token and port come from
# C:\xt3d\.xt3d_devtoken (written by DevServer.Start).

set -euo pipefail
ERRFILE=/mnt/c/xt3d/livecode_errors.txt
if [[ "${1:-}" == errors ]]; then
  [[ -f "$ERRFILE" ]] || { echo "no error log yet ($ERRFILE)"; exit 0; }
  tr -d '\r' < "$ERRFILE" | awk -v n="${2:-5}" '/^==== /{c++} {e[c]=e[c] $0 "\n"} END{for(i=(c-n+1>1?c-n+1:1);i<=c;i++) printf "%s", e[i]}'
  exit 0
fi
TOKEN_FILE="${XT3D_TOKEN_FILE:-/mnt/c/xt3d/.xt3d_devtoken}"
[[ -f "$TOKEN_FILE" ]] || { echo "No $TOKEN_FILE: tick 'Dev server' in the test bench" >&2; exit 2; }
TOKEN="$(sed -n 1p "$TOKEN_FILE" | tr -d '\r')"
PORT="$(sed -n 2p "$TOKEN_FILE" | tr -d '\r')"
BASE="http://127.0.0.1:${PORT:-8766}"

urlenc() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }

# req METHOD PATH [body on stdin when METHOD is POST]
req() {
  local out code
  if [[ "$1" == POST ]]; then
    out="$(curl.exe -sS -w '\n%{http_code}' -X POST -H "X-Token: $TOKEN" -H "Expect:" \
           -H "Content-Type: text/plain; charset=utf-8" --data-binary @- "$BASE$2")" \
      || { echo "LiveCode not answering on $BASE" >&2; exit 3; }
  else
    out="$(curl.exe -sS -w '\n%{http_code}' -H "X-Token: $TOKEN" "$BASE$2")" \
      || { echo "LiveCode not answering on $BASE" >&2; exit 3; }
  fi
  code="${out##*$'\n'}"
  printf '%s\n' "${out%$'\n'*}" | tr -d '\r'
  [[ "$code" == 200 ]] || { echo "[HTTP $code]" >&2; return 1; }
}

body() { if [[ "${1:-}" == "-" ]]; then cat; else printf '%s' "$1"; fi; }

cmd="${1:-}"; shift || true
case "$cmd" in
  ping)   req GET /ping ;;
  run)    body "$1" | req POST /run ;;
  runs)   body "$1" | req POST "/run?in=server" ;;
  eval)   body "$1" | req POST /eval ;;
  reload) if [[ -n "${1:-}" ]]; then printf '' | req POST "/reload?path=$(urlenc "$1")"; else printf '' | req POST /reload; fi ;;
  snap)   if [[ -n "${1:-}" ]]; then req GET "/snap?file=$(urlenc "$1")"; else req GET /snap; fi ;;
  checks) printf 'xbRunChecks' | req POST /run >/dev/null; tr -d '\r' < /mnt/c/xt3d/bench_checks.txt | grep -E 'PASS|FAIL' ;;
  *) sed -n '2,15p' "$0"; exit 1 ;;
esac
