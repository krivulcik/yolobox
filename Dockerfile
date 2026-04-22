FROM ubuntu:24.04

# Build arguments
ARG USERNAME=yolo
ARG GITHUB_USERNAME=""
ARG INSTALL_PI=true

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=20
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

# Install Node.js (latest stable LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs

# Install pi-coding-agent globally and apply body-timeout patch (optional, controlled by INSTALL_PI)
COPY patches/body-timeout-fix-dist.zip /tmp/body-timeout-fix-dist.zip
RUN if [ "${INSTALL_PI}" = "true" ]; then \
        set -eux; \
        npm install -g @mariozechner/pi-coding-agent; \
        PI_AI_DIST="$(npm root -g)/@mariozechner/pi-coding-agent/node_modules/@mariozechner/pi-ai/dist"; \
        test -d "$PI_AI_DIST/providers"; \
        unzip -o /tmp/body-timeout-fix-dist.zip -d "$PI_AI_DIST"; \
        grep -q fetchWithNoBodyTimeout "$PI_AI_DIST/providers/anthropic.js"; \
        test -f "$PI_AI_DIST/utils/fetch.js"; \
    else \
        echo "Skipping pi-coding-agent install (INSTALL_PI=${INSTALL_PI})"; \
    fi && \
    rm -f /tmp/body-timeout-fix-dist.zip

# Install .NET 10 SDK
RUN wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y dotnet-sdk-10.0 && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root user, allow passwordless sudo
RUN useradd -m -s /bin/bash ${USERNAME} && \
    usermod -aG sudo ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${USERNAME} && \
    chmod 440 /etc/sudoers.d/90-${USERNAME} && \
    mkdir /workspace && \
    chown ${USERNAME}: /workspace

COPY home/yolo/ /home/${USERNAME}/

# When pi is installed, require the models.json template to exist in the image
RUN if [ "${INSTALL_PI}" = "true" ]; then \
        test -f /home/${USERNAME}/.pi/agent/models.json.template \
          || (echo "Missing home/yolo/.pi/agent/models.json.template (required when INSTALL_PI=true)" >&2 && exit 1); \
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

# Add .local/bin to PATH in bashrc
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/${USERNAME}/.bashrc && \
    chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.bashrc

# Install Claude Code CLI as the user
RUN su - ${USERNAME} -c "curl -fsSL https://claude.ai/install.sh | bash"

# Set default working directory
WORKDIR /workspace

# Entrypoint renders ~/.pi/agent/models.json from template using env vars
ENV USERNAME=${USERNAME}
ENV INSTALL_PI=${INSTALL_PI}
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
SHELL ["/bin/bash", "-c"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D"]
