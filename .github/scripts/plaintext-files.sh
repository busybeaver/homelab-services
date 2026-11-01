#!/usr/bin/env bash
# Lists the tracked files (optionally narrowed by git pathspecs), without git-crypt files that are still encrypted
# in the working tree, so the formatters and linters also run in a clone that is not unlocked.
set -Eeuo pipefail

while IFS= read -r -d '' path && IFS= read -r -d '' _attr && IFS= read -r -d '' filter; do
  # every git-crypt blob starts with this header
  if [ "${filter}" = git-crypt ] && cmp -s <(head -c 10 -- "${path}" 2>/dev/null) <(printf '\0GITCRYPT\0'); then
    continue
  fi
  printf '%s\n' "${path}"
done < <(git ls-files -z -- "$@" | git check-attr -z --stdin filter)
