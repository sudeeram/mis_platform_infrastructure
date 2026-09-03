#!/bin/sh
set -eu

script_directory="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
repository_root="$(git -C "$script_directory/.." rev-parse --show-toplevel)"
git -C "$repository_root" config core.hooksPath .githooks
printf '%s\n' "Git workflow hooks enabled for $repository_root"
