#!/usr/bin/env bash
# Compares Hark (Swift, linking the Needle engine directly) with the Python SDK
# (`pip install cactus-needle`) on the same clips: cold start, warm latency, peak memory.
#
# Usage: scripts/benchmark.sh [path/to/python-with-cactus-needle]
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON=${1:-}
APP_BIN=build/Hark.app/Contents/MacOS/Hark
[[ -x $APP_BIN ]] || scripts/build-app.sh >/dev/null

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
say -o "$WORK/short.wav" --data-format=LEI16@16000 "Refactor the login function and add unit tests for the edge cases."
say -o "$WORK/long.wav" --data-format=LEI16@16000 \
  "Hark is a dictation app for the Mac. Hold a key, speak, and let go. Your words are transcribed on this computer \
   and typed into whatever app you are using, without sending audio anywhere."

# Prints "<max RSS in MB> <wall seconds>" for a command.
measure() {
  local out
  out=$( { /usr/bin/time -l "$@" >/dev/null; } 2>&1 )
  local rss wall
  rss=$(awk '/maximum resident set size/ {printf "%.0f", $1 / 1048576}' <<<"$out")
  wall=$(awk '/ real / {print $1}' <<<"$out")
  echo "$rss $wall"
}

median() { tr ',' '\n' | sort -g | awk '{a[NR]=$1} END {print (NR%2 ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2)}'; }

PY_SCRIPT='
import json, sys, time
import needle
start = time.perf_counter(); model = needle.Whistle(); load = (time.perf_counter() - start) * 1000
runs = []
for _ in range(int(sys.argv[2])):
    t = time.perf_counter(); out = model.transcribe(sys.argv[1]); runs.append((time.perf_counter() - t) * 1000)
print(json.dumps({"load_ms": load, "transcribe_ms": runs}))
'

printf "%-8s %-7s %10s %12s %14s %10s\n" impl clip cold_start_s model_load_ms median_warm_ms peak_rss_mb
for clip in short long; do
  read -r rss wall < <(measure "$APP_BIN" --transcribe "$WORK/$clip.wav")
  json=$("$APP_BIN" --transcribe "$WORK/$clip.wav" --repeat 10)
  load=$(python3 -c 'import json,sys; print(round(json.load(sys.stdin)["load_ms"]))' <<<"$json")
  warm=$(python3 -c 'import json,sys; print(",".join(str(x) for x in json.load(sys.stdin)["transcribe_ms"][1:]))' <<<"$json" | median)
  printf "%-8s %-7s %10s %12s %14.1f %10s\n" swift $clip "$wall" "$load" "$warm" "$rss"

  if [[ -n $PYTHON ]]; then
    export NEEDLE_TELEMETRY=0
    read -r rss wall < <(measure "$PYTHON" -I -c "$PY_SCRIPT" "$WORK/$clip.wav" 1)
    json=$("$PYTHON" -I -c "$PY_SCRIPT" "$WORK/$clip.wav" 10)
    load=$(python3 -c 'import json,sys; print(round(json.load(sys.stdin)["load_ms"]))' <<<"$json")
    warm=$(python3 -c 'import json,sys; print(",".join(str(x) for x in json.load(sys.stdin)["transcribe_ms"][1:]))' <<<"$json" | median)
    printf "%-8s %-7s %10s %12s %14.1f %10s\n" python $clip "$wall" "$load" "$warm" "$rss"
  fi
done
