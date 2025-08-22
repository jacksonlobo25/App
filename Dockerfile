FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG DEV_USERNAME=dev
ARG DEV_UID=1000
ARG DEV_GID=1000
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

# PostgreSQL server + client (PGDG)
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg \
    && bash -lc 'echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
    && apt-get update && apt-get install -y --no-install-recommends \
        postgresql postgresql-client postgresql-contrib libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# prepare PG cluster in a single persistent location
ENV PGDATA=/var/lib/postgresql/data
RUN bash -lc 'PG_MAJOR=$(psql -V | awk "{print \$3}" | cut -d. -f1) \
    && pg_dropcluster --stop $PG_MAJOR main \
    && pg_createcluster $PG_MAJOR main -- --data-directory=$PGDATA \
    && sed -ri "s/^#?listen_addresses.*/listen_addresses = '\''*'\''/" /etc/postgresql/$PG_MAJOR/main/postgresql.conf \
    && echo "host all all 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/$PG_MAJOR/main/pg_hba.conf \
    && echo "host all all ::0/0 scram-sha-256" >> /etc/postgresql/$PG_MAJOR/main/pg_hba.conf \
    && echo $PG_MAJOR > /etc/postgresql/PG_MAJOR'

# pyenv + Python 3.13.x
ENV PYENV_ROOT=/opt/pyenv
ENV PATH=${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}
RUN git clone --depth=1 https://github.com/pyenv/pyenv.git ${PYENV_ROOT} \
    && bash -lc "pyenv install ${PYTHON_VERSION} && pyenv global ${PYTHON_VERSION}" \
    && bash -lc "python -m ensurepip && python -m pip install -U pip pipx" \
    && bash -lc "pipx ensurepath"

# dev user
RUN groupadd -g ${DEV_GID} ${DEV_USERNAME} \
    && useradd -m -s /bin/bash -u ${DEV_UID} -g ${DEV_GID} -G sudo ${DEV_USERNAME} \
    && echo "${DEV_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEV_USERNAME}

# SSHD for JetBrains Gateway
RUN mkdir -p /var/run/sshd \
    && sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# SDKMAN! (Maven, Gradle, Spring Boot CLI) as DEV user
USER ${DEV_USERNAME}
ENV SDKMAN_DIR=/home/${DEV_USERNAME}/.sdkman
RUN curl -s https://get.sdkman.io | bash \
    && bash -lc "source $SDKMAN_DIR/bin/sdkman-init.sh && sdk install maven ${MAVEN_VERSION} && sdk install gradle ${GRADLE_VERSION} && sdk install springboot ${SPRINGBOOT_CLI_VERSION}"
ENV PATH=/home/${DEV_USERNAME}/.sdkman/candidates/maven/current/bin:/home/${DEV_USERNAME}/.sdkman/candidates/gradle/current/bin:/home/${DEV_USERNAME}/.sdkman/candidates/springboot/current/bin:${PATH}
USER root

# scripts
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

# supervisor config (postgres + ssh key setup + sshd + one-shot DB bootstrap)
RUN bash -lc 'cat > /etc/supervisor/supervisord.conf << "EOF"\n\
[supervisord]\n\
nodaemon=true\n\
logfile=/var/log/supervisord.log\n\
\n\
[program:postgres]\n\
command=/opt/scripts/start-postgres.sh\n\
user=postgres\n\
autostart=true\n\
autorestart=true\n\
stdout_logfile=/var/log/postgres.supervisor.log\n\
stderr_logfile=/var/log/postgres.supervisor.err\n\
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
\n\
[program:pg_bootstrap]\n\
command=/opt/scripts/pg-bootstrap.sh\n\
priority=60\n\
autostart=true\n\
autorestart=false\n\
stdout_logfile=/var/log/pg-bootstrap.log\n\
stderr_logfile=/var/log/pg-bootstrap.err\n\
EOF'

EXPOSE 22 5432 8080 5173
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/supervisord","-n","-c","/etc/supervisor/supervisord.conf"]