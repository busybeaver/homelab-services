#!/usr/bin/env bash
# Assembles the release assets (see docs/plans/2026-10-16-homelab-services-github-releases-design.md §2).
# Usage: assemble-release.sh <dist dir> <release notes file>
# Environment: TAG, HEAD_SHA (the checked-out release commit), LAST_TAG (previous release, may be empty).
set -Eeuo pipefail

dist="${1:?dist directory required}"
notes="${2:?release notes file required}"
: "${TAG:?TAG is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"

[[ ${TAG} =~ ^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]+$ ]] || {
  echo "::error::invalid tag ${TAG}"
  exit 1
}

mapfile -t targets < <(git ls-files 'docker-compose.*.yaml' | grep -vx 'docker-compose.ci.yaml' | LC_ALL=C sort)
[ "${#targets[@]}" -gt 0 ] || {
  echo "::error::no release targets found"
  exit 1
}
mkdir -p -- "${dist}"
for file in "${targets[@]}"; do
  target="${file#docker-compose.}"
  target="${target%.yaml}"
  [[ ${target} =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
    echo "::error::invalid target id ${target}"
    exit 1
  }
  cp -- "${file}" "${dist}/"
done
printf '%s\n' "${TAG}" >"${dist}/RELEASE"
(cd -- "${dist}" && sha256sum RELEASE docker-compose.*.yaml | LC_ALL=C sort -k2 >SHA256SUMS)

{
  echo "Signed Docker Compose release \`${TAG}\` of ${HEAD_SHA}."
  echo
  if [ -n "${LAST_TAG:-}" ]; then
    echo "Compose changes since \`${LAST_TAG}\`:"
    git log --format='- %h %s' "${LAST_TAG}..${HEAD_SHA}" -- 'docker-compose.*.yaml' ':(exclude)docker-compose.ci.yaml'
    echo
  fi
  # shellcheck disable=SC2016 # the backticks are Markdown, not a command substitution
  echo 'Verify: `cosign verify-blob --key public_key/cosign.pub --bundle SHA256SUMS.sigstore.json SHA256SUMS && sha256sum -c SHA256SUMS`'
} >"${notes}"
