#!/bin/bash
# Deliberate fault for the troubleshooting exercise: runaway logging into a log with no rotation.
# Usage: fault-disk.sh fill [seconds]   write until the disk is full, or for that many seconds
#        fault-disk.sh clean            remove the runaway log
set -u
log="${FAULT_LOG:-/var/log/asktala/gateway-debug.log}"
fs="${FAULT_FS:-/}"
case "${1:-}" in
  fill)
    limit="${2:-0}"
    start="$(date +%s)"
    echo "fault started: $(date -u +%FT%TZ)"
    df -h "$fs"
    while :; do
      if ! yes "$(date -u +%FT%TZ) DEBUG gateway verbose request trace, runaway logging" | head -c 52428800 >>"$log"; then
        break
      fi
      avail="$(df --output=avail "$fs" | tail -1 | tr -d ' ')"
      [ "$avail" -lt 1024 ] && break
      if [ "$limit" -gt 0 ] && [ $(( $(date +%s) - start )) -ge "$limit" ]; then break; fi
      sleep 1
    done
    echo "writer stopped: $(date -u +%FT%TZ)"
    df -h "$fs"
    ;;
  clean)
    rm -f "$log" "$log".*
    df -h "$fs"
    ;;
  *)
    echo "Usage: $0 fill [seconds] | clean"
    exit 1
    ;;
esac
