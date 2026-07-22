# Architecture

## Overview

Two host roles carry the whole system (a third, `agent`, exists only for future Portainer-managed nodes with no services of their own — see [docs/roadmap.md](roadmap.md)'s Deployment Journey):

- **`management`** — Jenkins (CI/CD), Portainer (Docker management), a private Docker Registry, and the observability stack (Prometheus, Alertmanager, Grafana, Uptime Kuma), all fronted by a single shared reverse proxy.
- **`app`** — the actual application stack: Nginx → `app` (a single container — Next.js static export served by the .NET API's own process) → PostgreSQL.

The two communicate through exactly one channel by design: the `app` host pulls images that Jenkins (on `management`) built and pushed to the Registry. Nothing else crosses the host boundary except, optionally, Prometheus scraping the `app` host's metrics exporters (see [docker/monitoring-agent/README.md](../docker/monitoring-agent/README.md) — off by default, a documented opt-in).

## Component diagram

```mermaid
graph TB
    subgraph GitHub
        Repo[Application repo]
    end

    subgraph management["management host"]
        Jenkins[Jenkins]
        Portainer[Portainer]
        Registry[("Private Registry")]
        MgmtProxy["management-proxy (nginx)"]
        Prom[Prometheus]
        Alert[Alertmanager]
        Grafana[Grafana]
        Uptime["Uptime Kuma"]
    end

    subgraph app["app host"]
        AppNginx["nginx"]
        App["app (Next.js export + .NET API)"]
        Postgres[("PostgreSQL")]
    end

    Repo -- webhook --> Jenkins
    Jenkins -- docker push --> Registry
    Jenkins -. "SSH deploy" .-> AppNginx
    Registry -. "docker pull" .-> App
    MgmtProxy --> Jenkins
    MgmtProxy --> Grafana
    MgmtProxy --> Uptime
    Grafana --> Prom
    Prom --> Alert
    AppNginx --> App
    App --> Postgres
```

## Network topology (externally reachable ports)

Matches `scripts/harden-host.sh`'s `role_ports()` exactly — this diagram and that function should never drift apart.

```mermaid
graph LR
    Internet((Internet))

    subgraph management["management role"]
        M1["80/tcp, 443/tcp — management-proxy"]
        M2["9443/tcp — Portainer"]
        M3["5000/tcp — Registry"]
    end

    subgraph appRole["app role"]
        A1["80/tcp, 443/tcp — app nginx"]
    end

    subgraph agentRole["agent role"]
        AG1["9001/tcp — Portainer Agent"]
    end

    Internet --> M1
    Internet --> M2
    Internet --> M3
    Internet --> A1
    Internet --> AG1
```

Deliberately absent: Node Exporter (9100) and cAdvisor (8080), on every role. Both bind to `127.0.0.1` only and are never in the externally-reachable set — see [docker/monitoring-agent/README.md](../docker/monitoring-agent/README.md) for why and how the opt-in works.

## CI/CD flow

Visualizes [vars/standardDeployPipeline.groovy](../vars/standardDeployPipeline.groovy)'s stage order — this is the same flow whether it's Jenkins running it or the manual fallback (`scripts/deploy.sh`, see [docs/deployment.md](deployment.md)) doing the equivalent by hand.

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant GH as GitHub
    participant CI as Jenkins
    participant Reg as Private Registry
    participant Host as Target host

    Dev->>GH: git push
    GH->>CI: webhook
    CI->>CI: Checkout, Build
    CI->>CI: Docker Build
    CI->>Reg: docker push
    CI->>Host: SSH: docker compose pull
    Host->>Reg: docker pull
    CI->>Host: SSH: docker compose up -d
    CI->>Host: wait for healthy
    alt healthy
        CI->>Dev: deployment successful
    else unhealthy
        CI->>Host: re-tag previous image, restart
        CI->>Dev: deployment failed, rolled back
    end
```

## Further reading

- [docs/deployment.md](deployment.md) — the deploy flow and role vocabulary in prose.
- [docs/platforms/](platforms/) — how each host actually gets provisioned, per cloud provider.
- [docs/recovery.md](recovery.md) — what happens when a host in this diagram is lost.
- [docs/runbooks.md](runbooks.md) — what to do when one of the alerts in the observability stack fires.
