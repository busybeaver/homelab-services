#!/usr/bin/env bash
# Tests check-compose-release.sh against the fixtures:
# - fixtures/pass/*: must succeed without a warning
# - fixtures/warn/*: must succeed with a warning
# - fixtures/fail/<rule>/*: must fail and print the message in fixtures/fail/<rule>/expected
set -Eeuo pipefail
shopt -s nullglob

cd "$(dirname -- "${BASH_SOURCE[0]}")"
checker=./check-compose-release.sh
env_file=fixtures/.env.fixtures
tests=0
failures=0

# usage: check <file> <expect: pass|warn|fail> [expected message]
check() {
  local file="$1" expect="$2" message="${3:-}" output status=0
  tests=$((tests + 1))
  output="$(bash "${checker}" "${file}" "${env_file}" 2>&1)" || status=$?

  local problem=""
  case "${expect}" in
  pass)
    [ "${status}" -eq 0 ] || problem="expected success, got exit ${status}"
    [ -n "${problem}" ] || ! grep -q '::warning' <<<"${output}" || problem="expected no warning"
    ;;
  warn)
    [ "${status}" -eq 0 ] || problem="expected success, got exit ${status}"
    [ -n "${problem}" ] || grep -q '::warning' <<<"${output}" || problem="expected a warning"
    ;;
  fail)
    [ "${status}" -ne 0 ] || problem="expected failure, got exit 0"
    [ -n "${problem}" ] || grep -qF -- "${message}" <<<"${output}" || problem="expected message: ${message}"
    ;;
  esac

  if [ -n "${problem}" ]; then
    failures=$((failures + 1))
    echo "FAIL ${file}: ${problem}"
    while IFS= read -r line; do echo "    ${line}"; done <<<"${output}"
  else
    echo "ok   ${file}"
  fi
}

for file in fixtures/pass/docker-compose.*.yaml; do
  check "${file}" pass
done
for file in fixtures/warn/docker-compose.*.yaml; do
  check "${file}" warn
done
for dir in fixtures/fail/*/; do
  for file in "${dir}"docker-compose.*.yaml; do
    check "${file}" fail "$(cat -- "${dir}expected")"
  done
done

# unparsable file: generated here, so the repository linters never see invalid YAML
invalid="$(mktemp -d)"
trap 'rm -rf -- "${invalid}"' EXIT
printf 'services:\n  web: [\n' >"${invalid}/docker-compose.cloud-a.yaml"
check "${invalid}/docker-compose.cloud-a.yaml" fail "cannot parse"

echo "${tests} tests, ${failures} failures"
[ "${tests}" -gt 0 ] && [ "${failures}" -eq 0 ]
