#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: status-app-base.sh <app-id>}"
PROJECT_NAME="${PROJECT_NAME:-ieta-znz-deploy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$BASE_DIR/apps/$APP.env"
[[ -f "$MANIFEST" ]] || { echo "Unknown app '$APP'." >&2; exit 1; }
services="$(grep -E '^REQUIRED_SERVICES=' "$MANIFEST" | head -n1 | cut -d= -f2- || true)"
if [[ -z "$services" ]]; then
  echo "No required base services declared for $APP."
  exit 0
fi
IFS=',' read -ra svc <<< "$services"
cd "$BASE_DIR"
docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml ps "${svc[@]}"
