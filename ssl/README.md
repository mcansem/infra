# ssl/

Certificate material lives here at runtime, mounted read-only into whichever service terminates TLS (Nginx, the private registry). Certificate files themselves are **never committed** — see [.gitignore](../.gitignore). Only this README and [obtain-cert.sh](obtain-cert.sh) are tracked in version control.

## obtain-cert.sh

```bash
bash ssl/obtain-cert.sh <service-name> <domain> [--self-signed]
```

Obtains (or renews) a certificate for `<service-name>`, always writing to the same predictable location regardless of mode:

```text
ssl/<service-name>/fullchain.pem
ssl/<service-name>/privkey.pem
```

- **Default (Let's Encrypt):** runs Certbot's webroot flow against `ssl/.webroot`. Requires `<domain>`'s DNS to already point at this host, and an Nginx server block already serving `ssl/.webroot` at `/.well-known/acme-challenge/` (see the consuming service's own README for its exact bootstrap order — Nginx has to be up *before* this script runs, since the ACME challenge is served through it).
- **`--self-signed`:** generates a local self-signed certificate instead — no domain or running Nginx required. Useful before a real domain exists, or for local testing.

Consumers (`nginx.conf`, the registry's `docker-compose.yml`) always point at `ssl/<service-name>/{fullchain,privkey}.pem` and don't need to know which mode produced them.

Optional env var: `LETSENCRYPT_EMAIL` (contact address for expiry notices; omitted registrations still work but get no renewal-reminder emails from Let's Encrypt).

## Renewal

Re-run the same command later; Certbot only actually renews if the certificate is close to expiry. Set up a host cron entry (not automated by this repo yet) to run it periodically, e.g. weekly.
