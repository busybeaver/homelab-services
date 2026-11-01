#!/usr/bin/env bash
# Tests release-gate.sh and assemble-release.sh against throwaway git repositories.
set -Eeuo pipefail

scripts="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
tests=0
failures=0

# usage: assert <name> <condition...>
assert() {
  local name="$1"
  shift
  tests=$((tests + 1))
  if "$@"; then
    echo "ok   ${name}"
  else
    failures=$((failures + 1))
    echo "FAIL ${name}"
    [ ! -s "${work}/log" ] || while IFS= read -r line; do echo "    ${line}"; done <"${work}/log"
  fi
}

# fresh repository on branch main; prints nothing
new_repo() {
  rm -rf -- "${work}/repo"
  git init -q -b main "${work}/repo"
  git -C "${work}/repo" config user.email test@example.invalid
  git -C "${work}/repo" config user.name test
  git -C "${work}/repo" config commit.gpgsign false
  git -C "${work}/repo" config tag.gpgsign false
}
# usage: commit <message> [<file> <content>]... ; content "-" deletes the file; prints the new SHA
commit() {
  local message="$1"
  shift
  while [ "$#" -gt 0 ]; do
    if [ "$2" = "-" ]; then git -C "${work}/repo" rm -q -- "$1"; else
      printf '%s\n' "$2" >"${work}/repo/$1"
      git -C "${work}/repo" add -- "$1"
    fi
    shift 2
  done
  git -C "${work}/repo" commit -q --allow-empty -m "${message}"
  git -C "${work}/repo" rev-parse HEAD
}

# usage: gate <head> <last_tag> <force>; sets $status and $out (contents of the step outputs)
gate() {
  : >"${work}/out"
  status=0
  (cd "${work}/repo" && HEAD_SHA="$1" LAST_TAG="$2" FORCE="$3" MAIN_REF=main GITHUB_OUTPUT="${work}/out" \
    bash "${scripts}/release-gate.sh") >"${work}/log" 2>&1 || status=$?
  out="$(cat "${work}/out")"
}
released() { [ "${status}" -eq 0 ] && grep -qx 'release=true' <<<"${out}"; }
skipped() { [ "${status}" -eq 0 ] && grep -qx 'release=false' <<<"${out}"; }
has_output() { grep -qx -- "$1" <<<"${out}"; }
failed_with() { [ "${status}" -ne 0 ] && grep -qF -- "$1" "${work}/log"; }

# --- release-gate.sh ---
new_repo
c1="$(commit c1 docker-compose.homelab.yaml v1 docker-compose.ci.yaml ci1 README.md r1)"
gate "${c1}" "" false
assert "gate: first release" released
assert "gate: first release has empty last_tag" has_output 'last_tag='

git -C "${work}/repo" tag v2026.01.01-1 "${c1}"
gate "${c1}" v2026.01.01-1 false
assert "gate: already released commit is skipped" skipped
gate "${c1}" v2026.01.01-1 true
assert "gate: forced re-release of the released commit" released

c2="$(commit c2 README.md r2)"
gate "${c2}" v2026.01.01-1 false
assert "gate: docs-only change is skipped" skipped
gate "${c2}" v2026.01.01-1 true
assert "gate: forced release without compose change" released

c3="$(commit c3 docker-compose.ci.yaml ci2)"
gate "${c3}" v2026.01.01-1 false
assert "gate: CI overlay change is skipped" skipped

c4="$(commit c4 docker-compose.homelab.yaml v2)"
gate "${c4}" v2026.01.01-1 false
assert "gate: target change is released" released
assert "gate: last_tag is passed on" has_output 'last_tag=v2026.01.01-1'

c5="$(commit c5 docker-compose.cloud-a.yaml a1)"
gate "${c5}" v2026.01.01-1 false
assert "gate: added target is released" released

git -C "${work}/repo" tag v2026.01.02-2 "${c5}"
c6="$(commit c6 docker-compose.cloud-a.yaml -)"
gate "${c6}" v2026.01.02-2 false
assert "gate: deleted target is released" released

gate "${c4}" v2026.01.02-2 false
assert "gate: commit older than the last release is skipped" skipped
gate "${c4}" v2026.01.02-2 true
assert "gate: force does not release an older commit" skipped

git -C "${work}/repo" switch -q -c side "${c1}"
c7="$(commit c7 docker-compose.homelab.yaml side)"
git -C "${work}/repo" switch -q main
gate "${c7}" v2026.01.02-2 false
assert "gate: commit not on main fails" failed_with "is not on main"
gate "${c7}" "" false
assert "gate: commit not on main fails without a previous release" failed_with "is not on main"

# --- assemble-release.sh ---
# usage: assemble <tag> <head> <last_tag>; sets $status, assets in ${work}/dist, notes in ${work}/notes.md
assemble() {
  rm -rf -- "${work}/dist" "${work}/notes.md"
  status=0
  (cd "${work}/repo" && TAG="$1" HEAD_SHA="$2" LAST_TAG="$3" \
    bash "${scripts}/assemble-release.sh" "${work}/dist" "${work}/notes.md") >"${work}/log" 2>&1 || status=$?
}

new_repo
commit base docker-compose.homelab.yaml h1 docker-compose.ci.yaml ci README.md r >/dev/null
mkdir -p "${work}/repo/fixtures"
b1="$(commit "first target" docker-compose.cloud-a.yaml a1 fixtures/docker-compose.cloud-x.yaml x)"
git -C "${work}/repo" tag v2026.01.01-1 "${b1}"
b2="$(commit "feat: change homelab" docker-compose.homelab.yaml h2 README.md r2)"

assemble v2026.01.03-7 "${b2}" v2026.01.01-1
assert "assemble: succeeds" [ "${status}" -eq 0 ]
assert "assemble: ships exactly RELEASE, SHA256SUMS and the targets" \
  [ "$(cd "${work}/dist" && LC_ALL=C && printf '%s ' *)" = "RELEASE SHA256SUMS docker-compose.cloud-a.yaml docker-compose.homelab.yaml " ]
assert "assemble: RELEASE is the tag with LF" cmp -s "${work}/dist/RELEASE" <(printf '%s\n' v2026.01.03-7)
assert "assemble: targets are byte-identical to the commit" \
  cmp -s "${work}/dist/docker-compose.homelab.yaml" <(git -C "${work}/repo" show "${b2}:docker-compose.homelab.yaml")
assert "assemble: SHA256SUMS lists RELEASE and the targets in C order" \
  [ "$(awk '{print $2}' "${work}/dist/SHA256SUMS" | tr '\n' ' ')" = "RELEASE docker-compose.cloud-a.yaml docker-compose.homelab.yaml " ]
assert "assemble: SHA256SUMS uses two spaces and bare names" \
  grep -qE '^[0-9a-f]{64}  RELEASE$' "${work}/dist/SHA256SUMS"
assert "assemble: SHA256SUMS verifies" bash -c "cd '${work}/dist' && sha256sum -c SHA256SUMS >/dev/null"
assert "assemble: notes list the target commits since the last release" grep -q -- '- [0-9a-f]* feat: change homelab' "${work}/notes.md"
assert "assemble: notes leave out commits that touch no target" bash -c "[ -s '${work}/notes.md' ] && ! grep -q 'first target' '${work}/notes.md'"
# shellcheck disable=SC2016 # the backticks are Markdown
assert "assemble: notes list the changed targets" grep -qx -- '- `homelab`' "${work}/notes.md"
assert "assemble: notes leave out unchanged targets" bash -c "! grep -q 'cloud-a' '${work}/notes.md'"

assemble v2026.01.01-1 "${b2}" v2026.01.01-1
assert "assemble: tag equal to the last release fails" failed_with "is not newer than"
assemble v2025.12.31-9 "${b2}" v2026.01.01-1
assert "assemble: tag older than the last release fails" failed_with "is not newer than"
git -C "${work}/repo" tag v2026.01.01-9 "${b1}"
assemble v2026.01.01-10 "${b2}" v2026.01.01-9
assert "assemble: run number compares numerically" [ "${status}" -eq 0 ]
# tag creation is not restricted, and GitHub publishes a release on an existing tag instead of --target
git -C "${work}/repo" tag -a -m stray v2026.01.04-1 "${b1}"
assemble v2026.01.04-1 "${b2}" v2026.01.01-1
assert "assemble: existing tag at another commit fails" failed_with "already exists"
git -C "${work}/repo" tag v2026.01.04-2 "${b2}"
assemble v2026.01.04-2 "${b2}" v2026.01.01-1
assert "assemble: existing tag at the release commit succeeds" [ "${status}" -eq 0 ]

# --- release-targets.sh ---
assert "targets: top-level targets only, CI overlay and nested files excluded, C order" \
  [ "$(cd "${work}/repo" && bash "${scripts}/release-targets.sh" | tr '\n' ' ')" = "docker-compose.cloud-a.yaml docker-compose.homelab.yaml " ]

assemble v2026.1.3-7 "${b2}" v2026.01.01-1
assert "assemble: invalid tag fails" failed_with "invalid tag"

commit "bad target" docker-compose.Bad.yaml b >/dev/null
assemble v2026.01.03-8 "$(git -C "${work}/repo" rev-parse HEAD)" v2026.01.01-1
assert "assemble: invalid target id fails" failed_with "invalid target id"

echo "${tests} tests, ${failures} failures"
[ "${failures}" -eq 0 ]
