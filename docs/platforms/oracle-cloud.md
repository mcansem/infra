# Oracle Cloud — app host (production)

The `app` role's eventual production target — per the Short Term roadmap in [docs/roadmap.md](../roadmap.md): "Google Cloud VM → Oracle Cloud (Production)". Staging stays on GCP; this is where `docker/app/docker-compose.production.yml` actually runs for real traffic.

## Provisioning

1. **Compute instance** — Oracle Cloud's Always Free tier includes Ampere A1 (ARM/`arm64`) instances, a genuinely popular choice here since it's free and reasonably capable. Worth an explicit note before committing to it: `docker/app/`'s own images — `nginx:alpine` and `postgres:16-alpine` — both publish official multi-arch manifests including `arm64`, so they're not a blocker. The `app` image is built by the application repo's own CI (the Jenkins pipeline, `vars/standardDeployPipeline.groovy`) — whether *it* ends up multi-arch depends on that repo's own build setup, not anything in this repo. Confirm that separately before standardizing on ARM for production. An x86 (AMD/Intel) shape sidesteps the question entirely if it's not worth resolving up front.
2. **Security Lists / Network Security Groups** — Oracle's firewall layer, opened to the same ports `scripts/harden-host.sh app` manages: `22`, `80`, `443`.
3. **Reserved public IP** — same reasoning as the AWS/GCP docs: DNS and any future cross-host Prometheus scraping opt-in need a stable address.
4. **SSH access** — Oracle Cloud provisions a default user (commonly `opc` or `ubuntu` depending on the image) with your uploaded key; confirm connectivity before proceeding.

## From here, it's the same as every other host

```bash
git clone <this-repo-url> infra && cd infra
sudo scripts/harden-host.sh app
```

Then [docker/app/README.md](../../docker/app/README.md)'s bootstrap sequence, using `docker-compose.production.yml` this time instead of staging's. Nothing past this point is Oracle-specific.
