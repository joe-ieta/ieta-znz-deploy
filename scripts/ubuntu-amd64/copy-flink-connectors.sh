#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: copy-flink-connectors.sh <connector-jars-dir>" >&2; exit 1; }

SRC="${1:-}"
[[ -n "$SRC" ]] || usage
PROJECT_NAME="${PROJECT_NAME:-ieta-znz-deploy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

[[ -d "$SRC" ]] || { echo "Connector source directory not found: $SRC" >&2; exit 1; }
mapfile -t jars < <(find "$SRC" -maxdepth 1 -type f -name "*.jar" | sort)
[[ "${#jars[@]}" -gt 0 ]] || { echo "No *.jar files found in $SRC" >&2; exit 1; }

cd "$BASE_DIR"
echo "Copying ${#jars[@]} jar(s) into flink_lib (mounted at /opt/flink/lib/ieta)."
docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml \
  run --rm --no-deps --entrypoint /bin/sh \
  -v "$(cd "$SRC" && pwd):/connectors:ro" \
  flink-jobmanager -c 'for j in /connectors/*.jar; do cp -v "$j" /opt/flink/lib/ieta/; done'

echo "Restarting Flink services so connectors load into the classpath."
docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml \
  restart flink-jobmanager flink-taskmanager

echo "Done. Connector jars now persist in the flink_lib named volume across compose down/up."
echo "Verify: docker compose --project-name $PROJECT_NAME -f docker-compose.ieta-znz-deploy.yml ps"
echo "And from the host: curl -fs http://127.0.0.1:$(grep -E '^FLINK_REST_PORT=' "$BASE_DIR/.env" 2>/dev/null | head -n1 | cut -d= -f2-)/overview"
