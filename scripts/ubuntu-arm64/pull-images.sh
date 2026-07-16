#!/usr/bin/env bash
set -euo pipefail

PLATFORM="linux/arm64"
INCLUDE_LLM="${INCLUDE_LLM:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$BASE_DIR"

lists=(image-list.core.txt image-list.ragflow.txt image-list.cdc.txt image-list.dyna-report.txt)
if [[ "$INCLUDE_LLM" == "1" ]]; then
  lists+=(image-list.llm.txt)
fi

declare -A seen=()
count=0
for list in "${lists[@]}"; do
  [[ -f "$list" ]] || continue
  while IFS= read -r image; do
    [[ -n "$image" && ! "$image" =~ ^# ]] || continue
    [[ -z "${seen[$image]:-}" ]] || continue
    seen["$image"]=1
    echo "Pulling $image for $PLATFORM"
    docker pull --platform "$PLATFORM" "$image"
    count=$((count + 1))
  done < "$list"
done

echo "Pulled $count pinned image references for $PLATFORM."
