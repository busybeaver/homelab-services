# Rules for coding agents

`busybeaver-homelab/services` holds the Docker Compose stacks of the homelab. Hosts deploy them only from signed GitHub
Releases (see the README). The repository is **public**.

## Secrets and privacy

- Never write real hostnames, internal IPs, subnets, domains, MAC addresses, credentials or tokens into tracked files,
  commit messages, PR titles or descriptions, or issues. `.env.ci` holds synthetic values only.
- Never read, print or commit the local `.env` or the other ignored local files (`HANDOFF.md`, `.vlan-config.json`,
  `local-*.yaml`). They hold the real values.
- `docs/` is encrypted with git-crypt. Inspect its diffs with `git diff --no-textconv`, and never commit a file under
  `docs/` in a clone that is not unlocked; `check-git-crypt.sh` blocks it in the hook and in CI.

## Workflow

- Run `mise run setup` once, and `mise run check` before every commit and PR. Never bypass the hooks (`--no-verify`).
- Commit messages follow Conventional Commits (`cog verify` runs in the `commit-msg` hook).
- Branch from `origin/main` and open a PR; `main` only takes squash merges of PRs with green checks.
- Changed behaviour needs a test in `.github/scripts/test-*.sh`. Write it first and watch it fail.
- Git worktrees of an unlocked clone need git-crypt: create them with `--no-checkout`, symlink `../../git-crypt` into
  `.git/worktrees/<name>/git-crypt`, then check out. Otherwise `docs/` stays encrypted.

## Compose files and releases

- `docker-compose.<target>.yaml` files are release targets; `docker-compose.<target>.ci.yaml` files are CI overlays and
  are never released. `mise run check:release` runs the release policy (digest-pinned images, self-contained files).
- Never create `v*` tags or releases by hand; `Release CI` creates them.

## GitHub Actions

- Pin every action and reusable workflow to a full commit SHA with a version comment; the repository enforces it.
- A new third-party action must also be added to the Actions allowlist (repository and organisation settings). Only the
  owner changes settings, secrets and rulesets.
