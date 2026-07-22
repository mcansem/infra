# nginx/

Reverse proxy configuration, consumed by [docker/app/](../docker/app/) (the staging/production app stack) and mounted read-only into its `nginx` service — this folder holds the config file, not the compose service definition itself.

## app.conf

- Port 80: redirects everything to HTTPS, except `/.well-known/acme-challenge/` (served for Let's Encrypt's webroot verification — see [ssl/README.md](../ssl/README.md)).
- Port 443: TLS termination, gzip, security headers (`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `HSTS`, `Permissions-Policy`, a conservative starter `Content-Security-Policy`), rate limiting (`limit_req`, 10r/s with burst 20 - a starting point, not a measured value), and a single proxied location: everything goes to `app`, the one container serving both the API and the Next.js static export (see [docker/app/README.md](../docker/app/README.md)).

The upstream is referenced by its Compose service name (`app`) — this config only works mounted into the `docker/app/` stack, on `app_net`.

## Conventions

Production-ready configuration, not tutorial-level: real security headers, no wildcard CORS, TLS termination via a real (or self-signed-until-a-domain-exists) certificate rather than plaintext HTTP.
