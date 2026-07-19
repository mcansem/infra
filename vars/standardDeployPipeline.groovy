/**
 * Reusable pipeline: GitHub -> Build -> Docker Build -> Deploy via SSH.
 *
 * Required config:
 *   targetHost  - host to deploy to (e.g. staging.example.com)
 *   imageName   - Docker image name to build/tag
 *
 * Optional config:
 *   targetEnv         - environment label, used only for logging/echo (default: 'staging')
 *   sshCredentialsId  - Jenkins credentials ID for the deploy SSH key (default: 'deploy-ssh-key')
 *   deployUser        - SSH user on the target host (default: 'deploy')
 *   remoteDir         - directory on the target host containing the app's docker-compose.yml (default: '/opt/app')
 *   buildStep         - closure with app-specific build steps (default: no-op)
 */
def call(Map config = [:]) {
    if (!config.targetHost) {
        error("standardDeployPipeline: 'targetHost' is required")
    }
    if (!config.imageName) {
        error("standardDeployPipeline: 'imageName' is required")
    }

    def targetEnv = config.targetEnv ?: 'staging'
    def sshCredentialsId = config.sshCredentialsId ?: 'deploy-ssh-key'
    def deployUser = config.deployUser ?: 'deploy'
    def remoteDir = config.remoteDir ?: '/opt/app'

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

            stage('Docker Build') {
                steps {
                    script {
                        docker.build("${config.imageName}:${env.BUILD_NUMBER}")
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
                echo "Deployed ${config.imageName}:${env.BUILD_NUMBER} to ${targetEnv} (${config.targetHost})"
            }
        }
    }
}
