#!/usr/bin/env bash
# Tests check-git-crypt.sh against throwaway git repositories.
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

# fresh repository that encrypts secret/**; git-crypt is not configured, so files are staged as written
new_repo() {
  rm -rf -- "${work}/repo"
  git init -q -b main "${work}/repo"
  printf '%s\n' 'secret/** filter=git-crypt diff=git-crypt' >"${work}/repo/.gitattributes"
  git -C "${work}/repo" add .gitattributes
}
# usage: stage <file> <plain|encrypted>
stage() {
  mkdir -p -- "$(dirname -- "${work}/repo/$1")"
  if [ "$2" = encrypted ]; then printf '\0GITCRYPT\0%s' 'ciphertext' >"${work}/repo/$1"; else
    printf '%s\n' 'plaintext' >"${work}/repo/$1"
  fi
  git -C "${work}/repo" add -- "$1"
}
check() {
  status=0
  (cd "${work}/repo" && bash "${scripts}/check-git-crypt.sh") >"${work}/log" 2>&1 || status=$?
}
passed() { [ "${status}" -eq 0 ]; }
failed_with() { [ "${status}" -ne 0 ] && grep -qF -- "$1" "${work}/log"; }

new_repo
check
assert "no encrypted paths passes" passed

new_repo
stage secret/a.md encrypted
stage public/b.md plain
check
assert "encrypted file and plaintext outside the encrypted paths pass" passed

new_repo
stage secret/a.md encrypted
stage secret/b.md plain
check
assert "staged plaintext file in an encrypted path fails" failed_with "secret/b.md"
assert "only the plaintext file is reported" bash -c "! grep -qF 'secret/a.md' '${work}/log'"

new_repo
stage 'secret/with space.md' plain
check
assert "plaintext file with a space in its name fails" failed_with "secret/with space.md"

new_repo
stage secret/empty.md plain
: >"${work}/repo/secret/empty.md"
git -C "${work}/repo" add secret/empty.md
check
assert "empty file in an encrypted path fails" failed_with "secret/empty.md"

echo "${tests} tests, ${failures} failures"
[ "${failures}" -eq 0 ]
