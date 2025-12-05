#!/bin/bash
# Monitor experiment progress and check for TPS/latency results

LOG_FILE="/tmp/experiment_run.log"
CHECK_INTERVAL=30  # Check every 30 seconds

echo "Monitoring experiment progress..."
echo "Looking for TPS and latency results..."
echo ""

while true; do
    if [ -f "$LOG_FILE" ]; then
        # Check for TPS/latency results
        if grep -q -E "(TPS|latency|End-to-end|Consensus)" "$LOG_FILE"; then
            echo "=========================================="
            echo "Found TPS/latency results!"
            echo "=========================================="
            grep -E "(TPS|latency|End-to-end|Consensus|Success|Failed|Summary)" "$LOG_FILE" | tail -20
            echo ""
            echo "Full results:"
            tail -100 "$LOG_FILE" | grep -A 5 -B 5 -E "(TPS|latency|End-to-end|Consensus)"
            break
        fi
        
        # Check if experiment is still running
        if ps aux | grep -q "[r]un_remote_experiment"; then
            echo "$(date): Experiment still running... (last 3 lines:)"
            tail -3 "$LOG_FILE"
            echo ""
        else
            echo "$(date): Experiment process not found. Checking final output..."
            tail -50 "$LOG_FILE"
            break
        fi
    else
        echo "$(date): Log file not found, waiting..."
    fi
    
    sleep $CHECK_INTERVAL
done




