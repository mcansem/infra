# ssl/

> Status: empty. Landing in v0.4.0+ (Staging/Production Environment phases).

At runtime, this folder holds certificate material (`.pem`, `.key`, `.crt`, `.csr`) mounted into the Nginx container. Certificate files themselves are **never committed** — see [.gitignore](../.gitignore). Only this README and, later, certificate-generation/renewal scripts live here in version control.
