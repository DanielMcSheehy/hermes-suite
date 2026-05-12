# =============================================================================
# Hermes Suite — All-in-One Container Image
# Combines: hermes-agent + hermes-webui + hermes-dashboard
#
# Services:
#   hermes-gateway   — Agent gateway on port 8642
#   hermes-dashboard — Monitoring dashboard on port 9119
#   hermes-webui     — Browser chat interface on port 8787
# =============================================================================

ARG AGENT_VERSION=v2026.5.7
FROM docker.io/nousresearch/hermes-agent:${AGENT_VERSION}

USER root

# ---------------------------------------------------------------------------
# Install system dependencies
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    git \
    curl \
    nano \
    net-tools \
    iputils-ping \
    iproute2 \
    openssh-client \
    procps \
  && rm -rf /var/lib/apt/lists/*

# Allow hermes user to use sudo without password
RUN echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ---------------------------------------------------------------------------
# Install Tinker-Atropos reasoning engine
# ---------------------------------------------------------------------------
RUN uv pip install -e /opt/hermes/tinker-atropos

# ---------------------------------------------------------------------------
# Install browser/tool dependencies for agent
# ---------------------------------------------------------------------------
RUN cd /opt/hermes \
  && npm install --prefer-offline --no-audit \
  && npx playwright install --with-deps chromium \
  && rm -rf /opt/hermes/scripts/whatsapp-bridge \
  && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install supervisord into dedicated venv
# ---------------------------------------------------------------------------
RUN uv venv /opt/supervisor \
  && uv pip install --python /opt/supervisor/bin/python3 supervisor \
  && ln -sf /opt/supervisor/bin/supervisord /usr/local/bin/supervisord \
  && ln -sf /opt/supervisor/bin/supervisorctl /usr/local/bin/supervisorctl

# ---------------------------------------------------------------------------
# Install hermes-webui
# ---------------------------------------------------------------------------
ARG HERMES_WEBUI_VERSION=v0.51.50

RUN cd /opt \
  && git clone --depth 1 --branch ${HERMES_WEBUI_VERSION} \
      https://github.com/nesquena/hermes-webui.git hermes-webui \
  && uv venv /opt/hermes-webui/venv \
  && uv pip install --python /opt/hermes-webui/venv/bin/python3 --no-cache-dir \
      -r /opt/hermes-webui/requirements.txt \
  && uv pip install --python /opt/hermes-webui/venv/bin/python3 --no-cache-dir \
      -e "/opt/hermes[all]" \
  && rm -rf /opt/hermes-webui/.git

# Bake version tag into webui
RUN echo "__version__ = '${HERMES_WEBUI_VERSION}'" > /opt/hermes-webui/api/_version.py

# ---------------------------------------------------------------------------
# Runtime config
# ---------------------------------------------------------------------------
ARG AGENT_VERSION=v2026.5.7
ARG HERMES_WEBUI_VERSION=v0.51.50

LABEL org.opencontainers.image.title="Hermes Suite" \
      org.opencontainers.image.description="All-in-one: hermes-agent + hermes-webui + hermes-dashboard" \
      org.opencontainers.image.source="https://github.com/sunnysktsang/hermes-suite" \
      org.opencontainers.image.vendor="sunnysktsang" \
      hermes-suite.agent-version="${AGENT_VERSION}" \
      hermes-suite.webui-version="${HERMES_WEBUI_VERSION}"

ENV PATH="/opt/hermes/.venv/bin:/opt/hermes-webui/venv/bin:$PATH"
ENV HERMES_HOME=/opt/data
ENV HERMES_DATA_DIR=/opt/data
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist

ENV HERMES_WEBUI_HOST=0.0.0.0
ENV HERMES_WEBUI_PORT=8787
ENV HERMES_WEBUI_STATE_DIR=/opt/data/webui
ENV HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace
ENV HERMES_WEBUI_AGENT_DIR=/opt/hermes

# ---------------------------------------------------------------------------
# Supervisor config and startup script
# ---------------------------------------------------------------------------
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY start.sh /opt/hermes-suite/start.sh

# Make all runtime paths writable before start.sh drops root privileges
RUN mkdir -p \
      /opt/data \
      /opt/data/webui \
      /workspace \
      /tmp \
      /var/log/supervisor \
      /var/run/supervisor \
      /opt/hermes-suite \
  && chmod +x /opt/hermes-suite/start.sh \
  && chown -R hermes:hermes \
      /opt/data \
      /workspace \
      /var/log/supervisor \
      /var/run/supervisor \
      /opt/hermes-suite \
  && chmod -R 775 \
      /opt/data \
      /workspace \
      /var/log/supervisor \
      /var/run/supervisor \
      /opt/hermes-suite \
  && chmod 1777 /tmp

EXPOSE 8642 8787 9119

WORKDIR /opt/hermes

ENTRYPOINT ["/opt/hermes-suite/start.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n"]
