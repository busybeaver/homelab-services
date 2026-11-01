# homelab-services

Services running in the personal HomeLab

## Development

The tooling is managed with [mise](https://mise.jdx.dev):

```sh
mise run setup   # install the pinned tools and the git hooks
mise tasks       # list all tasks
mise run check   # run all checks (same linter configs as the CI)
mise run format  # format all tracked files
```

## Releases

Hosts deploy only from signed GitHub Releases (design: [docs/plans](docs/plans/2026-10-16-homelab-services-github-releases-design.md)).

- **Trigger:** `Release CI` runs after every green `Docker CI` push run on `main`. It releases only if a released Compose
  file (`docker-compose.<target>.yaml`, not `docker-compose.ci.yaml`) changed since the last release.
- **Tag:** `v<YYYY.MM.DD>-<run number>` (UTC), strictly increasing.
- **Assets:** every `docker-compose.<target>.yaml` as committed, `RELEASE` (the tag), `SHA256SUMS` and the cosign bundle
  `SHA256SUMS.sigstore.json`. Every release contains all targets.
- **Verify** (in the directory with the downloaded assets):

  ```sh
  cosign verify-blob --key public_key/cosign.pub --bundle SHA256SUMS.sigstore.json SHA256SUMS
  sha256sum -c SHA256SUMS
  ```

- **Add a target:** add `docker-compose.<target>.yaml` (lowercase letters, digits and `-`; `ci` is reserved) and its
  variables to `.env.ci` (synthetic values only). Cloud targets are bridge-only (no `network_mode: host`, macvlan/ipvlan,
  `mac_address`, external networks or `${VAR}` in `network_mode`/network drivers). Images must be digest-pinned and the file self-contained (no relative paths, `include` or
  `extends.file`). `mise run check:release` runs the same policy check as the CI.
- **Force a release** (e.g. after a signing key rotation): `gh workflow run release.yaml -f force=true`. It still
  requires a green `Docker CI` push run for the commit.
- **Fix forward:** never re-mark an old release as latest; hosts reject downgrades. Commit a fix instead, which creates a
  new release.
