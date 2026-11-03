#!/usr/bin/env bash
# End-to-end test of the real app: real hotkey events, real microphone (speech is played
# through the speakers with `say`), real paste into a text field.
#
# Run from a terminal that has Microphone, Input Monitoring and Accessibility access; the
# app inherits them. Keep the room quiet and don't touch the keyboard or mouse (~40 s).
#
# Usage: scripts/e2e/run.sh [path/to/Hark.app]
set -uo pipefail
cd "$(dirname "$0")/../.."
APP=${1:-build/Hark.app}
WORK=.build/e2e
mkdir -p "$WORK"
swiftc -O scripts/e2e/key.swift -o "$WORK/key" 2>/dev/null
swiftc -O scripts/e2e/target.swift -o "$WORK/target" 2>/dev/null
[[ -d $APP ]] || scripts/build-app.sh >/dev/null

pkill -x Hark
rm -f "$WORK/out.txt"
/usr/bin/log stream --level debug --predicate 'subsystem == "io.github.debanjanc01.hark"' --style compact > "$WORK/hark.log" 2>&1 &
LOG_PID=$!
sleep 3  # log stream needs a moment before it captures anything
"$WORK/target" 30 "$WORK/out.txt" & TARGET_PID=$!
sleep 2
"$APP/Contents/MacOS/Hark" & HARK_PID=$!
sleep 3

key() { "$WORK/key" "$@"; }
echo "1. dictate";                  key down; say "Then send the notes to the team."; key up; sleep 2.5
echo "2. dictate again";            key down; say "The quarterly revenue grew by twelve percent."; key up; sleep 2.5
echo "3. hotkey + another key";     key down; sleep 0.3; key tap 124; say "This should not appear."; key up; sleep 2
echo "4. quick tap";                key down; sleep 0.1; key up; sleep 1
echo "5. hold without speaking";    key down; sleep 1.5; key up; sleep 2
while kill -0 $TARGET_PID 2>/dev/null; do sleep 0.5; done
kill $HARK_PID $LOG_PID 2>/dev/null

text=$(cat "$WORK/out.txt")
lower=$(tr "[:upper:]" "[:lower:]" <<<"$text")
echo; echo "Text field: $text"; echo
grep -E "Model loaded|hotkey|cancel|Heard|Transcribed|error" "$WORK/hark.log" | sed -E 's/^[0-9-]+ ([0-9:.]+).*\] /  \1 /'

failed=0
check() { if eval "$2"; then echo "✔ $1"; else echo "✘ $1"; failed=1; fi; }
echo
check "dictation is pasted"                 '[[ $lower == *"notes to the team"* ]]'
check "second dictation is pasted, spaced"  '[[ $lower == *"team. the quarterly"* ]]'
check "hotkey + another key cancels"        '[[ $lower != *"should not appear"* ]] && grep -q cancel "$WORK/hark.log"'
check "quick tap and silence paste nothing" '[[ $(grep -c Transcribed "$WORK/hark.log") == 2 ]]'
exit $failed
