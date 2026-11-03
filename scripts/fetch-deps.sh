#!/usr/bin/env bash
# Downloads the Needle engine and the Whistle speech model at pinned upstream
# revisions and verifies each file's SHA-256 before it is used.
set -euo pipefail
cd "$(dirname "$0")/.."

NEEDLE_REV=d6c7d6a2e9655505e0f8e23339356dd1705900eb   # huggingface.co/Cactus-Compute/needle3
WHISTLE_REV=741118687e1f008f06d1351a402a731274789790  # huggingface.co/Cactus-Compute/whistle
HF=https://huggingface.co

fetch() {
  local url=$1 dest=$2 sha=$3
  if [[ -f $dest ]] && echo "$sha  $dest" | shasum -a 256 -c --status; then
    return
  fi
  echo "Fetching $dest"
  mkdir -p "$(dirname "$dest")"
  curl -fsSL --retry 3 -o "$dest.part" "$url"
  if ! echo "$sha  $dest.part" | shasum -a 256 -c --status; then
    echo "error: checksum mismatch for $dest ($url)" >&2
    rm -f "$dest.part"
    exit 1
  fi
  mv "$dest.part" "$dest"
}

fetch "$HF/Cactus-Compute/needle3/resolve/$NEEDLE_REV/macos-arm64/libneedle.a" \
  vendor/needle/libneedle.a 7d1368a4a42a745aba055f310913c3ed6d929dee98a89dcb955b9032b2335700
fetch "$HF/Cactus-Compute/needle3/resolve/$NEEDLE_REV/macos-arm64/needle.h" \
  Sources/CNeedle/include/needle.h a27dac4b3239eead91d124b7f7dbce5495c13019903fd817b68c16d39b055a99
fetch "$HF/Cactus-Compute/whistle/resolve/$WHISTLE_REV/whistle.cact" \
  vendor/whistle/whistle.cact b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb
