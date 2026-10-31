# NAS deployment checklist

Manual steps on the Synology NAS before deploying the compose hardening changes (`chore/compose-hardening`).
They cannot be done or verified from CI, which only runs with the dummy values in `.env.ci`.

## 1. Back up the Postgres data

- [ ] Stop the stack and back up `${VOLUME_BASE_DIRECTORY}/postgres/data` before the first start.

The Postgres mount moved to `/var/lib/postgresql` (the pg18 image declares it as `VOLUME`) with
`PGDATA=/var/lib/postgresql/pgdata`. This maps to the same host directory as before
(`${VOLUME_BASE_DIRECTORY}/postgres/data/pgdata`), so the data should stay in place, but this was never tested
against the real data.

## 2. Complete the `.env`

Every variable is now required (`${VAR:?...}`): compose refuses to run any command if a variable is unset **or
empty**. Use `.env.ci` as the list of variable names (its values are dummies).

- [ ] Define every variable from `.env.ci` in the NAS `.env`, especially the new ones: `ADGUARD_DOMAIN`,
      `BESZEL_DOMAIN`, `NODE_RED_DOMAIN`, `LITELLM_SALT_KEY`, `OPEN_WEBUI_LITELLM_API_KEY`.
- [ ] If a variable is meant to be optional/empty, change it in `docker-compose.homelab.yaml` to `${VAR:-}` instead.
- [ ] The stack file is now `docker-compose.homelab.yaml`. Until the release-based reconciler deploys it, pass it
      explicitly (`docker compose -f docker-compose.homelab.yaml …`) or set `COMPOSE_FILE=docker-compose.homelab.yaml`
      in the NAS `.env`.
- [ ] Validate on the NAS: `docker compose -f docker-compose.homelab.yaml config --quiet` must print nothing.

## 3. LiteLLM salt key

- [ ] Generate `LITELLM_SALT_KEY` once (e.g. `openssl rand -hex 32`). **Never change it afterwards**: it encrypts the
      provider credentials stored in the LiteLLM database.
- [ ] If provider credentials were already stored in LiteLLM's database (encrypted with the master key before),
      re-enter them in the LiteLLM admin UI after the first start.

## 4. Scoped LiteLLM key for Open WebUI

Open WebUI no longer uses the LiteLLM master key. Order:

- [ ] Start Postgres and LiteLLM only: `docker compose up -d postgres litellm`.
- [ ] Create a virtual key for Open WebUI in the LiteLLM admin UI (or `/key/generate`), limited to the models it
      needs.
- [ ] Put that key into `OPEN_WEBUI_LITELLM_API_KEY` in the `.env`.
- [ ] Start the rest of the stack.

## 5. Open WebUI vector store

- [ ] Re-ingest the Open WebUI documents/knowledge bases: the vector DB switched from Chroma to pgvector
      (`VECTOR_DB=pgvector`) and existing embeddings are not migrated.

`ENABLE_OLLAMA_API=false` is a persistent config value: it only applies on the first start. If Open WebUI was
started before, disable the Ollama connection in its admin UI instead.

## 6. Node-RED healthcheck

The compose healthcheck was removed; the image's own `HEALTHCHECK` (`node /healthcheck.js`) is used. It reads
`/data/settings.js` and ignores the `PORT` environment variable.

- [ ] Confirm the NAS `${VOLUME_BASE_DIRECTORY}/node-red/data/settings.js` sets `uiPort: 443` and an `https`
      block. Otherwise the container is reported as unhealthy.

## 7. Resource limits

- [ ] Review `mem_limit` / `pids_limit` per service against the NAS RAM (they are estimates):
      adguard-home 256m, node-red 768m, postgres 1g, litellm 2g, open-webui 4g.
- [ ] After the deployment, check `docker stats` for containers running close to their limit.

## 8. After the deployment

- [ ] `docker compose ps`: all services `healthy` (the Tailscale sidecars only become healthy once they have a
      tailnet IP).
- [ ] Spot-check the logs for permission errors on `/tmp` (fixed to `mode=770`) or on the Postgres mount.
