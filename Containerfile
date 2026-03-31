# FreeSynergy packaging for Zentinel Control Plane — Fleet Management UI
# Build: podman build -t ghcr.io/freesynergy/zentinel-plane:latest .
# Elixir/Phoenix application — uses Mix release for a self-contained binary.
FROM docker.io/hexpm/elixir:1.17-erlang-27-debian-bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git nodejs npm \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix assets.deploy && \
    mix release

FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libncurses6 libssl3 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -r -s /bin/false zentinel-plane && \
    mkdir -p /var/lib/zentinel-plane && \
    chown -R zentinel-plane:zentinel-plane /var/lib/zentinel-plane

COPY --from=builder --chown=zentinel-plane:zentinel-plane \
    /build/_build/prod/rel/zentinel_cp /app

VOLUME ["/var/lib/zentinel-plane"]
EXPOSE 4000

USER zentinel-plane
ENV HOME=/var/lib/zentinel-plane
ENTRYPOINT ["/app/bin/zentinel_cp"]
CMD ["start"]
