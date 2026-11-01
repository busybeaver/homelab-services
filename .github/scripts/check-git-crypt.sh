#!/usr/bin/env bash
# Fails if a staged file that .gitattributes marks for git-crypt is not encrypted in the index.
# A clone that is not unlocked has no git-crypt filter configured, so git stages new files there as plaintext without a warning.
set -Eeuo pipefail

plaintext=0
while IFS= read -r -d '' path && IFS= read -r -d '' _attr && IFS= read -r -d '' filter; do
  [ "${filter}" = git-crypt ] || continue
  # every git-crypt blob starts with this header
  if ! cmp -s <(git cat-file blob ":${path}" | head -c 10) <(printf '\0GITCRYPT\0'); then
    echo "::error file=${path}::${path} is not encrypted; run git-crypt unlock and stage it again"
    plaintext=$((plaintext + 1))
  fi
done < <(git ls-files -z | git check-attr -z --stdin filter)

[ "${plaintext}" -eq 0 ]
