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

update.sh

Ubuntu updates

Docker updates

Cleanup

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

deployment.md

backup.md

restore.md

recovery.md

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

Roadmap:

v0.1.0

Repository Foundation

README

CHANGELOG

LICENSE

Folder Structure

Basic Documentation

v0.2.0

Docker Infrastructure

Docker

Compose

Networks

Volumes

Portainer

v0.3.0

CI/CD

Jenkins

Pipeline

SSH Deployment

v0.4.0

Staging Environment

Nginx

PostgreSQL

Next.js

.NET

SSL

v0.5.0

Production Environment

Oracle Deployment

Production Configuration

Healthchecks

v0.6.0

Operations

Backup

Restore

Update

Cleanup

v0.7.0

Observability

Prometheus

Grafana

Monitoring

Alerts

v0.8.0

Homelab

Migration

Self-hosted Jenkins

Internal Infrastructure

v0.9.0

Documentation

Architecture

Runbooks

Recovery Guides

Diagrams

v1.0.0

Production Ready Stable Release

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

# Final Goal

The final result should not simply be a deployment repository.

It should become a reusable Infrastructure platform that can support multiple applications across cloud providers and future homelab environments.

The repository should reflect real-world DevOps practices rather than tutorial-level examples.

Whenever architectural decisions are made, prioritize:

* Simplicity
* Reusability
* Maintainability
* Automation
* Scalability
* Production-readiness

If multiple implementations are possible, always recommend the solution that would be preferred by an experienced Senior DevOps Engineer, and explain the trade-offs before generating code.
