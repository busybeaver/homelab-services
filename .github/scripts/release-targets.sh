#!/usr/bin/env bash
# Prints the release targets, one per line in C order: every tracked docker-compose.<target>.yaml at the repository
# root except the CI overlay docker-compose.ci.yaml. The single definition of the released file set.
set -Eeuo pipefail

git ls-files -- 'docker-compose.*.yaml' | { grep -vx 'docker-compose.ci.yaml' || true; } | LC_ALL=C sort
