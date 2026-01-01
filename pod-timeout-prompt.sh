#!/bin/bash
# Pod timeout tracker for bash prompt
# Displays time remaining before 6-hour pod limit

POD_START_FILE="/tmp/pod_start_time"
POD_TIMEOUT_SECONDS=21600  # 6 hours

# Create start time file if it doesn't exist (use process 1's start time as reference)
if [[ ! -f "$POD_START_FILE" ]]; then
    # Get the start time of PID 1 (container's main process) as seconds since epoch
    if [[ -f /proc/1/stat ]]; then
        # Extract start time in clock ticks from /proc/1/stat (field 22)
        pid1_start_ticks=$(awk '{print $22}' /proc/1/stat)
        clock_ticks_per_sec=$(getconf CLK_TCK 2>/dev/null || echo 100)
        boot_time=$(awk '/btime/ {print $2}' /proc/stat)
        # Calculate when PID 1 started (approximate container start time)
        pid1_start_time=$((boot_time + pid1_start_ticks / clock_ticks_per_sec))
        echo "$pid1_start_time" > "$POD_START_FILE"
    else
        # Fallback: use current time (will be time of first shell, not container start)
        date +%s > "$POD_START_FILE"
    fi
fi

# Function to calculate and format time remaining
pod_time_remaining() {
    if [[ ! -f "$POD_START_FILE" ]]; then
        echo -n "[no-start-time]"
        return
    fi

    local start_time=$(cat "$POD_START_FILE")
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    local remaining=$((POD_TIMEOUT_SECONDS - elapsed))

    if [[ $remaining -le 0 ]]; then
        echo -n "[EXPIRED]"
        return
    fi

    # Calculate hours and minutes
    local hours=$((remaining / 3600))
    local minutes=$(((remaining % 3600) / 60))

    # Output with color - using \[ \] to mark non-printing sequences
    # Color based on time remaining
    if [[ $remaining -lt 1800 ]]; then  # < 30 min
        echo -n "[${hours}h${minutes}m]"  # Red in PS1
    elif [[ $remaining -lt 3600 ]]; then  # < 1 hour
        echo -n "[${hours}h${minutes}m]"  # Yellow in PS1
    else
        echo -n "[${hours}h${minutes}m]"  # Green in PS1
    fi
}

# Color codes for PS1 (must be wrapped in \[ \])
RED='\[\033[0;31m\]'
YELLOW='\[\033[0;33m\]'
GREEN='\[\033[0;32m\]'
NC='\[\033[0m\]'

# Set PS1 with proper color handling
if [[ -f "$POD_START_FILE" ]]; then
    start_time=$(cat "$POD_START_FILE")
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    remaining=$((POD_TIMEOUT_SECONDS - elapsed))

    if [[ $remaining -le 0 ]]; then
        COLOR=$RED
    elif [[ $remaining -lt 1800 ]]; then
        COLOR=$RED
    elif [[ $remaining -lt 3600 ]]; then
        COLOR=$YELLOW
    else
        COLOR=$GREEN
    fi
else
    COLOR=$NC
fi

# Add to PS1 if not already there
if [[ ! "$PS1" =~ pod_time_remaining ]]; then
    export PS1="${COLOR}\$(pod_time_remaining)${NC} $PS1"
fi
