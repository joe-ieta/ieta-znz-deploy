#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ARCH="arm64"
PROJECT_NAME="${PROJECT_NAME:-ieta-znz-deploy}"
PRESET="${1:-all-no-llm}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

actual_arch="$(uname -m)"
case "$EXPECTED_ARCH" in
  amd64)
    [[ "$actual_arch" == "x86_64" || "$actual_arch" == "amd64" ]] || { echo "This script is for amd64, current machine is $actual_arch." >&2; exit 1; }
    ;;
  arm64)
    [[ "$actual_arch" == "aarch64" || "$actual_arch" == "arm64" ]] || { echo "This script is for arm64, current machine is $actual_arch." >&2; exit 1; }
    ;;
esac

profiles_for_preset() {
  case "$PRESET" in
    core) echo "core" ;;
    ragflow) echo "ragflow" ;;
    cdc) echo "cdc" ;;
    dyna-report) echo "dyna-report" ;;
    llm) echo "llm llama-cpp vllm" ;;
    all) echo "ragflow cdc dyna-report llm llama-cpp vllm" ;;
    *) echo "ragflow cdc dyna-report" ;;
  esac
}

cd "$BASE_DIR"
compose_args=(compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml)
for profile in $(profiles_for_preset); do
  compose_args+=(--profile "$profile")
done
compose_args+=(up -d)

docker "${compose_args[@]}"
docker compose --project-name "$PROJECT_NAME" -f docker-compose.ieta-znz-deploy.yml ps
