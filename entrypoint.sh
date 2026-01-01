#!/bin/bash
# Record pod start time
date +%s > /tmp/pod_start_time

# Execute the main command
exec "$@"
