#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: status-app-base.sh <app-id>}"
PROJECT_NAME="${PROJECT_NAME:-ieta-znz-deploy}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$BASE_DIR/apps/$APP.env"
[[ -f "$MANIFEST" ]] || { echo "Unknown app '$APP'." >&2; exit 1; }

get_value() {
  local key="$1" file="$2"
  grep -E "^${key}=" "$file" 2>/dev/null | head -n1 | cut -d= -f2- | xargs || true
}

services="$(get_value REQUIRED_SERVICES "$MANIFEST")"
if [[ -z "$services" ]]; then
  echo "No required base services declared for $APP."
  exit 0
fi
IFS=',' read -ra svc <<< "$services"

cd "$BASE_DIR"
compose=(docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml)

"${compose[@]}" ps "${svc[@]}"

fail=0
ps_output="$("${compose[@]}" ps --format '{{.Name}}|{{.State}}|{{.Status}}' "${svc[@]}" || true)"

# 1) service presence and container health
for s in "${svc[@]}"; do
  if ! grep -qF -- "-${s}-" <<< "$ps_output"; then
    echo "[FAIL] service $s: no running container found." >&2
    fail=1
    continue
  fi
  while IFS='|' read -r name state status; do
    [[ -n "$name" ]] || continue
    if [[ "$name" != *"-${s}-"* ]]; then continue; fi
    if [[ "$state" != "running" ]]; then
      echo "[FAIL] $name: not running (state=$state)." >&2
      fail=1
    elif [[ "$status" == *"(unhealthy)"* || "$status" == *"(health:"* ]]; then
      echo "[FAIL] $name: $status" >&2
      fail=1
    elif [[ "$status" == *"(healthy)"* ]]; then
      echo "[OK] $name: $status"
    else
      echo "[OK] $name: $status (no healthcheck defined)"
    fi
  done <<< "$ps_output"
done

# 2) host connectivity probes declared in the app manifest
#    HOST_PROBES format: ENV_VAR:kind[:path][:user],...  kind=tcp|http
probes="$(get_value HOST_PROBES "$MANIFEST")"
if [[ -n "$probes" ]]; then
  IFS=',' read -ra entries <<< "$probes"
  for entry in "${entries[@]}"; do
    [[ -n "$entry" ]] || continue
    IFS=':' read -r var kind path user <<< "$entry"
    port="$(get_value "$var" "$BASE_DIR/.env")"
    if [[ -z "$port" ]]; then
      echo "[FAIL] $var is not defined in .env (probe entry '$entry')." >&2
      fail=1
      continue
    fi
    case "$kind" in
      tcp)
        if timeout 5 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null; then
          echo "[OK] tcp 127.0.0.1:$port reachable"
        else
          echo "[FAIL] tcp 127.0.0.1:$port unreachable" >&2
          fail=1
        fi
        ;;
      http)
        url="http://127.0.0.1:${port}${path:-/}"
        curl_args=(-fs -o /dev/null)
        if [[ -n "$user" ]]; then
          curl_args+=(-u "${user}:$(get_value ELASTIC_PASSWORD "$BASE_DIR/.env")")
        elif [[ "$var" == "ES7_CDC_PORT" && "$(get_value ES7_SECURITY_ENABLED "$BASE_DIR/.env")" == "true" ]]; then
          curl_args+=(-u "elastic:$(get_value ELASTIC_PASSWORD "$BASE_DIR/.env")")
        fi
        if command -v curl >/dev/null 2>&1; then
          if timeout 10 curl "${curl_args[@]}" "$url" 2>/dev/null; then
            echo "[OK] $url (HTTP 2xx)"
          else
            echo "[FAIL] $url (HTTP probe failed)" >&2
            fail=1
          fi
        else
          if timeout 10 bash -c "
            exec 3<>/dev/tcp/127.0.0.1/$port || exit 1
            printf 'GET ${path:-/} HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n' >&3
            grep -qE 'HTTP/1\.[01] 2' <&3
          " 2>/dev/null; then
            echo "[OK] $url (HTTP 2xx)"
          else
            echo "[FAIL] $url (HTTP probe failed)" >&2
            fail=1
          fi
        fi
        ;;
      *)
        echo "[FAIL] unknown probe kind '$kind' in HOST_PROBES entry '$entry'." >&2
        fail=1
        ;;
    esac
  done
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Base environment for $APP is NOT ready." >&2
  exit 1
fi
echo "Base environment for $APP is ready: all services healthy and host probes passed."
