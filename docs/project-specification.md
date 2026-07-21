# Infrastructure Repository - Technical Specification (v1)

## Project Vision

This repository is **NOT** a project-specific deployment repository.

Its goal is to become a reusable Infrastructure repository that can be used across multiple applications and servers.

The long-term objective is to create a clean, modular, production-ready DevOps repository that supports:

* Cloud deployments
* Self-hosted deployments
* Homelab deployments
* CI/CD
* Staging
* Production
* Disaster Recovery

The repository should follow **Senior DevOps Engineer** best practices.

---

# Main Philosophy

Application code and Infrastructure code must always remain separated.

Repositories:

portfolio/

* Next.js
* .NET 10

infra/

* Infrastructure
* Docker
* Jenkins
* Nginx
* Bash Scripts
* SSL
* Deployment
* Documentation

Infrastructure must be reusable regardless of the application.

---

# Guiding Principles

Write once, deploy anywhere.

Infrastructure code should not change depending on where it is deployed. Cloud providers (AWS, Google Cloud, Oracle Cloud, future Homelab) are deployment targets, not repository features.

* Infrastructure-as-Code
* Cloud-agnostic
* Modular
* Idempotent
* Reusable
* Production-ready
* Automation-first
* Self-hosting friendly
* Future-proof for Homelab

---

# Current Infrastructure Roadmap

Short Term

GitHub

↓

AWS EC2

* Ubuntu
* Docker
* Jenkins
* Portainer

↓

Google Cloud VM

* Ubuntu
* Docker
* Nginx
* PostgreSQL
* Next.js
* .NET API

↓

Oracle Cloud

Production

Long Term

GitHub

↓

Homelab

↓

Oracle Cloud Production

Jenkins will eventually migrate from AWS to Homelab.

The repository must be designed with this migration in mind.

---

# Repository Structure

infra/

scripts/

docker/

jenkins/

vars/

nginx/

ssl/

docs/

.github/

README.md

CHANGELOG.md

LICENSE

CONTRIBUTING.md

.editorconfig

.gitignore

Everything should be modular.

---

# Bash Scripts

Scripts should be parameter driven.

Example:

./install.sh ci

./install.sh staging

./install.sh production

Behavior should depend on the selected environment.

Requirements:

* Idempotent
* Modular
* Reusable
* Safe to execute multiple times

Use:

set -euo pipefail

Functions instead of duplicated code.

Colored logging.

Proper error handling.

---

# Docker

Docker Compose must be used.

Profiles or override files are acceptable.

Requirements:

* Healthchecks
* Restart policies
* Named volumes
* Custom networks
* Environment variables
* Clean naming convention

---

# Jenkins

Runs inside Docker.

Pipeline:

GitHub

↓

Build

↓

Docker Build

↓

Deploy via SSH

The pipeline must support future multi-environment deployment.

Future targets:

AWS

Google

Oracle

Homelab

---

# Portainer

Used for Docker management.

Architecture should allow one Portainer instance to manage multiple Docker hosts whenever possible.

---

# Nginx

Responsibilities:

Reverse Proxy

SSL

Compression

Security Headers

Rate Limiting (optional)

Production Ready Configuration

---

# PostgreSQL

Dockerized.

Backup support.

Restore support.

Persistent storage.

---

# Operations

backup.sh

Database backup

Volume backup

Rotation

Verification

restore.sh

Database restore

Volume restore

Validation

update.sh

Ubuntu updates

Docker updates

cleanup.sh

Docker system cleanup

Build cache cleanup

Never touches volumes

deploy.sh

Git Pull

Docker Pull

Docker Compose Up

Health Check

Rollback Ready

---

# Logging

Every script must provide readable output.

Levels:

INFO

SUCCESS

WARNING

ERROR

---

# Documentation

The docs folder should include:

architecture.md

roadmap.md

project-specification.md

deployment.md

platforms/ (AWS, Google Cloud, Oracle Cloud, Homelab guides)

backup.md

restore.md

recovery.md

runbooks.md

onboarding.md

Directory structure should remain easy to navigate.

---

# Coding Standards

Follow:

Bash Best Practices

Docker Best Practices

DevOps Best Practices

Keep everything:

Readable

Maintainable

Reusable

Extensible

---

# Versioning Strategy

Semantic Versioning will be adopted from the very beginning.

The project will evolve through incremental releases.

See [docs/roadmap.md](roadmap.md) for the full phase-by-phase roadmap (v0.1.0 through v1.0.0), current status of each phase, and the history of roadmap revisions.

---

# Git Strategy

Every roadmap phase should result in:

One Pull Request (if applicable)

One Release

One Git Tag

One CHANGELOG update

Meaningful commit history.

Commit messages should follow Conventional Commits whenever applicable.

Examples:

feat:

fix:

docs:

refactor:

chore:

ci:

build:

---

# CHANGELOG

CHANGELOG.md must exist from the very first commit.

Use the **Keep a Changelog** format.

Follow Semantic Versioning.

Every release must document:

Added

Changed

Fixed

Removed

Deprecated (when applicable)

---

# Out of Scope

Kubernetes, Terraform, and Ansible are intentionally excluded from the v1 roadmap.

They are not rejected permanently. They belong to a future v2.x roadmap, after the Docker-based infrastructure reaches a stable v1.0.0 release.

---

# Final Goal

The final result should not simply be a deployment repository.

It should become a reusable Infrastructure platform that can support multiple applications across cloud providers and future homelab environments.

The repository should reflect real-world DevOps practices rather than tutorial-level examples.

Whenever architectural decisions are made, prioritize the Guiding Principles defined at the top of this document.

If multiple implementations are possible, always recommend the solution that would be preferred by an experienced Senior DevOps Engineer, and explain the trade-offs before generating code.
