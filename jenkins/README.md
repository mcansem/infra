# jenkins/

> Status: empty. Landing in v0.3.0 (CI/CD phase).

This folder will hold the Dockerized Jenkins setup and declarative `Jenkinsfile` pipeline definitions.

Pipeline shape: `GitHub → Build → Docker Build → Deploy via SSH`, parametrized by target host so the same pipeline can later serve AWS, Google Cloud, Oracle Cloud, and the homelab (see the Long Term roadmap in [project-specification.md](../docs/project-specification.md)).
