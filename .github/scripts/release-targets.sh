#!/usr/bin/env bash
# Prints the release targets, one per line in C order: every tracked docker-compose.<target>.yaml at the repository
# root except the CI overlays docker-compose.<target>.ci.yaml. The single definition of the released file set.
set -Eeuo pipefail

git ls-files -- 'docker-compose.*.yaml' ':(exclude)docker-compose.*.ci.yaml' | LC_ALL=C sort
