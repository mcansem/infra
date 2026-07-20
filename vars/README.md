# vars/

This is the root of the Jenkins **Shared Library** (`infra-shared-library`, registered via [jenkins/casc.yaml](../jenkins/casc.yaml)).

It lives at the repository root — not under `jenkins/` — because Jenkins' `modernSCM` library retriever only auto-discovers `vars/`, `src/`, `resources/` when they sit at the root of the library's source repo. There is no reliable way to point it at a subdirectory, so this is a deliberate exception to the rest of the repo's per-concern folder layout.

## Usage

An application repo (e.g. `portfolio/`) consumes this library with a minimal `Jenkinsfile`:

```groovy
@Library('infra-shared-library') _

standardDeployPipeline(
    targetEnv: 'staging',
    targetHost: 'staging.example.com',
    imageName: 'portfolio-app',
    registryUrl: 'https://registry.example.com:5000'
)
```

See [standardDeployPipeline.groovy](standardDeployPipeline.groovy) for the full parameter list and pipeline stages.
