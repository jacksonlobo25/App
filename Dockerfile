FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG DEV_USERNAME=dev
ARG DEV_UID=1001
ARG DEV_GID=1001
ARG PYTHON_VERSION=3.13.2
ARG NODE_MAJOR=22
ARG MAVEN_VERSION=3.9.8
ARG GRADLE_VERSION=8.10.2
ARG SPRINGBOOT_CLI_VERSION=3.3.2
ARG TZ=UTC

ENV TZ=${TZ}

# base
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release software-properties-common \
    build-essential pkg-config unzip zip tar xz-utils locales tzdata sudo \
    openssh-server supervisor vim less htop git git-lfs \
    postgresql-client \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    libncursesw5-dev tk-dev libffi-dev liblzma-dev libxml2-dev libxmlsec1-dev \
    && rm -rf /var/lib/apt/lists/* && git lfs install --system

# locale
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Java 21
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-21-jdk \
    && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:${PATH}"

# Node.js (NodeSource, configurable major)
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
RUN corepack enable

# pyenv + Python 3.13.x
ENV PYENV_ROOT=/opt/pyenv
ENV PATH=${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}
RUN git clone --depth=1 https://github.com/pyenv/pyenv.git "${PYENV_ROOT}" \
 && "${PYENV_ROOT}/bin/pyenv" install -s "${PYTHON_VERSION}" \
 && "${PYENV_ROOT}/bin/pyenv" global "${PYTHON_VERSION}" \
 && python -m ensurepip \
 && python -m pip install -U pip pipx \
 && python -m pipx ensurepath \
 && "${PYENV_ROOT}/bin/pyenv" rehash

# dev user
RUN groupadd -g ${DEV_GID} ${DEV_USERNAME} \
 && useradd -m -s /bin/bash -u ${DEV_UID} -g ${DEV_GID} -G sudo ${DEV_USERNAME} \
 && install -d -m 0755 /etc/sudoers.d \
 && echo "${DEV_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEV_USERNAME} \
 && chmod 0440 /etc/sudoers.d/${DEV_USERNAME}

# SSHD for JetBrains Gateway (keys only)
RUN mkdir -p /var/run/sshd \
    && sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# SDKMAN! (Maven, Gradle, Spring Boot CLI) as DEV user
USER ${DEV_USERNAME}
SHELL ["/bin/bash", "-lc"]

ENV SDKMAN_DIR="/home/${DEV_USERNAME}/.sdkman"
# Prevent SDKMAN from prompting during install
ENV SDKMAN_NON_INTERACTIVE=true

RUN curl -s https://get.sdkman.io | bash
RUN source "$SDKMAN_DIR/bin/sdkman-init.sh" \
 && sdk install maven ${MAVEN_VERSION} \
 && sdk install gradle ${GRADLE_VERSION} \
 && sdk install springboot ${SPRINGBOOT_CLI_VERSION}

ENV PATH="$SDKMAN_DIR/candidates/maven/current/bin:$SDKMAN_DIR/candidates/gradle/current/bin:$SDKMAN_DIR/candidates/springboot/current/bin:$PATH"

USER root
SHELL ["/bin/sh", "-c"]


# scripts
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# supervisor config (ssh key setup + sshd)
RUN bash -lc 'cat > /etc/supervisor/supervisord.conf << "EOF"\n\
[supervisord]\n\
nodaemon=true\n\
logfile=/var/log/supervisord.log\n\
\n\
[program:ssh_setup_keys]\n\
command=/opt/scripts/ssh-setup-keys.sh\n\
user=root\n\
priority=10\n\
autostart=true\n\
autorestart=false\n\
stdout_logfile=/var/log/ssh-setup-keys.log\n\
stderr_logfile=/var/log/ssh-setup-keys.err\n\
\n\
[program:sshd]\n\
command=/usr/sbin/sshd -D\n\
priority=50\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/var/log/sshd.supervisor.log\n\
stderr_logfile=/var/log/sshd.supervisor.err\n\
EOF'

EXPOSE 22 8080 5173
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/supervisord","-n","-c","/etc/supervisor/supervisord.conf"]
