#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: status-app-base.sh <app-id>}"
PROJECT_NAME="${PROJECT_NAME:-ieta-znz-deploy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$BASE_DIR/apps/$APP.env"
[[ -f "$MANIFEST" ]] || { echo "Unknown app '$APP'." >&2; exit 1; }

fail=0

services="$(grep -E '^REQUIRED_SERVICES=' "$MANIFEST" | head -n1 | cut -d= -f2- || true)"
if [[ -n "$services" ]]; then
  IFS=',' read -ra svc <<< "$services"
  for s in "${svc[@]}"; do
    s="$(echo "$s" | xargs)"
    [[ -n "$s" ]] || continue
    id="$(cd "$BASE_DIR" && docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml ps -q "$s" 2>/dev/null || true)"
    if [[ -z "$id" ]]; then
      echo "[FAIL] service $s: not running" >&2
      fail=1
      continue
    fi
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}|{{.State.Status}}' "$id" 2>/dev/null || true)"
    health="${status%%|*}"
    state="${status#*|}"
    case "$health" in
      healthy) echo "[OK]   service $s: healthy" ;;
      no-healthcheck)
        if [[ "$state" == "running" ]]; then
          echo "[OK]   service $s: running (no healthcheck declared)"
        else
          echo "[FAIL] service $s: $state" >&2
          fail=1
        fi
        ;;
      "") echo "[FAIL] service $s: cannot inspect container" >&2; fail=1 ;;
      *) echo "[FAIL] service $s: $health" >&2; fail=1 ;;
    esac
  done
fi

probes="$(grep -E '^HOST_PROBES=' "$MANIFEST" | head -n1 | cut -d= -f2- || true)"
if [[ -n "$probes" ]]; then
  ENV_FILE="$BASE_DIR/.env"
  get_env() {
    local name="$1" val
    val="${!name:-}"
    if [[ -z "$val" ]]; then
      val="$(grep -E "^$name=" "$ENV_FILE" | head -n1 | cut -d= -f2-)"
    fi
    val="${val%$'\r'}"
    val="${val#\"}"; val="${val%\"}"
    val="${val#\'}"; val="${val%\'}"
    printf '%s' "$val"
  }
  es_password="$(get_env ELASTIC_PASSWORD)"
  IFS=',' read -ra plist <<< "$probes"
  for p in "${plist[@]}"; do
    p="$(echo "$p" | xargs)"
    [[ -n "$p" ]] || continue
    port_var="${p%%:*}"
    rest="${p#*:}"
    proto="${rest%%:*}"
    path="${rest#*:}"
    [[ "$path" == "/" ]] && path=""
    port="$(get_env "$port_var")"
    if [[ -z "$port" || ! "$port" =~ ^[0-9]+$ ]]; then
      echo "[FAIL] probe $port_var: .env value missing or not numeric" >&2
      fail=1
      continue
    fi
    if [[ "$proto" == "tcp" ]]; then
      if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
        echo "[OK]   probe 127.0.0.1:$port (tcp)"
      else
        echo "[FAIL] probe 127.0.0.1:$port (tcp): connection failed" >&2
        fail=1
      fi
    elif [[ "$proto" == "http" ]]; then
      # Shared Elasticsearch password is sent for http probes; services without auth ignore it.
      if curl -fsS --max-time 5 -u "elastic:${es_password}" "http://127.0.0.1:$port$path" >/dev/null 2>&1; then
        echo "[OK]   probe http://127.0.0.1:$port$path"
      else
        echo "[FAIL] probe http://127.0.0.1:$port$path: HTTP check failed" >&2
        fail=1
      fi
    else
      echo "[FAIL] probe $p: unknown protocol '$proto'" >&2
      fail=1
    fi
  done
fi

if [[ "$fail" != "0" ]]; then
  echo "Status check FAILED for $APP." >&2
  exit 1
fi
echo "Status check PASSED for $APP."
exit 0
