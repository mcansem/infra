FROM jenkins/jenkins:lts-jdk17

USER root

# Install Docker CLI so pipeline stages can run `docker build` against the
# host's Docker daemon (Docker-outside-of-Docker via the mounted socket).
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Match the jenkins user's docker group to the host's docker.sock GID.
# Get the real value on the host with: getent group docker | cut -d: -f3
ARG DOCKER_GID=999
RUN groupmod -g ${DOCKER_GID} docker 2>/dev/null || groupadd -g ${DOCKER_GID} docker && \
    usermod -aG docker jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

USER jenkins
