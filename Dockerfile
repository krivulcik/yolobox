FROM ubuntu:24.04

# Build arguments
ARG USERNAME=yolo
# UID/GID the container user is created with. Build with your host user's IDs
# (docker-compose passes HOST_UID/HOST_GID through) so the user and its home
# directory match the host from the start; the entrypoint still remaps at
# runtime if the image was built with different IDs.
ARG USER_UID=1000
ARG USER_GID=1000
ARG GITHUB_USERNAME=""
ARG INSTALL_PI=true

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=22
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools

# Update system and install basic dependencies
RUN apt-get update && apt-get install -y \
    curl \
    vim \
    mc \
    wget \
    gpg \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    unzip \
    openssh-client \
    openssh-server \
    expect \
    sshpass \
    screen \
    tmux \
    sudo \
    git \
    libxml2-utils \
    jq \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Harden SSH configuration
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    echo "AllowUsers ${USERNAME}" >> /etc/ssh/sshd_config && \
    echo "Protocol 2" >> /etc/ssh/sshd_config && \
    echo "LoginGraceTime 20" >> /etc/ssh/sshd_config && \
    echo "MaxAuthTries 3" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config && \
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config && \
    echo "UsePAM yes" >> /etc/ssh/sshd_config

# Install Node.js (>=22.19.0 required by @earendil-works/pi-coding-agent)
# Installed from the official nodejs.org tarball rather than NodeSource: the
# deb.nodesource.com setup script and gpg key currently return HTTP 403, and a
# non-fatal fetch there silently falls back to Ubuntu's nodejs 18, which ships
# no npm at all. Fail loudly instead, and verify npm is present.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) node_arch=x64 ;; \
        arm64) node_arch=arm64 ;; \
        *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    node_ver="$(curl -fsSL https://nodejs.org/dist/index.json \
        | jq -r --arg m "v${NODE_VERSION}." '[.[] | select(.version | startswith($m))][0].version')"; \
    test -n "$node_ver" -a "$node_ver" != "null"; \
    curl -fsSL "https://nodejs.org/dist/${node_ver}/node-${node_ver}-linux-${node_arch}.tar.xz" -o /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
        --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md; \
    rm /tmp/node.tar.xz; \
    node --version; \
    npm --version

# Install pi-coding-agent globally (optional, controlled by INSTALL_PI)
# Package migrated from @mariozechner to the @earendil-works org (https://github.com/earendil-works/pi).
# Note: body-timeout fix is now handled by the anthropic-no-timeout extension
RUN if [ "${INSTALL_PI}" = "true" ]; then \
        set -eux; \
        npm install -g @earendil-works/pi-coding-agent; \
    else \
        echo "Skipping pi-coding-agent install (INSTALL_PI=${INSTALL_PI})"; \
    fi

# Install .NET 10 SDK
RUN wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y dotnet-sdk-10.0 && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root user with host-matching UID/GID, allow passwordless sudo
RUN set -eux; \
    # Remove the default 'ubuntu' user and whatever else occupies the target
    # UID/GID, so useradd/groupadd can't fail or half-apply on a collision.
    if id ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi; \
    existing_user="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
    if [ -n "$existing_user" ]; then userdel -r "$existing_user" || userdel "$existing_user" || true; fi; \
    existing_group="$(getent group "${USER_GID}" | cut -d: -f1)"; \
    if [ -n "$existing_group" ]; then groupdel "$existing_group" || true; fi; \
    groupadd -g ${USER_GID} ${USERNAME}; \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USERNAME}; \
    usermod -aG sudo ${USERNAME}; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${USERNAME}; \
    chmod 440 /etc/sudoers.d/90-${USERNAME}; \
    mkdir /workspace; \
    chown ${USERNAME}: /workspace

COPY home/yolo/ /home/${USERNAME}/

# Install anthropic-no-timeout extension dependencies (optional, controlled by INSTALL_PI)
# Extension source is already in home/yolo/.pi/agent/extensions/anthropic-no-timeout/
RUN if [ "${INSTALL_PI}" = "true" ]; then \
        set -eux; \
        cd /home/${USERNAME}/.pi/agent/extensions/anthropic-no-timeout; \
        npm install --omit=dev; \
        chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.pi; \
        echo "Installed anthropic-no-timeout extension dependencies"; \
    else \
        echo "Skipping anthropic-no-timeout extension (INSTALL_PI=${INSTALL_PI})"; \
    fi

# When pi is installed, require the extension to exist in the image
RUN if [ "${INSTALL_PI}" = "true" ]; then \
        test -f /home/${USERNAME}/.pi/agent/extensions/anthropic-no-timeout/index.ts \
          || (echo "Missing home/yolo/.pi/agent/extensions/anthropic-no-timeout/index.ts (required when INSTALL_PI=true)" >&2 && exit 1); \
    fi

# Install the pi-subagents extension from its own repo (optional, controlled by INSTALL_PI).
# Kept as a clone (not vendored) so the extension stays a single source of truth in its repo;
# yolobox only owns the box-specific config.json, generated at runtime by entrypoint.sh.
# Override PI_SUBAGENTS_REPO/REF to use a fork or pin a commit/tag. Changing REF busts the cache.
ARG PI_SUBAGENTS_REPO=https://github.com/MirecX/pi-subagents
ARG PI_SUBAGENTS_REF=main
RUN if [ "${INSTALL_PI}" = "true" ]; then \
        set -eux; \
        su - ${USERNAME} -c "git clone '${PI_SUBAGENTS_REPO}' ~/.pi/agent/extensions/pi-subagents \
            && git -C ~/.pi/agent/extensions/pi-subagents checkout '${PI_SUBAGENTS_REF}' \
            && rm -rf ~/.pi/agent/extensions/pi-subagents/.git"; \
        test -f /home/${USERNAME}/.pi/agent/extensions/pi-subagents/index.ts \
          || (echo "pi-subagents clone missing index.ts (repo=${PI_SUBAGENTS_REPO} ref=${PI_SUBAGENTS_REF})" >&2 && exit 1); \
    else \
        echo "Skipping pi-subagents (INSTALL_PI=${INSTALL_PI})"; \
    fi

# Install the pi-searxng extension (web_search + web_fetch) from its repo (optional, INSTALL_PI).
# Unlike the other extensions this one has npm deps and a build step (tsc -> dist/), so we
# clone, `npm install`, then `npm run build`. The SearXNG endpoint is provided at runtime via
# the SEARXNG_URL env var (a shared instance; see docker-compose.yml / .env).
# NOTE: this fork's default branch is `master`.
ARG PI_SEARXNG_REPO=https://github.com/MirecX/pi-searxng
ARG PI_SEARXNG_REF=master
RUN if [ "${INSTALL_PI}" = "true" ]; then \
        set -eux; \
        su - ${USERNAME} -c "git clone '${PI_SEARXNG_REPO}' ~/.pi/agent/extensions/pi-searxng \
            && git -C ~/.pi/agent/extensions/pi-searxng checkout '${PI_SEARXNG_REF}' \
            && rm -rf ~/.pi/agent/extensions/pi-searxng/.git \
            && cd ~/.pi/agent/extensions/pi-searxng && npm install && npm run build"; \
        test -f /home/${USERNAME}/.pi/agent/extensions/pi-searxng/dist/index.js \
          || (echo "pi-searxng build missing dist/index.js (repo=${PI_SEARXNG_REPO} ref=${PI_SEARXNG_REF})" >&2 && exit 1); \
    else \
        echo "Skipping pi-searxng (INSTALL_PI=${INSTALL_PI})"; \
    fi

# Fetch GitHub public keys (only if GITHUB_USERNAME is set)
RUN mkdir -p /home/${USERNAME}/.ssh && \
    if [ -n "${GITHUB_USERNAME}" ]; then \
        curl -s https://github.com/${GITHUB_USERNAME}.keys -o /home/${USERNAME}/.ssh/authorized_keys && \
        chmod 600 /home/${USERNAME}/.ssh/authorized_keys; \
    fi && \
    chmod 700 /home/${USERNAME}/.ssh && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME} && \
    mkdir /var/run/sshd

# Add .local/bin to PATH and a 'claude' alias (always skip permission prompts) in bashrc
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/${USERNAME}/.bashrc && \
    echo "alias claude='claude --dangerously-skip-permissions'" >> /home/${USERNAME}/.bashrc && \
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.bashrc

# deepseek_override: system script that sets a model to a DeepSeek reasoning profile in
# pi's models.json (post-deploy, no entrypoint change). Installed to /usr/local/bin so it
# is on PATH for all shells (SSH, agent bash tool, root). home/yolo/.local/bin copy is for
# interactive login shells.
COPY home/yolo/.local/bin/deepseek_override /usr/local/bin/deepseek_override
RUN chmod 755 /usr/local/bin/deepseek_override /home/${USERNAME}/.local/bin/deepseek_override && \
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.local/bin/deepseek_override

# Install Claude Code CLI as the user
RUN su - ${USERNAME} -c "curl -fsSL https://claude.ai/install.sh | bash"

# Install TPM (Tmux Plugin Manager)
RUN su - ${USERNAME} -c "git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"

# Set default working directory
WORKDIR /workspace

# Entrypoint renders ~/.pi/agent/models.json from template using env vars
ENV USERNAME=${USERNAME}
ENV INSTALL_PI=${INSTALL_PI}
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
SHELL ["/bin/bash", "-c"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D"]
