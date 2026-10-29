# Both digests identify multi-platform indexes, including linux/arm64.
FROM ghcr.io/astral-sh/uv:0.12.19@sha256:04d046b13e60d6bcec73cbc5e1cad25d680dea90c8573340950a0ac2d1aef424 AS uv
FROM python:3.12.15-slim-bookworm@sha256:34386ef0cb081344d7ec1c103ba398e6e9f64e9ab3a1509accc92a4e24a07258 AS base

FROM base AS dependencies
COPY --from=uv /uv /bin/uv
ENV UV_PYTHON_DOWNLOADS=never UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /build/backend
COPY backend/pyproject.toml backend/uv.lock ./
# Fail if the lock is stale or a platform lacks a prebuilt wheel.
RUN uv sync --locked --no-dev --no-install-project --no-editable --no-build --compile-bytecode --python /usr/local/bin/python

FROM base AS runtime_base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    BINGO_SQLITE_PATH=/var/lib/bingo/totem.sqlite3
RUN groupadd --gid 10001 bingo \
    && useradd --uid 10001 --gid bingo --no-create-home --shell /usr/sbin/nologin bingo \
    && install -d -o bingo -g bingo -m 0700 /var/lib/bingo
COPY --from=dependencies /opt/venv /opt/venv
WORKDIR /opt/totem/backend
COPY backend/app ./app
COPY frontend/index.html frontend/styles.css frontend/script.js frontend/local_api.js frontend/operational.js /opt/totem/frontend/
COPY frontend/assets /opt/totem/frontend/assets
COPY deploy/start.py deploy/healthcheck.py /opt/totem/deploy/
USER 10001:10001
EXPOSE 8000
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD ["/opt/venv/bin/python", "/opt/totem/deploy/healthcheck.py"]
CMD ["/opt/venv/bin/python", "/opt/totem/deploy/start.py"]

# Explicit development target; the final/default target below stays operational.
FROM runtime_base AS simulation
USER root
RUN install -d -o bingo -g bingo -m 0700 /var/lib/bingo-simulation
COPY deploy/start_simulation.py /opt/totem/deploy/
ENV BINGO_SQLITE_PATH=/var/lib/bingo-simulation/simulation.sqlite3 \
    BINGO_SIMULATION_CONTEXT=development
USER 10001:10001
CMD ["/opt/venv/bin/python", "/opt/totem/deploy/start_simulation.py"]

FROM runtime_base AS dev_integration
USER root
RUN install -d -o bingo -g bingo -m 0700 /var/lib/bingo-dev-integration
COPY deploy/start_dev_integration.py /opt/totem/deploy/
ENV BINGO_SQLITE_PATH=/var/lib/bingo-dev-integration/simulation.sqlite3 \
    BINGO_DEV_CONTEXT=development
USER 10001:10001
CMD ["/opt/venv/bin/python", "/opt/totem/deploy/start_dev_integration.py"]

FROM runtime_base AS runtime
