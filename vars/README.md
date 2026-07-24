# vars/

This is the root of the Jenkins **Shared Library** (`infra-shared-library`, registered via [jenkins/casc.yaml](../jenkins/casc.yaml)).

It lives at the repository root — not under `jenkins/` — because Jenkins' `modernSCM` library retriever only auto-discovers `vars/`, `src/`, `resources/` when they sit at the root of the library's source repo. There is no reliable way to point it at a subdirectory, so this is a deliberate exception to the rest of the repo's per-concern folder layout.

## Usage

A single-image application repo consumes this library with a minimal `Jenkinsfile`:

```groovy
@Library('infra-shared-library') _

standardDeployPipeline(
    targetEnv: 'staging',
    targetHost: 'staging.example.com',
    imageName: 'my-app',
    registryUrl: 'https://registry.example.com:5000'
)
```

An app that builds more than one image from the same repo (e.g. `portfolio/` — a Next.js frontend and a .NET API, each with their own Dockerfile) uses `images` instead of `imageName`:

```groovy
standardDeployPipeline(
    targetEnv: 'staging',
    targetHost: 'staging.example.com',
    images: [
        [name: 'portfolio-web', context: 'frontend'],
        [name: 'portfolio-app', context: 'backend'],
    ],
    registryUrl: 'https://registry.example.com:5000'
)
```

See [standardDeployPipeline.groovy](standardDeployPipeline.groovy) for the full parameter list (including per-image `dockerfile`/`buildArgs`) and pipeline stages.
