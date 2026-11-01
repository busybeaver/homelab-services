#!/usr/bin/env bash
# Release CI provenance, ordering and change gate (see docs/plans/2026-10-16-homelab-services-github-releases-design.md §5.2).
# Environment: HEAD_SHA (commit to release), LAST_TAG (newest published release, may be empty), FORCE ("true" to release
# without a released Compose file change), MAIN_REF (default origin/main), GITHUB_OUTPUT (receives release= and last_tag=).
set -Eeuo pipefail

: "${HEAD_SHA:?HEAD_SHA is required}"
last_tag="${LAST_TAG:-}"
main_ref="${MAIN_REF:-origin/main}"
output="${GITHUB_OUTPUT:-/dev/stdout}"

git merge-base --is-ancestor "${HEAD_SHA}" "${main_ref}" ||
  {
    echo "::error::${HEAD_SHA} is not on ${main_ref}, so it is not on main"
    exit 1
  }

release=true
if [ -n "${last_tag}" ]; then
  last_sha="$(git rev-list -n 1 "refs/tags/${last_tag}")"
  if [ "${last_sha}" = "$(git rev-parse "${HEAD_SHA}")" ]; then
    if [ "${FORCE:-}" = "true" ]; then
      echo "::notice::forced re-release of ${HEAD_SHA}"
    else
      echo "::notice::${HEAD_SHA} is already released as ${last_tag}"
      release=false
    fi
  elif ! git merge-base --is-ancestor "${last_sha}" "${HEAD_SHA}"; then
    echo "::notice::${HEAD_SHA} is not newer than ${last_tag} (out-of-order CI completion); skipping"
    release=false
  elif [ "${FORCE:-}" != "true" ] &&
    [ -z "$(git diff --name-only "${last_sha}" "${HEAD_SHA}" -- 'docker-compose.*.yaml' ':(exclude)docker-compose.*.ci.yaml')" ]; then
    echo "::notice::no released Compose file changed since ${last_tag}; skipping"
    release=false
  fi
fi

{
  echo "release=${release}"
  echo "last_tag=${last_tag}"
} >>"${output}"
