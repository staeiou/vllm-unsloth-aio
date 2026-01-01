#!/bin/bash
set -euo pipefail

# s6-overlay entrypoint wrapper.
# This preserves the existing "exec start_services.sh" Kubernetes pattern while
# upgrading supervision to s6 (vLLM + LiteLLM become supervised longruns).

if [ ! -x /init ]; then
  echo "[start_services] ERROR: /init not found; did you install s6-overlay?" >&2
  exit 1
fi

exec /init
