#!/bin/sh
set -eu
. "$(dirname -- "$0")/local-common.sh"

for name in frontend aws network auth; do
  pid_file="$RUNTIME_DIR/$name.pid"
  if [ -f "$pid_file" ]; then
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      printf '%s\n' "Stopped $name (PID $pid)."
    fi
    rm -f "$pid_file"
  fi
done
