#!/usr/bin/env bash
set -euo pipefail

PLATFORM="linux/arm64"
FORCE_RELOAD="${FORCE_RELOAD:-0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$BASE_DIR/scripts/common/image-archives.txt"

required_lists=(
  "$BASE_DIR/image-list.core.txt"
  "$BASE_DIR/image-list.ragflow.txt"
  "$BASE_DIR/image-list.cdc.txt"
  "$BASE_DIR/image-list.dyna-report.txt"
)

missing=0
if [[ "$FORCE_RELOAD" != "1" ]]; then
  while IFS= read -r image; do
    [[ -n "$image" && ! "$image" =~ ^# ]] || continue
    if ! docker image inspect "$image" >/dev/null 2>&1; then
      echo "Missing base image: $image"
      missing=1
    fi
  done < <(cat "${required_lists[@]}" | sed 's/^\s*//;s/\s*$//' | awk 'NF > 0 && $1 !~ /^#/' | sort -u)
fi

if [[ "$FORCE_RELOAD" != "1" && "$missing" == "0" ]]; then
  echo "All required base images are already present for $PLATFORM."
  exit 0
fi

while IFS='|' read -r platform runtime_image archive_image archive; do
  [[ "${platform:-}" =~ ^# ]] && continue
  [[ -n "${platform:-}" && -n "${runtime_image:-}" && -n "${archive_image:-}" && -n "${archive:-}" ]] || continue
  archive="${archive%$'\r'}"
  [[ "$platform" == "$PLATFORM" ]] || continue
  full_path="$BASE_DIR/$archive"
  [[ -f "$full_path" ]] || { echo "Offline archive not found: $full_path" >&2; exit 1; }
  echo "Loading offline image archive $full_path"
  docker load -i "$full_path"
  docker image inspect "$archive_image" >/dev/null 2>&1 || { echo "Archive did not load $archive_image." >&2; exit 1; }
  if [[ "$archive_image" != "$runtime_image" ]]; then
    echo "Tagging $archive_image as $runtime_image"
    docker tag "$archive_image" "$runtime_image"
  fi
  docker image inspect "$runtime_image" >/dev/null 2>&1 || { echo "Required runtime image is unavailable: $runtime_image" >&2; exit 1; }
done < "$MANIFEST"

while IFS= read -r image; do
  [[ -n "$image" && ! "$image" =~ ^# ]] || continue
  docker image inspect "$image" >/dev/null 2>&1 || { echo "Required base image is unavailable: $image" >&2; exit 1; }
done < <(cat "${required_lists[@]}" | sed 's/^\s*//;s/\s*$//' | awk 'NF > 0 && $1 !~ /^#/' | sort -u)

echo "Offline images loaded and verified for $PLATFORM."
