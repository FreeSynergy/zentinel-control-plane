# FreeSynergy packaging for Zentinel Control Plane
# Build: podman build -t ghcr.io/freesynergy/zentinel-plane:latest .
FROM docker.io/library/rust:1-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential clang libclang-dev cmake libssl-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .
RUN cargo build --release

FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/zentinel-control-plane /usr/local/bin/zentinel-control-plane 2>/dev/null || true
COPY --from=builder /build/target/release/zentinel_control_plane /usr/local/bin/zentinel-control-plane 2>/dev/null || true

EXPOSE 9090
ENTRYPOINT ["/usr/local/bin/zentinel-control-plane"]
