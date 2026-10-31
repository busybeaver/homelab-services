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
