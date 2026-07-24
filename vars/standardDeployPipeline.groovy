/**
 * Reusable pipeline: GitHub -> Build -> Docker Build -> Push -> Deploy via SSH.
 *
 * Required config:
 *   targetHost  - host to deploy to (e.g. staging.example.com)
 *   Exactly one of:
 *     imageName - single Docker image name to build/tag/push (single-image apps)
 *     images    - list of maps, for apps that build more than one image from
 *                 one repo (e.g. a frontend + an API, each with their own
 *                 Dockerfile). Each entry:
 *                   name       - image name to build/tag/push (required)
 *                   context    - docker build context dir (default: '.')
 *                   dockerfile - path to the Dockerfile, relative to context
 *                                (default: 'Dockerfile')
 *                   buildArgs  - map of --build-arg KEY=VALUE pairs (optional)
 *
 * Optional config:
 *   targetEnv             - environment label, used only for logging/echo (default: 'staging')
 *   sshCredentialsId      - Jenkins credentials ID for the deploy SSH key (default: 'deploy-ssh-key')
 *   deployUser            - SSH user on the target host (default: 'deploy')
 *   remoteDir             - directory on the target host containing the app's docker-compose.yml (default: '/opt/app')
 *   registryUrl           - private registry URL (default: 'https://registry.example.com:5000' - override per environment)
 *   registryCredentialsId - Jenkins credentials ID for the registry (default: 'registry-credentials')
 *   buildStep             - closure with app-specific build steps (default: no-op)
 *
 * Example (two images, e.g. portfolio/'s Next.js frontend + .NET API):
 *   standardDeployPipeline(
 *       targetEnv: 'staging',
 *       targetHost: 'staging.example.com',
 *       images: [
 *           [name: 'portfolio-web', context: 'frontend'],
 *           [name: 'portfolio-app', context: 'backend'],
 *       ],
 *       registryUrl: 'https://registry.example.com:5000'
 *   )
 */
def call(Map config = [:]) {
    if (!config.targetHost) {
        error("standardDeployPipeline: 'targetHost' is required")
    }

    def images = []
    if (config.images) {
        images = config.images
    } else if (config.imageName) {
        images = [[name: config.imageName]]
    } else {
        error("standardDeployPipeline: either 'imageName' or 'images' is required")
    }

    def targetEnv = config.targetEnv ?: 'staging'
    def sshCredentialsId = config.sshCredentialsId ?: 'deploy-ssh-key'
    def deployUser = config.deployUser ?: 'deploy'
    def remoteDir = config.remoteDir ?: '/opt/app'
    def registryUrl = config.registryUrl ?: 'https://registry.example.com:5000'
    def registryCredentialsId = config.registryCredentialsId ?: 'registry-credentials'

    pipeline {
        agent any

        stages {
            stage('Checkout') {
                steps {
                    checkout scm
                }
            }

            stage('Build') {
                steps {
                    script {
                        if (config.buildStep) {
                            config.buildStep.call()
                        } else {
                            echo "No buildStep provided, skipping app-specific build."
                        }
                    }
                }
            }

            stage('Docker Build & Push') {
                steps {
                    script {
                        docker.withRegistry(registryUrl, registryCredentialsId) {
                            images.each { img ->
                                def context = img.context ?: '.'
                                def dockerfile = img.dockerfile ?: 'Dockerfile'
                                def buildArgs = (img.buildArgs ?: [:]).collect { k, v -> "--build-arg ${k}=${v}" }.join(' ')
                                def image = docker.build("${img.name}:${env.BUILD_NUMBER}", "-f ${context}/${dockerfile} ${buildArgs} ${context}")
                                image.push()
                                image.push('latest')
                            }
                        }
                    }
                }
            }

            stage('Deploy via SSH') {
                steps {
                    sshagent([sshCredentialsId]) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ${deployUser}@${config.targetHost} '
                                cd ${remoteDir} &&
                                docker compose pull &&
                                docker compose up -d
                            '
                        """
                    }
                }
            }
        }

        post {
            success {
                echo "Deployed [${images.collect { it.name }.join(', ')}]:${env.BUILD_NUMBER} to ${targetEnv} (${config.targetHost})"
            }
        }
    }
}
