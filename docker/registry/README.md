# docker/registry/

A private, self-hosted Docker Registry — deliberately not Docker Hub/GHCR/any public registry. Runs on the management host (AWS EC2), alongside Portainer and Jenkins.

## Bootstrap

1. Point the registry's domain at this host, then obtain a certificate (Let's Encrypt by default, see [ssl/README.md](../../ssl/README.md) for the bootstrap sequence and the self-signed fallback):

   ```bash
   bash ../../ssl/obtain-cert.sh registry registry.<your-domain>
   ```

2. Generate the htpasswd auth file (never committed — see `.gitignore`):

   ```bash
   mkdir -p auth
   docker run --rm httpd:alpine htpasswd -Bbn <user> <password> > auth/htpasswd
   ```

3. Start it:

   ```bash
   docker compose -f docker/registry/docker-compose.yml up -d
   ```

4. On every other Docker host that needs to `docker login`/`push`/`pull` (Jenkins, the staging GCP VM, your own machine), log in with the same credentials:

   ```bash
   docker login registry.<your-domain>:5000
   ```

Because the cert comes from a real Let's Encrypt CA (once a domain is in place), no manual CA-trust distribution is needed on any of those hosts — unlike a self-signed setup, where each Docker daemon would need the registry's CA added under `/etc/docker/certs.d/`.

## Conventions

Same as every other stack in this repo: healthcheck, restart policy, named volume, custom network, pinned image tag (`registry:2`, the official Distribution image).
