#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ARCH="amd64"
APP="${1:?usage: start-app-base.sh <app-id> [docker-args are not supported]}"
PROJECT_NAME="${PROJECT_NAME:-ieta-znz-deploy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$BASE_DIR/apps/$APP.env"

actual_arch="$(uname -m)"
case "$EXPECTED_ARCH" in
  amd64)
    [[ "$actual_arch" == "x86_64" || "$actual_arch" == "amd64" ]] || { echo "This script is for amd64, current machine is $actual_arch." >&2; exit 1; }
    ;;
  arm64)
    [[ "$actual_arch" == "aarch64" || "$actual_arch" == "arm64" ]] || { echo "This script is for arm64, current machine is $actual_arch." >&2; exit 1; }
    ;;
esac

[[ -f "$MANIFEST" ]] || { echo "Unknown app '$APP'. Add apps/$APP.env first." >&2; exit 1; }
capabilities="$(grep -E '^CAPABILITIES=' "$MANIFEST" | head -n1 | cut -d= -f2- || true)"
if [[ -z "$capabilities" ]]; then
  echo "No shared base capabilities are declared for $APP. Nothing to start."
  exit 0
fi

cd "$BASE_DIR"
bash "$SCRIPT_DIR/load-images.sh"
compose_args=(compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml)
IFS=',' read -ra caps <<< "$capabilities"
for cap in "${caps[@]}"; do
  cap="$(echo "$cap" | xargs)"
  [[ -n "$cap" ]] && compose_args+=(--profile "$cap")
done
compose_args+=(up -d)

docker "${compose_args[@]}"
docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml ps
