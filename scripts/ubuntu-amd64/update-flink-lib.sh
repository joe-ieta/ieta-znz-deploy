#!/usr/bin/env bash
set -euo pipefail
# usage: update-flink-lib.sh <jar-file> [jar-file...]
# Copies connector/runner jars into the shared flink_lib volume, mounted at
# /opt/flink/lib/ieta inside flink-jobmanager and all flink-taskmanager replicas.
# The flink_lib named volume survives container recreation and docker compose down;
# it is removed only by `docker compose down -v` (or stop-base-env.sh -RemoveVolumes).
PROJECT_NAME="${PROJECT_NAME:-ieta-znz-deploy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: update-flink-lib.sh <jar-file> [jar-file...]" >&2
  echo "  e.g. flink-sql-connector-postgres-cdc-3.6.0.jar, flink-connector-jdbc-3.3.0.jar, postgresql-42.x.jar" >&2
  echo "  WARNING: do not place the non-SQL shaded flink-connector-elasticsearch7-*.jar here;" >&2
  echo "           it conflicts with Flink SQL factory loading." >&2
  exit 1
fi

for jar in "$@"; do
  [[ -f "$jar" ]] || { echo "Jar not found: $jar" >&2; exit 1; }
  [[ "$jar" == *.jar ]] || { echo "Not a jar file: $jar" >&2; exit 1; }
done

cd "$BASE_DIR"
docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml up -d flink-jobmanager

for jar in "$@"; do
  echo "Copying $(basename "$jar") into flink_lib volume (/opt/flink/lib/ieta/)"
  docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml cp "$jar" "flink-jobmanager:/opt/flink/lib/ieta/"
done

echo "Copied $# jar(s) into the flink_lib volume."
echo "Restart Flink so the classpath picks up the new jars (taskmanagers reconnect automatically):"
echo "  docker compose --project-name $PROJECT_NAME -f docker-compose.ieta-znz-deploy.yml restart flink-taskmanager flink-jobmanager"
