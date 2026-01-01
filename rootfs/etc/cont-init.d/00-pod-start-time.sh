#!/command/with-contenv bash
set -euo pipefail

# Mirrors the old /usr/local/bin/entrypoint.sh behavior so that shells sourcing
# pod-timeout-prompt.sh keep working even if ENTRYPOINT is overridden.
date +%s > /tmp/pod_start_time
