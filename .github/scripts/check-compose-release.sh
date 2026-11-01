#!/usr/bin/env bash
# Release policy for docker-compose.<target>.yaml files (see docs/plans/2026-10-16-homelab-services-github-releases-design.md §4).
# Usage: check-compose-release.sh <docker-compose.<target>.yaml> [env-file]
set -Eeuo pipefail

file="${1:?compose file required}"
env_file="${2:-.env.ci}"
errors=0
fail() {
  echo "::error file=${file}::$*"
  errors=$((errors + 1))
}

name="$(basename -- "${file}")"
target="${name#docker-compose.}"
target="${target%.yaml}"
if [[ ! ${name} =~ ^docker-compose\.[a-z0-9][a-z0-9-]*\.yaml$ ]] || [ "${target}" = "ci" ]; then
  echo "::error file=${file}::invalid target file name" >&2
  exit 1
fi

# Raw YAML: constructs that `docker compose config` resolves away, needs to exist, or that the sentinel values below
# would hide.
raw_json="$(yq --yaml-fix-merge-anchor-to-spec=true -o=json 'explode(.)' "${file}" 2>&1)" || {
  echo "::error file=${file}::cannot parse ${file}: ${raw_json//$'\n'/ }"
  exit 1
}
raw_check() { # <jq filter emitting offending names> <message>
  local hits
  hits="$(jq -r "$1" <<<"${raw_json}")"
  [ -z "${hits}" ] || fail "$2: ${hits//$'\n'/, }"
}
not_abs='select((startswith("/") or startswith("$")) | not)'
as_list='if type == "array" then .[] else . end'
raw_check '(.include // [])[] | (.path? // .) | tostring' 'top-level include: is not allowed'
raw_check '(.services // {}) | to_entries[] | select((.value.extends | objects | .file) != null) | .key' 'extends.file is not allowed'
# env_file and label_file are folded into environment/labels when rendering (and must exist)
raw_check "[.services[]?.env_file? // empty | ${as_list} | (.path? // .) | ${not_abs}] | .[]" 'relative env_file'
raw_check "[.services[]?.label_file? // empty | ${as_list} | ${not_abs}] | .[]" 'relative label_file'
if [ "${target}" != "homelab" ]; then
  raw_check '((.services // {}) | to_entries[] | select((.value.network_mode // "") | tostring | contains("$")) | .key),
    ((.networks // {}) | to_entries[] | select((.value.driver // "") | tostring | contains("$")) | .key)' \
    'network_mode and network drivers must be literal for cloud targets'
  # the driver of an external network is defined on the host, so bridge-only cannot be verified
  raw_check '(.networks // {}) | to_entries[] | select(.value.external // false | . == true or type == "object") | .key' \
    'external networks are not allowed for cloud targets'
fi
[ "${errors}" -eq 0 ] || exit 1 # the model below cannot be rendered without the referenced files

# Variable references in the file, without comments and $$ escapes: "${NAME", "${NAME:-", "$NAME", ...
raw="$(yq --yaml-fix-merge-anchor-to-spec=true '... comments=""' "${file}")"
refs="$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(:?[-?+])?|\$[A-Za-z_][A-Za-z0-9_]*' <<<"${raw//\$\$/}" || true)"
names="$(sed -E 's/^\$\{?([A-Za-z0-9_]+).*/\1/' <<<"${refs}" | LC_ALL=C sort -u)"
# references without a default (-) or alternative (+) value must be provided by the env file
required="$(grep -vE ':?[-+]$' <<<"${refs}" | sed -E 's/^\$\{?([A-Za-z0-9_]+).*/\1/' | LC_ALL=C sort -u || true)"

# Model rendered with every variable set to an absolute sentinel path, so ${VAR}-based paths count as absolute while
# relative paths stay visible. Rendering without interpolation is not portable: Compose 2.x rejects short volume syntax
# like "${VAR:?msg}/x:/y:rw" with --no-interpolate ("too many colons").
sentinel_env="$(mktemp)"
trap 'rm -f -- "${sentinel_env}"' EXIT
while IFS= read -r var; do
  [ -z "${var}" ] || printf '%s=/__%s__\n' "${var}" "${var}"
done <<<"${names}" >"${sentinel_env}"
model="$(docker compose --env-file "${sentinel_env}" -f "${file}" config --no-path-resolution --format json)"
check() { # <jq filter emitting offending names> <message>
  local hits
  hits="$(jq -r "$1" <<<"${model}")"
  [ -z "${hits}" ] || fail "$2: ${hits//$'\n'/, }"
}
check '.services | to_entries[] | select(.value.build) | .key' 'build: is not allowed'
check "[.services[].volumes[]? | select(.type == \"bind\") | .source | ${not_abs}] | .[]" 'relative bind mount'
check "[(.secrets // {}), (.configs // {}) | .[] | (.file? // empty) | ${not_abs}] | .[]" 'relative secrets/configs file'
check "[(.volumes // {})[] | .driver_opts.device? // empty | ${not_abs}] | .[]" 'relative volume device'
check '.services | to_entries[] | select((.value.image // "") | test("@sha256:[0-9a-f]{64}$") | not) | .key' 'image not digest-pinned'
if [ "${target}" != "homelab" ]; then
  check '.services | to_entries[] | select(.value.network_mode == "host") | .key' 'network_mode: host is not allowed for cloud targets'
  check '(.networks // {}) | to_entries[] | select(.value.driver == "macvlan" or .value.driver == "ipvlan") | .key' 'macvlan/ipvlan is not allowed for cloud targets'
  check '.services | to_entries[] | select(.value.mac_address or ([(.value.networks // {})[]? | objects | .mac_address] | any)) | .key' 'mac_address is not allowed for cloud targets'
fi
# services relying on their image's HEALTHCHECK are labelled, since the image metadata is not available here
missing_hc="$(jq -r '.services | to_entries[] | select(.value.healthcheck == null and (.value.labels["homelab.compose.oneshot"] // "") != "true" and (.value.labels["homelab.compose.image-healthcheck"] // "") != "true") | .key' <<<"${model}")"
[ -z "${missing_hc}" ] || echo "::warning file=${file}::no healthcheck: ${missing_hc//$'\n'/, }"

# Every variable without a default must be provided by the env file.
while IFS= read -r var; do
  [ -z "${var}" ] || grep -q "^${var}=" "${env_file}" || fail "variable ${var} has no default and is missing from ${env_file}"
done <<<"${required}"

[ "${errors}" -eq 0 ] || exit 1
echo "release policy OK: ${file}"
