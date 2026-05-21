# syntax=docker/dockerfile:1.7
# ---------- Stage 1: builder ----------
# Use Python 3.13-slim (matches `requires-python = ">=3.13"` in pyproject.toml).
# 3.13 is chosen instead of 3.14 because `python:3.13-slim` is a stable Docker Hub
# image at the time of this build, while 3.14 wheels for some dependencies may
# not yet be widely available.
FROM python:3.13-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Build deps for any wheels that need to compile (kept minimal).
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy package metadata + source. setuptools `find` selects only `app*`.
COPY pyproject.toml ./
COPY app ./app

# pyproject.toml references README.md; create a minimal placeholder if absent so
# the build is reproducible regardless of whether a README has been authored.
RUN test -f README.md || printf '%s\n' '# zava-ops-agent' > README.md

# Install the package and all runtime dependencies into a relocatable prefix.
RUN pip install --no-cache-dir --prefix=/install .

# ---------- Stage 2: runtime ----------
FROM python:3.13-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DATA_DIR=/srv/data

# Copy installed site-packages + console scripts from the builder.
COPY --from=builder /install /usr/local

# App code and synthetic Zava data.
WORKDIR /srv
COPY app /srv/app
COPY data /srv/data

# Non-root user (uid 1001).
RUN groupadd --system --gid 1001 appuser \
    && useradd --system --uid 1001 --gid appuser --home-dir /srv --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /srv

USER appuser

EXPOSE 9000

# `python -m app` -> app/__main__.py -> app.server.main()
ENTRYPOINT ["python", "-m", "app"]
