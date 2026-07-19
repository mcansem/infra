# docker/

> Status: empty. Landing in v0.2.0 (Docker Infrastructure phase).

This folder will hold the base `docker-compose.yml` plus per-environment override files (e.g. `docker-compose.staging.yml`, `docker-compose.production.yml`).

Every service defined here must have:

- A healthcheck
- An explicit restart policy
- Named volumes (no anonymous volumes)
- A custom network (no reliance on the default bridge network)
- A clean, consistent naming convention
