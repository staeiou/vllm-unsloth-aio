#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model-name> [KEY=VALUE ...]" >&2
  exit 1
fi

MODEL="$1"
shift

ENV_STATE_FILE="${ENV_STATE_FILE:-/workspace/service_env.sh}"
if [ ! -f "$ENV_STATE_FILE" ]; then
  echo "[change_model] State file $ENV_STATE_FILE not found" >&2
  exit 1
fi

STATE_KEYS=(
  JUDGE_MODEL
  GEN_MODEL
  JUDGE_PORT
  JUDGE_PARALLEL
  DATA_PARALLEL_SIZE
  DATA_PARALLEL_SIZE_LOCAL
  DATA_PARALLEL_BACKEND
  DATA_PARALLEL_ADDRESS
  DATA_PARALLEL_RPC_PORT
  VLLM_MAX_MODEL_LEN
  VLLM_GPU_MEM_UTIL
  LITELLM_PORT
  JUDGE_MODEL_NAME
  GEN_MODEL_NAME
  DEFAULT_ROUTER_MODEL
)

set -a
source "$ENV_STATE_FILE"
set +a

JUDGE_MODEL="$MODEL"
GEN_MODEL="$MODEL"

EXTRA_KEYS=()
for arg in "$@"; do
  if [[ "$arg" != *=* ]]; then
    echo "[change_model] Extra args must be KEY=VALUE" >&2
    exit 1
  fi
  key=${arg%%=*}
  val=${arg#*=}
  export "$key"="$val"
  if [[ ! " ${STATE_KEYS[*]} " =~ " $key " ]]; then
    STATE_KEYS+=("$key")
  fi
  EXTRA_KEYS+=("$key")
 done

 tmp=$(mktemp)
 trap 'rm -f "$tmp"' EXIT
 for key in "${STATE_KEYS[@]}"; do
   # Preserve empty values (KEY=) so downstream scripts can safely reference
   # variables under `set -u`.
   if [ "${!key+x}" = "x" ]; then
     printf '%s=%s\n' "$key" "${!key}" >> "$tmp"
   fi
 done
 mv "$tmp" "$ENV_STATE_FILE"
 chmod 600 "$ENV_STATE_FILE"

 echo "[change_model] Updated $ENV_STATE_FILE with JUDGE_MODEL=$MODEL"

VLLM_SERVICE_CANDIDATES=(
  "${VLLM_SERVICE_DIR:-/run/service/vllm}"
  "/run/service/vllm"
  "/var/run/s6/services/vllm"
)

S6_SVC_BIN=""
if command -v s6-svc >/dev/null 2>&1; then
  S6_SVC_BIN="s6-svc"
elif command -v /command/s6-svc >/dev/null 2>&1; then
  S6_SVC_BIN="/command/s6-svc"
fi

for svc_dir in "${VLLM_SERVICE_CANDIDATES[@]}"; do
  if [ -n "$S6_SVC_BIN" ] && [ -d "$svc_dir" ]; then
    "$S6_SVC_BIN" -t "$svc_dir"
    echo "[change_model] Restarted vLLM via s6 ($svc_dir)"
    break
  fi
done

LITELLM_SERVICE_CANDIDATES=(
  "${LITELLM_SERVICE_DIR:-/run/service/litellm}"
  "/run/service/litellm"
  "/var/run/s6/services/litellm"
)

restarted_litellm=0
for svc_dir in "${LITELLM_SERVICE_CANDIDATES[@]}"; do
  if [ -n "$S6_SVC_BIN" ] && [ -d "$svc_dir" ]; then
    "$S6_SVC_BIN" -t "$svc_dir"
    echo "[change_model] Restarted LiteLLM via s6 ($svc_dir)"
    restarted_litellm=1
    break
  fi
done

if [ -z "$S6_SVC_BIN" ]; then
  echo "[change_model] ERROR: s6-svc not found (expected s6-overlay)" >&2
  exit 1
fi

ok_vllm=0
for svc_dir in "${VLLM_SERVICE_CANDIDATES[@]}"; do
  if [ -d "$svc_dir" ]; then ok_vllm=1; fi
done
if [ "$ok_vllm" -ne 1 ]; then
  echo "[change_model] ERROR: vLLM service dir missing (tried: ${VLLM_SERVICE_CANDIDATES[*]})" >&2
  exit 1
fi

if [ "$restarted_litellm" -ne 1 ]; then
  echo "[change_model] WARNING: LiteLLM service dir not found; config may still point at old model" >&2
fi

exit 0
