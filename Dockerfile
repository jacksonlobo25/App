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

RUN set -eux; apt-get update
RUN apt-get install -y --no-install-recommends software-properties-common
RUN add-apt-repository -y universe && apt-get update

# preseed tz first
RUN set -eux; ln -fs "/usr/share/zoneinfo/${TZ:-UTC}" /etc/localtime; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata; \
    dpkg-reconfigure -f noninteractive tzdata

# now install in chunks so the failing package is obvious
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    unzip zip tar xz-utils locales sudo vim less htop
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential pkg-config git git-lfs
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openssh-server supervisor
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    postgresql-client
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    libncurses-dev tk-dev libffi-dev liblzma-dev libxml2-dev libxmlsec1-dev
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openjdk-21-jdk-headless

# locale
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Java 21
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
# keep it quiet and non-interactive
ENV SDKMAN_NON_INTERACTIVE=true
ENV SDKMAN_CLI_NO_INTERACTIVE=true
ENV SDKMAN_CLI_QUIET=true

# install SDKMAN
RUN curl -s https://get.sdkman.io | bash

# prove sdk is initialized
RUN test -s "$SDKMAN_DIR/bin/sdkman-init.sh" \
 && source "$SDKMAN_DIR/bin/sdkman-init.sh" \
 && sdk version

# Try exact versions; if not available, install latest
RUN source "$SDKMAN_DIR/bin/sdkman-init.sh" \
 && (yes | sdk install maven ${MAVEN_VERSION}     || yes | sdk install maven) \
 && (yes | sdk install gradle ${GRADLE_VERSION}   || yes | sdk install gradle) \
 && (yes | sdk install springboot ${SPRINGBOOT_CLI_VERSION} || yes | sdk install springboot)

# Put candidates on PATH
ENV PATH="$SDKMAN_DIR/candidates/maven/current/bin:$SDKMAN_DIR/candidates/gradle/current/bin:$SDKMAN_DIR/candidates/springboot/current/bin:$PATH"

# back to root
USER root
SHELL ["/bin/sh", "-c"]

# scripts
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# supervisor config — pidfile in /var/run, logs to stdout/stderr, ensure host keys first
RUN install -d -m 0755 /var/run /var/log/supervisor

RUN cat >/etc/supervisor/supervisord.conf <<'EOF'
[supervisord]
nodaemon=true
pidfile=/var/run/supervisord.pid
logfile=/dev/stdout
logfile_maxbytes=0

[program:ssh_hostkeys]
command=/usr/bin/ssh-keygen -A
user=root
priority=5
autostart=true
startsecs=0
startretries=0
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:ssh_setup_keys]
command=/opt/scripts/ssh-setup-keys.sh
user=root
priority=10
autostart=true
startsecs=0
startretries=0
autorestart=false
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:sshd]
command=/usr/sbin/sshd -D
user=root
priority=50
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

EXPOSE 22 8080 5173
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/supervisord","-n","-c","/etc/supervisor/supervisord.conf"]
