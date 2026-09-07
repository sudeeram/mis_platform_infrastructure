#!/bin/sh
set -eu
. "$(dirname -- "$0")/local-common.sh"

for name in auth network aws frontend; do
  pid_file="$RUNTIME_DIR/$name.pid"
  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    printf '%-10s %s\n' "$name" "running (PID $(cat "$pid_file"))"
  else
    printf '%-10s %s\n' "$name" "stopped"
  fi
done
