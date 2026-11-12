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
#   tools/xt3d_dev.sh compile <file>           compile a LiveCode script without running it:
#                                              COMPILES OK, or the errors with file line numbers
#   tools/xt3d_dev.sh --standalone <command>   talk to the standalone xt3d_MCP.exe (port 8767)
#                                              instead of the IDE (8766); started if not running
#
# compile uses the standalone (started if needed) and falls back to the IDE.
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
IDE_TOKEN=/mnt/c/xt3d/.xt3d_devtoken
SA_TOKEN=/mnt/c/xt3d/.xt3d_devtoken_8767
SA_EXE='C:\xt3d\xt3d_MCP\xt3d_MCP.exe'

# start the standalone if its token file is missing; wait up to 15 s for it
start_standalone() {
  [[ -f "$SA_TOKEN" ]] && return 0
  [[ -f /mnt/c/xt3d/xt3d_MCP/xt3d_MCP.exe ]] || return 1
  (cd /mnt/c/xt3d && cmd.exe /c start "" "$SA_EXE" >/dev/null 2>&1)
  for _ in $(seq 30); do [[ -f "$SA_TOKEN" ]] && return 0; sleep 0.5; done
  return 1
}

if [[ "${1:-}" == --standalone ]]; then
  shift; start_standalone || { echo "could not start $SA_EXE (rebuilt with the launcher script?)" >&2; exit 2; }
  TOKEN_FILE="$SA_TOKEN"
elif [[ "${1:-}" == compile ]]; then
  if start_standalone; then TOKEN_FILE="$SA_TOKEN"; else TOKEN_FILE="$IDE_TOKEN"; fi
else
  TOKEN_FILE="${XT3D_TOKEN_FILE:-$IDE_TOKEN}"
fi
[[ -f "$TOKEN_FILE" ]] || { echo "No $TOKEN_FILE: open the xt3d test bench in LiveCode (it starts the server), or use --standalone" >&2; exit 2; }
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
  compile) f="$1"; [[ -f "$f" ]] || { echo "no such file: $f" >&2; exit 2; }
          # sent as plain statements so it works with any dev server version; the script's
          # first line (script "name") is blanked so error line numbers match the file
          tr -d '\r' < "$f" > /mnt/c/xt3d/.compile_check.txt
          req POST "/run?in=server" <<'LC'
put URL ("file:C:/xt3d/.compile_check.txt") into xtccScript
if line 1 of xtccScript begins with "script " then put empty into line 1 of xtccScript
if there is not a stack "xtCompileCheck" then
   put the defaultStack into xtccOld
   create invisible stack "xtCompileCheck"
   set the defaultStack to xtccOld
end if
set the script of stack "xtCompileCheck" to xtccScript
put the result into xtccErr
delete stack "xtCompileCheck"
if xtccErr is empty then
   put "COMPILES OK"
else
   put "COMPILE ERROR" & return & DevServer.ErrorText(xtccErr, true)
end if
LC
          ;;
  run)    body "$1" | req POST /run ;;
  runs)   body "$1" | req POST "/run?in=server" ;;
  eval)   body "$1" | req POST /eval ;;
  reload) if [[ -n "${1:-}" ]]; then printf '' | req POST "/reload?path=$(urlenc "$1")"; else printf '' | req POST /reload; fi ;;
  snap)   if [[ -n "${1:-}" ]]; then req GET "/snap?file=$(urlenc "$1")"; else req GET /snap; fi ;;
  checks) printf 'xbRunChecks' | req POST /run >/dev/null; tr -d '\r' < /mnt/c/xt3d/bench_checks.txt | grep -E 'PASS|FAIL' ;;
  *) sed -n '2,22p' "$0"; exit 1 ;;
esac
